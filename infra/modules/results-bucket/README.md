# results-bucket

A private bucket with uniform bucket-level access, public access prevention, versioning and a retention rule, plus `objectCreator` on that one bucket for the listed members.

Used for: Step 2 (worker writes, nothing else).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the bucket. | `string` | required |
| `name` | Globally unique bucket name. | `string` | required |
| `location` | Bucket location, for example europe-west1. | `string` | required |
| `labels` | Labels for the bucket. | `map(string)` | `{}` |
| `creator_members` | IAM members that may create objects in this bucket and nothing else, keyed by a fixed label (the keys must be known at plan time, the members need not be). | `map(string)` | `{}` |
| `retention_days` | Days after which result files are deleted. | `number` | `30` |
| `force_destroy` | Delete the bucket even when it holds objects. True only for a sandbox. | `bool` | `false` |

## Outputs

| Name | Description |
| --- | --- |
| `name` | Bucket name. |
| `url` | gs:// URL of the bucket. |
| `creator_members` | Members that may create objects. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

yes (`tests/*.tftest.hcl`, mock provider). Run `make test-terraform` from the repository root.
