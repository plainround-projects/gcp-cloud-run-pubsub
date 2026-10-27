# pyproject.toml (and TOML, setuptools)

## 1. What it is

`pyproject.toml` is the standard single file that describes a Python project: its name, version, required Python, dependencies, and the settings of its tools. It is written in **TOML**, a simple configuration format made of `[tables]` (sections) and `key = value` lines. The build backend named in it, **setuptools**, turns the folder into an installable package.

## 2. Why this repository uses it

The repository rules ask for "one tool config file". Everything — package metadata, ruff, mypy, pytest, coverage, import-linter — lives here, so a reader finds all settings in one place.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `pyproject.toml` | Metadata, dependencies, and all `[tool.*]` sections. |
| `requirements.lock`, `requirements-dev.lock` | Generated from it (see `pip-lock-files.md`). |
| `Makefile` | The install step depends on it, so editing it re-installs. |

## 4. How it works underneath

TOML has strings in quotes, numbers, booleans (`true`), arrays (`["a", "b"]`), tables (`[name]`) and arrays of tables (`[[name]]`, repeated blocks). Tools that find their own table (`[tool.ruff]`) read only that part. `pip` reads `[build-system]` to learn how to build the package, installs that backend (setuptools), and asks it to produce the package. `pip install -e .` ("editable") installs the project so that changes to `src/` take effect at once.

## 5. Walkthrough of this repository's use

`pyproject.toml`

```toml
[build-system]
requires = ["setuptools>=75"]
build-backend = "setuptools.build_meta"

[project]
name = "gcp-cloud-run-pubsub"
version = "0.1.0"
description = "An upload API and a Pub/Sub push worker on Cloud Run, each with its own service account and no keys, defined in Terraform."
readme = "README.md"
requires-python = ">=3.12"
license = { text = "MIT" }
authors = [{ name = "Sumit Srivastava" }]
dependencies = [
    "flask==3.1.3",
    "gunicorn==26.2.0",
    "google-cloud-pubsub==2.43.0",
    "google-cloud-storage==3.17.1",
    "requests>=2.32",
]

[project.optional-dependencies]
dev = [
    "pytest>=8,<10",
    "pytest-cov>=5",
    "ruff>=0.6",
    "mypy>=1.11",
    "import-linter>=2.0",
    "pip-audit>=2.7",
    "types-requests",
]

[tool.setuptools.packages.find]
where = ["src"]
```

- `[build-system]`: `requires` lists what must be installed to build; `build-backend` names the entry point.
- `[project]`: `name` and `version` identify the package. `requires-python = ">=3.12"` refuses older Pythons. `license` and `authors` are metadata.
- `dependencies = [...]` are the libraries needed at **run time**, written as `name==version` or `name>=version`. `==` pins an exact version.
- `[project.optional-dependencies]` with `dev = [...]` groups extra libraries for development (tests, linting). They install with `pip install .[dev]` (here the lock file does it).


The last table, `[tool.setuptools.packages.find] where = ["src"]`, tells setuptools that the package code is under `src/` (the "src layout"), so tests import the installed package and not the loose folder.

The remaining `[tool.*]` tables are settings for other tools; each has its own note: `ruff.md`, `mypy.md`, `pytest.md`, `import-linter.md`.

## 6. Try it yourself

```bash
.venv/bin/python -c "import tomllib; d = tomllib.load(open('pyproject.toml','rb')); print(d['project']['name'], d['project']['requires-python'])"
```
Expected: `gcp-cloud-run-pubsub >=3.12`

```bash
.venv/bin/python -c "import tomllib; d = tomllib.load(open('pyproject.toml','rb')); print(sorted(d['tool']))"
```
Expected: `['coverage', 'importlinter', 'mypy', 'pytest', 'ruff', 'setuptools']`

```bash
.venv/bin/pip show gcp-cloud-run-pubsub | head -3
```
Expected: `Name: gcp-cloud-run-pubsub` and `Version: 0.1.0` (installed in editable mode by `make install`).

## 7. Mistakes people make

- **Pinning nothing** and getting a different library tomorrow. Dependencies here are pinned, then locked with hashes.
- **Putting dev tools in run-time dependencies.** They go under the `dev` extra.
- **Tabs or odd quoting in TOML.** Strings use double quotes; arrays use brackets.
- **Editing the file and forgetting to regenerate the lock file.** See `pip-lock-files.md`.

## 8. Check yourself

1. What file format is `pyproject.toml`? *TOML.*
2. What does `requires-python` do? *Refuses to install on older Python versions.*
3. Which section lists run-time libraries? *`[project] dependencies`.*
4. What does the "src layout" mean? *Package code lives under `src/`.*
5. Where do dev-only libraries go? *`[project.optional-dependencies] dev`.*

## 9. Further reading

- Python Packaging guide: <https://packaging.python.org/en/latest/guides/writing-pyproject-toml/>
- TOML 1.0: <https://toml.io/en/v1.0.0>
- setuptools: <https://setuptools.pypa.io/en/latest/userguide/pyproject_config.html>
