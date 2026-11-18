# usage: ssh_user_keygen_args
# Build the global keygen_args array for signing a user key from the parsed args
# (ca-public-key, user-identity, --principal, --option, --validity) and the
# default_signing_options command variable.
ssh_user_keygen_args() {
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
}

# usage: ssh_sign_user_key $user_public_key_path
# Sign the key with the global keygen_args, store the certificate and print it.
# The certificate is written next to the key as <name>-cert.pub.
ssh_sign_user_key() {
    local user_public_key="$1"

    ssh-keygen \
        "${keygen_args[@]}" \
        "$user_public_key"
    chmod 0600 "${user_public_key%.pub}-cert.pub"

    psql_upsert_certificate \
        "${args[ca-public-key]}" \
        "$user_public_key" \
        "${user_public_key%.pub}-cert.pub" \
        "${args[--description]:-}" \
        > /dev/null

    ssh_print_certificate "${user_public_key%.pub}-cert.pub"
}

# usage: ssh_describe_keygen_args
# Print the certificate fields that the global keygen_args will produce, one per line.
ssh_describe_keygen_args() {
    local identity="" principals="" validity="" options=() i
    for (( i = 0; i < ${#keygen_args[@]}; i++ )); do
        case "${keygen_args[$i]}" in
            -I) identity="${keygen_args[++i]}" ;;
            -n) principals="${keygen_args[++i]}" ;;
            -V) validity="${keygen_args[++i]}" ;;
            -O)
                (( ++i ))
                if [[ "${keygen_args[$i]}" != "clear" ]]; then
                    options+=("${keygen_args[$i]}")
                fi
                ;;
            -D|-s) (( ++i )) ;;
        esac
    done
    local options_str
    IFS=','; options_str="${options[*]}"; unset IFS
    echo "identity:    $identity"
    echo "principals:  ${principals:-(none)}"
    echo "validity:    ${validity:-forever (no -V given)}"
    echo "options:     ${options_str:-(none)}"
}
