#!/usr/bin/env bash
# The lesson's flow on this machine: upload twice through the local API, let the emulator push to the worker,
# and list the result files in the fake bucket. Start the stack first with `make up`.
# Names carry the time of the run, so a file left by an earlier run can never satisfy this one.
set -euo pipefail

API=http://localhost:8080
GCS=http://localhost:4443
RUN="demo-$(date +%s)"

health="$(curl -fsS "$API/health")"
echo "health: $health"
[[ "$health" == '{"db_password_set":true}' ]] || { echo "the API did not receive its secret" >&2; exit 1; }

for n in 1 2; do
  reply="$(curl -fsS -X POST "$API/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$RUN-$n\"}")"
  echo "upload $RUN-$n: $reply"
done

files=""
for _ in $(seq 1 60); do
  files="$(curl -fsS "$GCS/storage/v1/b/local-results/o" | python3 -c 'import json,sys; print(" ".join(sorted(i["name"] for i in json.load(sys.stdin).get("items", []))))')"
  [[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] && break
  sleep 1
done
echo "results in gs://local-results: $files"
[[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] || { echo "the worker did not write both results" >&2; exit 1; }
