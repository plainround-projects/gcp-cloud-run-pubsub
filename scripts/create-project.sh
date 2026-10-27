#!/usr/bin/env bash
# Step 1, first half: create the project, link billing, and write the Terraform variables file.
# The budget and the key-creation policy are Terraform (modules/project-baseline).
# Needs BILLING_ACCOUNT (and optionally ORG_ID) in .env.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT in .env (gcloud billing accounts list)}"

gcloud projects create "$PROJECT_ID" ${ORG_ID:+--organization="$ORG_ID"} --labels=purpose=sandbox
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

cat >"$ENV_DIR/sandbox.tfvars" <<VARS
project_id                      = "$PROJECT_ID"
project_number                  = "$PROJECT_NUMBER"
region                          = "$REGION"
billing_account                 = "$BILLING_ACCOUNT"
budget_amount                   = ${BUDGET_AMOUNT:-10}
enforce_no_service_account_keys = $([[ -n "${ORG_ID:-}" ]] && echo true || echo false)
VARS
echo "wrote $ENV_DIR/sandbox.tfvars"
