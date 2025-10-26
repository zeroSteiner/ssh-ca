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
    echo "Warning: No recipients found!" >&2
    echo "Warning: The resulting file will only be decryptable by these two YubiKeys!" >&2
else
    echo "YubiKey age recipients:"
    for recipient in "${age_recipients[@]}"; do
        echo "  * $recipient"
    done
fi
