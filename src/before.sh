if [[ -v args[--database] ]]; then
    if [[ "$action" != "initialize" && "$action" != "database "* ]]; then
        psql_schema_assert_version;
    fi
fi

if [[ -v args[--trace] ]]; then
    inspect_args
    set -x
fi
