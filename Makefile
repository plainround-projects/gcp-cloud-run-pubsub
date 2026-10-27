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
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

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
	$(COMPOSE) up -d --wait pubsub gcs

test-integration: $(STAMP) emulators ## adapters against the emulators
	$(PY) -m pytest tests/integration -m integration

test-e2e: $(STAMP) emulators ## the lesson's scenario: API -> topic -> push -> worker -> bucket, and the failing variant
	$(PY) -m pytest tests/e2e -m e2e

up: ## build and start the emulators, the API and the worker as containers
	DB_PASSWORD=$$(openssl rand -hex 12) $(COMPOSE) --profile apps up -d --build --wait
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
