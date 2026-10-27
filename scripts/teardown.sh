#!/usr/bin/env bash
# Step 6, the end: delete the project. Deletion takes 30 days to complete and can be undone in that time
# (gcloud projects undelete). A budget lives on the billing account, outside the project: delete it too.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

read -r -p "Delete project $PROJECT_ID? Type the project id to confirm: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "not confirmed"; exit 1; }

if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  BUDGET="$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --filter="displayName:$PROJECT_ID-budget" --format='value(name)')"
  [[ -z "$BUDGET" ]] || gcloud billing budgets delete "$BUDGET"
fi
gcloud projects delete "$PROJECT_ID" --quiet
gcloud projects describe "$PROJECT_ID" --format='value(lifecycleState)'   # DELETE_REQUESTED
