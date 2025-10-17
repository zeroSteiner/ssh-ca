data=$(psql_export "${args[fingerprint]}")

if [ -z "${data}" ]; then
  printf "[-] Invalid fingerprint: ${args[fingerprint]}\n" >&2
  exit 1
fi

echo "$data"
