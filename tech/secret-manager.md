# Secret Manager

## 1. What it is

Secret Manager is Google Cloud's safe store for small secret values such as passwords and API keys. A **secret** is a named container. Each value you put in it is a numbered **version**. Access is controlled by IAM, every read is logged, and the value never has to live in code, images or configuration files.

## 2. Why this repository uses it

The lesson's API receives a "database password" from Secret Manager at start-up. There is no database; the password only proves that a secret can reach a container through the container's own identity, with no key file.

## 3. Where it appears

| Path | What it does with Secret Manager |
| --- | --- |
| `infra/modules/secret/main.tf` | Creates the secret, writes its first version, grants read access on that one secret. |
| `infra/environments/sandbox/main.tf` | Instantiates it as `db-password` and lets only `api-sa` read it. |
| `infra/modules/cloud-run-service/main.tf` | The `secret_env` variable wires a secret version into an environment variable. |
| `src/uploads/infrastructure/settings.py` | `Secret` wraps the value so it never prints. |
| `src/uploads/interfaces/api.py` | `/health` reports only whether the value is set. |
| `scripts/deploy.sh` | Generates a throwaway password with `openssl` and exports it as `TF_VAR_db_password`. |

## 4. How it works underneath

- The value is sent to Google over TLS and stored encrypted. Reading a version needs the permission `secretmanager.versions.access`, which the role `roles/secretmanager.secretAccessor` contains.
- `latest` is an alias for the newest enabled version. A Cloud Run revision reads the secret at start-up, so a new version is seen only by a new revision.
- **Write-only arguments** are a Terraform feature (1.11 and later): a value is sent to the provider but is never saved in the Terraform state file or plan. Normally anything Terraform sends is stored in state, which makes state sensitive. `secret_data_wo` is such an argument, and the variable is marked `ephemeral` so Terraform does not keep it either.

## 5. Walkthrough of this repository's use

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
```

- The first resource is the container. `replication { auto {} }` lets Google choose where copies live.
- The second creates version 1. `count = var.create_version ? 1 : 0` makes it optional. `secret_data_wo = var.secret_data` is the write-only value; `secret_data_wo_version = var.secret_version` is a counter: change the number to make Terraform write the value again.
- The third grants `secretAccessor` on this secret to each listed member. `for_each` with a map keyed by a fixed label (`api`) keeps the keys known when the plan is made.

The variable that carries the value:

`infra/modules/secret/variables.tf`

```hcl
variable "secret_data" {
  description = "The secret value. Ephemeral and sensitive: it never reaches the state file."
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
}
```

`ephemeral = true` and `sensitive = true`: not saved, not printed.

The container gets it by name, not by value:

`infra/environments/sandbox/main.tf`

```hcl
  secret_env = {
    DB_PASSWORD = {
      secret  = module.db_password.secret_id
      version = "latest"
    }
```

The helper that generates the throwaway value:

`scripts/deploy.sh`

```bash
TF_VAR_db_password="${TF_VAR_db_password:-$(openssl rand -base64 18)}"
export TF_VAR_db_password
```

## 6. Try it yourself

```bash
cd infra/modules/secret && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 3 passed, 0 failed.` (a write-only version is created, access is granted on the secret to the listed member only, and `create_version = false` creates none).

```bash
.venv/bin/python -c "from uploads.infrastructure.settings import Secret; s = Secret('hunter2'); print(s, repr(s), s.reveal())"
```
Expected: `*** Secret(***) hunter2`

```bash
grep -rn "secret_data" infra --include=*.tf | head
```
Expected: the module and the environment pass `secret_data`/`db_password`; nothing stores the value in a file.

## 7. Mistakes people make

- **Storing a password in the Terraform state.** Use a write-only argument.
- **Giving the whole project `secretAccessor`.** Grant it on the single secret.
- **Referencing `latest` before any version exists.** The Cloud Run revision cannot start.
- **Logging the value.** `Secret` prints `***`.
- **Expecting a running service to see a new version.** It needs a new revision.

## 8. Check yourself

1. What is a version? *One stored value of a secret, numbered.*
2. Which role reads a secret? *`roles/secretmanager.secretAccessor`.*
3. Why `ephemeral` plus `secret_data_wo`? *The value reaches Secret Manager but never Terraform state or plan.*
4. Who can read `db-password` here? *Only `api-sa`, on that secret.*
5. What does `secret_data_wo_version` do? *Changing it makes Terraform send the value again.*

## 9. Further reading

- Secret Manager: <https://cloud.google.com/secret-manager/docs>
- Cloud Run secrets: <https://cloud.google.com/run/docs/configuring/services/secrets>
- Terraform write-only arguments: <https://developer.hashicorp.com/terraform/language/resources/ephemeral#write-only-arguments> (Terraform 1.11 or newer)
- Resource `google_secret_manager_secret_version`: <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version>
