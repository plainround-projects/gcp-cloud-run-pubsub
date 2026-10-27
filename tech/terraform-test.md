# `terraform test` (native Terraform tests)

## 1. What it is

`terraform test` is a built-in Terraform command that runs test files ending in `.tftest.hcl`. Each file contains `run` blocks. A run executes a plan (or an apply) with chosen variable values and then checks **assertions**: true/false conditions about the result. With a **mock provider** the whole thing runs offline: Terraform pretends to be Google instead of calling it. The feature needs Terraform 1.7 or newer (mock providers) and is used here with 1.17.

## 2. Why this repository uses it

The "no credentials needed" rule: the least-privilege wiring (who gets which role on what) can be tested on a laptop. A test fails if a module grants the wrong role, a bad variable is accepted, or a setting regresses.

## 3. Where it appears

| Path | What it checks |
| --- | --- |
| `infra/modules/results-bucket/tests/bucket.tftest.hcl` | Private bucket, only `objectCreator` for given members, bad names rejected. |
| `infra/modules/pubsub-push/tests/pipeline.tftest.hcl` | OIDC token, 5 attempts, service agent grants, `https` only. |
| `infra/modules/cloud-run-service/tests/service.tftest.hcl` | Runs as the given account; private by default; secrets by reference. |
| `infra/modules/secret/tests/secret.tftest.hcl` | Write-only value; access on the secret only. |
| `infra/modules/project-baseline/tests/baseline.tftest.hcl` | Budget and key policy switches. |
| `infra/environments/sandbox/tests/wiring.tftest.hcl` | Three different identities; only the worker creates objects; only the API publishes. |
| `Makefile` | `test-terraform` loops over every folder that has a `tests/` directory. |

## 4. How it works underneath

Terraform loads the module in the current folder, applies the test's `variables`, and for each `run` makes a plan (`command = plan`) in memory. `mock_provider "google" {}` replaces the real provider: computed attributes (emails, URLs, ids) get random placeholder values, and nothing leaves your machine. Assertions are evaluated against resource attributes (inside a module under test) or module outputs (from an environment). `expect_failures = [var.name]` states that this run *should* fail validation of that variable; the run passes only if it does.

Two limits shape the tests: placeholders are random strings, so an assertion cannot compare an email to a literal; and a list in a variable differs from a tuple literal, so comparisons use `tolist(...)` or `jsonencode(...)`.

## 5. Walkthrough of this repository's use

`infra/modules/results-bucket/tests/bucket.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id      = "example-sandbox-0000"
  name            = "example-sandbox-0000-results"
  location        = "europe-west1"
  creator_members = { worker = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "bucket_is_private_and_uniform" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access && google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "The bucket must use uniform access and block public access."
  }
}

run "only_the_creator_role_is_granted_and_only_to_the_given_members" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_member.creator) == 1 && alltrue([for b in google_storage_bucket_iam_member.creator : b.role == "roles/storage.objectCreator"])
    error_message = "Exactly one binding with roles/storage.objectCreator is expected."
  }
}

run "no_members_means_no_bindings" {
```

- `mock_provider "google" {}`: use the fake provider.
- `variables { ... }` at the top gives defaults to every run.
- `run "name" { command = plan; assert { condition = ...; error_message = ... } }`: one test. `condition` is any expression; the run fails with the message if it is false. `length(...)`, `alltrue([for ... : ...])` and `==` are the usual tools.

A rejection test:

`infra/modules/results-bucket/tests/bucket.tftest.hcl`

```hcl
run "a_bad_bucket_name_is_rejected" {
  command = plan

  variables {
    name = "Bad_Name"
  }
```

The environment test fixes the fake identities so emails can be compared:

`infra/environments/sandbox/tests/wiring.tftest.hcl`

```hcl
mock_provider "google" {}

override_module {
  target = module.api_sa
  outputs = {
    email  = "api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/api-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.worker_sa
  outputs = {
    email  = "worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.invoker_sa
  outputs = {
    email  = "pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_resource {
```

`override_module` replaces a module's outputs with fixed values; `override_resource` fixes attributes of one resource during `plan`. Then:

`infra/environments/sandbox/tests/wiring.tftest.hcl`

```hcl
run "only_the_worker_account_creates_objects_and_only_the_invoker_calls_the_worker" {
  command = plan

  assert {
    condition     = module.results.creator_members == tolist([module.worker_sa.member]) && module.worker.invoker_members == tolist([module.invoker_sa.member])
    error_message = "Bucket creator is the worker account; worker invoker is the invoker account."
  }
```

`tolist([...])` makes the literal the same type as the module output.

## Every test file, run by run

Words used below. A **`run` block** is one test. `command = plan` makes the plan in memory and checks it; no resource is created anywhere. An **`assert` block** has a `condition` (must be true) and an `error_message`. `&&` means "and". A `variables` block at the top of a file sets the inputs of every run; one inside a run replaces some of them for that run only. `expect_failures = [var.name]` makes a run pass only if that variable's `validation` rejects the value. `mock_provider "google" {}` replaces the real provider with a fake one, so nothing contacts Google. Two modules have no tests of their own: `service-account` (one resource, exercised by the environment test) and `artifact-registry`.

### `infra/modules/cloud-run-service/tests/service.tftest.hcl`

`infra/modules/cloud-run-service/tests/service.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id            = "example-sandbox-0000"
  name                  = "worker"
  location              = "europe-west1"
  image                 = "europe-west1-docker.pkg.dev/example-sandbox-0000/uploads/worker:1"
  service_account_email = "worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
  labels                = { environment = "sandbox" }
}

run "the_service_runs_as_the_given_account_with_labels" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].service_account == var.service_account_email && google_cloud_run_v2_service.this.labels["environment"] == "sandbox"
    error_message = "The service must run as the given account and carry its labels."
  }
}

run "a_private_service_has_no_invoker_bindings" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "With no invoker members the service must stay private."
  }
}

run "the_invoker_binding_is_on_the_service" {
  command = plan

  variables {
    invoker_members = { pubsub = "serviceAccount:pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com" }
  }

  assert {
    condition     = alltrue([for b in google_cloud_run_v2_service_iam_member.invoker : b.role == "roles/run.invoker"])
    error_message = "Only roles/run.invoker is granted."
  }
}

run "secrets_are_referenced_not_copied" {
  command = plan

  variables {
    secret_env = {
      DB_PASSWORD = { secret = "db-password", version = "latest" } # checkov:skip=CKV_SECRET_6:a secret name, not a value
    }
  }

  assert {
    condition     = length([for e in google_cloud_run_v2_service.this.template[0].containers[0].env : e if length(e.value_source) > 0]) == 1
    error_message = "The secret must be wired through value_source, not as a plain value."
  }
}

run "an_unknown_ingress_value_is_rejected" {
  command = plan

  variables {
    ingress = "EVERYWHERE"
  }

  expect_failures = [var.ingress]
}
```

- Run one: the service runs as the given account and carries the label `environment = "sandbox"`. `template[0]` picks the first (only) copy of a nested block.
- Run two: with no invokers there are no invoker bindings. Run three: when an invoker is given, its role is `roles/run.invoker`.
- Run four: of the container's environment variables exactly one has a `value_source` (the secret): secrets are referenced, not copied.
- Run five: an unknown `ingress` value is rejected.

### `infra/modules/project-baseline/tests/baseline.tftest.hcl`

`infra/modules/project-baseline/tests/baseline.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id     = "example-sandbox-0000"
  project_number = "000000000000"
  services       = ["run.googleapis.com", "pubsub.googleapis.com"]
}

run "no_billing_account_means_no_budget_and_no_policy_by_default" {
  command = plan

  assert {
    condition     = length(google_billing_budget.this) == 0 && length(google_org_policy_policy.no_service_account_keys) == 0
    error_message = "Defaults must create neither a budget nor an organization policy."
  }
}

run "a_billing_account_creates_one_budget_with_a_threshold_per_alert" {
  command = plan

  variables {
    billing_account = "AAAAAA-BBBBBB-CCCCCC"
  }

  assert {
    condition     = length(google_billing_budget.this) == 1 && length(google_billing_budget.this[0].threshold_rules) == 3
    error_message = "One budget with three thresholds is expected."
  }
}

run "the_key_policy_is_enforced_when_asked" {
  command = plan

  variables {
    enforce_no_service_account_keys = true
  }

  assert {
    condition     = google_org_policy_policy.no_service_account_keys[0].name == "projects/example-sandbox-0000/policies/iam.disableServiceAccountKeyCreation"
    error_message = "The policy must target iam.disableServiceAccountKeyCreation on the project."
  }
}

run "a_non_numeric_project_number_is_rejected" {
  command = plan

  variables {
    project_number = "abc"
  }

  expect_failures = [var.project_number]
}
```

Run one: with no billing account there is no budget and no policy. Run two: a billing account creates one budget with three threshold rules (the default thresholds). Run three: the key policy is enforced when asked, and its name is `projects/example-sandbox-0000/policies/iam.disableServiceAccountKeyCreation`. Run four: a non-numeric project number is rejected.

### `infra/modules/pubsub-push/tests/pipeline.tftest.hcl`

`infra/modules/pubsub-push/tests/pipeline.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id                    = "example-sandbox-0000"
  project_number                = "000000000000"
  topic_name                    = "uploads"
  push_endpoint                 = "https://worker-example.a.run.app/"
  oidc_audience                 = "https://worker-example.a.run.app"
  invoker_service_account_email = "pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
  publisher_members             = { api = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "push_is_authenticated_and_failures_are_dead_lettered" {
  command = plan

  assert {
    condition     = one(google_pubsub_subscription.push.push_config).oidc_token[0].service_account_email == var.invoker_service_account_email
    error_message = "The push subscription must send an OIDC token for the invoker account."
  }

  assert {
    condition     = one(google_pubsub_subscription.push.dead_letter_policy).max_delivery_attempts == 5
    error_message = "A message must be dead-lettered after 5 attempts."
  }
}

run "the_service_agent_has_the_grants_dead_lettering_needs" {
  command = plan

  assert {
    condition     = google_pubsub_topic_iam_member.agent_publishes_dead_letters.member == "serviceAccount:service-000000000000@gcp-sa-pubsub.iam.gserviceaccount.com" && google_pubsub_subscription_iam_member.agent_acknowledges.role == "roles/pubsub.subscriber"
    error_message = "The Pub/Sub service agent must publish to the dead-letter topic and subscribe on the push subscription."
  }
}

run "publishing_is_granted_on_the_topic_only" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic_iam_member.publisher) == 1
    error_message = "One publisher binding on the topic is expected."
  }
}

run "an_insecure_endpoint_is_rejected" {
  command = plan

  variables {
    push_endpoint = "http://worker.example/"
  }

  expect_failures = [var.push_endpoint]
}

run "fewer_than_five_attempts_is_rejected" {
  command = plan

  variables {
    max_delivery_attempts = 3
  }

  expect_failures = [var.max_delivery_attempts]
}
```

Run one: the push subscription sends an OIDC token for the invoker account and dead-letters after 5 attempts (`one(...)` takes the single element of a nested list). Run two: the Pub/Sub service agent holds the grants dead-lettering needs (its email contains the project number `000000000000`). Run three: publishing is granted on the topic only. Run four: an `http://` endpoint is rejected. Run five: fewer than five attempts is rejected.

### `infra/modules/results-bucket/tests/bucket.tftest.hcl`

`infra/modules/results-bucket/tests/bucket.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id      = "example-sandbox-0000"
  name            = "example-sandbox-0000-results"
  location        = "europe-west1"
  creator_members = { worker = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "bucket_is_private_and_uniform" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access && google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "The bucket must use uniform access and block public access."
  }
}

run "only_the_creator_role_is_granted_and_only_to_the_given_members" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_member.creator) == 1 && alltrue([for b in google_storage_bucket_iam_member.creator : b.role == "roles/storage.objectCreator"])
    error_message = "Exactly one binding with roles/storage.objectCreator is expected."
  }
}

run "no_members_means_no_bindings" {
  command = plan

  variables {
    creator_members = {}
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.creator) == 0
    error_message = "An empty member list must create no bindings."
  }
}

run "a_bad_bucket_name_is_rejected" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}
```

Run one: uniform access and enforced public-access prevention. Run two: exactly one binding, with the creator role. Run three: with no members there are no bindings. Run four: a bad bucket name is rejected.

### `infra/modules/secret/tests/secret.tftest.hcl`

`infra/modules/secret/tests/secret.tftest.hcl`

```hcl
mock_provider "google" {}

variables {
  project_id       = "example-sandbox-0000"
  secret_id        = "db-password"
  secret_data      = "placeholder" # checkov:skip=CKV_SECRET_6:placeholder in a test fixture
  accessor_members = { api = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "the_value_is_written_as_a_write_only_argument" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret_version.this) == 1
    error_message = "The first version must be written through secret_data_wo."
  }
}

run "access_is_granted_on_the_secret_to_the_listed_members_only" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 1 && alltrue([for b in google_secret_manager_secret_iam_member.accessor : b.role == "roles/secretmanager.secretAccessor"])
    error_message = "One secretAccessor binding on the secret is expected."
  }
}

run "no_version_when_the_caller_adds_one_by_hand" {
  command = plan

  variables {
    create_version = false
  }

  assert {
    condition     = length(google_secret_manager_secret_version.this) == 0
    error_message = "create_version = false must create no version."
  }
}
```

Run one: a version is written (as a write-only argument). Run two: access is granted on the secret, with the accessor role, to the listed members only. Run three: with `create_version = false` no version is written.

### `infra/environments/sandbox/tests/wiring.tftest.hcl`

`infra/environments/sandbox/tests/wiring.tftest.hcl`

```hcl
# The mock provider invents computed values, so the service-account modules are overridden with fixed outputs and the
# runs plan against the mock to check the wiring between modules.
mock_provider "google" {}

override_module {
  target = module.api_sa
  outputs = {
    email  = "api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/api-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.worker_sa
  outputs = {
    email  = "worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.invoker_sa
  outputs = {
    email  = "pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_resource {
  target          = module.worker.google_cloud_run_v2_service.this
  override_during = plan
  values = {
    uri = "https://worker-example.a.run.app"
  }
}

override_resource {
  target          = module.api.google_cloud_run_v2_service.this
  override_during = plan
  values = {
    uri = "https://api-example.a.run.app"
  }
}

variables {
  project_id     = "example-sandbox-0000"
  project_number = "000000000000"
  db_password    = "placeholder" # checkov:skip=CKV_SECRET_6:placeholder in a test fixture
}

run "each_workload_has_its_own_identity" {
  command = plan

  assert {
    condition     = length(distinct(values(output.service_accounts))) == 3
    error_message = "The API, the worker and the invoker need three different service accounts."
  }
}

run "the_results_bucket_is_named_after_the_project" {
  command = plan

  assert {
    condition     = output.results_bucket == "example-sandbox-0000-results"
    error_message = "The bucket name must derive from the project id."
  }
}

run "only_the_worker_account_creates_objects_and_only_the_invoker_calls_the_worker" {
  command = plan

  assert {
    condition     = module.results.creator_members == tolist([module.worker_sa.member]) && module.worker.invoker_members == tolist([module.invoker_sa.member])
    error_message = "Bucket creator is the worker account; worker invoker is the invoker account."
  }
}

run "only_the_api_account_publishes_and_reads_the_secret" {
  command = plan

  assert {
    condition     = module.pipeline.publisher_members == tolist([module.api_sa.member]) && module.db_password.accessor_members == tolist([module.api_sa.member])
    error_message = "Publisher and secret accessor are the API account."
  }
}

run "the_push_subscription_calls_the_worker_as_the_invoker_account" {
  command = plan

  assert {
    condition     = module.worker.uri != null && module.pipeline.push_subscription_name == "uploads-push"
    error_message = "The pipeline must push to the worker."
  }
}

run "the_api_is_public_by_default" {
  command = plan

  assert {
    condition     = module.api.invoker_members == tolist(["allUsers"])
    error_message = "The exercise API is public by default."
  }
}

run "a_private_api_on_request" {
  command = plan

  variables {
    api_public = false
  }

  assert {
    condition     = length(module.api.invoker_members) == 0
    error_message = "api_public = false must remove the allUsers binding."
  }
}
```

- The first two comment lines say why overrides are needed: a mock provider invents values for things Google would compute (emails, URLs), and the wiring between modules needs real-looking ones.
- `override_module { target = module.api_sa  outputs = {...} }` replaces a whole module's outputs with fixed values, here the three service-account modules. `override_resource { target = module.worker.google_cloud_run_v2_service.this  override_during = plan  values = {...} }` sets one computed attribute (the service URL) of one resource during the plan.
- Run one: the three accounts are distinct (`length(distinct(values(...))) == 3`). Run two: the bucket is named after the project. Run three: only the worker's account may create objects and only the invoker may call the worker. Run four: only the API's account publishes and reads the secret. Run five: the push subscription is named `uploads-push` and the worker has a URL. Run six: the API is public by default (`["allUsers"]`). Run seven: with `api_public = false` it has no invokers.

## 6. Try it yourself

```bash
cd infra/modules/results-bucket && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 4 passed, 0 failed.` with each run name listed as `pass`.

```bash
cd infra/environments/sandbox && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 7 passed, 0 failed.`

Break one on purpose: in `infra/modules/results-bucket/main.tf` change `"roles/storage.objectCreator"` to `"roles/storage.objectAdmin"`, run `terraform test` in that module, read the failure message, then undo the change.

```bash
make test-terraform
```
Expected: `== infra/modules/...` headings and a `Success!` line for each of the seven modules with tests and the environment.

## 7. Mistakes people make

- **Comparing against random mock values.** Override the module or resource first.
- **Comparing a list with a tuple literal.** Use `tolist()`.
- **Forgetting `expect_failures`.** A validation error would fail the whole run.
- **Testing the provider, not your logic.** Assert your wiring (who gets which role), not that Terraform works.
- **Believing a mock proves Google accepts it.** It does not; `scripts/prove.sh` does that against a real project.

## 8. Check yourself

1. What does `mock_provider` do? *Replaces the real provider so nothing contacts the cloud.*
2. What does `expect_failures` mean? *The run passes only if that variable's validation fails.*
3. Why use `override_module` in the environment test? *To give identities fixed emails that assertions can compare.*
4. Which command runs all tests of a module? *`terraform test` in that folder.*
5. Why `tolist(...)`? *To make a literal the same type as the output.*

## 9. Further reading

- `terraform test`: <https://developer.hashicorp.com/terraform/language/tests>
- Mock providers: <https://developer.hashicorp.com/terraform/language/tests/mocking>
- Command reference: <https://developer.hashicorp.com/terraform/cli/commands/test>
