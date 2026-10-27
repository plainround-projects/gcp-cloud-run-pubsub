# artifact-registry

A Docker repository with immutable tags and a cleanup policy.

Used for: Step 3 (where the images live).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the repository. | `string` | required |
| `location` | Region of the repository. | `string` | required |
| `repository_id` | Repository name. | `string` | required |
| `keep_count` | Number of most recent image versions the cleanup policy always keeps. | `number` | `5` |
| `labels` | Labels for the repository. | `map(string)` | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `image_prefix` | Prefix for image names: LOCATION-docker.pkg.dev/PROJECT/REPOSITORY. |
| `repository_id` | Repository name. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

none (a single resource, covered by the environment's plan). Run `make test-terraform` from the repository root.
