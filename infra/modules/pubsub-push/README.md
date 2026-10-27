# pubsub-push

A topic, a dead-letter topic with a pull subscription, a push subscription that authenticates with an OIDC token, and every grant the Pub/Sub service agent needs for dead-lettering.

Used for: Step 4 (push subscription, dead-letter topic).

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Project that owns the topics and subscriptions. | `string` | required |
| `project_number` | Project number; the Pub/Sub service agent's email contains it. | `string` | required |
| `topic_name` | Name of the main topic; the dead-letter topic and the subscriptions derive their names from it. | `string` | required |
| `push_endpoint` | HTTPS URL that receives each message. | `string` | required |
| `oidc_audience` | Audience claim of the OIDC token; for Cloud Run, the service URL. | `string` | required |
| `invoker_service_account_email` | Account whose OIDC token Pub/Sub sends. Give it roles/run.invoker on the receiving service only. | `string` | required |
| `publisher_members` | IAM members that may publish to the main topic (granted on the topic, not the project), keyed by a fixed label. | `map(string)` | `{}` |
| `max_delivery_attempts` | Attempts before a message goes to the dead-letter topic (5 to 100). | `number` | `5` |
| `ack_deadline_seconds` | Seconds the worker has to answer before Pub/Sub redelivers. | `number` | `30` |
| `minimum_backoff` | Shortest wait before a retry. | `string` | `"10s"` |
| `maximum_backoff` | Longest wait before a retry. | `string` | `"120s"` |
| `labels` | Labels for topics and subscriptions. | `map(string)` | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `topic_name` | Name of the main topic. |
| `dead_letter_topic_name` | Name of the dead-letter topic. |
| `push_subscription_name` | Name of the push subscription. |
| `dead_letter_subscription_name` | Name of the pull subscription on the dead-letter topic. |
| `publisher_members` | Members granted the publisher role on the main topic. |

## Example

See `infra/environments/sandbox/main.tf`, which composes this module.

## Tests

yes (`tests/*.tftest.hcl`, mock provider). Run `make test-terraform` from the repository root.
