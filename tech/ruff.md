# Ruff

## 1. What it is

Ruff is a very fast Python **linter** and **formatter** written in Rust. A **linter** reads your code without running it and reports likely mistakes and style problems (an unused import, a variable named in the wrong style). A **formatter** rewrites the layout of your code (spaces, line breaks, quotes) into one fixed style, so nobody argues about it. Ruff does both with one tool and one configuration. Version 0.17.2 is pinned in `requirements-dev.lock`.

## 2. Why this repository uses it

The rule set for these repositories asks for "a formatter and a linter configured in the repository and run in CI". Ruff replaces what used to be several tools (flake8 and its plug-ins, isort, black).

## 3. Where it appears

| Path | What it does with Ruff |
| --- | --- |
| `pyproject.toml` | `[tool.ruff]` and `[tool.ruff.lint]` choose the line length, the target Python version and the rules. |
| `Makefile` | `make lint-python` runs `ruff check .` and `ruff format --check .`; `make format` fixes. |
| `.github/workflows/ci.yml` | Runs `make lint-python` on every push. |

## 4. How it works underneath

Ruff parses each `.py` file into a **syntax tree** (a structured form of the code), runs a set of **rules** over the tree, and prints a message for each hit with a rule **code** such as `E501`. Each code starts with letters that name a rule family (a "plug-in" from older tools), followed by digits. `ruff check` lints; `ruff check --fix` applies the fixes that are safe; `ruff format` rewrites the file layout; `ruff format --check` only reports files that would change and exits non-zero.

## 5. Walkthrough of this repository's use

`pyproject.toml`

```toml
[tool.ruff]
line-length = 120
target-version = "py312"
src = ["src", "tests"]
extend-exclude = ["tech"]  # the learning notes quote code fragments; ruff would re-indent them

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "N", "C4", "RUF", "PT", "S", "D100", "D101", "D103", "D104"]
# Named errors such as PublishFailed read as the event they report; the suffix would only lengthen them.
ignore = ["N818"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["D", "S101", "S105", "S106"]

[tool.mypy]
```

- `line-length = 120`: lines longer than 120 characters are reported (`E501`) and the formatter wraps at that width.
- `target-version = "py312"`: assume Python 3.12 syntax; the `UP` rules then suggest modern spellings (for example `X | None`).
- `src = ["src", "tests"]`: where first-party code lives, so import sorting can tell your imports from libraries.
- `extend-exclude = ["tech"]`: do not touch the learning notes. Ruff can also format code blocks inside Markdown, and the notes quote indented fragments of real files that it would re-indent.
- `select = [...]` lists the rule families that are switched on:
  - `E`, `F`: style errors and real mistakes (unused names, undefined names).
  - `I`: import order.
  - `B`: common bug patterns (for example a mutable default argument).
  - `UP`: code that can use newer Python features.
  - `SIM`: needlessly complicated code.
  - `N`: naming conventions (classes in `CapWords`, functions in `snake_case`).
  - `C4`: simpler comprehensions.
  - `RUF`: Ruff's own rules.
  - `PT`: pytest style.
  - `S`: security smells (hard-coded passwords, `assert` in production code, `subprocess` use).
  - `D100`, `D101`, `D103`, `D104`: docstring required on a module, a class, a public function and a package. The public surface must be documented.
- `ignore = ["N818"]` (when present) turns off one rule with a written reason: error classes here are named for the situation (`PublishFailed`), not with an `Error` suffix.
- `[tool.ruff.lint.per-file-ignores]` relaxes rules for tests: no docstrings (`D`), and `assert` is allowed (`S101`) because that is what tests do.

## 6. Try it yourself

```bash
.venv/bin/ruff --version
```
Expected: `ruff 0.17.2`

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check .
```
Expected: `All checks passed!` then `60 files already formatted`.

Make a mistake and watch it get caught:
```bash
printf 'import os\nx=1\n' > /tmp/bad.py && .venv/bin/ruff check --isolated --select F,E /tmp/bad.py; rm -f /tmp/bad.py
```
Expected: ``F401 [*] `os` imported but unused`` and a hint that a fix is available.

```bash
.venv/bin/ruff rule E501
```
Expected: the rule's name (`line-too-long`) and an explanation.

## 7. Mistakes people make

- **Silencing a rule everywhere** to make a warning go away. Here only a few rules are disabled, each with a reason in `pyproject.toml`.
- **Using `# noqa` without a code.** Say which rule (`# noqa: S104`), and remove it when it stops being needed (rule `RUF100` reports unused ones).
- **Arguing about layout.** Run `make format` and move on.
- **Formatting with one tool and linting with another** with clashing settings. One tool avoids this.

## 8. Check yourself

1. What is the difference between `ruff check` and `ruff format`? *Check finds problems; format rewrites layout.*
2. What does `E501` mean? *A line is longer than the configured limit.*
3. What does `select` do? *Chooses which rule families are active.*
4. Why are some rules relaxed for `tests/**`? *Tests legitimately use `assert` and need no docstrings.*
5. What does `ruff format --check` return when a file would change? *A non-zero exit status.*

## 9. Further reading

- Ruff documentation: <https://docs.astral.sh/ruff/>
- Rule list: <https://docs.astral.sh/ruff/rules/>
- Configuration: <https://docs.astral.sh/ruff/configuration/>
