# Terraform (and its HCL language)

## 1. What it is

Terraform is a command-line tool that builds cloud infrastructure from text files. You **describe** what should exist (a bucket, a service account, a Cloud Run service) in files written in **HCL** (HashiCorp Configuration Language), and Terraform works out what to create, change or delete to make reality match. A **provider** is a plug-in that knows one platform's API; here `hashicorp/google` (version 8.8.x). A **resource** is one thing Terraform manages. The **state** is a file in which Terraform remembers what it created. This repository was built with Terraform 1.17.0 and requires 1.11 or newer.

## 2. Why this repository uses it

The lesson says "no key, one identity each, roles on resources". Written as code, those rules can be reviewed, repeated, tested without a cloud account, and removed with one command.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `infra/modules/*/` | Seven reusable pieces (`service-account`, `secret`, `results-bucket`, `pubsub-push`, `artifact-registry`, `cloud-run-service`, `project-baseline`), each with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, a README and tests. |
| `infra/environments/sandbox/` | The composition: calls the modules and wires them together. |
| `infra/environments/sandbox/sandbox.tfvars.example` | Example values. |
| `infra/environments/sandbox/.terraform.lock.hcl` | Pins the exact provider version and checksums. |
| `infra/environments/sandbox/backend.tf.example` | How to keep state in a bucket (not used by default). |
| `scripts/deploy.sh`, `create-project.sh` | Run `terraform init` and `apply`. |

## 4. How it works underneath

1. `terraform init` downloads the provider into a hidden `.terraform/` folder and records its version and hashes in `.terraform.lock.hcl`. With `-backend=false` it does not set up remote state, so it needs no credentials.
2. `terraform validate` checks that the files are well formed and the arguments exist, without contacting any cloud.
3. `terraform plan` reads the files and the **state**, asks the provider what exists, and prints what it would change: `+` create, `~` change, `-` destroy. A resource that does not exist yet needs no cloud call, which is why this repository can plan offline (it uses no `data` sources). The provider still needs *a* token to start, so `make plan` sets a placeholder `GOOGLE_OAUTH_ACCESS_TOKEN`.
4. `terraform apply` performs the plan and writes the new state. `terraform destroy` removes everything in the state.

Terraform builds a **dependency graph**: if resource B uses `A.id`, B waits for A. When two things are related without a visible reference, you add `depends_on`. Values that are only known after creation are shown as `(known after apply)`.

A **module** is a folder of Terraform files used as a function: variables in, outputs out. The environment calls modules with `module "name" { source = "..." }`.

## 5. Walkthrough of this repository's use

### Version pins

`infra/environments/sandbox/versions.tf`

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
```

`required_version` refuses an older Terraform. `required_providers` names the provider, its registry address and the allowed versions: `~> 8.8` means 8.8 or newer but below 9.0. Modules use `>= 8.0, < 9.0`, a wider window, because the environment's lock decides the exact version. The `provider "google"` block below it sets the project and region and `user_project_override`/`billing_project` so organization-level calls are billed to the sandbox project.

### Variables with checks

`infra/modules/project-baseline/variables.tf`

```hcl
variable "project_id" {
  description = "Id of the existing project to prepare."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
```

A `variable` is an input. `validation { condition = ...; error_message = ... }` runs when the plan is made: `can(regex(...))` is true when the regular expression matches. A bad value stops the plan with your message.

`infra/environments/sandbox/variables.tf`

```hcl
variable "db_password" {
  description = "Throwaway value for the db-password secret. Ephemeral: it is written to Secret Manager and not kept in the state."
  type        = string
  ephemeral   = true
  sensitive   = true
}
```

`ephemeral = true` means the value is used while Terraform runs but never saved in the plan or state; `sensitive = true` hides it in output.

### Resources, `for_each` and maps

`infra/modules/results-bucket/main.tf`

```hcl
resource "google_storage_bucket_iam_member" "creator" {
  for_each = var.creator_members

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectCreator"
  member = each.value
}
```

- `resource "TYPE" "NAME" { ... }` declares one managed thing.
- `for_each = var.creator_members` makes one copy per map entry; `each.value` is the entry's value. The map is keyed by a fixed word (`worker`) so Terraform knows the keys during planning even though the member string (an email) is only known later. Using a list of unknown values as keys would fail.
- `bucket = google_storage_bucket.this.name` is a **reference**; it creates the dependency.

### Dynamic blocks and conditions

`infra/modules/cloud-run-service/main.tf`

```hcl
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
```

`dynamic` writes a nested block once per item. `count = var.create_version ? 1 : 0` (in `modules/secret`) is the usual on/off switch: `condition ? a : b`.

### Locals and string building

`infra/modules/pubsub-push/main.tf`

```hcl
locals {
  # The Pub/Sub service agent publishes dead letters and acknowledges deliveries on the subscription's behalf.
  service_agent = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
```

`locals` are named values computed once. `"${var.project_number}"` inside a string substitutes a value.

### Composition

`infra/environments/sandbox/main.tf`

```hcl
module "api" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  name                  = "api"
  location              = var.region
  image                 = var.api_image
  service_account_email = module.api_sa.email
  labels                = var.labels
  env = {
    PROJECT_ID = var.project_id
    TOPIC_ID   = module.pipeline.topic_name
  }
  secret_env = {
    DB_PASSWORD = {
      secret  = module.db_password.secret_id
      version = "latest"
    }
  }
  invoker_members = var.api_public ? { public = "allUsers" } : {}

  depends_on = [module.baseline, module.db_password]
```

Each argument sets a module variable. `module.worker.uri` reads that module's output. `var.api_public ? { public = "allUsers" } : {}` builds the invoker map only when the API is public.

### Outputs

`infra/environments/sandbox/outputs.tf`

```hcl
output "api_url" {
  description = "URL of the API."
  value       = module.api.uri
}
```

Outputs print after `apply` and are read by other tools.

## 6. Try it yourself

```bash
terraform version
```
Expected: `Terraform v1.17.0` (1.11 or newer works).

```bash
terraform fmt -check -recursive infra; echo "exit=$?"
```
Expected: `exit=0` (all files are in canonical style; a file that is not is listed and the exit status is 3).

```bash
cd infra/environments/sandbox && terraform init -backend=false -input=false >/dev/null && terraform validate
```
Expected: `Success! The configuration is valid.`

```bash
TF_VAR_db_password=x GOOGLE_OAUTH_ACCESS_TOKEN=x terraform plan -input=false -lock=false -var-file=sandbox.tfvars.example | grep -E "^Plan"
```
Expected: `Plan: 32 to add, 0 to change, 0 to destroy.` (colors may add escape codes). Nothing is created: it is a plan.

```bash
head -8 .terraform.lock.hcl
```
Expected: the provider address `registry.terraform.io/hashicorp/google`, `version = "8.8.1"` and the constraints.

## 7. Mistakes people make

- **Putting secrets in state.** State holds every attribute. This repository uses a write-only secret value and an ephemeral variable.
- **Granting broad roles on the project.** Grant on the resource (see `iam-and-service-accounts.md`).
- **Editing the state by hand.** Use Terraform commands.
- **Using unknown values as `for_each` keys.** Key by fixed labels.
- **Committing `.terraform/` or `*.tfvars` with real ids.** `.gitignore` excludes them; only `*.tfvars.example` is tracked.
- **Not pinning the provider.** `.terraform.lock.hcl` is committed for the environment.
- **Running `apply` from an unknown directory or workspace.** The scripts `cd` into the environment first.

## 8. Check yourself

1. What does `terraform plan` change in the cloud? *Nothing; it only shows what apply would do.*
2. Why does `terraform init -backend=false` need no credentials? *It only downloads providers and sets up local files.*
3. What does `~> 8.8` allow? *8.8 and newer 8.x versions, not 9.0.*
4. What does `ephemeral = true` guarantee? *The value is not written to plan or state.*
5. Why key `for_each` maps by fixed words? *Keys must be known at plan time; emails are not.*

## 9. Further reading

- Terraform documentation (v1.17): <https://developer.hashicorp.com/terraform/docs>
- Language reference: <https://developer.hashicorp.com/terraform/language>
- Ephemeral variables: <https://developer.hashicorp.com/terraform/language/values/variables#ephemeral-variables>
- Google provider docs (8.x): <https://registry.terraform.io/providers/hashicorp/google/latest/docs>
