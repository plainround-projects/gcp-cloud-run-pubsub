# Billing budgets and organization policies

## 1. What it is

A **budget** (Cloud Billing Budgets) watches a project's spending and sends alerts at percentages of an amount you set. It alerts; it does not stop spending. An **organization policy** is a rule set by an administrator that limits what can be done in a project, folder or organization. This repository uses one: the constraint `iam.disableServiceAccountKeyCreation`, which makes creating service account keys fail.

## 2. Why this repository uses it

Step 1 of the lesson: "put the project under a budget with an alert" and "an attempt to create a key for any service account fails".

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `infra/modules/project-baseline/main.tf` | Enables the APIs, creates the budget, and (optionally) enforces the key policy. |
| `infra/environments/sandbox/main.tf` | Calls the module with the billing account and the policy switch. |
| `scripts/prove.sh` | Lists the budget and tries to create a key. |
| `scripts/teardown.sh` | Deletes the budget (it lives on the billing account, outside the project). |

## 4. How it works underneath

A budget belongs to a **billing account** and is filtered to the project by its number. Alerts at thresholds (0.5 = 50 percent) go to the billing account's administrators by default. Organization policies require an **organization** (a top-level node, for example from a free Cloud Identity domain). A boolean constraint is either enforced or not; when enforced, a request that violates it is refused with an error that names the constraint. Without an organization the policy cannot be set, so the lesson's fallback is a rule you follow: never run `gcloud iam service-accounts keys create`.

## 5. Walkthrough of this repository's use

`infra/modules/project-baseline/main.tf`

```hcl
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
```

- `count = var.billing_account == "" ? 0 : 1`: no billing account, no budget.
- `budget_filter { projects = ["projects/NUMBER"] }`: watch this project only.
- `amount { specified_amount { currency_code, units } }`: the limit in whole units of the account's currency (`units` is a string).
- `dynamic "threshold_rules"`: one rule per fraction in `budget_thresholds` (0.5, 0.9, 1.0).

`infra/modules/project-baseline/main.tf`

```hcl
# Blocks the creation of downloadable service account keys. Needs the project to sit under an organization.
resource "google_org_policy_policy" "no_service_account_keys" {
  count = var.enforce_no_service_account_keys ? 1 : 0

  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
```

`name` and `parent` point at the project; `spec { rules { enforce = "TRUE" } }` turns the constraint on. The module's variable `enforce_no_service_account_keys` defaults to `false` because it needs an organization.

## 6. Try it yourself

```bash
cd infra/modules/project-baseline && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 4 passed, 0 failed.` (no budget and no policy by default; one budget with three thresholds when a billing account is given; the key policy targets `iam.disableServiceAccountKeyCreation` when enabled; a non-numeric project number is rejected).

```bash
grep -n "budget_thresholds" -A3 infra/modules/project-baseline/variables.tf | head -6
```
Expected: the default `[0.5, 0.9, 1.0]`.

With an organization and a project (not run here):
```bash
gcloud iam service-accounts keys create /tmp/key.json --iam-account=api-sa@PROJECT_ID.iam.gserviceaccount.com
```
Expected: `FAILED_PRECONDITION: Key creation is not allowed on this service account`.

## 7. Mistakes people make

- **Thinking a budget stops spending.** It only alerts.
- **Forgetting that the budget lives outside the project.** Deleting the project leaves it; the teardown script removes it.
- **Setting an organization policy in a project with no organization.** It cannot be set; follow the written rule instead.
- **Testing a policy right after setting it.** Policies take a minute or more to apply.

## 8. Check yourself

1. Does a budget stop spending at 100 percent? *No; it sends alerts.*
2. What does `count = ... ? 0 : 1` do? *Creates the resource only when a billing account is given.*
3. Which constraint blocks keys? *`iam.disableServiceAccountKeyCreation`.*
4. Why is the policy switch off by default? *It requires an organization.*
5. How is the budget tied to the project? *A filter on the project number.*

## 9. Further reading

- Budgets and alerts: <https://cloud.google.com/billing/docs/how-to/budgets>
- Organization policy constraints: <https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints>
- Terraform `google_billing_budget`: <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget>
