keygen_args=()
keygen_args+=(-D "$libykcs11")
keygen_args+=(-I "${args[host-identity]}")
keygen_args+=(-s "${args[ca-public-key]}")
keygen_args+=(-h)

if [[ -v args[--principal] ]] && [ -n "${args[--principal]}" ]; then
    principals_ary=(${args[--principal]})
    IFS=','; principals_str="${principals_ary[*]}"; unset IFS
    keygen_args+=(-n "$principals_str")
    unset principals_ary principals_str
fi

if [[ -v args[--validity] ]] && [ -n "${args[--validity]}" ]; then
  keygen_args+=(-V "${args[--validity]}")
fi

ssh-keygen \
    "${keygen_args[@]}" \
    "${args[host-public-key]}"
chmod 0600 "${args[host-public-key]%.pub}-cert.pub"

psql_upsert_certificate \
    "${args[ca-public-key]}" \
    "${args[host-public-key]}" \
    "${args[host-public-key]%.pub}-cert.pub" \
    "${args[--description]:-}" \
    > /dev/null

ssh_print_certificate "${args[host-public-key]%.pub}-cert.pub"
