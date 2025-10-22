initialize_schema_v001() {
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
