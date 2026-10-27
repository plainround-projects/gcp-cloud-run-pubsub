# GitHub Actions

## 1. What it is

GitHub Actions runs automated jobs when something happens in a GitHub repository, such as a push. A **workflow** is a YAML file in `.github/workflows/`. It contains **jobs**; each job runs on a fresh virtual machine (a **runner**) and consists of **steps**: either a shell command (`run:`) or a ready-made **action** (`uses:`) such as "check out the code". This is the repository's continuous integration (**CI**): the same checks you run locally run on every push.

## 2. Why this repository uses it

The rule set says CI must run format, lint, types, tests and the dependency audit on every push, and that the CI file mirrors the local commands. The workflow calls the same `make` targets, so a green local `make check` and a green CI mean the same thing. It has not run on GitHub yet: the repository has not been pushed.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `.github/workflows/ci.yml` | The only workflow. |

## 4. How it works underneath

GitHub reads `on:` to know when to start. For every job it starts a runner (`ubuntu-latest`), runs steps in order and stops the job at the first failing step. Actions are referenced as `owner/name@version`; `actions/checkout@v4` downloads the repository, `actions/setup-python@v5` installs a Python version, `hashicorp/setup-terraform@v3` installs Terraform. A job gets a token for GitHub's API; `permissions: contents: read` limits it to reading.

## 5. Walkthrough of this repository's use

`.github/workflows/ci.yml`

```yaml
name: ci

on: [push, pull_request]

permissions:
  contents: read

jobs:
  python:
    name: Format, lint, types, import rules, unit tests with coverage, dependency audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: make lint-python test-python
      - run: make audit

  terraform:
    name: Terraform format, tflint, validate, offline plan, policy tests, checkov
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.17.0"
          terraform_wrapper: false
      - uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: v0.65.0
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install checkov==3.3.30
      - run: make lint-terraform test-terraform validate

  emulators:
    name: Integration and end-to-end tests (Pub/Sub emulator and fake Cloud Storage)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: make test-integration test-e2e
      - if: always()
        run: docker compose logs --no-color
      - if: always()
        run: docker compose down -v

  images:
    name: Both images build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make docker-build
```

- `name: ci` is the workflow's label in the GitHub UI.
- `on: [push, pull_request]` starts it on every push and every pull request.
- `permissions: contents: read` gives the built-in token the least access needed.
- `jobs:` lists parallel jobs. Each has a `name`, `runs-on: ubuntu-latest` and `steps`.
- `uses: actions/setup-python@v5` with `python-version: "3.12"` installs the oldest supported Python, so CI proves the lowest version works (the lock file is also built for 3.12).
- `run: make ...` executes the Makefile targets (see `make.md`).
- Four jobs run in parallel: `python` (lint, unit tests, audit), `terraform` (format, tflint, tests, validate, checkov with `hashicorp/setup-terraform`, `setup-tflint` and `pip install checkov==3.3.30`), `emulators` (`make test-integration test-e2e` with Docker on the runner, then the logs and `docker compose down -v` in steps marked `if: always()` so they run even after a failure) and `images` (`make docker-build`).

## 6. Try it yourself

```bash
actionlint .github/workflows/ci.yml && echo "workflow ok"
```
Expected: `workflow ok` (actionlint is a linter for workflow files; it needs no GitHub access).

```bash
grep -n "make " .github/workflows/ci.yml
```
Expected: the `make` targets CI runs; run the same ones locally.

```bash
make lint-python test-python lint-terraform test-terraform validate
```
Expected: the same pass results CI would produce.

## 7. Mistakes people make

- **A workflow that differs from the local commands.** Then "works on my machine" returns. This one calls `make`.
- **Too-broad token permissions.** The workflow sets `contents: read`.
- **Unpinned tool versions.** Terraform, TFLint and Checkov versions are pinned in the file.
- **Secrets in the workflow file.** None are used; no deployment happens from CI.

## 8. Check yourself

1. What starts the workflow? *A push or a pull request (`on:`).*
2. What is a job? *A set of steps that runs on one fresh runner.*
3. What does `uses:` do? *Runs a reusable action such as checkout.*
4. Why call `make` in `run:`? *So CI and local runs are identical.*
5. What does `permissions: contents: read` do? *Limits the token to reading the repository.*

## 9. Further reading

- GitHub Actions: <https://docs.github.com/en/actions>
- Workflow syntax: <https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions>
- actionlint: <https://github.com/rhysd/actionlint>
