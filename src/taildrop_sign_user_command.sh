## Receive one OpenSSH public key over Taildrop, show what is known about it, ask for
## confirmation, sign it and send the certificate back. Everything about the received file
## (its name, size, and contents) is controlled by whoever sent it.
##
## Received files stay in $inbox until a decision is made about them: rejected files (and
## anything left there when ssh-ca stops early) are moved to a taildrop-rejected-* directory,
## because the Taildrop inbox is shared by the whole machine and they may be unrelated to
## ssh-ca. A signed certificate that was not delivered is always saved before exiting.

taildrop_printable() {
    LC_ALL=C tr -cd '[:print:]' <<< "$1"
}

taildrop_output_dir() {
    local dir
    for dir in "$PWD" "$HOME"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            echo "$dir"
            return
        fi
    done
    return 1
}

# usage: taildrop_flush_tty
# Throw away anything typed before a prompt, so a "y" typed while waiting can't answer it.
taildrop_flush_tty() {
    while IFS= read -r -s -t 0.2 -n 4096 _ < /dev/tty; do
        :
    done
}

# usage: taildrop_keep_inbox
# Move everything still in the inbox to a new private taildrop-rejected-* directory.
taildrop_keep_inbox() {
    local base dest file
    local -a files
    mapfile -d '' -t files < <(find "$inbox" -mindepth 1 -maxdepth 1 -print0 2> /dev/null)
    if (( ${#files[@]} == 0 )); then
        return 0
    fi

    if ! base="$(taildrop_output_dir)"; then
        echo "[-] No writable directory to keep the received files in" >&2
        return 1
    fi
    dest="$base/taildrop-rejected-$(date +%Y%m%d-%H%M%S)"
    if ! mkdir -m 0700 -- "$dest" 2> /dev/null; then
        dest="$(mktemp -d "$dest.XXXX")" || return 1
    fi
    for file in "${files[@]}"; do
        if LC_ALL=C grep -aq 'PRIVATE KEY' -- "$file" 2> /dev/null; then
            echo "$(taildrop_printable "$(basename -- "$file")") looks like a PRIVATE key. Treat that key as exposed and replace it." >&2
        fi
        if ! mv -- "$file" "$dest/" 2> /dev/null; then
            # e.g. still owned by root after a failed sudo chown
            if ! (( tailscale_use_sudo )) || ! sudo mv -- "$file" "$dest/"; then
                echo "[-] Could not move $(taildrop_printable "$(basename -- "$file")") to $dest" >&2
                return 1
            fi
            sudo chown -- "$(id -u):$(id -g)" "$dest/$(basename -- "$file")" || true
        fi
    done
    echo "Received files were kept in: $dest" >&2
}

# usage: taildrop_save_cert
# Save the signed certificate next to where ssh-ca was run (never overwriting anything).
taildrop_save_cert() {
    local base dest n=1 cert_fingerprint
    if ! base="$(taildrop_output_dir)"; then
        echo "[-] No writable directory to save the certificate in" >&2
        return 1
    fi
    dest="$base/$safe_base-cert.pub"
    while [[ -e "$dest" ]]; do
        dest="$base/$safe_base-cert.pub.$n"
        n=$(( n + 1 ))
    done
    cp -- "$cert_file" "$dest" || return 1
    echo "The signed certificate was saved to: $dest" >&2
    cert_fingerprint="$(psql_certificate_fingerprint "$cert_file" 2> /dev/null)" || cert_fingerprint=""
    if [[ -n "$cert_fingerprint" ]]; then
        echo "It is also stored in the database: ssh-ca export $cert_fingerprint" >&2
    else
        echo "[-] It is NOT stored in the database" >&2
    fi
}

taildrop_cleanup() {
    if [[ -z "${tmp_dir:-}" || ! -d "$tmp_dir" ]]; then
        return 0
    fi
    local keep=0
    if ! taildrop_keep_inbox; then
        keep=1
    fi
    if [[ -n "${cert_file:-}" && -f "$cert_file" ]] && (( ! cert_delivered )); then
        if ! taildrop_save_cert; then
            keep=1
        fi
    fi
    if (( keep )); then
        echo "Left ssh-ca's working directory in place: $tmp_dir" >&2
    else
        rm -rf -- "$tmp_dir"
    fi
}

# usage: taildrop_reject $reason
taildrop_reject() {
    echo "[-] Not signed: $1" >&2
    exit 1
}

if ! { : < /dev/tty; } 2> /dev/null; then
    echo "[-] Confirmation needs a terminal (/dev/tty is not available)" >&2
    exit 1
fi
# everything the confirmation depends on goes to the terminal, even if stdout is redirected
exec 3> /dev/tty

ssh_user_keygen_args

peer="${args[--peer]:-}"
if [[ -n "$peer" ]] && tailscale_target_is_offline "$peer"; then
    echo "$peer is offline right now, sending the certificate back may fail" >&2
fi
self_name="$(tailscale_self_name)"

cert_delivered=0
cert_file=""
tmp_dir="$(mktemp -d)"
trap taildrop_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
inbox="$tmp_dir/inbox"
work="$tmp_dir/work"
mkdir -m 0700 -- "$inbox" "$work"

cat >&3 <<EOF
On the device, note the key's fingerprint, send the public key to $self_name, then wait for the certificate:
  ssh-keygen -lf ~/.ssh/id_ed25519.pub
  tailscale file cp ~/.ssh/id_ed25519.pub $self_name:
  tailscale file get --wait --conflict=overwrite ~/.ssh/

Waiting for a file... (Ctrl-C to cancel)
EOF

tailscale_file_get_wait "$inbox"
waited=$(( SECONDS - tailscale_wait_started ))
mapfile -d '' -t received < <(find "$inbox" -mindepth 1 -maxdepth 1 -print0)

if (( ${#received[@]} == 0 )); then
    taildrop_reject "no file was received"
elif (( ${#received[@]} > 1 )); then
    echo "[-] ${#received[@]} files were received at once:" >&2
    for file in "${received[@]}"; do
        echo "      $(taildrop_printable "$(basename -- "$file")")" >&2
    done
    taildrop_reject "expected exactly one public key"
fi

source_file="${received[0]}"
received_name="$(taildrop_printable "$(basename -- "$source_file")")"
if [[ -L "$source_file" || ! -f "$source_file" ]]; then
    taildrop_reject "$received_name is not a regular file"
fi
received_size="$(stat -c %s -- "$source_file")"
if (( received_size > 16384 )); then
    taildrop_reject "$received_name is too large to be a public key ($received_size bytes)"
fi
if LC_ALL=C grep -aq 'PRIVATE KEY' -- "$source_file"; then
    taildrop_reject "$received_name is a private key"
fi
if (( $(LC_ALL=C tr -cd '\000' < "$source_file" | wc -c) > 0 )); then
    taildrop_reject "$received_name contains NUL bytes"
fi

# parse exactly one line (one optional trailing newline), check every field, then write a
# normalized copy; only that copy is fingerprinted, looked up, shown and signed
key_line=""
IFS= read -r -d '' key_line < "$source_file" || true
key_line="${key_line%$'\n'}"
key_line="${key_line%$'\r'}"
if [[ "$key_line" == *[$'\n\r']* ]]; then
    taildrop_reject "$received_name has more than one line"
fi
key_type="" key_blob="" key_comment=""
read -r key_type key_blob key_comment <<< "$key_line" || true
if [[ "$key_type" == *-cert-v01@openssh.com ]]; then
    taildrop_reject "$received_name is already a certificate"
fi
if [[ ! "$key_type" =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)$ ]]; then
    taildrop_reject "$received_name is not an OpenSSH public key (unsupported or missing key type)"
fi
if [[ ! "$key_blob" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
    taildrop_reject "$received_name is not an OpenSSH public key (bad key data)"
fi
if [[ "$key_comment" != "$(taildrop_printable "$key_comment")" ]]; then
    taildrop_reject "$received_name has non-ASCII or control characters in its comment"
fi
if (( ${#key_comment} > 256 )); then
    taildrop_reject "$received_name has a comment longer than 256 characters"
fi

# never build a path from the received name: derive a safe base name for the working copy
# (and for the certificate that goes back)
safe_base="$(LC_ALL=C tr -cd 'A-Za-z0-9._@-' <<< "${received_name%.pub}")"
while [[ "$safe_base" == [.-]* ]]; do
    safe_base="${safe_base:1}"
done
safe_base="${safe_base:0:64}"
safe_base="${safe_base:-id}"
key_file="$work/$safe_base.pub"
printf '%s %s%s\n' "$key_type" "$key_blob" "${key_comment:+ $key_comment}" > "$key_file"
chmod 0600 "$key_file"

key_error="$(validate_is_openssh_public_key "$key_file")"
if [[ -n "$key_error" ]]; then
    taildrop_reject "$received_name is not an OpenSSH public key"
fi
if ! key_fingerprint_line="$(ssh-keygen -lf "$key_file" 2> /dev/null)" || [[ "$key_fingerprint_line" == *$'\n'* ]]; then
    taildrop_reject "ssh-keygen can't read $received_name"
fi
read -r key_bits key_fingerprint _ <<< "$key_fingerprint_line"
key_algorithm="${key_fingerprint_line##* }"
key_algorithm="${key_algorithm#(}"
key_algorithm="${key_algorithm%)}"
ca_fingerprint="$(ssh-keygen -lf "${args[ca-public-key]}" | awk '{ print $2 }')"

db_summary="$(psql_public_key_summary "$key_file")"
if [[ -n "$db_summary" ]]; then
    IFS=$'\x1f' read -r db_created db_description db_cert_count db_latest db_latest_description <<< "$db_summary"
    db_line="known since $db_created"
    [[ -n "$db_description" ]] && db_line+=" \"$(taildrop_printable "$db_description")\""
    if (( db_cert_count > 0 )); then
        db_line+="; $db_cert_count certificate(s), latest $db_latest"
        [[ -n "$db_latest_description" ]] && db_line+=" \"$(taildrop_printable "$db_latest_description")\""
    else
        db_line+="; no certificates yet"
    fi
else
    db_line="new key (not in the database)"
fi

{
    echo
    echo "Received file:   $received_name ($received_size bytes)"
    if (( waited < 2 )); then
        echo "                 It arrived right away, so it was probably already waiting in"
        echo "                 the Taildrop inbox before ssh-ca started."
    fi
    echo "Key:             $key_algorithm $key_bits $key_fingerprint"
    echo "Key comment:     ${key_comment:-(none)}"
    ssh-keygen -lvf "$key_file" 2> /dev/null | tail -n +2 | sed 's/^/                 /'
    echo "In database:     $db_line"
    echo "CA key:          $ca_fingerprint ($(taildrop_printable "$(basename -- "${args[ca-public-key]}")"))"
    echo "Certificate:"
    ssh_describe_keygen_args | sed 's/^/                 /'
    echo "                 description: ${args[--description]:-(none)}"
    echo "Cert goes to:    ${peer:-chosen after you confirm}"
    echo "Sender:          not reported by Taildrop, compare the fingerprint on the device"
    echo
} >&3

taildrop_flush_tty
answer=""
printf 'Sign this key? [y/N] ' >&3
read -r answer < /dev/tty || answer=""
case "${answer,,}" in
    y|yes) ;;
    *)
        rm -f -- "$source_file"
        echo "[-] Not signed, the received key was discarded" >&2
        exit 1
        ;;
esac

if [[ -z "$peer" ]]; then
    mapfile -t targets < <(tailscale_targets)
    if (( ${#targets[@]} == 0 )); then
        taildrop_reject "there are no Taildrop targets to send the certificate to"
    fi
    for i in "${!targets[@]}"; do
        IFS=$'\t' read -r target_name target_status <<< "${targets[$i]}"
        printf '  %d) %s%s\n' "$(( i + 1 ))" "$target_name" "${target_status:+ ($target_status)}" >&3
    done
    taildrop_flush_tty
    choice=""
    printf 'Send the certificate to which device? [1-%d] ' "${#targets[@]}" >&3
    read -r choice < /dev/tty || choice=""
    if [[ ! "$choice" =~ ^[0-9]{1,3}$ ]] || (( 10#$choice < 1 || 10#$choice > ${#targets[@]} )); then
        taildrop_reject "no device was chosen"
    fi
    IFS=$'\t' read -r peer _ <<< "${targets[$(( 10#$choice - 1 ))]}"
fi

# the normalized working copy is what gets signed; the received file stays in the inbox
# (and is kept by the EXIT trap) until signing and storing have succeeded
cert_file="$work/$safe_base-cert.pub"
ssh_sign_user_key "$key_file"
rm -f -- "$source_file"

if ! tailscale_run file cp "$cert_file" "$peer:"; then
    echo "[-] Sending the certificate to $peer failed" >&2
    exit 1
fi
cert_delivered=1
echo "Certificate $safe_base-cert.pub sent to $peer"
