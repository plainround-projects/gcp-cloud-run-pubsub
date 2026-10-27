# mypy

## 1. What it is

mypy is a **static type checker** for Python. "Static" means it studies the code without running it. Python programs can carry **type hints** (`def add(a: int, b: int) -> int`). Python ignores them when running; mypy reads them and reports places where the types do not fit: calling a function with the wrong kind of value, forgetting that something can be `None`, returning the wrong type. Version 2.4.0 is pinned in `requirements-dev.lock`.

## 2. Why this repository uses it

The rule set asks for typed code checked in CI. Types make the layers' contracts explicit: what a port accepts, what an adapter returns, which errors exist. A wrong call to a fake or a real adapter is caught before any test runs.

## 3. Where it appears

| Path | What it does with mypy |
| --- | --- |
| `pyproject.toml` | `[tool.mypy]` sets `strict = true` and the files to check. |
| `Makefile` | `make lint-python` runs `mypy`. |
| `src/`, `tests/` | The checked code, including tests. |

## 4. How it works underneath

mypy parses every file in the configured list, builds a model of all names and types (including the libraries' type information), and then checks each statement against it. A library that ships a `py.typed` marker brings its own types. For a library without types, mypy would report "missing stubs" unless told to ignore it, which the `overrides` below do for specific modules.

`strict = true` switches on a bundle of checks: every function must have annotations, no implicit `Any`, no calls to untyped functions, no returning `Any`, and more.

## 5. Walkthrough of this repository's use

`pyproject.toml`

```toml
[tool.mypy]
python_version = "3.12"
strict = true
files = ["src", "tests"]

[[tool.mypy.overrides]]
module = ["google.*"]
ignore_missing_imports = true

# google-auth ships AnonymousCredentials without annotations.
[[tool.mypy.overrides]]
module = ["uploads.infrastructure.gcs_result_store"]
disallow_untyped_calls = false

# Test functions are named for the behavior they check; annotating every one adds noise, not safety.
[[tool.mypy.overrides]]
module = ["tests.*"]
disallow_untyped_defs = false
disallow_incomplete_defs = false
disallow_untyped_calls = false

[tool.pytest.ini_options]
```

- `python_version = "3.12"`: check against Python 3.12 rules.
- `strict = true`: the strict bundle.
- `files = ["src", "tests"]`: what `mypy` checks when run with no arguments.
- `[[tool.mypy.overrides]]` is a TOML **array of tables**: each block applies extra settings to the listed `module`s. The first block ignores missing type information for the `google` libraries. The second switches off one strict check (`disallow_untyped_calls`) for the storage adapter, because `google-auth` ships `AnonymousCredentials` without annotations.
- The tests override relaxes `disallow_untyped_defs` and friends: test functions are named for the behavior they check, and annotating every one adds noise.

Typical features you will see in the typed code:

- `X | None` for "maybe nothing", checked so you cannot call a method on `None` by accident.
- `Protocol` classes for ports (see `python.md`) so a fake and the real adapter both type-check.
- `Mapping[str, str]`, `Sequence[...]` for read-only inputs.
- `-> None` on functions that return nothing.

## 6. Try it yourself

```bash
.venv/bin/mypy
```
Expected: `Success: no issues found in 45 source files`

Introduce a type error and see it caught:
```bash
printf 'def f(a: int) -> str:\n    return a\n' > /tmp/t.py && .venv/bin/mypy --strict /tmp/t.py; rm -f /tmp/t.py
```
Expected: `error: Incompatible return value type (got "int", expected "str")  [return-value]` and `Found 1 error in 1 file`.

```bash
.venv/bin/mypy --version
```
Expected: `mypy 2.4.0 (compiled: yes)`

## 7. Mistakes people make

- **Adding `# type: ignore` to silence an error** instead of fixing the cause. Where an ignore or override exists here, a comment gives the reason.
- **Using `Any` as a shortcut.** It switches the checker off for that value.
- **Treating hints as run-time checks.** Python does not enforce them; validate input at the boundary (this repository does).
- **Forgetting `Optional` handling.** `strict` makes mypy remind you.

## 8. Check yourself

1. Does Python enforce type hints when running? *No; mypy checks them separately.*
2. What does `strict = true` change? *Turns on a bundle of stricter checks, such as required annotations.*
3. What does an `overrides` block do? *Applies extra settings to specific modules.*
4. Why are tests checked too? *So fakes and helpers cannot drift from the real interfaces.*
5. What does `X | None` tell you? *The value may be missing and must be checked.*

## 9. Further reading

- mypy documentation: <https://mypy.readthedocs.io/en/stable/>
- Strict mode flags: <https://mypy.readthedocs.io/en/stable/command_line.html#cmdoption-mypy-strict>
- Type hints cheat sheet: <https://mypy.readthedocs.io/en/stable/cheat_sheet_py3.html>
