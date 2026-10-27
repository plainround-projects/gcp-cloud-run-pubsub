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
