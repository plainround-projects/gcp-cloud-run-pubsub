#!/usr/bin/env bash
# Steps 2-4 in two Terraform passes: (1) everything, with Google's placeholder image so Cloud Run can start;
# (2) the same configuration with your two images. Terraform asks for confirmation before each apply.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# The database password is a throwaway. It is written to Secret Manager as a write-only value and never kept in state.
TF_VAR_db_password="${TF_VAR_db_password:-$(openssl rand -base64 18)}"
export TF_VAR_db_password

cd "$ENV_DIR" || exit 1
rm -f images.auto.tfvars
terraform init
terraform apply -var-file=sandbox.tfvars

"$ROOT/scripts/build-images.sh"
terraform apply -var-file=sandbox.tfvars

terraform output
