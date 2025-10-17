keygen_args=()
keygen_args+=(-D "$libykcs11")
keygen_args+=(-I "${args[user-identity]}")
keygen_args+=(-O "clear")
keygen_args+=(-s "${args[ca-public-key]}")

if [[ -v args[--principal] ]] && [ -n "${args[--principal]}" ]; then
    principals_ary=(${args[--principal]})
    IFS=','; principals_str="${principals_ary[*]}"; unset IFS
    keygen_args+=(-n "$principals_str")
    unset principals_ary principals_str
fi

declare -A signing_options
set -- ${args[--option]}
declare -a signing_option_flags=("${default_signing_options[@]}" "$@")
for option in "${signing_option_flags[@]}"; do
  if [[ $option == permit-* ]]; then
    option="${option#permit-}"
    signing_options["$option"]="permit"
  elif [[ $option == no-* ]]; then
    option="${option#no-}"
    signing_options["$option"]="no"
  fi
done

for option in "${!signing_options[@]}"; do
  if [[ ${signing_options[$option]} == "permit" ]]; then
    keygen_args+=("-O" "permit-$option")
  fi
done

if [[ -v args[--validity] ]] && [ -n "${args[--validity]}" ]; then
  keygen_args+=(-V "${args[--validity]}")
fi

ssh-keygen \
    "${keygen_args[@]}" \
    "${args[user-public-key]}"
chmod 0600 "${args[user-public-key]%.pub}-cert.pub"

psql_upsert_certificate \
    "${args[ca-public-key]}" \
    "${args[user-public-key]}" \
    "${args[user-public-key]%.pub}-cert.pub" \
    "${args[--description]:-}" \
    > /dev/null

ssh_print_certificate "${args[user-public-key]%.pub}-cert.pub"
