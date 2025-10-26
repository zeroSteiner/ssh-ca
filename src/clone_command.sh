get_recipients() {
    local data_sha256=$(sha256sum "${args[filename]}" | cut -d' ' -f1)
    _psql -tA \
        -v data_sha256="$data_sha256" \
        <<'EOF'
        SELECT unnest(recipients) FROM encrypted_private_keys WHERE data_sha256 = decode(:'data_sha256', 'hex');
EOF
}

echo "Info: Extracting the identity from the source YubiKey." >&2
if ! src_identity="$(age-plugin-yubikey --serial "${args[yubikey-src-serial]}" --slot "${args[--age-key-slot]}" --identity 2>/dev/null)"; then
    echo "Error: Failed to extract the identity from the source YubiKey" >&2
    exit 1
fi

echo "Info: Decrypting the CA private key." >&2
if ! ca_priv_key="$(age -i <(echo "$src_identity") --decrypt "${args[filename]}" 2>/dev/null)"; then
    echo "Error: Failed to decrypt the CA private key" >&2
    exit 1
fi

echo "Info: Importing the CA private key into the YubiKey PIV module." >&2
ykman --device "${args[yubikey-dst-serial]}" piv keys import \
    --pin-policy "${args[--yk-pin-policy]}" \
    --touch-policy "${args[--yk-touch-policy]}" \
    "${args[--yk-piv-slot]}" \
    <(echo "$ca_priv_key")

mapfile -t age_recipients < <(get_recipients)

if [ "${#age_recipients[@]}" -eq 0 ]; then
    echo "Warning: No preexisting recipients were found in the database for this CA file!" >&2
    echo "Warning: The resulting file will only be decryptable by these two YubiKeys!" >&2
fi

age_recipients+=($(age-plugin-yubikey --serial "${args[yubikey-src-serial]}" --slot "${args[--age-key-slot]}" --list | grep '^age1'))
age_recipients+=($(age-plugin-yubikey --serial "${args[yubikey-dst-serial]}" --slot "${args[--age-key-slot]}" --list | grep '^age1'))

# Remove duplicate recipients
mapfile -t age_recipients < <(printf '%s\n' "${age_recipients[@]}" | sort -u)

echo "YubiKey age recipients:"
for recipient in "${age_recipients[@]}"; do
    echo "  * $recipient"
done

recipient_args=()
for recipient in "${age_recipients[@]}"; do
  recipient_args+=("--recipient" "$recipient")
done

if [ -n "${args[--new-filename]}" ]; then
    output_file="${args[--new-filename]}"
else
    output_file=$(mktemp --suffix=".age")
fi

echo "Info: Encrypting the CA private key for future cloning." >&2
if ! age --encrypt "${recipient_args[@]}" -o "$output_file" <(echo "$ca_priv_key") 2>/dev/null; then
    echo "Error: Failed to encrypt the CA private key." >&2
    exit 1
fi

if [ -z "${args[--new-filename]}" ]; then
    if [ -w "${args[filename]}" ]; then
        if mv "$output_file" "${args[filename]}"; then
            echo "Info: New encrypted CA private key stored in: ${args[filename]}"
        else
            echo "Error: Failed to overwrite the source CA file." >&2
            echo "Error: New encrypted CA private key stored in: $output_file"
        fi
    else
        echo "Error: Original file can not be overwritten." >&2
        echo "Error: New encrypted CA private key stored in: $output_file"
    fi
fi

unset recipient_args
unset ca_priv_key

# todo: upload the keys to the db with the new sha256 and recipients
