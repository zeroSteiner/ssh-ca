local current_version="$(psql_schema_current_version)"
local latest_version="$(psql_schema_latest_version)"

printf "Current schema version: $current_version\n"
printf "Latest schema version: $latest_version\n"
