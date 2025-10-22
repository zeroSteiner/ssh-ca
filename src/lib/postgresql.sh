_psql() {
    psql_args=("$@")
    if [[ -v args[--trace] ]]; then
        psql_args=("--echo-queries" "${psql_args[@]}")
    fi
    if [[ -v args[--database] && "${args[--database]}" ]]; then
        database_uri="${args[--database]}"
    elif [[ -v SSH_CA_DATABASE_URI ]]; then
        database_uri="$SSH_CA_DATABASE_URI"
    fi
    psql "$database_uri" --set ON_ERROR_STOP=1 "${psql_args[@]}"
}

psql_current_schema_version() {
    local version=$(_psql -tA 2>/dev/null <<'EOF'
SELECT schema_version FROM metadata LIMIT 1;
EOF
    )

    # If we got a version, return it
    if [ -n "$version" ]; then
        echo "$version"
        return
    fi

    # Check if public_keys exists
    if _psql -tA <<'EOF' | grep -q 't'
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name = 'public_keys'
);
EOF
    then
        echo 1
        return
    fi

    echo 0
    return
}

psql_latest_schema_version() {
    local version=1
    while declare -f $(printf "initialize_schema_v%03d" "$version") > /dev/null; do
        ((version++))
    done
    echo $((version - 1))
}

psql_initialize() {
    local current_version=$(psql_current_schema_version)
    local latest_version=$(psql_latest_schema_version)

    if [ "$current_version" -ge "$latest_version" ]; then
        return 0
    fi

    printf "Migrating database schema from v$current_version to v$latest_version"

    local num_migrations=$((latest_version - current_version))

    # Run each migration in sequence
    for ((version=current_version+1; version<=latest_version; version++)); do
        local function_name=$(printf "initialize_schema_v%03d" "$version")

        echo "Running database migration: ${function_name}"
        "$function_name" &>/dev/null
    done
}

# usage: psql_export_certificate $fingerprint
psql_export_certificate() {
    fingerprint="${1:-}"
    fingerprint="${fingerprint%%=*}"
    _psql -t -A -F' ' \
        -v fingerprint="$fingerprint" \
        <<'EOF'
        SELECT
            type,
            translate(encode(data, 'base64'), E'\n', ''),
            comment
        FROM certificates
        WHERE regexp_replace(concat('SHA256:', encode(data_sha256, 'base64')), '=+$', '') = :'fingerprint'
        LIMIT 1
EOF
}

# usage: psql_export $fingerprint
psql_export() {
    fingerprint="${1:-}"
    fingerprint="${fingerprint%%=*}"
    _psql -t -A -F' ' \
        -v fingerprint="$fingerprint" \
        <<'EOF'
        SELECT
            type,
            translate(encode(data, 'base64'), E'\n', ''),
            comment
        FROM public_keys
        WHERE regexp_replace(concat('SHA256:', encode(data_sha256, 'base64')), '=+$', '') = :'fingerprint'
        UNION ALL
        SELECT
            type,
            translate(encode(data, 'base64'), E'\n', ''),
            comment
        FROM certificates
        WHERE regexp_replace(concat('SHA256:', encode(data_sha256, 'base64')), '=+$', '') = :'fingerprint'
        LIMIT 1
EOF
}

psql_list() {
    echo "SSH Public Keys and Certificates"
    echo "------------+----------------------------------------------------"

    _psql --expanded --tuples-only \
    <<'EOF'
    SELECT 'public key' as class, type, concat('SHA256:', encode(data_sha256, 'base64')) as fingerprint, comment, description, created_on FROM public_keys
    UNION
    SELECT class || ' certificate' as class, type, concat('SHA256:', encode(data_sha256, 'base64')) as fingerprint, comment, description, created_on FROM certificates
EOF
}

# usage: psql_upsert_certificate $ca_public_key_path $public_key_path $certificate_path $description
psql_upsert_certificate() {
    read -r ca_public_key_type ca_public_key ca_public_key_comment < <(cat "$1")
    read -r public_key_type public_key public_key_comment < <(cat "$2")
    read -r certificate_type certificate certificate_comment < <(cat "$3")
    certificate_class=$(ssh-keygen -Lf "$3" | awk '/Type:\s+\S+\s+\S+\s+certificate/ {print $3}')
    _psql \
        -v ca_public_key_type="$ca_public_key_type" \
        -v ca_public_key="$ca_public_key" \
        -v ca_public_key_comment="$ca_public_key_comment" \
        -v public_key_type="$public_key_type" \
        -v public_key="$public_key" \
        -v public_key_comment="$public_key_comment" \
        -v certificate_type="$certificate_type" \
        -v certificate_class="$certificate_class" \
        -v certificate="$certificate" \
        -v certificate_comment="$certificate_comment" \
        -v description="${4:-}" \
        <<'EOF'
        WITH
        upserted_ca_public_key AS (
            INSERT INTO public_keys (type, data, comment)
            VALUES (:'ca_public_key_type', decode(:'ca_public_key', 'base64'), NULLIF(:'ca_public_key_comment', ''))
            ON CONFLICT (data) DO NOTHING
            RETURNING id
        ),
        upserted_public_key AS (
            INSERT INTO public_keys (type, data, comment)
            VALUES (:'public_key_type', decode(:'public_key', 'base64'), NULLIF(:'public_key_comment', ''))
            ON CONFLICT (data) DO NOTHING
            RETURNING id
        )
        INSERT INTO certificates (type, data, comment, class, description, ca_public_key_id, public_key_id)
        VALUES (
            :'certificate_type',
            decode(:'certificate', 'base64'),
            NULLIF(:'certificate_comment', ''),
            :'certificate_class',
            NULLIF(:'description', ''),
            COALESCE(
                (SELECT id FROM upserted_ca_public_key),
                (SELECT id FROM public_keys WHERE type = :'ca_public_key_type' AND data = decode(:'ca_public_key', 'base64'))
            ),
            COALESCE(
                (SELECT id FROM upserted_public_key),
                (SELECT id FROM public_keys WHERE type = :'public_key_type' AND data = decode(:'public_key', 'base64'))
            )
        )
        ON CONFLICT (data) DO UPDATE SET description = EXCLUDED.description
EOF
}

# usage: psql_upsert_public_key $public_key_path $description
psql_upsert_public_key() {
    read -r public_key_type public_key public_key_comment < <(cat "$1")
    _psql \
        -v public_key_type="$public_key_type" \
        -v public_key="$public_key" \
        -v public_key_comment="$public_key_comment" \
        -v description="${2:-}" \
        <<'EOF'
        INSERT INTO public_keys (type, data, comment, description)
        VALUES (:'public_key_type', decode(:'public_key', 'base64'), NULLIF(:'public_key_comment', ''), NULLIF(:'description', ''))
        ON CONFLICT (data) DO UPDATE SET description = EXCLUDED.description
EOF
}
