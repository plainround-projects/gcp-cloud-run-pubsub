# IAM and service accounts

## 1. What it is

**IAM** (Identity and Access Management) is the part of Google Cloud that answers "who may do what to which thing". An **identity** is a user, a group or a **service account**. A service account is an identity for a program, not a person: it has an email such as `worker-sa@PROJECT.iam.gserviceaccount.com`. A **permission** is one allowed action (`storage.objects.create`). A **role** is a named bundle of permissions. A **binding** says "this member has this role on this resource". A **policy** is the list of bindings on one resource.

## 2. Why this repository uses it

The lesson is about identity: each workload gets its own account with only the roles it needs, and no key file exists anywhere. The repository then breaks one permission on purpose to read the exact denial.

## 3. Where it appears

| Path | What it does with IAM |
| --- | --- |
| `infra/modules/service-account/` | Creates one service account. It never creates a key and grants no role. |
| `infra/modules/results-bucket/main.tf` | `objectCreator` for the worker, on the bucket only. |
| `infra/modules/pubsub-push/main.tf` | Publisher on the topic for the API; grants for the Pub/Sub service agent. |
| `infra/modules/secret/main.tf` | `secretAccessor` for the API, on the secret only. |
| `infra/modules/cloud-run-service/main.tf` | `run.invoker` on a service. |
| `infra/modules/project-baseline/main.tf` | Optional organization policy that forbids creating service account keys. |
| `tests/unit/test_infrastructure_policy.py` | Fails if any project-level role, key resource or broad role appears. |
| `scripts/prove.sh`, `break-permission.sh`, `read-denial.sh` | Check and break the bindings with `gcloud`. |

## 4. How it works underneath

- A running service gets credentials from the platform. On Cloud Run the program asks a local **metadata server** for a short-lived token for the service's account; the Google libraries do this automatically ("Application Default Credentials"). Because tokens are short-lived and handed out by the platform, **no key file** is needed. A key file is a long-lived password that can leak.
- **Where a role is granted matters.** A role granted on the project applies to every resource inside it. A role granted on one bucket, topic or secret applies to that thing only. This repository grants only on resources, so no account has a project-level role.
- **Smallest role that works.** `objectCreator` can create objects but not read, overwrite or delete them; `pubsub.publisher` can publish but not subscribe; `secretAccessor` can read secret values but not change them.
- **Service agents** are Google-run accounts that act for a service. The Pub/Sub service agent publishes dead letters and acknowledges deliveries for a subscription, so it needs its own grants.
- **`actAs`.** To attach a service account to a service you need permission to act as it (the Service Account User role). That is a permission of the person deploying, not of the workload.
- A denial names the account, the permission and the resource, for example `worker-sa@... does not have storage.objects.create access to the Google Cloud Storage object`.

## 5. Walkthrough of this repository's use

`infra/modules/service-account/main.tf`

```hcl
# No google_service_account_key anywhere in this repository: workloads use the credentials the platform gives them.
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
```

The module creates the account and nothing else. Three are made in the environment: `api-sa`, `worker-sa`, `pubsub-invoker` (only used so Pub/Sub can call the worker).

The members are passed around as strings of the form `serviceAccount:EMAIL`; the module exposes that string as `member`:

`infra/modules/service-account/outputs.tf`

```hcl
output "member" {
  description = "IAM member string, serviceAccount:EMAIL."
  value       = "serviceAccount:${google_service_account.this.email}"
```

Examples of resource-level grants (shown in other notes): the bucket's `objectCreator` loop, the secret's `secretAccessor` loop, the topic's publisher loop and the worker's `run.invoker`. Each takes a **map** `{ label = member }` so Terraform can build the plan even though the emails are only known after creation.

The guard that keeps it this way:

`tests/unit/test_infrastructure_policy.py`

```python
def test_no_service_account_key_is_ever_created():
    assert _hits(r'resource\s+"google_service_account_key"') == []


@pytest.mark.parametrize(
    "kind", ["google_project_iam_member", "google_project_iam_binding", "google_project_iam_policy"]
)
def test_no_project_level_role_is_granted(kind):
    assert _hits(rf'resource\s+"{kind}"') == []


@pytest.mark.parametrize(
    "role", ["roles/owner", "roles/editor", "roles/storage.admin", "roles/storage.objectAdmin", "roles/pubsub.admin"]
)
def test_no_broad_role_appears(role):
    assert _hits(re.escape(role)) == []


def test_all_authenticated_users_is_never_used():
    assert _hits("allAuthenticatedUsers") == []
```

These tests read the Terraform source as text and fail if a key resource, a project-level IAM resource, a broad role (`roles/owner`, `roles/editor`, `roles/storage.admin`, ...) or `allAuthenticatedUsers` appears.

## 6. Try it yourself

```bash
.venv/bin/python -m pytest tests/unit/test_infrastructure_policy.py -q -p no:cacheprovider
```
Expected: `14 passed`. Now add a line `resource "google_project_iam_member" "oops" {}` to any `.tf` file under `infra/` and run it again to watch a test fail; remove the line afterwards.

```bash
grep -rn "roles/" infra --include=main.tf
```
Expected: only `objectCreator`, `publisher`, `subscriber`, `serviceAccountTokenCreator`, `secretAccessor`, `run.invoker`.

```bash
cd infra/modules/results-bucket && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 4 passed, 0 failed.`

## 7. Mistakes people make

- **Using the default compute service account.** It often holds Editor.
- **Granting `roles/storage.admin` on the project "to make it work".** Then the break in step 5 shows nothing.
- **Creating a key "just for the local test".** A key in an image is a leaked key.
- **Reading "permission denied" as "not logged in".** The caller authenticated; IAM found no role.
- **Forgetting the service agent grants.** Dead-lettering silently does not happen.

## 8. Check yourself

1. What is a binding? *A member, a role and a resource tied together.*
2. Why is a resource-level grant safer than a project-level one? *It reaches only that resource.*
3. How does Cloud Run give credentials to a program? *A metadata server issues short-lived tokens for the service's account.*
4. What can `objectCreator` not do? *Read, overwrite or delete objects.*
5. What three things does a denial message name? *The account, the permission, and the resource.*

## 9. Further reading

- IAM overview: <https://cloud.google.com/iam/docs/overview>
- Service accounts: <https://cloud.google.com/iam/docs/service-account-overview>
- Best practices for service accounts: <https://cloud.google.com/iam/docs/best-practices-service-accounts>
- Roles reference: <https://cloud.google.com/iam/docs/understanding-roles>
