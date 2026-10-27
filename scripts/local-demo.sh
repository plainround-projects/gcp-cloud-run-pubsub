#!/usr/bin/env bash
# The lesson's flow on this machine: upload twice through the local API, let the emulator push to the worker,
# and list the result files in the fake bucket. Start the stack first with `make up`.
set -euo pipefail

API=http://localhost:8080
GCS=http://localhost:4443

echo "health: $(curl -fsS "$API/health")"
for name in report-1 report-2; do
  echo "upload $name: $(curl -fsS -X POST "$API/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$name\"}")"
done

for _ in $(seq 1 30); do
  files="$(curl -fsS "$GCS/storage/v1/b/local-results/o" | python3 -c 'import json,sys; print(" ".join(sorted(i["name"] for i in json.load(sys.stdin).get("items", []))))')"
  [[ "$files" == *report-1* && "$files" == *report-2* ]] && break
  sleep 1
done
echo "results in gs://local-results: $files"
[[ "$files" == *results/report-1.txt* && "$files" == *results/report-2.txt* ]]
