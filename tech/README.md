# Technology notes

One file per technology this repository uses, written for a reader who has never met it. Each file explains what the thing is, why the repository uses it, where it appears, how it works, then walks through this repository's own files line by line, with commands you can run and questions to check yourself.

## Ten minutes? Read these three

1. [iam-and-service-accounts.md](iam-and-service-accounts.md): the lesson's point, who is allowed to do what, and why no key exists.
2. [cloud-pubsub.md](cloud-pubsub.md): the queue between the API and the worker, retries and the dead-letter topic.
3. [cloud-run.md](cloud-run.md): where the two services run and who may call them.

## Reading order

**The language and how the project is built**

| File | Role |
| --- | --- |
| [python.md](python.md) | The language of the services and tests (3.12+): dataclasses, `Protocol`, enums, logging. |
| [pyproject-toml.md](pyproject-toml.md) | `pyproject.toml` and TOML: package metadata and every tool's settings. |
| [pip-lock-files.md](pip-lock-files.md) | Virtual environment, hash-pinned lock files, `uv`, `pip-audit`. |
| [make.md](make.md) | The `Makefile`: `make install`, `lint`, `test`, `validate`. |
| [bash.md](bash.md) | The runbook scripts under `scripts/`. |
| [unix-command-line-tools.md](unix-command-line-tools.md) | `curl`, `grep`, `sed`, `seq`, `base64`, `openssl` as used by the scripts. |
| [git.md](git.md) | The history and `.gitignore`. |
| [editorconfig.md](editorconfig.md) | One formatting habit for every editor. |

**The services' code and libraries**

| File | Role |
| --- | --- |
| [flask.md](flask.md) | The web framework behind `POST /upload` and the push endpoint. |
| [gunicorn.md](gunicorn.md) | The server that runs Flask in the container. |
| [json.md](json.md) | The format of requests, messages and log lines. |
| [requests.md](requests.md) | The HTTP library whose errors the storage adapter catches. |
| [google-api-core-and-auth.md](google-api-core-and-auth.md) | Google's shared error classes and credentials. |
| [google-cloud-pubsub.md](google-cloud-pubsub.md) | The Python client that publishes messages. |

**Google Cloud services**

| File | Role |
| --- | --- |
| [iam-and-service-accounts.md](iam-and-service-accounts.md) | Identities, roles, bindings, no keys. |
| [cloud-pubsub.md](cloud-pubsub.md) | Topics, subscriptions, push, OIDC, dead letters, the emulator. |
| [cloud-storage.md](cloud-storage.md) | Buckets and objects, create-only writes, the fake server. |
| [cloud-run.md](cloud-run.md) | The runtime for the API and the worker. |
| [secret-manager.md](secret-manager.md) | The database password, delivered without a key. |
| [artifact-registry.md](artifact-registry.md) | Where the images live. |
| [cloud-logging.md](cloud-logging.md) | JSON logs and finding the denial. |
| [budgets-and-organization-policy.md](budgets-and-organization-policy.md) | The budget alert and the no-keys policy. |
| [gcloud-cli.md](gcloud-cli.md) | The command-line tool the scripts use. |

**Infrastructure as code**

| File | Role |
| --- | --- |
| [terraform.md](terraform.md) | The infrastructure code in `infra/`. |
| [terraform-test.md](terraform-test.md) | Offline tests of the wiring with a mock provider. |
| [tflint.md](tflint.md) | Linter for the Terraform. |
| [checkov.md](checkov.md) | Security scanner and recorded exceptions. |

**Containers and local stack**

| File | Role |
| --- | --- |
| [docker.md](docker.md) | The `Dockerfile` and its two targets. |
| [docker-compose.md](docker-compose.md) | The emulators and the local stack. |
| [yaml.md](yaml.md) | The format of the Compose file, the workflow and the checkov config. |

**Tests and quality gates**

| File | Role |
| --- | --- |
| [pytest.md](pytest.md) | The test runner and coverage. |
| [ruff.md](ruff.md) | Linter and formatter for Python. |
| [mypy.md](mypy.md) | Type checker. |
| [import-linter.md](import-linter.md) | Enforces the layer rule. |
| [shellcheck.md](shellcheck.md) | Linter for the shell scripts. |
| [github-actions.md](github-actions.md) | The CI workflow that runs it all. |

The notes describe the code as it is. When the code changes, update the file that quotes it.
