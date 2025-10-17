data=$(psql_export_certificate "${args[fingerprint]}")

if [ -z "${data}" ]; then
  printf "[-] Invalid fingerprint: ${args[fingerprint]}\n" >&2
  exit 1
fi

echo "Certificate:"
echo "    Fingerprint: ${args[fingerprint]}"
ssh_print_certificate - < <(echo "$data")
