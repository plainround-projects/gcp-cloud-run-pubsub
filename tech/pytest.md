# pytest (and coverage)

## 1. What it is

pytest is a Python **test runner**. A **test** is a small function that calls your code and checks the result; if a check fails, the test fails. pytest finds files named `test_*.py`, runs every function whose name starts with `test_`, and prints a summary. A plain `assert` statement is the check. **Coverage** measures which lines of your code the tests actually ran; the `pytest-cov` plug-in adds it to pytest. Versions are pinned in `requirements-dev.lock`.

## 2. Why this repository uses it

Tests are how the repository proves its rules without a cloud account: the validation rules, the error handling and the wiring all run in a few seconds. The README's "Done when" table points at them.

## 3. Where it appears

| Path | What it does with pytest |
| --- | --- |
| `tests/unit/` | Fast tests with no network: domain, application (with fakes), adapters, web or command-line layers, and checks on the infrastructure files. |
| `tests/e2e/` | The lesson's whole scenario against the emulators (API, topic, push, worker, bucket), then the failing variant with retry, dead letter and replay. Marker `e2e`; needs Docker. |
| `tests/conftest.py` | Shared **fixtures** (setup helpers) used by many tests. |
| `pyproject.toml` | `[tool.pytest.ini_options]` and `[tool.coverage.*]`. |
| `Makefile` | `make test-python` runs unit tests with coverage and fails below 95% on the domain and application layers. |
| `.github/workflows/ci.yml` | Runs the same make target on every push. |

## 4. How it works underneath

pytest imports each test file, collects the test functions, and calls them one by one. When it sees `assert a == b` it rewrites the assertion at import time so that a failure shows both values. A **fixture** is a function marked `@pytest.fixture`; a test that lists its name as a parameter receives its return value. `@pytest.mark.parametrize("x", [1, 2, 3])` runs one test function once per value. **Markers** are labels such as `e2e` that let you select tests (`-m e2e`). `monkeypatch` and `caplog` are built-in fixtures: the first changes environment variables or attributes for one test and undoes the change; the second captures log records.

Coverage works by watching which lines run. With `branch = true` it also notes whether each `if` took both ways.

## 5. Walkthrough of this repository's use

`pyproject.toml`

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra --strict-markers"
markers = [
    "integration: needs the emulators from docker-compose.yml (make emulators)",
    "e2e: runs the lesson's scenario through the real adapters against the emulators",
]
```

- `testpaths = ["tests"]`: where to look when you run plain `pytest`.
- `addopts = "-ra --strict-markers"`: `-ra` prints a summary of everything that was not a plain pass; `--strict-markers` turns an unknown marker (a typo) into an error.
- `markers = [...]` declares the allowed markers and explains them.

`pyproject.toml`

```toml
[tool.coverage.run]
source = ["uploads"]
branch = true
omit = ["src/uploads/interfaces/gunicorn_conf.py"]  # settings read by gunicorn, exercised by `make run`

[tool.coverage.report]
show_missing = true

[tool.importlinter]
```

- `source = ["uploads"]` limits measuring to this package.
- `branch = true` measures branches as well as lines.
- `show_missing = true` lists the line numbers that no test reached.

The make target:

`Makefile`

```make
test-python: $(STAMP)
	$(PY) -m pytest tests/unit --cov=uploads --cov-report=term
	$(PY) -m coverage report --include='src/uploads/domain/*,src/uploads/application/*' --fail-under=95
```

`--cov=uploads --cov-report=term` prints a coverage table; the second command (`coverage report ... --fail-under=95`) fails the build if the domain and application layers drop below 95%, which keeps the core fully tested.

### An example test

`tests/unit/application/test_process_upload.py`

```python
def test_a_duplicate_delivery_is_a_success_that_changes_nothing():
    store = InMemoryStore()
    use_case = ProcessUpload(store)
    use_case.execute(MESSAGE)
    assert use_case.execute(MESSAGE) is Outcome.ALREADY_PROCESSED
    assert len(store.objects) == 1
```

`InMemoryStore` (in `tests/unit/application/fakes.py`) is a fake that keeps objects in a dictionary and refuses to overwrite, exactly like the real adapter's contract. The test sends the same message twice and checks that the second call reports `ALREADY_PROCESSED` and that only one object exists. It needs no network and runs in milliseconds. The test name reads as the behavior it protects.

## 6. Try it yourself

```bash
make test-python
```
Expected: a line of dots, then a coverage table ending with `TOTAL` and a pass count such as `103 passed`.

```bash
.venv/bin/python -m pytest tests/unit -q -p no:cacheprovider -k "duplicate or malformed"
```
Expected: only the tests whose names contain the words run; the others show as deselected.

```bash
.venv/bin/python -m pytest tests/unit --collect-only -q -p no:cacheprovider | tail -3
```
Expected: the last lines list test ids and a count like `103 tests collected`.

```bash
.venv/bin/python -m coverage report --include='src/uploads/domain/*,src/uploads/application/*' --fail-under=95 | tail -3
```
Expected: a `TOTAL` line at or above 95% (run `make test-python` first so coverage data exists).

## 7. Mistakes people make

- **Tests that need the network or the cloud.** These are slow and flaky; this repository keeps them in a separate folder and behind markers or containers.
- **Tests that depend on each other's order.** Each test builds its own world.
- **Asserting too little** (`assert result`) or too much (every field of a huge object). Assert the behavior the test name states.
- **Chasing 100% coverage.** Coverage shows what was not run; it does not prove the checks were good.
- **Forgetting that a hidden bug can sit on a path no test takes.** This project once had a logging bug visible only at INFO level; a regression test now runs at INFO.

## 8. Check yourself

1. How does pytest decide something is a test? *File named `test_*.py`, function named `test_*`.*
2. What is a fixture? *A setup function whose result is passed to tests by name.*
3. What does `parametrize` do? *Runs one test with several inputs.*
4. What does `--strict-markers` prevent? *Silent typos in marker names.*
5. What does `branch = true` add to coverage? *Whether both outcomes of each condition ran.*

## 9. Further reading

- pytest documentation: <https://docs.pytest.org/en/stable/>
- Fixtures: <https://docs.pytest.org/en/stable/how-to/fixtures.html>
- Parametrize: <https://docs.pytest.org/en/stable/how-to/parametrize.html>
- Coverage.py: <https://coverage.readthedocs.io/>
- pytest-cov: <https://pytest-cov.readthedocs.io/>
