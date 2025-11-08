psql_schema_assert_version() {
    local current_version="$(psql_schema_current_version)"
    local latest_version="$(psql_schema_latest_version)"

    if [ "$current_version" -ge "$latest_version" ]; then
        return
    fi

    printf "The database schema needs to be upgraded.\n" >&2
    printf "Current schema version: $current_version, latest schema version: $latest_version\n" >&2
    printf "Upgrade the schema using the \`database upgrade\` command.\n" >&2
    exit 1
}

psql_schema_current_version() {
    local version=$(_psql -tAc 'SELECT value FROM metadata WHERE key = '\''schema_version'\'' LIMIT 1;' 2> /dev/null)

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

psql_schema_latest_version() {
    local version=1
    while declare -f $(printf "initialize_schema_v%03d" "$version") > /dev/null; do
        ((version++))
    done
    echo $((version - 1))
}

psql_schema_upgrade() {
    local current_version="$(psql_schema_current_version)"
    local latest_version="$(psql_schema_latest_version)"

    if [ "$current_version" -ge "$latest_version" ]; then
        printf "The database schema is already current.\n"
        return 0
    fi

    printf "Upgrading database schema from $current_version -> $latest_version\n"

    local num_migrations=$((latest_version - current_version))

    # Run each migration in sequence
    for ((version=current_version+1; version<=latest_version; version++)); do
        local function_name=$(printf "initialize_schema_v%03d" "$version")

        echo "Running database migration: ${function_name}"
        "$function_name" &>/dev/null
    done
}
