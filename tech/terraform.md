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

## Every Terraform file, module by module

The earlier sections explained the language by examples. This part covers every file of `infra/`, so that nothing is left out. First the vocabulary that every file uses.

- A **file** ending in `.tf` is read by Terraform together with all other `.tf` files in the same folder, as one configuration. The names `main.tf`, `variables.tf`, `outputs.tf` and `versions.tf` are only a convention for what goes where.
- A **block** is `type "label" "label" { ... }`. `resource "google_folder" "this" { ... }` declares a thing to manage; `google_folder` is its type, `this` is a name you choose to refer to it (`google_folder.this`). `variable`, `output`, `locals`, `module`, `data` and `terraform` are other block types.
- An **argument** is `name = value` inside a block. Values can be text in double quotes, numbers, `true`/`false`, lists `[...]`, and maps/objects `{ key = value }`.
- A **type** says what a variable may hold: `string`, `bool`, `number`, `list(string)` (a list of texts), `map(string)` (named texts), `object({ ... })` (a fixed set of named fields of given types), and `optional(type, default)` inside an object (a field that may be left out).
- An **expression** computes a value: `var.x` reads a variable, `local.x` a local, `module.m.out` a module's output, `resource_type.name.attribute` a resource's attribute. Functions are called like `length(list)`.
- `# ...` starts a comment.

The seven modules all have the same `versions.tf`:

`infra/modules/service-account/versions.tf`

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
  }
}
```

- `required_version = ">= 1.11"`: Terraform itself must be at least 1.11.
- `required_providers` says which plug-in provides the resources: `source = "hashicorp/google"` is its address in the public registry; `version = ">= 8.0, < 9.0"` allows any 8.x release. A module declares a window, and the environment's `~> 8.8` and lock file choose the exact version.

### Module `service-account`

`infra/modules/service-account/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the service account."
  type        = string
}

variable "account_id" {
  description = "Account id, the part before the @ (6-30 characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "account_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "display_name" {
  description = "Human-readable name."
  type        = string
}

variable "description" {
  description = "What this identity is for and what it may touch."
  type        = string
}
```

`account_id` is the part before the `@` of the email; the check allows 6 to 30 characters, lowercase letters, digits and hyphens, starting with a letter. `display_name` and `description` are plain texts; the description says what the identity may touch.

`infra/modules/service-account/main.tf`

```hcl
# No google_service_account_key anywhere in this repository: workloads use the credentials the platform gives them.
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}
```

One resource: `google_service_account`. The comment states the rule: no key resource exists anywhere; workloads use the credentials the platform gives them (see `iam-and-service-accounts.md`).

`infra/modules/service-account/outputs.tf`

```hcl
output "email" {
  description = "Service account email."
  value       = google_service_account.this.email
}

output "member" {
  description = "IAM member string, serviceAccount:EMAIL."
  value       = "serviceAccount:${google_service_account.this.email}"
}

output "name" {
  description = "Full resource name, projects/PROJECT/serviceAccounts/EMAIL."
  value       = google_service_account.this.name
}
```

`email`, the IAM member text `serviceAccount:EMAIL` (`"serviceAccount:${...}"` inserts the email into a string), and the full resource name.

### Module `project-baseline`

`infra/modules/project-baseline/variables.tf`

```hcl
variable "project_id" {
  description = "Id of the existing project to prepare."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "project_number" {
  description = "Number of the project (gcloud projects describe PROJECT_ID --format='value(projectNumber)'); the budget filters on it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must contain digits only."
  }
}

variable "services" {
  description = "APIs to enable."
  type        = list(string)
}

variable "billing_account" {
  description = "Billing account id for the budget (gcloud billing accounts list). Empty skips the budget."
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget in whole units of budget_currency."
  type        = number
  default     = 10

  validation {
    condition     = var.budget_amount > 0 && floor(var.budget_amount) == var.budget_amount
    error_message = "budget_amount must be a positive whole number."
  }
}

variable "budget_currency" {
  description = "ISO 4217 currency code of the billing account."
  type        = string
  default     = "USD"
}

variable "budget_thresholds" {
  description = "Fractions of the budget that send an alert (0.5 is 50 percent)."
  type        = list(number)
  default     = [0.5, 0.9, 1.0]

  validation {
    condition     = alltrue([for t in var.budget_thresholds : t > 0 && t <= 1.5])
    error_message = "Each threshold must be above 0 and at most 1.5."
  }
}

variable "enforce_no_service_account_keys" {
  description = "Enforce iam.disableServiceAccountKeyCreation on the project. Requires an organization; without one, leave false and follow the rule by hand."
  type        = bool
  default     = false
}
```

- `project_id`, `project_number`: the ids; the number must be digits only.
- `services`: the APIs to enable. `billing_account` defaults to `""`, which skips the budget.
- `budget_amount`: default 10; `floor(var.budget_amount) == var.budget_amount` is true only for a whole number. `budget_currency` defaults to `USD`. `budget_thresholds` is a list of numbers (`list(number)`); default `[0.5, 0.9, 1.0]` means alerts at 50, 90 and 100 percent; each must be above 0 and at most 1.5.
- `enforce_no_service_account_keys`: default false because the organization policy needs an organization.

`infra/modules/project-baseline/main.tf`

```hcl
resource "google_project_service" "enabled" {
  for_each = toset(var.services)

  project = var.project_id
  service = each.value

  # Leaving an API enabled on destroy avoids breaking other things in a shared project.
  disable_on_destroy = false
}

resource "google_billing_budget" "this" {
  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account
  display_name    = "${var.project_id}-budget"

  budget_filter {
    projects = ["projects/${var.project_number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_thresholds
    content {
      threshold_percent = threshold_rules.value
    }
  }

  depends_on = [google_project_service.enabled]
}

# Blocks the creation of downloadable service account keys. Needs the project to sit under an organization.
resource "google_org_policy_policy" "no_service_account_keys" {
  count = var.enforce_no_service_account_keys ? 1 : 0

  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.enabled]
}
```

- `google_project_service.enabled` enables each API (`for_each = toset(var.services)`); `disable_on_destroy = false` leaves them on when Terraform lets go.
- `google_billing_budget.this` has `count = var.billing_account == "" ? 0 : 1`: no billing account, no budget. `budget_filter` limits it to this project (`projects/NUMBER`), `amount.specified_amount` sets the currency and the whole units (`tostring` turns the number into the text the API wants), and the `dynamic "threshold_rules"` block writes one alert rule per threshold. See `budgets-and-organization-policy.md`.
- `google_org_policy_policy.no_service_account_keys` is created only when asked (`count`); `enforce = "TRUE"` (text, as the provider requires) blocks service account key creation.
- `depends_on = [google_project_service.enabled]` makes both wait for the APIs.

`infra/modules/project-baseline/outputs.tf`

```hcl
output "enabled_services" {
  description = "APIs enabled by this module."
  value       = sort([for s in google_project_service.enabled : s.service])
}

output "budget_name" {
  description = "Resource name of the budget, or null when no billing account was given."
  value       = one(google_billing_budget.this[*].name)
}

output "key_creation_blocked" {
  description = "Whether the organization policy that blocks service account keys is enforced by this module."
  value       = var.enforce_no_service_account_keys
}
```

`one(google_billing_budget.this[*].name)` returns the budget's name or `null` when there are zero copies (`[*]` turns zero-or-one copies into a list; `one` takes the single element).

### Module `secret`

`infra/modules/secret/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the secret."
  type        = string
}

variable "secret_id" {
  description = "Secret name."
  type        = string
}

variable "labels" {
  description = "Labels for the secret."
  type        = map(string)
  default     = {}
}

variable "accessor_members" {
  description = "IAM members that may read this one secret (roles/secretmanager.secretAccessor, on the secret, not the project), keyed by a fixed label."
  type        = map(string)
  default     = {}
}

variable "create_version" {
  description = "Write a first version from secret_data. Set false to add versions outside Terraform."
  type        = bool
  default     = true
}

variable "secret_data" {
  description = "The secret value. Ephemeral and sensitive: it never reaches the state file."
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
}

variable "secret_version" {
  description = "Counter that tells Terraform to write secret_data again."
  type        = number
  default     = 1
}
```

- `accessor_members`: who may read this one secret, keyed by a fixed label.
- `create_version`: write a first version from `secret_data`.
- `secret_data` is **`ephemeral = true`** and **`sensitive = true`**: an ephemeral value exists only while Terraform runs and is never written to the plan or the state; a sensitive value is hidden in output. Its default is `null`.
- `secret_version` is a counter: changing it tells Terraform to write the secret again.

`infra/modules/secret/main.tf`

```hcl
resource "google_secret_manager_secret" "this" {
  project   = var.project_id
  secret_id = var.secret_id
  labels    = var.labels

  replication {
    auto {}
  }
}

# The value is a write-only argument: it is sent to Secret Manager and never stored in the Terraform state or plan.
# Bump secret_version to write a new version.
resource "google_secret_manager_secret_version" "this" {
  count = var.create_version ? 1 : 0

  secret                 = google_secret_manager_secret.this.id
  secret_data_wo         = var.secret_data
  secret_data_wo_version = var.secret_version
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.accessor_members

  project   = var.project_id
  secret_id = google_secret_manager_secret.this.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}
```

- `replication { auto {} }` lets Google choose where the secret is stored.
- The version uses `secret_data_wo`, a **write-only** argument: the provider sends it to Secret Manager and keeps no copy in the state; `secret_data_wo_version` is the counter that triggers a new write. `count = var.create_version ? 1 : 0` makes the resource optional. See `secret-manager.md`.
- The IAM binding gives `roles/secretmanager.secretAccessor` to each member on this secret only.

`infra/modules/secret/outputs.tf`

```hcl
output "secret_id" {
  description = "Secret name, as Cloud Run refers to it."
  value       = google_secret_manager_secret.this.secret_id
}

output "id" {
  description = "Full resource id, projects/PROJECT/secrets/NAME."
  value       = google_secret_manager_secret.this.id
}

output "accessor_members" {
  description = "Members granted access to this secret."
  value       = sort(values(var.accessor_members))
}
```

### Module `results-bucket`

`infra/modules/results-bucket/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the bucket."
  type        = string
}

variable "name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters: lowercase letters, digits, dot, underscore and hyphen."
  }
}

variable "location" {
  description = "Bucket location, for example europe-west1."
  type        = string
}

variable "labels" {
  description = "Labels for the bucket."
  type        = map(string)
  default     = {}
}

variable "creator_members" {
  description = "IAM members that may create objects in this bucket and nothing else, keyed by a fixed label (the keys must be known at plan time, the members need not be)."
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Days after which result files are deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "force_destroy" {
  description = "Delete the bucket even when it holds objects. True only for a sandbox."
  type        = bool
  default     = false
}
```

The name rule is Google's bucket-name rule. `creator_members` maps a fixed label to a member. `retention_days` defaults to 30 and must be at least 1. `force_destroy` is true only in a sandbox.

`infra/modules/results-bucket/main.tf`

```hcl
resource "google_storage_bucket" "this" {
  #checkov:skip=CKV_GCP_62:A one-day sandbox needs no separate access-log bucket; Cloud Audit Logs record administrative activity. Add a log bucket before real use
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

# objectCreator creates objects but cannot read, overwrite or delete them. The bucket is the only place it is granted.
resource "google_storage_bucket_iam_member" "creator" {
  for_each = var.creator_members

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectCreator"
  member = each.value
}
```

- `uniform_bucket_level_access`, `public_access_prevention = "enforced"` and `versioning` are explained in `cloud-storage.md`.
- Two `lifecycle_rule` blocks delete objects: those older than `retention_days`, and old versions seven days after they stopped being current (`days_since_noncurrent_time`).
- The IAM binding gives `roles/storage.objectCreator`: create objects, but not read, overwrite or delete. The comment says it is granted only here.
- The `#checkov:skip` comment records why the access-log check does not apply (see `checkov.md`).

`infra/modules/results-bucket/outputs.tf`

```hcl
output "name" {
  description = "Bucket name."
  value       = google_storage_bucket.this.name
}

output "url" {
  description = "gs:// URL of the bucket."
  value       = google_storage_bucket.this.url
}

output "creator_members" {
  description = "Members that may create objects."
  value       = sort(values(var.creator_members))
}
```

### Module `artifact-registry`

`infra/modules/artifact-registry/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the repository."
  type        = string
}

variable "location" {
  description = "Region of the repository."
  type        = string
}

variable "repository_id" {
  description = "Repository name."
  type        = string
}

variable "keep_count" {
  description = "Number of most recent image versions the cleanup policy always keeps."
  type        = number
  default     = 5
}

variable "labels" {
  description = "Labels for the repository."
  type        = map(string)
  default     = {}
}
```

`infra/modules/artifact-registry/main.tf`

```hcl
resource "google_artifact_registry_repository" "this" {
  #checkov:skip=CKV_GCP_84:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Container images for the upload API and worker."
  labels        = var.labels

  docker_config {
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_count
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }
}
```

`format = "DOCKER"` makes a repository for container images. `docker_config { immutable_tags = true }` means a tag, once pushed, cannot be moved to another image. The two `cleanup_policies` keep the most recent `keep_count` versions and delete anything older than 30 days (`2592000s`); `cleanup_policy_dry_run = false` makes them real. See `artifact-registry.md`.

`infra/modules/artifact-registry/outputs.tf`

```hcl
output "image_prefix" {
  description = "Prefix for image names: LOCATION-docker.pkg.dev/PROJECT/REPOSITORY."
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}

output "repository_id" {
  description = "Repository name."
  value       = google_artifact_registry_repository.this.repository_id
}
```

`image_prefix` builds the address images are pushed to: `LOCATION-docker.pkg.dev/PROJECT/REPOSITORY`.

### Module `cloud-run-service`

`infra/modules/cloud-run-service/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the service."
  type        = string
}

variable "name" {
  description = "Service name."
  type        = string
}

variable "location" {
  description = "Region."
  type        = string
}

variable "image" {
  description = "Container image to run."
  type        = string
}

variable "service_account_email" {
  description = "Identity the service runs as. Required: the default compute account is never used."
  type        = string
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Environment variables filled from Secret Manager: name => { secret, version }."
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}

variable "invoker_members" {
  description = "Members that may call the service, keyed by a fixed label. Empty keeps it private to IAM; allUsers makes it public."
  type        = map(string)
  default     = {}
}

variable "ingress" {
  description = "Ingress setting of the service."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.ingress)
    error_message = "ingress must be INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU limit per instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance."
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Instances kept warm. Zero scales to zero and costs nothing idle."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Upper bound on instances, which also bounds the bill."
  type        = number
  default     = 3
}

variable "concurrency" {
  description = "Requests one instance handles at once."
  type        = number
  default     = 20
}

variable "request_timeout_seconds" {
  description = "Request timeout."
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Refuse to delete the service. False in a sandbox so the teardown works."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels for the service."
  type        = map(string)
  default     = {}
}
```

- Required: `project_id`, `name`, `location`, `image`, `service_account_email` (the description says the default compute account is never used).
- `env` is a map of plain environment variables; `secret_env` is a map of objects `{ secret, version }` for variables filled from Secret Manager; `invoker_members` is a map of who may call the service.
- `ingress` is limited to three words. `container_port` (8080), `cpu` (`"1"`), `memory` (`"512Mi"`), `min_instances` (0: scale to zero), `max_instances` (3: also a limit on the bill), `concurrency` (20 requests per instance), `request_timeout_seconds` (60), `deletion_protection` (false in a sandbox) and `labels`.

`infra/modules/cloud-run-service/main.tf`

```hcl
resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels

  ingress             = var.ingress
  deletion_protection = var.deletion_protection

  template {
    # The service's own identity. Leaving this out would run the service as the default compute account.
    service_account = var.service_account_email
    timeout         = "${var.request_timeout_seconds}s"

    max_instance_request_concurrency = var.concurrency

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = true
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Cloud Run reads the secret with the service's own identity at start-up.
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

# Invoker access is granted on this one service. allUsers appears only when the caller asks for a public service.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.invoker_members

  project  = var.project_id
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
```

See `cloud-run.md` for the service itself. In Terraform terms: `template` holds the settings of each revision; `service_account` sets the identity; `timeout` takes a text such as `"60s"`; `scaling` bounds the instance count; `containers` holds the image, `ports`, `resources` (limits, and `cpu_idle = true` to charge CPU only while handling requests); the first `dynamic "env"` writes one variable per map entry (`env.key`, `env.value`); the second writes variables whose `value_source.secret_key_ref` points at a secret and version. The invoker resource grants `roles/run.invoker` on this one service.

`infra/modules/cloud-run-service/outputs.tf`

```hcl
output "uri" {
  description = "HTTPS URL of the service."
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  description = "Service name."
  value       = google_cloud_run_v2_service.this.name
}

output "service_account_email" {
  description = "Identity the service runs as."
  value       = var.service_account_email
}

output "invoker_members" {
  description = "Members granted roles/run.invoker on this service."
  value       = sort(values(var.invoker_members))
}
```

### Module `pubsub-push`

`infra/modules/pubsub-push/variables.tf`

```hcl
variable "project_id" {
  description = "Project that owns the topics and subscriptions."
  type        = string
}

variable "project_number" {
  description = "Project number; the Pub/Sub service agent's email contains it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must contain digits only."
  }
}

variable "topic_name" {
  description = "Name of the main topic; the dead-letter topic and the subscriptions derive their names from it."
  type        = string
}

variable "push_endpoint" {
  description = "HTTPS URL that receives each message."
  type        = string

  validation {
    condition     = startswith(var.push_endpoint, "https://")
    error_message = "push_endpoint must be an https URL."
  }
}

variable "oidc_audience" {
  description = "Audience claim of the OIDC token; for Cloud Run, the service URL."
  type        = string
}

variable "invoker_service_account_email" {
  description = "Account whose OIDC token Pub/Sub sends. Give it roles/run.invoker on the receiving service only."
  type        = string
}

variable "publisher_members" {
  description = "IAM members that may publish to the main topic (granted on the topic, not the project), keyed by a fixed label."
  type        = map(string)
  default     = {}
}

variable "max_delivery_attempts" {
  description = "Attempts before a message goes to the dead-letter topic (5 to 100)."
  type        = number
  default     = 5

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100."
  }
}

variable "ack_deadline_seconds" {
  description = "Seconds the worker has to answer before Pub/Sub redelivers."
  type        = number
  default     = 30
}

variable "minimum_backoff" {
  description = "Shortest wait before a retry."
  type        = string
  default     = "10s"
}

variable "maximum_backoff" {
  description = "Longest wait before a retry."
  type        = string
  default     = "120s"
}

variable "labels" {
  description = "Labels for topics and subscriptions."
  type        = map(string)
  default     = {}
}
```

`push_endpoint` must start with `https://` (`startswith`). `max_delivery_attempts` is between 5 and 100. `ack_deadline_seconds` (30) is how long the worker has to answer before Pub/Sub redelivers. `minimum_backoff` (`10s`) and `maximum_backoff` (`120s`) bound the wait between retries.

`infra/modules/pubsub-push/main.tf`

```hcl
locals {
  # The Pub/Sub service agent publishes dead letters and acknowledges deliveries on the subscription's behalf.
  service_agent = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "main" {
  #checkov:skip=CKV_GCP_83:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project = var.project_id
  name    = var.topic_name
  labels  = var.labels
}

resource "google_pubsub_topic" "dead_letter" {
  #checkov:skip=CKV_GCP_83:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project = var.project_id
  name    = "${var.topic_name}-dead"
  labels  = var.labels
}

# Pull subscription on the dead-letter topic so a failed message can be read and replayed.
resource "google_pubsub_subscription" "dead_letter_pull" {
  project = var.project_id
  name    = "${var.topic_name}-dead-pull"
  topic   = google_pubsub_topic.dead_letter.id
  labels  = var.labels

  message_retention_duration = "604800s"
  ack_deadline_seconds       = 20

  expiration_policy {
    ttl = "" # never expires
  }
}

resource "google_pubsub_subscription" "push" {
  project = var.project_id
  name    = "${var.topic_name}-push"
  topic   = google_pubsub_topic.main.id
  labels  = var.labels

  ack_deadline_seconds = var.ack_deadline_seconds

  push_config {
    push_endpoint = var.push_endpoint

    # Pub/Sub signs a token for the invoker account; Cloud Run checks it. The invoker holds run.invoker on the worker only.
    oidc_token {
      service_account_email = var.invoker_service_account_email
      audience              = var.oidc_audience
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = var.minimum_backoff
    maximum_backoff = var.maximum_backoff
  }

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = var.publisher_members

  project = var.project_id
  topic   = google_pubsub_topic.main.name
  role    = "roles/pubsub.publisher"
  member  = each.value
}

resource "google_pubsub_topic_iam_member" "agent_publishes_dead_letters" {
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter.name
  role    = "roles/pubsub.publisher"
  member  = local.service_agent
}

resource "google_pubsub_subscription_iam_member" "agent_acknowledges" {
  project      = var.project_id
  subscription = google_pubsub_subscription.push.name
  role         = "roles/pubsub.subscriber"
  member       = local.service_agent
}

# Needed for projects whose Pub/Sub API was enabled after April 2021: the agent mints the invoker's OIDC token.
resource "google_service_account_iam_member" "agent_signs_invoker_token" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.invoker_service_account_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.service_agent
}
```

- `locals.service_agent` is the Google-run identity that Pub/Sub uses, whose email contains the project **number**.
- Two topics (`main`, and `dead_letter` named `NAME-dead`); a pull subscription on the dead-letter topic with seven days of retention and `ttl = ""` (never expires) so a failed message can be read and replayed; and the push subscription with `push_config`, `oidc_token`, `dead_letter_policy` and `retry_policy` (see `cloud-pubsub.md`).
- Four IAM bindings: the publishers on the main topic; the service agent may publish dead letters and acknowledge deliveries; and `agent_signs_invoker_token` lets the agent create the invoker's OIDC token (`roles/iam.serviceAccountTokenCreator` on that account).

`infra/modules/pubsub-push/outputs.tf`

```hcl
output "topic_name" {
  description = "Name of the main topic."
  value       = google_pubsub_topic.main.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead-letter topic."
  value       = google_pubsub_topic.dead_letter.name
}

output "push_subscription_name" {
  description = "Name of the push subscription."
  value       = google_pubsub_subscription.push.name
}

output "dead_letter_subscription_name" {
  description = "Name of the pull subscription on the dead-letter topic."
  value       = google_pubsub_subscription.dead_letter_pull.name
}

output "publisher_members" {
  description = "Members granted the publisher role on the main topic."
  value       = sort(values(var.publisher_members))
}
```

### The `sandbox` environment

`infra/environments/sandbox/main.tf`

```hcl
locals {
  services = [
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

module "baseline" {
  source = "../../modules/project-baseline"

  project_id                      = var.project_id
  project_number                  = var.project_number
  services                        = local.services
  billing_account                 = var.billing_account
  budget_amount                   = var.budget_amount
  enforce_no_service_account_keys = var.enforce_no_service_account_keys
}

# One identity per workload. None of them holds a project-level role.
module "api_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "api-sa"
  display_name = "Upload API"
  description  = "Runs the API. Publishes to the uploads topic and reads the db-password secret, nothing else."

  depends_on = [module.baseline]
}

module "worker_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "worker-sa"
  display_name = "Upload worker"
  description  = "Runs the worker. Creates objects in the results bucket, nothing else."

  depends_on = [module.baseline]
}

module "invoker_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "pubsub-invoker"
  display_name = "Pub/Sub invoker"
  description  = "Identity of the OIDC token Pub/Sub sends. Holds run.invoker on the worker only."

  depends_on = [module.baseline]
}

module "db_password" {
  source = "../../modules/secret"

  project_id       = var.project_id
  secret_id        = "db-password"
  labels           = var.labels
  accessor_members = { api = module.api_sa.member }
  secret_data      = var.db_password

  depends_on = [module.baseline]
}

module "results" {
  source = "../../modules/results-bucket"

  project_id      = var.project_id
  name            = "${var.project_id}-results"
  location        = var.region
  labels          = var.labels
  creator_members = { worker = module.worker_sa.member }
  force_destroy   = true

  depends_on = [module.baseline]
}

module "registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  location      = var.region
  repository_id = "uploads"
  labels        = var.labels

  depends_on = [module.baseline]
}

module "worker" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  name                  = "worker"
  location              = var.region
  image                 = var.worker_image
  service_account_email = module.worker_sa.email
  labels                = var.labels
  env = {
    BUCKET     = module.results.name
    PROJECT_ID = var.project_id
  }
  invoker_members = { pubsub = module.invoker_sa.member }

  depends_on = [module.baseline]
}

module "pipeline" {
  source = "../../modules/pubsub-push"

  project_id                    = var.project_id
  project_number                = var.project_number
  topic_name                    = "uploads"
  push_endpoint                 = "${module.worker.uri}/"
  oidc_audience                 = module.worker.uri
  invoker_service_account_email = module.invoker_sa.email
  publisher_members             = { api = module.api_sa.member }
  labels                        = var.labels

  depends_on = [module.baseline]
}

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
}
```

- `locals.services`: the ten APIs the sandbox needs.
- `baseline` first, then every other module `depends_on = [module.baseline]` so the APIs are on before anything is created.
- Three service accounts, one per workload, none with a project-level role: `api-sa`, `worker-sa`, `pubsub-invoker`.
- `db_password` creates the secret and lets only the API read it; `secret_data = var.db_password` passes the ephemeral value.
- `results` creates the bucket and lets only the worker create objects; `registry` creates the image repository.
- `worker` is a Cloud Run service with two plain variables and the invoker `pubsub-invoker`. `pipeline` wires Pub/Sub to the worker: the push endpoint is the worker's URL with a `/`, the OIDC audience is the URL itself, the API's identity may publish. `api` is the other service: its plain variables, one secret variable (`DB_PASSWORD` from the secret's `latest` version), and `invoker_members = var.api_public ? { public = "allUsers" } : {}`, a conditional that makes the API public only when asked.
- The order in the file is for reading; Terraform orders by references and `depends_on`.

`infra/environments/sandbox/variables.tf`

```hcl
variable "project_id" {
  description = "Id of the sandbox project (created by scripts/create-project.sh)."
  type        = string
}

variable "project_number" {
  description = "Number of the sandbox project."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and the bucket."
  type        = string
  default     = "europe-west1"
}

variable "billing_account" {
  description = "Billing account id for the budget alert. Empty skips the budget."
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget in whole units of the billing account's currency."
  type        = number
  default     = 10
}

variable "enforce_no_service_account_keys" {
  description = "Enforce the organization policy that blocks key creation. Needs an organization."
  type        = bool
  default     = false
}

variable "api_image" {
  description = "Image of the API. The placeholder lets the first apply succeed before your image exists."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "worker_image" {
  description = "Image of the worker. The placeholder lets the first apply succeed before your image exists."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_public" {
  description = "Let anyone call the API (the exercise does). The worker is never public."
  type        = bool
  default     = true
}

variable "db_password" {
  description = "Throwaway value for the db-password secret. Ephemeral: it is written to Secret Manager and not kept in the state."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "labels" {
  description = "Labels applied to every resource that supports them."
  type        = map(string)
  default = {
    environment = "sandbox"
    project     = "gcp-cloud-run-pubsub"
    managed-by  = "terraform"
  }
}
```

`api_image` and `worker_image` default to Google's public `hello` image, so the first apply works before your images exist. `api_public` defaults to true because the exercise calls the API from outside; the worker is never public. `db_password` is `ephemeral` and `sensitive` with no default: Terraform will not plan without it, and it never reaches the state.

`infra/environments/sandbox/outputs.tf`

```hcl
output "api_url" {
  description = "URL of the API."
  value       = module.api.uri
}

output "worker_url" {
  description = "URL of the worker; a call without a token returns 403."
  value       = module.worker.uri
}

output "results_bucket" {
  description = "Bucket that receives results/NAME.txt."
  value       = module.results.name
}

output "image_prefix" {
  description = "Where scripts/build-images.sh pushes the two images."
  value       = module.registry.image_prefix
}

output "service_accounts" {
  description = "The three identities."
  value = {
    api     = module.api_sa.email
    worker  = module.worker_sa.email
    invoker = module.invoker_sa.email
  }
}

output "topic" {
  description = "Main topic and its dead-letter companions."
  value = {
    topic             = module.pipeline.topic_name
    dead_letter_topic = module.pipeline.dead_letter_topic_name
    push_subscription = module.pipeline.push_subscription_name
    dead_letter_pull  = module.pipeline.dead_letter_subscription_name
  }
}
```

`infra/environments/sandbox/versions.tf`

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
  }

  # Local state is enough for a one-day sandbox. For shared use, add a gcs backend (see backend.tf.example).
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Budgets and organization policies are charged to a quota project; use the sandbox project itself.
  user_project_override = true
  billing_project       = var.project_id
}
```

This environment needs Terraform 1.11 or newer because the write-only argument and the ephemeral variable are newer features. `user_project_override = true` with `billing_project` makes budget and policy calls count against the sandbox project itself.

`infra/environments/sandbox/sandbox.tfvars.example`

```hcl
# Copy to sandbox.tfvars and edit. The values below are placeholders; `make plan` uses this file as it is.
project_id      = "example-sandbox-0000"
project_number  = "000000000000"
region          = "europe-west1"
billing_account = "AAAAAA-BBBBBB-CCCCCC" # gcloud billing accounts list; leave "" to skip the budget
budget_amount   = 10

# true only when the project sits under an organization; otherwise follow the rule by hand (README, step 1).
enforce_no_service_account_keys = false

# After scripts/build-images.sh, deploy.sh passes your images; these are the placeholders for the first apply.
# api_image    = "europe-west1-docker.pkg.dev/PROJECT/uploads/api:TAG"
# worker_image = "europe-west1-docker.pkg.dev/PROJECT/uploads/worker:TAG"

# db_password is not set here. Export TF_VAR_db_password (scripts/deploy.sh generates a throwaway one).
```

A `.tfvars` file gives values to variables. This example is what `make plan` uses, with placeholder ids. The two commented image lines show what `deploy.sh` passes after the images are built. `db_password` is deliberately absent: it comes from the environment variable `TF_VAR_db_password` (any variable `TF_VAR_name` fills the variable `name`).

`infra/environments/sandbox/backend.tf.example`

```hcl
# Copy to backend.tf for remote state. The bucket is created by hand, with versioning, before `terraform init`.
terraform {
  backend "gcs" {
    bucket = "EXAMPLE-terraform-state"
    prefix = "gcp-cloud-run-pubsub/sandbox"
  }
}
```

A **backend** says where the state file lives. By default it is local; `backend "gcs"` keeps it in a bucket. The file ends in `.example` so Terraform ignores it.

### The lock file

`infra/environments/sandbox/.terraform.lock.hcl`

```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/google" {
  version     = "8.8.1"
  constraints = ">= 8.0.0, ~> 8.8, < 9.0.0"
  hashes = [
    "h1:cj2w8+P7qqGDbhG+PIJcXmtu0CMBNLqdTNLpLgvhJrw=",
    "zh:1510c0a5ec95676bf9df8f4c4798eb21f1ddb49f1d0bfc52e323fcdec5240bad",
    "zh:18122322d83564567bfa8c4075f1b33263bf30217345c4cf967e5d9fb7df6134",
    "zh:3468de1e43ad4bee6d5191c23be7dbb39f6c1559027c598f99869f7e7fe180ba",
    "zh:55bfd12669b8dd9913e5ee00df060c3f53c2976a92291262c02eaa0504e6b5d4",
    "zh:5b643a92495934a22c594aca095eace27c817d83ef896042e4360b87216285df",
    "zh:5e9326c8392700c2d8a998b19ff253b7fcbe01a39e14c5518233da1b98d4d99b",
    "zh:9522b2ed7cd335488c7a91509bb70cf134a318b697c38255ed184209d11f0436",
    "zh:a55f6fb2f998b39dad5bb107c4c1b7ff022aa54cc77fe31e98d3ae8894833ce4",
    "zh:a7509f8d1db99156bbf1b72e1acc25ccf093a8fd4af264464e1b054e90a87eb8",
    "zh:b3ad9d84fc076f71cdd1574ca417e7b565b79a2d1e7afcc5ec211f1aaa8c0227",
    "zh:f569b65999264a9416862bca5cd2a6177d94ccb0424f3a4ef424428912b9cb3c",
    "zh:fd2a9f9741792a11d7f1fa9affe080c8b40b93e5f6a0b61cb25dfcd9c87dc44e",
  ]
}
```

`terraform init` writes this file. It records the exact provider version chosen and `hashes`, fingerprints of the provider's package, so a tampered download is refused. Commit it so everybody gets the same provider.

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
