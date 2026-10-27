# project-baseline

Prepares an existing project: enables the APIs the stack needs, creates a budget alert on the billing account, and optionally enforces the organization policy that blocks service account key creation.

Used for: Step 1 of the lesson (a project under a budget, no keys).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Id of the existing project to prepare. | `string` | required |
| `project_number` | Number of the project (gcloud projects describe PROJECT_ID --format='value(projectNumber)'); the budget filters on it. | `string` | required |
| `services` | APIs to enable. | `list(string)` | required |
| `billing_account` | Billing account id for the budget (gcloud billing accounts list). Empty skips the budget. | `string` | `""` |
| `budget_amount` | Budget in whole units of budget_currency. | `number` | `10` |
| `budget_currency` | ISO 4217 currency code of the billing account. | `string` | `"USD"` |
| `budget_thresholds` | Fractions of the budget that send an alert (0.5 is 50 percent). | `list(number)` | `[0.5, 0.9, 1.0]` |
| `enforce_no_service_account_keys` | Enforce iam.disableServiceAccountKeyCreation on the project. Requires an organization; without one, leave false and follow the rule by hand. | `bool` | `false` |

## Outputs

| Name | Description |
| --- | --- |
| `enabled_services` | APIs enabled by this module. |
| `budget_name` | Resource name of the budget, or null when no billing account was given. |
| `key_creation_blocked` | Whether the organization policy that blocks service account keys is enforced by this module. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

yes (`tests/*.tftest.hcl`, mock provider). Run `make test-terraform` from the repository root.
