ca_priv_key="${args[filename]}"
ca_pub_key="$ca_priv_key.pub"

printf "Initializing the database..."
psql_initialize > /dev/null
printf " done.\n"

set -- ${args[yubikey-serial]}
declare -a yubikey_serials=("$@")

declare -A age_recipients
for serial in "${yubikey_serials[@]}"; do
  age_recipients["$serial"]=$(age-plugin-yubikey --serial "$serial" --slot "${args[--age-key-slot]}" --list | grep '^age1')
done

echo "Yubikey age recipients:"
for serial in "${yubikey_serials[@]}"; do
  echo "  * Serial: $serial -> ${age_recipients[$serial]}"
done

case "${args[key-type]}" in
  ECCP*)
    keygen_args=("ecparam" "-noout" "-genkey")
    ;;&
  ECCP256)
    keygen_args+=("-name" "secp251r1")
    ;;
  ECCP384)
    keygen_args+=("-name" "secp384r1")
    ;;
  RSA*)
    keygen_args=("genpkey" "-algorithm" "RSA")
    ;;&
  RSA2048)
    keygen_args+=("-pkeyopt" "rsa_keygen_bits:2048")
    ;;
  RSA3072)
    keygen_args+=("-pkeyopt" "rsa_keygen_bits:3072")
    ;;
  # the NIST specification for PIV does not support RSA4096
esac
openssl "${keygen_args[@]}" -out "$ca_priv_key" &> /dev/null
unset keygen_args
ssh-keygen -i -m PKCS8 -f <(openssl pkey -in "$ca_priv_key" -pubout) > "$ca_pub_key"
chmod 0600 "$ca_pub_key"

for serial in "${yubikey_serials[@]}"; do
  ykman --device "$serial" piv keys import \
    --pin-policy "${args[--yk-pin-policy]}" \
    --touch-policy "${args[--yk-touch-policy]}" \
    "${args[--yk-piv-slot]}" \
    "$ca_priv_key"
done

recipient_args=()
for serial in "${yubikey_serials[@]}"; do
  recipient_args+=("--recipient" "${age_recipients[$serial]}")
done
age --encrypt "${recipient_args[@]}" -o "${ca_priv_key}.age" "$ca_priv_key"
unset recipient_args
rm "$ca_priv_key"

psql_upsert_public_key "$ca_pub_key" "${args[--description]:-}" > /dev/null
