# service-account

Creates one service account. It never creates a key and grants no role; roles are granted on resources by the modules that own them.

Used for: Step 2 (one identity per workload).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the service account. | `string` | required |
| `account_id` | Account id, the part before the @ (6-30 characters). | `string` | required |
| `display_name` | Human-readable name. | `string` | required |
| `description` | What this identity is for and what it may touch. | `string` | required |

## Outputs

| Name | Description |
| --- | --- |
| `email` | Service account email. |
| `member` | IAM member string, serviceAccount:EMAIL. |
| `name` | Full resource name, projects/PROJECT/serviceAccounts/EMAIL. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

none (a single resource, covered by the environment's plan). Run `make test-terraform` from the repository root.
