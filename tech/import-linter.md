# import-linter

## 1. What it is

import-linter is a tool that checks **which modules import which**. You write rules in `pyproject.toml`; the tool reads the real imports in your code and fails if a rule is broken. It turns an architecture drawing ("the domain must not know about the web layer") into a test. The command is `lint-imports`.

## 2. Why this repository uses it

The code is in four layers: `domain`, `application`, `infrastructure`, `interfaces`. The dependency rule says each layer may use only the layers below it, and the inner layers must not know about libraries like Flask or Google's clients. import-linter enforces that rule on every `make lint`.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `pyproject.toml` | `[tool.importlinter]` and two `[[tool.importlinter.contracts]]`. |
| `Makefile` | `make lint-python` runs `lint-imports`. |
| `src/uploads/` | The code being checked. |

## 4. How it works underneath

import-linter uses a library called Grimp to build an **import graph**: nodes are modules, an arrow means "this module imports that one". A **contract** is a rule about the graph. A `layers` contract lists layers from highest to lowest and fails if a lower layer imports a higher one. A `forbidden` contract lists source modules and modules they may never import, directly or through a chain. `include_external_packages = true` adds libraries (and the standard library) to the graph so rules can mention them.

## 5. Walkthrough of this repository's use

`pyproject.toml`

```toml
[tool.importlinter]
root_package = "uploads"
include_external_packages = true

[[tool.importlinter.contracts]]
name = "Layers: interfaces -> infrastructure -> application -> domain, never upward"
type = "layers"
layers = [
    "uploads.interfaces",
    "uploads.infrastructure",
    "uploads.application",
    "uploads.domain",
]

[[tool.importlinter.contracts]]
name = "Domain and application know nothing about Google Cloud, Flask or the network"
type = "forbidden"
source_modules = ["uploads.domain", "uploads.application"]
forbidden_modules = ["google", "flask", "requests"]
```


- `root_package = "uploads"`: the package whose imports are analyzed.
- `include_external_packages = true`: also track imports of third-party and standard-library modules, so the second contract can name them.
- The **layers** contract lists `interfaces`, then `infrastructure`, then `application`, then `domain`. Higher entries may import lower ones; the reverse is an error. Nothing may import `interfaces`, which sits at the top.
- The **forbidden** contract says what the inner layers may never import. `google`, `flask` and `requests` are the cloud, web and network libraries; the inner layers must stay free of them so they can be tested with plain Python.

## 6. Try it yourself

```bash
.venv/bin/lint-imports
```
Expected (numbers of files and dependencies vary):
```text
Layers: interfaces -> infrastructure -> application -> domain, never upward KEPT
Domain and application know nothing about Google Cloud, Flask or the network KEPT

Contracts: 2 kept, 0 broken.
```

Break a rule on purpose, then undo it:
```bash
echo "import flask" >> src/uploads/domain/errors.py && .venv/bin/lint-imports | tail -12; git checkout src/uploads/domain/errors.py
```
Expected: the second contract is `BROKEN` with a chain ending `uploads.domain.errors -> flask (l.N)`, and the command exits non-zero. The `git checkout` restores the file.

```bash
.venv/bin/lint-imports --help | head -5
```
Expected: usage text for the command.

## 7. Mistakes people make

- **Writing the rule once and never running it.** It runs in `make lint` and CI.
- **Checking only direct imports.** The tool also finds indirect chains.
- **Letting the "domain" import a convenience library** "just this once". That is how layers erode; the contract catches it.
- **Forgetting `include_external_packages`.** Rules naming libraries then do nothing.

## 8. Check yourself

1. What does a `layers` contract enforce? *Higher layers may import lower ones, never the reverse.*
2. What does a `forbidden` contract enforce? *Listed source modules must not import listed modules, even indirectly.*
3. Why is `interfaces` at the top? *Nothing may depend on it; it depends on everything below.*
4. Which command runs the checks? *`lint-imports` (run by `make lint-python`).*
5. Why test architecture automatically? *Drawings drift; a failing check does not.*

## 9. Further reading

- import-linter documentation: <https://import-linter.readthedocs.io/en/stable/>
- Contract types: <https://import-linter.readthedocs.io/en/stable/contract_types.html>
