psql_schema_initialize_v002() {
    _psql <<'EOF'
        SET client_min_messages = WARNING;

        --
        -- create table metadata
        --
        CREATE TABLE IF NOT EXISTS metadata (
            id SERIAL PRIMARY KEY,
            created_on DATE DEFAULT CURRENT_DATE,
            key TEXT UNIQUE NOT NULL,
            value TEXT NOT NULL
        );

        --
        -- create table encrypted_private_keys
        --
        -- encrypted private keys are effectively CA keys and this table holds
        -- meta data about them but not the data itself, encrypted or otherwise
        CREATE TABLE IF NOT EXISTS encrypted_private_keys (
            id SERIAL PRIMARY KEY,
            created_on DATE DEFAULT CURRENT_DATE,
            data_sha256 BYTEA UNIQUE NOT NULL,
            filename TEXT NOT NULL,
            recipients TEXT[] NOT NULL CHECK (array_length(recipients, 1) >= 1),
            public_key_id INTEGER,
            CONSTRAINT fk_public_key
                FOREIGN KEY (public_key_id)
                REFERENCES public_keys(id)
                ON DELETE CASCADE
        );

        INSERT INTO metadata (key, value) VALUES ('schema_version', '2');
EOF
}
