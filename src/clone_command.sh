age -i <(age-plugin-yubikey --serial "${args[yubikey-src-serial]}" --slot "${args[--age-key-slot]}" --identity 2>/dev/null) --decrypt "${args[filename]}"

get_recipients() {
    local data_sha256=$(sha256sum "${args[filename]}" | cut -d' ' -f1)
    _psql -tA \
        -v data_sha256="$data_sha256" \
        <<'EOF'
        SELECT unnest(recipients) FROM encrypted_private_keys WHERE data_sha256 = decode(:'data_sha256', 'hex');
EOF
}

mapfile -t age_recipients < <(get_recipients)

if [ "${#age_recipients[@]}" -eq 0 ]; then
    echo "Warning: No recipients found!" >&2
    echo "Warning: The resulting file will only be decryptable by these two YubiKeys!" >&2
else
    echo "YubiKey age recipients:"
    for recipient in "${age_recipients[@]}"; do
        echo "  * $recipient"
    done
fi
