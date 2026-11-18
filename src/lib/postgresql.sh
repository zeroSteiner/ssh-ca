_psql() {
    psql_args=("$@")
    psql "$(psql_database_uri)" --set ON_ERROR_STOP=1 "${psql_args[@]}"
}

psql_database_uri() {
    if [[ -v args[--database] && "${args[--database]}" ]]; then
        echo "${args[--database]}"
    elif [[ -v SSH_CA_DATABASE_URI ]]; then
        echo "$SSH_CA_DATABASE_URI"
    fi
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

# usage:psql_insert_encrypted_private_keys "$ca_priv_key" "$ca_pub_key" "${recipients[@]}"
psql_insert_encrypted_private_keys() {
    local encrypted_file="$1"
    local public_key_file="$2"
    shift 2
    local recipients=("$@")

    local data_sha256=$(sha256sum "$encrypted_file" | cut -d' ' -f1)

    local filename=$(basename "$encrypted_file")

    read -r public_key_type public_key public_key_comment < "$public_key_file"

    local recipients_sql="{"
    for recipient in "${recipients[@]}"; do
        recipients_sql+="$recipient,"
    done
    recipients_sql="${recipients_sql%,}}"  # Remove trailing comma and close

    _psql \
        -v data_sha256="$data_sha256" \
        -v filename="$filename" \
        -v public_key="$public_key" \
        -v recipients="$recipients_sql" \
        <<'EOF'
        INSERT INTO encrypted_private_keys (data_sha256, filename, recipients, public_key_id)
        VALUES (
            decode(:'data_sha256', 'hex'),
            :'filename',
            :'recipients'::text[],
            (SELECT id FROM public_keys WHERE data = decode(:'public_key', 'base64') LIMIT 1)
        );
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

# usage: psql_public_key_summary $public_key_path
# Print "created_on|description|certificate_count|latest_created_on|latest_description", separated
# by the ASCII unit separator (\x1f) so empty fields survive `read`. Prints nothing
# when the key is not in the database.
psql_public_key_summary() {
    read -r public_key_type public_key public_key_comment < <(cat "$1")
    _psql -t -A -F $'\x1f' \
        -v public_key="$public_key" \
        <<'EOF_SQL'
        SELECT
            pk.created_on,
            coalesce(pk.description, ''),
            count(c.id),
            coalesce(max(c.created_on)::text, ''),
            coalesce((
                SELECT description FROM certificates
                WHERE public_key_id = pk.id
                ORDER BY created_on DESC, id DESC
                LIMIT 1
            ), '')
        FROM public_keys pk
        LEFT JOIN certificates c ON c.public_key_id = pk.id
        WHERE pk.data = decode(:'public_key', 'base64')
        GROUP BY pk.id
EOF_SQL
}

# usage: psql_certificate_fingerprint $certificate_path
# Print the fingerprint that the list and export commands use for a stored certificate.
psql_certificate_fingerprint() {
    read -r certificate_type certificate certificate_comment < <(cat "$1")
    _psql -t -A \
        -v certificate="$certificate" \
        <<'EOF_SQL'
        SELECT regexp_replace(concat('SHA256:', encode(data_sha256, 'base64')), '=+$', '')
        FROM certificates
        WHERE data = decode(:'certificate', 'base64')
EOF_SQL
}
