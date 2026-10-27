# gcp-cloud-run-pubsub

An upload API and a Pub/Sub push worker on Cloud Run, each running as its own least-privilege service account with no key anywhere, defined in Terraform and rehearsed locally against the Pub/Sub emulator.

| | |
| --- | --- |
| **Lesson** | `/prep/gcp/project-cloud-run-pubsub`, "Deploy a Cloud Run service and a Pub/Sub worker" (`data-structure-explainer/src/content/tracks/gcp/15-project-cloud-run-pubsub.md` in the Plainround app) |
| **Planned hours** | 6 |
| **Level** | Beginner |
| **Architecture** | [ARCHITECTURE.md](ARCHITECTURE.md), decisions in [docs/adr](docs/adr) |
| **Author** | Sumit Srivastava |

## What is here

- `src/uploads/`: the API (`POST /upload`, `GET /health`) and the worker (`POST /`, the Pub/Sub push endpoint), in Python 3.12+ with Flask and gunicorn, in four layers behind two ports.
- `infra/`: Terraform (`google` provider `~> 8.8`) with seven modules and one environment, `sandbox`: the project baseline (APIs, budget, key policy), three service accounts, the secret, the bucket, the Artifact Registry repository, both Cloud Run services and the Pub/Sub pipeline with its dead-letter topic.
- `scripts/`: the lesson's runbook as the exact `gcloud` and `terraform` commands, plus `prove.sh`, which checks every Done when line against the real project.
- `docker-compose.yml`: the Pub/Sub emulator and a fake Cloud Storage server, so the whole flow, including retries and the dead-letter topic, runs on this machine.
- `tech/`: 39 notes, one per technology (Python, Terraform, Bash, Make, each Google Cloud service and every tool), written for a reader who has never met them. Start with [tech/README.md](tech/README.md).

Nothing here has been deployed: no Google Cloud project exists yet. Everything that does not need one is verified (see "Verification record"); the lines that do need one are marked "needs the project".

## Prerequisites

| Tool | Version | Used for |
| --- | --- | --- |
| Python | 3.12 or 3.13 (tested with 3.13; CI uses 3.12) | the services and tests |
| GNU Make | 3.81 or newer | every command below |
| Docker with Compose v2 | 24 or newer | the emulators and the images |
| Terraform | 1.11 or newer (tested with 1.17.0) | `make lint`, `make test`, `make validate`, deploy |
| tflint | 0.65 or newer (the Google ruleset 0.41.0 is downloaded by `tflint --init`) | `make lint` |
| checkov | 3.x (`uv tool install checkov` or `pip install checkov`) | `make validate` |
| shellcheck | 0.9 or newer | `make lint` |
| Google Cloud CLI (`gcloud`) | current | only the deploy steps, `scripts/*.sh` |
| A Google Cloud billing account | a free-trial or paid one | only the deploy steps |

For the deploy steps you also need the Owner role on the sandbox project (you create it), and, for the key-creation policy, a Google Cloud organization (a free Cloud Identity domain is enough). Without an organization, set `enforce_no_service_account_keys = false` and follow the rule by hand: never run `gcloud iam service-accounts keys create`.

## Run it on this machine (no cloud account)

```bash
make install        # .venv from the hash-pinned lock file
make up             # emulators + API + worker as containers, topics, push subscription and bucket created
make run            # uploads two files through the API, lets the emulator push them to the worker, lists the result files
make down           # stop everything, delete the emulators' data
```

`make run` ends with `results in gs://local-results:` followed by the two files of this run (`results/demo-TIME-1.txt results/demo-TIME-2.txt`); it fails if either file is missing.

## Test

```bash
make lint           # ruff, ruff format, mypy --strict, import-linter, shellcheck, terraform fmt -check, tflint
make test           # 103 unit tests with coverage (domain + application >= 95%) and the Terraform tests with a mock provider
make validate       # terraform init -backend=false + validate on every module and the environment, an offline plan, checkov
make test-integration   # the Pub/Sub and Cloud Storage adapters against the emulators
make test-e2e           # API -> emulator topic -> push -> worker -> bucket, then the failing variant with retry, dead letter, replay
make audit          # pip-audit over the locked dependencies
make check          # lint + test + validate
```

`make test-integration` and `make test-e2e` start the emulators themselves (`make emulators`).

## Deploy to your own project

1. Put the project id and billing account in `.env` (copy `.env.example`), then create the project and the Terraform variables file:

   ```bash
   scripts/create-project.sh      # gcloud projects create, gcloud billing projects link, writes infra/environments/sandbox/sandbox.tfvars
   ```

2. Apply (Terraform asks before each apply; the script runs two passes, the second with your images):

   ```bash
   scripts/deploy.sh              # terraform apply with placeholder images -> docker build/push -> terraform apply with yours
   ```

3. Check the Done when lines of steps 1 to 4 in one command:

   ```bash
   scripts/prove.sh
   ```

4. Break the permission, read the evidence, restore and replay (steps 5 and 6):

   ```bash
   scripts/break-permission.sh report-2
   scripts/read-denial.sh         # after a few minutes: the denial in the log and the message in the dead-letter subscription
   scripts/restore-and-replay.sh
   ```

5. Tear down:

   ```bash
   scripts/teardown.sh            # deletes the budget and the project (30 days to complete, undoable with gcloud projects undelete)
   ```

The same steps without the scripts (what each script runs):

```bash
terraform -chdir=infra/environments/sandbox init
export TF_VAR_db_password="$(openssl rand -base64 18)"      # throwaway; written to Secret Manager, never to state
terraform -chdir=infra/environments/sandbox apply -var-file=sandbox.tfvars
gcloud auth configure-docker europe-west1-docker.pkg.dev
docker build --platform linux/amd64 --target api    -t europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/api:TAG .
docker build --platform linux/amd64 --target worker -t europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/worker:TAG .
docker push europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/api:TAG
docker push europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/worker:TAG
terraform -chdir=infra/environments/sandbox apply -var-file=sandbox.tfvars \
  -var api_image=europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/api:TAG \
  -var worker_image=europe-west1-docker.pkg.dev/$PROJECT_ID/uploads/worker:TAG
```

### Cost

The lesson's register is a one-day sandbox under a budget alert with the project deleted at the end. Both services scale to zero (`min_instances = 0`, at most 3 instances), so nothing runs while idle. Expected spend for the exercise is cents, almost certainly under one US dollar; check the current prices before you rely on it.

| Resource | Why it is cheap here |
| --- | --- |
| Cloud Run (2 services) | request-based billing with a monthly free tier; a handful of requests |
| Pub/Sub | a monthly free allowance of data volume; messages are a few bytes |
| Secret Manager | one secret, one active version, a handful of accesses (within the free allowance) |
| Cloud Storage | a few tiny objects in `europe-west1` (the always-free storage tier covers some US regions only, so this is a fraction of a cent) |
| Artifact Registry | two small images, a cleanup policy keeps five versions and deletes after 30 days; a small storage charge after the free allowance |
| Budget | `budget_amount = 10` with alerts at 50, 90 and 100 percent, sent to the billing account's administrators |

A budget alerts; it does not cap spending. The teardown deletes the project; `scripts/teardown.sh` also deletes the budget, which lives on the billing account outside the project.

## Done when

The lesson's six steps, each with the proof. "Local" means it runs on this machine now; "needs the project" means only a real Google Cloud project can show it, and the command is ready.

| Step | Done when | Proof |
| --- | --- | --- |
| 1 | The budget exists, and an attempt to create a key for any service account fails (or the README notes the rule you follow instead). | **Needs the project:** `scripts/prove.sh` ("Step 1") lists the budget `PROJECT-budget` and tries `gcloud iam service-accounts keys create`; it must be refused. The budget and the policy are `modules/project-baseline` (tested locally by `terraform test`: one budget with three thresholds; the policy targets `iam.disableServiceAccountKeyCreation`). Without an organization the rule is: never create a key. The repository contains no `google_service_account_key` (`tests/unit/test_infrastructure_policy.py`). |
| 2 | Neither account has a project-level role, and the policy on each resource lists only the account that needs it. | **Local:** `tests/unit/test_infrastructure_policy.py` fails on any `google_project_iam_*` resource or broad role; `terraform test` asserts the bucket lists only the worker as `objectCreator`, the topic only the API as publisher, the secret only the API as accessor, the worker only the invoker as `run.invoker`. **Needs the project:** `scripts/prove.sh` ("Step 2") reads the live policies with `gcloud projects get-iam-policy`, `gcloud pubsub topics get-iam-policy`, `gcloud secrets get-iam-policy`, `gcloud storage buckets get-iam-policy`. |
| 3 | A request to the API publishes a message you can see in the topic's metrics, and the service's identity is the account you created, not the default. | **Local:** `make run` posts two uploads and the emulator delivers both; `tests/integration/test_pubsub_emulator.py` shows the message on the topic. **Needs the project:** `scripts/prove.sh` ("Step 3") checks `spec.template.spec.serviceAccountName` is `api-sa@...`, `/health` returns `{"db_password_set":true}`, and `POST /upload` returns `{"published":"..."}`; the publish count is on the topic's Metrics tab in the console. |
| 4 | Each upload request produces a result file in the bucket, and calling the worker's URL directly without a token returns 403. | **Local:** `make test-e2e` ("an upload request ends as a result file in the bucket"). **Needs the project:** `scripts/prove.sh` ("Step 4") lists `gs://BUCKET/results/NAME.txt` and expects `curl -o /dev/null -w '%{http_code}' $WORKER_URL` to print `403` (the emulators do not check tokens, so the 403 is Cloud Run's own). |
| 5 | You find the permission-denied entry in the logs naming the service account, the permission and the resource, and the message lands in the dead-letter topic after its retries. | **Local:** `make test-e2e` ("a denied worker is retried, then the message is dead-lettered"): the worker answers 500, the emulator retries, the message reaches the dead-letter subscription; `tests/unit/interfaces/test_worker.py` shows the denial text in the worker's `ERROR` log line. **Needs the project:** `scripts/break-permission.sh` removes the role, `scripts/read-denial.sh` prints the log entry (the lesson's text: `worker-sa@... does not have storage.objects.create access ... Permission 'storage.objects.create' denied on resource`) and the dead-letter message with `deliveryAttempt` 5. Paste the real text here after your run. |
| 6 | The replayed message produces its result file, and the project is scheduled for deletion. | **Local:** the same e2e test restores the store and replays `report-2`; the file appears. **Needs the project:** `scripts/restore-and-replay.sh` then `scripts/teardown.sh`, which ends by printing `DELETE_REQUESTED`. |

Review checklist from the lesson, mapped: budget and key refusal (1), own account and no project role (2), resource-level policies (2), request publishes and produces a file (3, 4), direct call returns 403 (4), denial found with account, permission and resource (5), dead letter and replay (5, 6), project scheduled for deletion (6).

## Stretch goals

| Stretch | Built? |
| --- | --- |
| Replace the push subscription with an Eventarc trigger and compare identity and retries | Not built. [ARCHITECTURE.md](ARCHITECTURE.md#extending-it) says what changes. |
| Add a custom role for the worker with only the single permission it needs | Not built; the guardrail test and the extension note say where it goes. |
| Put the API behind a load balancer with Cloud Armor | Not built; the `api_public` and `ingress` settings are the hooks. |

## Project structure

```text
.
├── README.md  ARCHITECTURE.md  CHANGELOG.md  LICENSE
├── Makefile  pyproject.toml  requirements.lock  requirements-dev.lock
├── Dockerfile  .dockerignore  docker-compose.yml  .env.example  .editorconfig  .shellcheckrc  .checkov.yaml
├── .github/workflows/ci.yml        python, terraform, emulator tests, image builds
├── src/uploads/
│   ├── domain/                     values and rules (UploadName, UploadRequested, UploadResult); imports nothing else
│   ├── application/                RequestUpload, ProcessUpload, the ports; imports domain
│   ├── infrastructure/             Pub/Sub and Cloud Storage adapters, settings, JSON logging; imports application, domain
│   └── interfaces/                 Flask apps, push envelope, gunicorn settings, entry points; imports all below
├── tests/
│   ├── unit/                       domain, application, infrastructure (fakes), interfaces, Terraform guardrails
│   ├── integration/                adapters against the emulators
│   └── e2e/                        the lesson's scenario against the emulators
├── infra/
│   ├── .tflint.hcl
│   ├── modules/                    one per reusable piece, each with a README and tests/
│   │   ├── project-baseline/  service-account/  secret/  results-bucket/
│   │   └── pubsub-push/  artifact-registry/  cloud-run-service/
│   └── environments/sandbox/       the composition: main.tf, variables.tf, outputs.tf, sandbox.tfvars.example, tests/
├── scripts/                        the runbook: create-project, deploy, build-images, prove, break-permission, read-denial,
│                                   restore-and-replay, teardown; local-demo and init_emulator for the local stack
├── tech/                           39 technology notes and an index (README.md)
└── docs/adr/                       decision records
```

Dependency rule: `interfaces` -> `infrastructure` -> `application` -> `domain`, never upward. `domain` and `application` may not import `google`, `flask` or `requests`. Both rules run in `make lint` through import-linter.

## What is simplified for teaching

- One environment (`sandbox`), local Terraform state, one region, one project.
- The API is public and unauthenticated, as the lesson says; `api_public = false` removes the public binding.
- Google-managed encryption throughout; no access-log bucket; no alert on dead-letter depth.
- The "database password" is a throwaway that only proves a secret can reach the container; there is no database, so there is no `sql/` folder.
- The emulators do not enforce IAM or OIDC; the 403 and the permission denials need the real project.

## Verification record

Last verified on 2026-10-27 on macOS with Python 3.13, Terraform 1.17.0, tflint 0.65.0 (ruleset google 0.41.0), checkov 3.3.30, Docker 24. From a fresh clone: `make install`, `make check` (103 unit tests, lint, types, import rules, shellcheck, Terraform format, tflint, 8 module and environment validations, the offline plan of 32 resources, the Terraform tests, checkov), `make test-integration` (4 tests) and `make test-e2e` (2 tests) all passed. In the working tree: `make up` and `make run` (the containers, the emulator pushing to the worker in the compose network, two result files) and `make audit` (no known vulnerabilities) passed. Not verified: anything against Google Cloud itself (IAM, OIDC tokens, Cloud Run, the log text of a denial).

## License

MIT, Copyright (c) 2026 Sumit Srivastava. See [LICENSE](LICENSE).
