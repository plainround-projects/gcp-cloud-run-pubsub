# secret

A Secret Manager secret, an optional first version written through a write-only argument (the value never reaches the Terraform state), and `secretAccessor` on that one secret for the listed members.

Used for: Steps 2 and 3 (the database password).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the secret. | `string` | required |
| `secret_id` | Secret name. | `string` | required |
| `labels` | Labels for the secret. | `map(string)` | `{}` |
| `accessor_members` | IAM members that may read this one secret (roles/secretmanager.secretAccessor, on the secret, not the project), keyed by a fixed label. | `map(string)` | `{}` |
| `create_version` | Write a first version from secret_data. Set false to add versions outside Terraform. | `bool` | `true` |
| `secret_data` | The secret value. Ephemeral and sensitive: it never reaches the state file. | `string` | `null` |
| `secret_version` | Counter that tells Terraform to write secret_data again. | `number` | `1` |

## Outputs

| Name | Description |
| --- | --- |
| `secret_id` | Secret name, as Cloud Run refers to it. |
| `id` | Full resource id, projects/PROJECT/secrets/NAME. |
| `accessor_members` | Members granted access to this secret. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

yes (`tests/*.tftest.hcl`, mock provider). Run `make test-terraform` from the repository root.
