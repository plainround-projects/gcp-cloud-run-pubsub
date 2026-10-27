# Make

## 1. What it is

`make` is a command-line tool that runs named recipes from a file called `Makefile`. A **target** is a name (`test`). A **recipe** is the list of shell commands under it, each line starting with a Tab character. A target can list **prerequisites**: other targets or files that must be up to date first. Make was designed to rebuild only what changed, but it is also a handy way to give a project short, memorable commands. This repository uses GNU Make syntax; the version that ships with macOS (3.81) is enough.

## 2. Why this repository uses it

The rule for every repository here is that a reader needs only a few commands: `make install`, `make lint`, `make test`, `make validate`. Each hides a longer, exact sequence of tool calls, and the CI workflow runs the very same targets, so what you run is what CI runs.

## 3. Where it appears

| Path | What it does with Make |
| --- | --- |
| `Makefile` | All targets: install, lint, format, test, validate, security, audit, emulators, up, run, down, deploy and the runbook shortcuts. |
| `.github/workflows/ci.yml` | Calls `make lint-python`, `make test-terraform` and the other targets. |

## 4. How it works underneath

Make reads the whole file, builds a graph of targets and prerequisites, and then runs the recipes needed for the target you asked for, prerequisites first. For each recipe line it starts a new shell (`/bin/sh`), so a `cd` on one line does not carry to the next. If any line exits with a non-zero status Make stops and reports `Error`.

If a target name is also a **file** and that file is newer than its prerequisites, Make skips the recipe. Targets that are only commands, not files, are listed under `.PHONY` so Make always runs them. The one real file target here is `.venv/.installed`, a **stamp file**: it only records "the environment was installed", and it depends on `requirements-dev.lock` and `pyproject.toml`, so editing either makes Make rebuild the environment next time.

## 5. Walkthrough of this repository's use

### Variables and settings

`Makefile`

```make
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
ENV_DIR := infra/environments/sandbox
TF ?= terraform
COMPOSE := docker compose

-include .env
export
```

- `NAME ?= value` sets the variable only if it is not already set, so you can override it: `make PYTHON=python3.12 install`.
- `$(shell command -v python3.13 || command -v python3.12 || command -v python3)` runs a shell command while reading the file; it picks the first Python found. `command -v` prints a program's path if it exists.
- `NAME := value` evaluates once, immediately; plain `=` would re-evaluate each use.
- `-include .env` reads `.env` if it exists (the leading `-` means "do not fail if missing"), and `export` passes all variables to the commands.
- `.PHONY: ...` lists the targets that are commands, not files.

### Self-documenting help

`Makefile`

```make
help: ## list the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```

Targets whose line ends with `## text` are described by this recipe. `$(MAKEFILE_LIST)` is the list of Makefiles read. `grep` keeps lines that start with a target name and contain `## `; `sed` swaps `:...## ` for a tab; `sort` orders them. A leading `@` in a recipe line stops Make from printing the command itself. This produced the output `make help` shows.

### The stamp file

`Makefile`

```make
$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	$(VENV)/bin/pip install -q --no-deps -e .
	touch $@
```

- `$(STAMP)` expands to `.venv/.installed`. The line says "to make this file, first you need these two files".
- The recipe creates the virtual environment, installs the locked packages (`--require-hashes` makes pip check every download's hash; see `pip-lock-files.md`), installs the project itself in editable mode without dependencies, and `touch $@` creates the stamp. `$@` is "the target being built".
- Targets like `lint-python: $(STAMP)` therefore install the environment first only when it is missing or out of date.

### Test targets and shell loops

`Makefile`

```make
test-terraform:
	@for dir in infra/modules/* $(ENV_DIR); do \
	  if [ -d $$dir/tests ]; then \
	    echo "== $$dir"; \
	    (cd $$dir && $(TF) init -backend=false -input=false >/dev/null && $(TF) test) || exit 1; \
	  fi; \
	done
```

- `@for dir in ...; do ... done` is one shell command spread over lines with a trailing `\`.
- `$$dir` — a doubled dollar sign passes a single `$` to the shell. Make would otherwise treat `$dir` as its own variable.
- `(cd $$dir && $(TF) init ... && $(TF) test) || exit 1` runs in a subshell so the `cd` does not leak; if it fails the loop stops with status 1.

### Calling Make from Make

`Makefile`

```make
validate-terraform:
	@for dir in infra/modules/* $(ENV_DIR); do \
	  echo "== $$dir"; \
	  (cd $$dir && $(TF) init -backend=false -input=false >/dev/null && $(TF) validate) || exit 1; \
	done
	$(MAKE) --no-print-directory plan
```

`$(MAKE)` is Make itself, so a recipe can run another target. `--no-print-directory` hides the "Entering directory" lines.

### Aggregates and ordering

`Makefile`

```make
check: lint test validate ## everything that needs no emulator and no cloud
```

`check` has no recipe; it only has prerequisites, so it runs `lint`, `test` and `validate` in that order. You can also name several targets on one command line: `make test-python test-e2e`.

## Every target of this Makefile, one by one

The whole file, then each target in turn. A target line has the form `name: prerequisites ## description`; everything after `##` is a comment that `help` prints. A recipe line starts with a Tab; a leading `@` hides the command and shows only its output.

`Makefile`

```make
# make help lists every target. Nothing here needs a Google Cloud account except the deploy-* and prove-* targets.
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
ENV_DIR := infra/environments/sandbox
TF ?= terraform
COMPOSE := docker compose

-include .env
export

.PHONY: help install lint lint-python lint-terraform format test test-python test-terraform test-integration test-e2e \
        validate validate-terraform plan security audit check up run emulators down docker-build clean \
        deploy build-images prove teardown

help: ## list the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	$(VENV)/bin/pip install -q --no-deps -e .
	touch $@

install: $(STAMP) ## create .venv from the lock file

lint: lint-python lint-terraform ## Python (ruff, mypy, import rules), shell, Terraform format and tflint

lint-python: $(STAMP)
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/mypy
	$(VENV)/bin/lint-imports
	shellcheck scripts/*.sh

lint-terraform:
	$(TF) fmt -check -recursive -diff infra
	cd infra && tflint --init >/dev/null && tflint --recursive --config "$$PWD/.tflint.hcl"

format: $(STAMP) ## apply ruff and terraform fmt
	$(VENV)/bin/ruff check --fix .
	$(VENV)/bin/ruff format .
	$(TF) fmt -recursive infra

# Unit tests need no emulator and no cloud. The domain and application layers must stay at 95% or more.
test: test-python test-terraform ## unit tests with coverage, then the Terraform policy tests (no cloud, no emulators)

test-python: $(STAMP)
	$(PY) -m pytest tests/unit --cov=uploads --cov-report=term
	$(PY) -m coverage report --include='src/uploads/domain/*,src/uploads/application/*' --fail-under=95

# `terraform test` with a mock provider: plans each module and the environment, no credentials needed.
test-terraform:
	@for dir in infra/modules/* $(ENV_DIR); do \
	  if [ -d $$dir/tests ]; then \
	    echo "== $$dir"; \
	    (cd $$dir && $(TF) init -backend=false -input=false >/dev/null && $(TF) test) || exit 1; \
	  fi; \
	done

validate: validate-terraform security ## terraform init -backend=false, validate, an offline plan, and checkov

validate-terraform:
	@for dir in infra/modules/* $(ENV_DIR); do \
	  echo "== $$dir"; \
	  (cd $$dir && $(TF) init -backend=false -input=false >/dev/null && $(TF) validate) || exit 1; \
	done
	$(MAKE) --no-print-directory plan

# The plan needs no credentials: nothing in the configuration reads from Google Cloud, so a placeholder token is enough.
# db_password is an ephemeral variable with no default; the placeholder is never written anywhere.
plan:
	cd $(ENV_DIR) && TF_VAR_db_password=offline-placeholder GOOGLE_OAUTH_ACCESS_TOKEN=offline-placeholder $(TF) plan -input=false -lock=false \
	  -var-file=sandbox.tfvars.example

security: ## checkov over the Terraform and the Dockerfile
	checkov --config-file .checkov.yaml

audit: $(STAMP) ## check the locked dependencies for known vulnerabilities
	$(VENV)/bin/pip-audit --no-deps --disable-pip -r requirements-dev.lock

check: lint test validate ## everything that needs no emulator and no cloud

emulators: ## start the Pub/Sub emulator and a fake Cloud Storage server
	$(COMPOSE) up -d --wait --wait-timeout 900 pubsub gcs

test-integration: $(STAMP) emulators ## adapters against the emulators
	$(PY) -m pytest tests/integration -m integration

test-e2e: $(STAMP) emulators ## the lesson's scenario: API -> topic -> push -> worker -> bucket, and the failing variant
	$(PY) -m pytest tests/e2e -m e2e

up: ## build and start the emulators, the API and the worker as containers
	DB_PASSWORD=$$(openssl rand -hex 12) $(COMPOSE) --profile apps up -d --build --wait --wait-timeout 900
	$(PY) scripts/init_emulator.py

run: $(STAMP) up ## upload twice through the local stack and list the result files
	scripts/local-demo.sh

down: ## stop everything and delete the emulators' data
	$(COMPOSE) --profile apps down -v

docker-build: ## build both service images
	docker build --target api -t uploads-api:dev .
	docker build --target worker -t uploads-worker:dev .

build-images: ## build for linux/amd64 and push both images to Artifact Registry (needs the project)
	scripts/build-images.sh

deploy: ## terraform apply in two passes: placeholder images, then yours (needs the project)
	scripts/deploy.sh

prove: ## the runbook checks for Done when steps 1-4 (needs the project)
	scripts/prove.sh

teardown: ## delete the project (needs the project)
	scripts/teardown.sh

clean: down
	rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .coverage .import_linter_cache
	find infra -name .terraform -type d -prune -exec rm -rf {} +
```

- `PYTHON ?=` picks the newest Python 3.13, 3.12 or 3. `VENV`, `PY`, `STAMP` are names used below; `ENV_DIR` is the Terraform environment; `TF ?= terraform`; `COMPOSE := docker compose` is the command for Docker Compose.
- `-include .env` loads your private settings if the file exists, and `export` passes them to the commands (see `env-files.md`). `.PHONY` lists the targets that are commands, not files.
- `help`, `$(STAMP)` and `install`: the help list, the environment creation (a virtual environment, `pip install --require-hashes -r requirements-dev.lock`, `pip install --no-deps -e .`, then `touch $@`) and the target that only depends on it.
- `lint` depends on `lint-python` and `lint-terraform`. `lint-python` runs `ruff check .`, `ruff format --check .`, `mypy`, `lint-imports`, `shellcheck scripts/*.sh`. `lint-terraform` runs `terraform fmt -check -recursive -diff infra` and then, in one shell line, `cd infra && tflint --init >/dev/null && tflint --recursive --config "$$PWD/.tflint.hcl"` (`$$` hands one `$` to the shell). `format` is the fixing version.
- `test` depends on `test-python` and `test-terraform`. `test-python` runs `pytest tests/unit --cov=uploads --cov-report=term`, then `coverage report ... --fail-under=95` for the domain and application layers. `test-terraform` and `validate-terraform` are shell loops over the modules and the environment (`$$dir`, `|| exit 1`), running `terraform test` or `terraform validate` after `terraform init -backend=false -input=false`; `validate-terraform` ends by calling `$(MAKE) --no-print-directory plan`.
- `plan`: `TF_VAR_db_password=offline-placeholder` fills the ephemeral variable and `GOOGLE_OAUTH_ACCESS_TOKEN=offline-placeholder` satisfies the provider, so the plan needs no cloud; neither is written anywhere. `-input=false` never asks, `-lock=false` skips state locking, `-var-file=sandbox.tfvars.example` gives the example values.
- `security` runs checkov. `audit` runs `pip-audit --no-deps --disable-pip -r requirements-dev.lock`. `check` depends on `lint`, `test`, `validate`.
- `emulators`: `docker compose up -d --wait --wait-timeout 900 pubsub gcs` starts the two emulator containers in the background (`-d`), waits until their health checks pass (`--wait`) for up to 900 seconds, and starts only those two services.
- `test-integration` and `test-e2e` depend on the stamp and on `emulators`, then run the tests marked `integration` or `e2e` (`-m`).
- `up`: `DB_PASSWORD=$$(openssl rand -hex 12) $(COMPOSE) --profile apps up -d --build --wait --wait-timeout 900` sets a random one-off password for this command only, starts the whole stack including the services in the `apps` profile, building images (`--build`); then `scripts/init_emulator.py` creates the topics and the bucket. `run` depends on `up` and runs `scripts/local-demo.sh`. `down` runs `docker compose --profile apps down -v` (stop everything and delete the volumes).
- `docker-build` builds both images with `docker build --target api -t uploads-api:dev .` and the same for the worker. `build-images`, `deploy`, `prove`, `teardown` run their scripts (they need the project).
- `clean` depends on `down`, then removes the environment and caches and the downloaded Terraform plug-ins with `find ... -prune -exec rm -rf {} +`.

## 6. Try it yourself

```bash
make help
```
Expected: one line per documented target (`audit`, `check`, ... `validate`), each followed by its description.

```bash
make -n lint-python
```
Expected (`-n` prints the commands without running them):
```text
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/mypy
.venv/bin/lint-imports
shellcheck scripts/*.sh
```
(If `.venv/.installed` is missing, or older than `pyproject.toml` or the lock file, you will first see the install commands.)

```bash
make -n check | head -5
```
Expected: the lint commands of `check` come first.

```bash
touch pyproject.toml && make -n install | head -3
```
Expected: the install commands appear because `pyproject.toml` is now newer than the stamp.

## 7. Mistakes people make

- **Spaces instead of a Tab** in a recipe: `*** missing separator`. The `.editorconfig` in this repository forces tabs in Makefiles.
- **Forgetting `.PHONY`.** A file called `test` would make `make test` say "up to date".
- **Assuming `cd` carries to the next line.** Each line is a new shell; chain with `&&`.
- **Single `$` in shell loops.** Use `$$`.
- **Expecting `make` to stop on a failing command inside a pipe.** Use `set -o pipefail` or avoid pipes in recipes.

## 8. Check yourself

1. What starts every recipe line? *A Tab character.*
2. What is `.venv/.installed` for? *A stamp so installing only repeats when the lock file or `pyproject.toml` changes.*
3. Why `$$dir` in a recipe? *Make turns `$$` into `$` for the shell.*
4. What does `?=` do? *Sets a variable only if it has no value yet.*
5. What does `make -n` do? *Prints the commands without running them.*

## 9. Further reading

- GNU Make manual: <https://www.gnu.org/software/make/manual/make.html>
- Recipe syntax and `$$`: <https://www.gnu.org/software/make/manual/make.html#Recipes>
- Phony targets: <https://www.gnu.org/software/make/manual/make.html#Phony-Targets>
