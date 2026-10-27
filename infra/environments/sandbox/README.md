# sandbox environment

The composition for a one-day sandbox project: project baseline, three service accounts, the secret, the results bucket, the Artifact Registry repository, the worker, the Pub/Sub pipeline and the API, in dependency order. Every module is in `../../modules`.

## Variables

See `variables.tf`; `sandbox.tfvars.example` shows every value with placeholders. `scripts/create-project.sh` writes the real `sandbox.tfvars` (git-ignored). `db_password` is an ephemeral variable: export `TF_VAR_db_password` (`scripts/deploy.sh` generates a throwaway).

## Validate without credentials

```bash
cd infra/environments/sandbox
terraform init -backend=false
terraform validate
TF_VAR_db_password=placeholder GOOGLE_OAUTH_ACCESS_TOKEN=offline-placeholder \
  terraform plan -var-file=sandbox.tfvars.example     # 32 resources to add, no API call
terraform test                                       # wiring checks against a mock provider
```

The offline plan works because nothing in the configuration reads from Google Cloud (no data sources); the placeholder token only satisfies the provider's configuration.

## Apply

`scripts/deploy.sh` from the repository root; see the README's "Deploy to your own project".

## Outputs

`api_url`, `worker_url`, `results_bucket`, `image_prefix`, `service_accounts`, `topic`.

## State

Local. For shared use copy `backend.tf.example` to `backend.tf`, create the bucket (versioning on) and run `terraform init -migrate-state`.
