# Markdown

## 1. What it is

Markdown is a way of writing formatted text in a plain text file. You type ordinary characters and a few marks, and a program turns them into headings, lists, tables, links and code blocks. A file ending in `.md` is a Markdown file. GitHub shows `README.md` below the file list of a repository, formatted. The dialect used here is GitHub Flavored Markdown, which adds tables and fenced code blocks to the original.

## 2. Why this repository uses it

A repository has to explain itself. The lesson asks for a README with run, test and deploy instructions, an architecture document with a diagram, a record of each decision, and operating notes. All of it is Markdown, so it lives next to the code, is reviewed with the code, and changes in the same commit. The `tech/` notes quote the code itself, so they are checked against it.

## 3. Where it appears

| Path | What it is |
| --- | --- |
| `README.md` | The front page: what the project is, how to run, test and deploy it, the "Done when" table, the project structure, what is simplified, the verification record. |
| `ARCHITECTURE.md` | The components, the hierarchy diagram (see `mermaid.md`), the pattern, trade-offs, failure modes and limits. |
| `CHANGELOG.md` | What changed in each version. |
| `docs/adr/000N-*.md` | Architecture decision records: one decision each, with context, the decision and the consequences. |
| `infra/modules/*/README.md`, `infra/environments/lab/README.md` | One page per Terraform module: inputs, outputs, example, tests. |
| `tech/*.md` | These notes. |

## 4. How it works underneath

A Markdown file is just text. A renderer (GitHub, an editor preview) reads it line by line and applies the rules. Nothing is run; there are no variables or loops. The marks used in this repository:

- `#`, `##`, `###` at the start of a line make headings of decreasing size. The text after the marks is the title. A blank line separates paragraphs.
- `-` or `*` at the start of a line makes a bullet; `1.` makes a numbered item. Indenting nests a list.
- `**bold**` is bold. Backticks make `code` inside a sentence.
- Three backticks on a line of their own start a **fenced code block**, three more end it. The word after the opening backticks (for example `bash`) names the language, for colors. Inside, nothing is formatted.
- `[text](address)` is a link. The address can be a file in the repository (`ARCHITECTURE.md`) or a web address. `#name` after a file name jumps to a heading.
- A **table** has a header row of cells between `|`, a divider row `| --- | --- |`, then rows. A `|` inside a cell must be written `\|`.
- A line with only `---` is a horizontal rule.

## 5. Walkthrough of this repository's use

### The README's table at the top

`README.md`

```markdown
| **Lesson** | `/prep/gcp/project-cloud-run-pubsub`, "Deploy a Cloud Run service and a Pub/Sub worker" (`data-structure-explainer/src/content/tracks/gcp/15-project-cloud-run-pubsub.md` in the Plainround app) |
| **Planned hours** | 6 |
| **Level** | Beginner |
| **Architecture** | [ARCHITECTURE.md](ARCHITECTURE.md), decisions in [docs/adr](docs/adr) |
| **Author** | Sumit Srivastava |
```

A two-column table with an empty header row (`| | |`), then the divider `| --- | --- |`, then one row per fact. Each row is a fact (lesson, planned hours, level, architecture, author) with `**bold**` labels and links.

### Headings in a fixed order

The README's second-level headings (`##`) are, in order: What is here, Prerequisites, Run it on this machine, Test, Deploy to your own project, Done when, Stretch goals, Project structure, What is simplified for teaching, Verification record, License. The order is a repository rule (`TEMPLATE.md`), so every project reads the same.

### A fenced block with a diagram of the folders

The "Project structure" section is a fence with the language `text`: a drawing made of the characters `├──`, `│` and `└──`, which only line up in a fixed-width font. That is why it is in a code block.

### A module README

`infra/modules/pubsub-push/README.md`

```markdown
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
```

- `# pubsub-push` is the title; the first paragraph says what the module is.
- "Used for:" ties the module to the lesson's steps.
- `## Inputs` and `## Outputs` are tables with the same columns as the Terraform variables and outputs files (see `terraform.md`): name in backticks, description, type, default.
- `## Example` points to the environment that uses the module; `## Tests` says how to run them.

### The other module pages and the environment page

They follow the same shape as the perimeter's page. Each one in full:

`infra/modules/service-account/README.md`

```markdown
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
```

`infra/modules/project-baseline/README.md`

```markdown
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
```

`infra/modules/secret/README.md`

```markdown
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
```

`infra/modules/results-bucket/README.md`

```markdown
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
```

`infra/modules/artifact-registry/README.md`

```markdown
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
```

`infra/modules/cloud-run-service/README.md`

```markdown
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
```

`infra/environments/sandbox/README.md`

```markdown
# sandbox environment

The composition for a one-day sandbox project: project baseline, three service accounts, the secret, the results bucket, the Artifact Registry repository, the worker, the Pub/Sub pipeline and the API, in dependency order. Every module is in `../../modules`.

## Variables

See `variables.tf`; `sandbox.tfvars.example` shows every value with placeholders. `scripts/create-project.sh` writes the real `sandbox.tfvars` (git-ignored). `db_password` is an ephemeral variable: export `TF_VAR_db_password` (`scripts/deploy.sh` generates a throwaway).

## Validate without credentials

```bash
cd infra/environments/sandbox
terraform init -backend=false
terraform validate
TF_VAR_db_password=placeholder GOOGLE_OAUTH_ACCESS_TOKEN=offline-placeholder \
  terraform plan -var-file=sandbox.tfvars.example     # 32 resources to add, no API call
terraform test                                       # wiring checks against a mock provider
```

The offline plan works because nothing in the configuration reads from Google Cloud (no data sources); the placeholder token only satisfies the provider's configuration.

## Apply

`scripts/deploy.sh` from the repository root; see the README's "Deploy to your own project".

## Outputs

`api_url`, `worker_url`, `results_bucket`, `image_prefix`, `service_accounts`, `topic`.

## State

Local. For shared use copy `backend.tf.example` to `backend.tf`, create the bucket (versioning on) and run `terraform init -migrate-state`.
```

The pages differ only in their title, the one-line description, the step they serve, and the rows of the two tables. The environment's page lists its own inputs and outputs and how to run it.

### An architecture decision record

`docs/adr/0003-create-only-writes-with-object-creator.md`

```markdown
# 3. Create-only writes with `roles/storage.objectCreator`

Status: accepted, 2026-10-27

## Context

The lesson grants the worker `roles/storage.objectCreator`, which can create objects but not read, overwrite or delete them. Pub/Sub delivers at least once, so the worker will sometimes see a message it has already processed. Overwriting an object needs `storage.objects.delete` as well as `create`, so a plain upload of a duplicate would be denied and the worker would return 500 for a message that was in fact done.

## Decision

The result store writes with `if_generation_match=0`. If the object exists, Cloud Storage answers `412 Precondition Failed`, the adapter returns `False`, and the use case reports `ALREADY_PROCESSED` and acknowledges the message.

## Consequences

- A duplicate delivery is a success that changes nothing, with the narrowest role.
- A result cannot be updated by the worker. If a future version must update, grant `objectUser` on the bucket and define the overwrite rule first.
- The retry of a failed write is safe: the conditional write is idempotent, so the client library may retry it.
```

An ADR is short and always has the same parts: a numbered title, a status and date, **Context** (the problem), **Decision** (what was chosen) and **Consequences**. The number never changes, so other documents can refer to "ADR 2".

## 6. Try it yourself

```bash
grep -n "^## " README.md
```
Expected: the eleven second-level headings of the README, with line numbers.

```bash
ls docs/adr
```
Expected: `0001-push-subscription-to-a-private-cloud-run-service.md`, `0002-ports-and-adapters-around-pubsub-and-storage.md`, `0003-create-only-writes-with-object-creator.md`.

```bash
grep -c '^| ' infra/modules/pubsub-push/README.md
```
Expected: the number of table rows in the perimeter module's page (headers and dividers included).

```bash
grep -rn "](" README.md | grep -o "](\([^)]*\))" | head -3
```
Expected: the first three link targets, for example `(ARCHITECTURE.md)`.

## 7. Mistakes people make

- **A missing blank line** before a list or table, so the renderer shows plain text.
- **A `|` inside a table cell** without a backslash, which splits the cell.
- **Tabs and spaces mixed** in nested lists.
- **Documents that drift from the code.** Here the `tech/` notes quote the code itself.
- **Absolute web links to files in the same repository.** Relative links keep working in a fork or a clone.
- **A fence that is never closed.** The rest of the page turns into code.

## 8. Check yourself

1. What marks a heading? *`#` characters at the start of a line.*
2. How do you write a code block? *Three backticks before and after, with the language after the first three.*
3. How do you put a `|` in a table cell? *Write `\|`.*
4. What are the four parts of an ADR? *Title with status and date, Context, Decision, Consequences.*
5. Why use relative links to files in the repository? *They keep working in a fork or a clone.*

## 9. Further reading

- GitHub Flavored Markdown specification: <https://github.github.com/gfm/>
- Basic writing and formatting syntax: <https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax>
- Architecture decision records: <https://adr.github.io/>
