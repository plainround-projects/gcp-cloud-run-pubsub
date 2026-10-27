#!/usr/bin/env bash
# Step 5: remove the worker's bucket role and send a request. Wait about a minute for the removal to apply first.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
NAME="${1:-report-2}"

gcloud storage buckets remove-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$WORKER_SA" --role=roles/storage.objectCreator
echo "waiting 60 seconds for the removal to apply"
sleep 60
curl -fsS -X POST "$(api_url)/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$NAME\"}"
echo
echo "Pub/Sub now retries with backoff and dead-letters the message after 5 attempts. Run scripts/read-denial.sh in a few minutes."
