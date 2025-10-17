printf "Upserting SSH public key..."
psql_upsert_public_key "${args[public-key]}" "${args[--description]:-}" > /dev/null
printf " done.\n"
