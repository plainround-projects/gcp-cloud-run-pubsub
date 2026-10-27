# Make

## 1. What it is

`make` is a command-line tool that runs named recipes from a file called `Makefile`. A **target** is a name (`test`). A **recipe** is the list of shell commands under it, each line starting with a Tab character. A target can list **prerequisites**: other targets or files that must be up to date first. Make was designed to rebuild only what changed, but it is also a handy way to give a project short, memorable commands. This repository uses GNU Make syntax; the version that ships with macOS (3.81) is enough.

## 2. Why this repository uses it

The rule for every repository here is that a reader needs only a few commands: `make install`, `make lint`, `make test`, `make validate`. Each hides a longer, exact sequence of tool calls, and the CI workflow runs the very same targets, so what you run is what CI runs.

## 3. Where it appears

| Path | What it does with Make |
| --- | --- |
| `Makefile` | All targets: install, lint, format, test, validate, security, audit, emulators, up, run, down, deploy and the runbook shortcuts. |
| `.github/workflows/ci.yml` | Calls `make lint-python`, `make test-terraform`, `make test-integration` and so on. |

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

`check` has no recipe; it only has prerequisites, so it runs `lint`, `test` and `validate` in that order. You can also name several targets on one command line: `make test-integration test-e2e`.

## 6. Try it yourself

```bash
make help
```
Expected: one line per documented target (`audit`, `build-images`, `check`, ... `validate`), each followed by its description.

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
(If `.venv/.installed` is missing you will first see the install commands.)

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
