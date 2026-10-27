# cloud-run-service

A Cloud Run v2 service that runs as a given service account, with plain and secret-backed environment variables, scale bounds, and `run.invoker` on that one service for the listed members.

Used for: Steps 3 and 4 (the API and the worker).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the service. | `string` | required |
| `name` | Service name. | `string` | required |
| `location` | Region. | `string` | required |
| `image` | Container image to run. | `string` | required |
| `service_account_email` | Identity the service runs as. Required: the default compute account is never used. | `string` | required |
| `env` | Plain environment variables. | `map(string)` | `{}` |
| `secret_env` | Environment variables filled from Secret Manager: name => { secret, version }. | `map(object({ secret = string version = string }))` | `{}` |
| `invoker_members` | Members that may call the service, keyed by a fixed label. Empty keeps it private to IAM; allUsers makes it public. | `map(string)` | `{}` |
| `ingress` | Ingress setting of the service. | `string` | `"INGRESS_TRAFFIC_ALL"` |
| `container_port` | Port the container listens on. | `number` | `8080` |
| `cpu` | CPU limit per instance. | `string` | `"1"` |
| `memory` | Memory limit per instance. | `string` | `"512Mi"` |
| `min_instances` | Instances kept warm. Zero scales to zero and costs nothing idle. | `number` | `0` |
| `max_instances` | Upper bound on instances, which also bounds the bill. | `number` | `3` |
| `concurrency` | Requests one instance handles at once. | `number` | `20` |
| `request_timeout_seconds` | Request timeout. | `number` | `60` |
| `deletion_protection` | Refuse to delete the service. False in a sandbox so the teardown works. | `bool` | `false` |
| `labels` | Labels for the service. | `map(string)` | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `uri` | HTTPS URL of the service. |
| `name` | Service name. |
| `service_account_email` | Identity the service runs as. |
| `invoker_members` | Members granted roles/run.invoker on this service. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

yes (`tests/*.tftest.hcl`, mock provider). Run `make test-terraform` from the repository root.
