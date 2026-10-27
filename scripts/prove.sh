#!/usr/bin/env bash
# Done when lines of steps 1-4, one check each. Exit status 1 if any check fails.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
API_URL="$(api_url)"
WORKER_URL="$(worker_url)"
NAME="report-$(date +%s)"

echo "== Step 1: budget and keys"
if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  check "a budget exists on the billing account" test -n "$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --filter="displayName:$PROJECT_ID-budget" --format='value(name)')"
fi
# Must be refused. Without an organization the constraint is not enforced; then the rule is "never create a key".
if gcloud iam service-accounts keys create /dev/null --iam-account="$API_SA" 2>/dev/null; then
  echo "FAIL  a key was created: delete it with 'gcloud iam service-accounts keys delete' and enable the policy"
  FAILED=1
else
  echo "PASS  creating a service account key is refused"
fi

echo "== Step 2: one identity each, no project-level role"
for account in "$API_SA" "$WORKER_SA" "$INVOKER_SA"; do
  check "$account holds no project-level role" test -z "$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$account" --format='value(bindings.role)')"
done
check "the topic lists only the API account as publisher" test "$(gcloud pubsub topics get-iam-policy uploads --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the secret lists only the API account" test "$(gcloud secrets get-iam-policy db-password --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the bucket lists only the worker account as object creator" test "$(gcloud storage buckets get-iam-policy "gs://$BUCKET" --flatten='bindings[].members' --filter='bindings.role:roles/storage.objectCreator' --format='value(bindings.members)')" = "serviceAccount:$WORKER_SA"

echo "== Step 3: the API"
check "the API runs as api-sa, not the default account" test "$(gcloud run services describe api --region="$REGION" --format='value(spec.template.spec.serviceAccountName)')" = "$API_SA"
check "/health reports the secret is set" test "$(curl -fsS "$API_URL/health")" = '{"db_password_set":true}'
check "POST /upload publishes a message" bash -c "curl -fsS -X POST '$API_URL/upload' -H 'Content-Type: application/json' -d '{\"name\":\"$NAME\"}' | grep -q published"

echo "== Step 4: the worker"
check "the worker runs as worker-sa" test "$(gcloud run services describe worker --region="$REGION" --format='value(spec.template.spec.serviceAccountName)')" = "$WORKER_SA"
check "a direct call to the worker without a token returns 403" test "$(curl -s -o /dev/null -w '%{http_code}' "$WORKER_URL")" = "403"
check "the upload produced results/$NAME.txt" bash -c "for _ in \$(seq 1 30); do gcloud storage ls 'gs://$BUCKET/results/$NAME.txt' && exit 0; sleep 2; done; exit 1"

echo "(project number $PROJECT_NUMBER)"
exit "$FAILED"
