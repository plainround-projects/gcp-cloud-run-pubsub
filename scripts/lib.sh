#!/usr/bin/env bash
# Shared by the runbook scripts: loads .env and sets the variables the lesson uses in every command.
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT/infra/environments/sandbox"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"
REGION="${REGION:-europe-west1}"
BUCKET="$PROJECT_ID-results"
API_SA="api-sa@$PROJECT_ID.iam.gserviceaccount.com"
WORKER_SA="worker-sa@$PROJECT_ID.iam.gserviceaccount.com"
INVOKER_SA="pubsub-invoker@$PROJECT_ID.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID" --quiet >/dev/null

api_url() { gcloud run services describe api --region="$REGION" --format='value(status.url)'; }
worker_url() { gcloud run services describe worker --region="$REGION" --format='value(status.url)'; }

# check "what is proved" command...: runs the command and prints PASS or FAIL for the Done when line it proves.
check() {
  local what="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $what"
  else
    echo "FAIL  $what"
    FAILED=1
  fi
}
FAILED=0
