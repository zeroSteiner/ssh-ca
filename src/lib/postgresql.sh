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

psql_initialize() {
    _psql <<'EOF'
        SET client_min_messages = WARNING;

        CREATE EXTENSION IF NOT EXISTS pgcrypto;

        CREATE OR REPLACE FUNCTION set_data_sha256()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.data_sha256 := digest(NEW.data, 'sha256');
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        --
        -- create table public_keys
        --
        CREATE TABLE IF NOT EXISTS public_keys (
            id SERIAL PRIMARY KEY,
            created_on DATE DEFAULT CURRENT_DATE,
            type VARCHAR(20) NOT NULL,
            data BYTEA UNIQUE NOT NULL,
            data_sha256 BYTEA UNIQUE NOT NULL,
            comment TEXT,
            description TEXT
        );

        CREATE OR REPLACE TRIGGER update_public_key_sha256
        BEFORE INSERT OR UPDATE ON public_keys
        FOR EACH ROW
        EXECUTE FUNCTION set_data_sha256();

        --
        -- create table certificates
        --
        CREATE TABLE IF NOT EXISTS certificates (
            id SERIAL PRIMARY KEY,
            created_on DATE DEFAULT CURRENT_DATE,
            type VARCHAR(40) NOT NULL,
            data BYTEA UNIQUE NOT NULL,
            data_sha256 BYTEA UNIQUE NOT NULL,
            comment TEXT,
            class CHAR(4) NOT NULL,
            description TEXT,
            ca_public_key_id INTEGER,
            public_key_id INTEGER,
            CONSTRAINT fk_ca_public_key
                FOREIGN KEY (ca_public_key_id)
                REFERENCES public_keys(id)
                ON DELETE CASCADE,
            CONSTRAINT fk_public_key
                FOREIGN KEY (public_key_id)
                REFERENCES public_keys(id)
                ON DELETE CASCADE
        );

        CREATE OR REPLACE TRIGGER update_certificate_sha256
        BEFORE INSERT OR UPDATE ON certificates
        FOR EACH ROW
        EXECUTE FUNCTION set_data_sha256();
EOF
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
