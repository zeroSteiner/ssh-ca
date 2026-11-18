tailscale_use_sudo=0
tailscale_wait_started=0

# usage: tailscale_try $tailscale_args...
# Run tailscale directly and return its exit code. Taildrop calls fail with "Access denied"
# unless the user is root or the tailscale operator; on that denial, print a notice instead
# of tailscale's error and turn on tailscale_use_sudo so the caller can retry with sudo.
tailscale_try() {
    # capture stderr (to look for the denial) while stdout still goes straight through
    local stderr_text rc=0
    { stderr_text="$(tailscale "$@" 2>&1 1>&3 3>&-)"; } 3>&1 || rc=$?
    if (( rc != 0 )) && [[ "$stderr_text" == *"Access denied"* ]]; then
        echo "tailscale needs elevated privileges for Taildrop, retrying with sudo" >&2
        tailscale_use_sudo=1
        return "$rc"
    fi
    if [[ -n "$stderr_text" ]]; then
        printf '%s\n' "$stderr_text" >&2
    fi
    return "$rc"
}

# usage: tailscale_run $tailscale_args...
# Run tailscale, falling back to sudo (for this and all later calls) when access is denied.
tailscale_run() {
    if (( ! tailscale_use_sudo )); then
        local rc=0
        tailscale_try "$@" || rc=$?
        if (( rc == 0 || ! tailscale_use_sudo )); then
            return "$rc"
        fi
    fi
    sudo tailscale "$@"
}

# usage: tailscale_file_get_wait $directory
# Wait for files to arrive in the Taildrop inbox and move all of them into $directory,
# making sure the current user owns them even when sudo was needed. Sets
# tailscale_wait_started to $SECONDS when the actual wait began (after any sudo prompt).
tailscale_file_get_wait() {
    local directory="$1"
    if (( ! tailscale_use_sudo )); then
        local rc=0
        tailscale_wait_started=$SECONDS
        tailscale_try file get --wait "$directory" || rc=$?
        if (( rc == 0 || ! tailscale_use_sudo )); then
            return "$rc"
        fi
    fi
    # one sudo call for both steps, so a long wait can't outlast the sudo timestamp and
    # leave root-owned files behind waiting on a second password prompt
    sudo -v
    tailscale_wait_started=$SECONDS
    sudo sh -c 'tailscale file get --wait "$1" && chown -R -- "$2" "$1"' sh "$directory" "$(id -u):$(id -g)"
}

# usage: tailscale_targets
# Print the Taildrop targets as "name<TAB>status" lines (status is empty when online).
tailscale_targets() {
    tailscale file cp --targets | awk -F'\t' 'NF >= 2 { print $2 "\t" $3 }'
}

# usage: tailscale_target_is_offline $name
tailscale_target_is_offline() {
    tailscale_targets | awk -F'\t' -v name="$1" '$1 == name && $2 ~ /^offline/ { found = 1 } END { exit !found }'
}

# usage: tailscale_self_name
tailscale_self_name() {
    tailscale status --self --peers=false | awk '$1 ~ /^[0-9a-f.:]+$/ { print $2; exit }'
}
