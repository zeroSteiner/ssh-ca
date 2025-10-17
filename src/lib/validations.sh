validate_database_connection() {
    if [[ -z "${args[--database]}" && ! -v SSH_CA_DATABASE_URI ]]; then
        echo "a database connection must be specified"
        return
    fi
    _psql <<< "SELECT 1" &> /dev/null || echo "database connection failed"
}

validate_is_openssh_public_key() {
    file -Lb "$1" | grep -Ei 'OpenSSH \w+ public key' &> /dev/null || echo "invalid OpenSSH public key: $1 (not a public key)"
    if [[ ! "$1" =~ \.pub$ ]]; then
        echo "invalid OpenSSH public key: $1 (filename must end in .pub)"
    fi
}

validate_is_principal_name() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9_\-]+$ ]]; then
        echo "invalid string (must be alphanumeric)"
    fi
}

validate_is_valid_signing_option() {
    if [[ ! "$1" =~ ^(no|permit)-(agent-forwarding|port-forwarding|pty|user-rc|x11-forwarding) ]]; then
        echo "invalid certificate signing option: $1"
    fi
}

validate_is_valid_validity_interval() {
    # see: https://www.man7.org/linux/man-pages/man1/ssh-keygen.1.html#:~:text=%2DV%20validity_interval
    is_timestamp() {
        if [[ "$1" =~ ^([0-9]{4})(0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])((2[0-3]|[01][0-9])([0-5][0-9])([0-5][0-9])?)?Z?$ ]]; then
            return 0
        fi
        return 1
    }
    is_relative_time() {
        if [[ "$1" =~ ^[+-]?[0-9]+$ ]]; then
            return 0
        elif [[ "$1" =~ ^[+-]?([0-9]+[sSmMhHdDwW])+$ ]]; then
            return 0
        fi
        return 1
    }

    local start_time=""
    local end_time="$1"

    if [[ "$end_time" == *:* ]]; then
        start_time="${end_time%%:*}"
        end_time="${end_time#*:}"

        if [ -z "$start_time" ]; then
            echo "invalid start time (can not be blank when a range is specified)"
        fi
        if [ -z "$end_time" ]; then
            echo "invalid end time (can not be blank when a range is specified)"
        fi
    fi

    if [ -z "$start_time" ]; then
        :
    elif [ "$start_time" == "always" ]; then
        :
    elif is_timestamp "$start_time"; then
        :
    elif is_relative_time "$start_time"; then
        :
    else
        echo "invalid start time: $start_time"
        return
    fi

    if [ -z "$end_time" ]; then
        :
    elif [ "$end_time" == "forever" ]; then
        :
    elif is_timestamp "$end_time"; then
        :
    elif is_relative_time "$end_time"; then
        :
    else
        echo "invalid end time: $end_time"
        return
    fi

    unset -f is_timestamp
    unset -f is_relative_time
}

validate_yubikey_serial_exists() {
    ykman --device "$1" info &> /dev/null || echo "invalid Yubikey serial number: $1"
}
