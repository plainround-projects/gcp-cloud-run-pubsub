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

## Every test file, and what each test proves

The basics first, as they appear in every file below.

- A **test** is a function whose name starts with `test_`. pytest finds it, calls it, and reports a pass if it returns normally and a failure if it raises an exception.
- `assert expression` raises `AssertionError` when the expression is false; pytest shows both sides of a failed comparison.
- A **fixture** is a helper marked `@pytest.fixture` whose result pytest passes to any test that names it as a parameter. Built-in fixtures used here: `monkeypatch` (temporarily set an environment variable or replace an attribute, undone after the test) and `caplog` (captures log records so the test can read them).
- `@pytest.mark.parametrize` runs one test several times with different inputs, each run reported separately.
- `with pytest.raises(SomeError, match="text"):` passes only if the code inside raises that exception and its message matches `text` (a regular expression).
- A **fake** is a small class that stands in for a real dependency so a test needs no network. `FakeBlob`, `FakeBucket`, `FakeFuture`, `FakeClient` in the adapter tests, and `InMemoryPublisher`, `InMemoryStore` in `fakes.py`, are fakes.
- Flask's `app.test_client()` is a pretend web browser: `client.post("/upload", json={...})` calls the route function directly and returns a response object with `.status_code` and `.get_json()`, with no server or port.

### `tests/unit/domain/test_upload.py`

`tests/unit/domain/test_upload.py`

```python
import json

import pytest

from uploads.domain.errors import InvalidUploadName, MalformedUploadMessage
from uploads.domain.upload import UploadName, UploadRequested, UploadResult


@pytest.mark.parametrize("name", ["report-1", "a", "Report_2.v3", "x" * 128, "2026-10-26.csv"])
def test_accepts_names_that_are_safe_object_name_parts(name):
    assert str(UploadName(name)) == name


@pytest.mark.parametrize(
    "name",
    ["", " ", "../etc", "a/b", "a..b", "-leading", ".hidden", "x" * 129, "white space", "ünïcode", None, 7, ["a"]],
)
def test_rejects_names_that_could_escape_the_results_prefix_or_are_not_text(name):
    with pytest.raises(InvalidUploadName):
        UploadName(name)


def test_event_is_built_from_a_request_body_and_round_trips_through_bytes():
    event = UploadRequested.from_request_body({"name": "report-1", "ignored": True})
    assert event.encode() == b'{"name":"report-1"}'
    assert UploadRequested.decode(event.encode()) == event


def test_request_body_without_a_name_is_invalid():
    with pytest.raises(InvalidUploadName):
        UploadRequested.from_request_body({})


@pytest.mark.parametrize(
    "data",
    [b"not json", b"\xff\xfe", b"[]", b'"text"', b"{}", json.dumps({"name": "../x"}).encode(), b'{"name": 5}'],
)
def test_decoding_a_message_that_is_not_an_upload_request_raises_a_named_error(data):
    with pytest.raises(MalformedUploadMessage):
        UploadRequested.decode(data)


def test_result_file_is_under_results_with_the_lessons_body():
    result = UploadResult.for_request(UploadRequested(UploadName("report-1")))
    assert result.key == "results/report-1.txt"
    assert result.body == "processed report-1\n"
```

- Accepted names: `report-1`, `a`, `Report_2.v3`, a 128-character name and `2026-10-26.csv` each round-trip through `str(UploadName(name))`.
- Rejected names (thirteen cases): empty, only a space, `../etc`, `a/b`, `a..b`, a leading hyphen, a leading dot, 129 characters, a space inside, non-ASCII letters, `None`, a number and a list. Each must raise `InvalidUploadName`.
- The event test checks the exact bytes `{"name":"report-1"}` (extra keys in the body are ignored) and that `decode(encode(event)) == event`: a **round trip**.
- A body with no name is invalid. Seven bad message payloads (not JSON, bytes that are not text, a list, a bare string, an object without `name`, a path-like name, a number) each raise `MalformedUploadMessage`.
- The last test checks the result key `results/report-1.txt` and the body `processed report-1` plus a line break.

### `tests/unit/application/test_request_upload.py` and `test_process_upload.py`

`tests/unit/application/test_request_upload.py`

```python
import pytest

from tests.unit.application.fakes import InMemoryPublisher
from uploads.application.ports import PublishFailed
from uploads.application.request_upload import RequestUpload
from uploads.domain.errors import InvalidUploadName


def test_a_valid_request_publishes_one_message_and_returns_its_id():
    publisher = InMemoryPublisher()
    receipt = RequestUpload(publisher).execute({"name": "report-1"})
    assert receipt.message_id == "1"
    assert publisher.published == [b'{"name":"report-1"}']


def test_an_invalid_name_publishes_nothing():
    publisher = InMemoryPublisher()
    with pytest.raises(InvalidUploadName):
        RequestUpload(publisher).execute({"name": "../x"})
    assert publisher.published == []


def test_a_broker_failure_propagates_as_the_named_port_error():
    with pytest.raises(PublishFailed, match="PermissionDenied"):
        RequestUpload(InMemoryPublisher(fail_with="PermissionDenied: no publisher role")).execute({"name": "a"})
```

`tests/unit/application/test_process_upload.py`

```python
import pytest

from tests.unit.application.fakes import InMemoryStore
from uploads.application.ports import StoreFailed
from uploads.application.process_upload import Outcome, ProcessUpload
from uploads.domain.errors import MalformedUploadMessage

MESSAGE = b'{"name":"report-1"}'


def test_a_message_creates_its_result_file():
    store = InMemoryStore()
    assert ProcessUpload(store).execute(MESSAGE) is Outcome.CREATED
    assert store.objects == {"results/report-1.txt": "processed report-1\n"}


def test_a_duplicate_delivery_is_a_success_that_changes_nothing():
    store = InMemoryStore()
    use_case = ProcessUpload(store)
    use_case.execute(MESSAGE)
    assert use_case.execute(MESSAGE) is Outcome.ALREADY_PROCESSED
    assert len(store.objects) == 1


def test_a_malformed_message_writes_nothing():
    store = InMemoryStore()
    with pytest.raises(MalformedUploadMessage):
        ProcessUpload(store).execute(b"nope")
    assert store.write_attempts == 0


def test_a_store_failure_is_not_swallowed():
    with pytest.raises(StoreFailed):
        ProcessUpload(InMemoryStore(fail_with="Forbidden")).execute(MESSAGE)
```

- Request: a valid request publishes exactly one message and returns its id; an invalid name publishes nothing (`publisher.published == []`); a broker failure propagates as `PublishFailed` and its text contains `PermissionDenied`.
- Process: a message creates its result file (`is Outcome.CREATED` compares by identity, right for enum members); a duplicate delivery is a success that changes nothing; a malformed message writes nothing (`write_attempts == 0`); a store failure is not swallowed.

### `tests/unit/infrastructure/test_settings.py`

`tests/unit/infrastructure/test_settings.py`

```python
import pytest

from uploads.infrastructure.settings import ApiSettings, ConfigError, Secret, WorkerSettings


def test_api_settings_take_defaults_and_keep_the_password_secret():
    settings = ApiSettings.from_env({"PROJECT_ID": "demo-project", "DB_PASSWORD": "hunter2"})
    assert settings.topic_id == "uploads"
    assert settings.publish_timeout_seconds == 10.0
    assert settings.db_password is not None
    assert settings.db_password.reveal() == "hunter2"
    assert "hunter2" not in repr(settings)
    assert "hunter2" not in str(settings.db_password)


def test_api_settings_without_a_password_have_none():
    assert ApiSettings.from_env({"PROJECT_ID": "p", "DB_PASSWORD": ""}).db_password is None


def test_every_problem_is_reported_at_once():
    with pytest.raises(ConfigError) as caught:
        ApiSettings.from_env({"PUBLISH_TIMEOUT_SECONDS": "soon", "LOG_LEVEL": "LOUD"})
    message = str(caught.value)
    assert "PROJECT_ID is required" in message
    assert "PUBLISH_TIMEOUT_SECONDS must be a number" in message
    assert "LOG_LEVEL must be" in message


def test_a_timeout_of_zero_or_less_is_rejected():
    with pytest.raises(ConfigError, match="greater than zero"):
        WorkerSettings.from_env({"BUCKET": "b", "STORE_TIMEOUT_SECONDS": "0"})


def test_worker_settings_need_a_bucket_and_project_is_optional():
    with pytest.raises(ConfigError, match="BUCKET is required"):
        WorkerSettings.from_env({})
    settings = WorkerSettings.from_env({"BUCKET": "demo-results", "LOG_LEVEL": "debug"})
    assert (settings.bucket, settings.project_id, settings.log_level) == ("demo-results", None, "DEBUG")


def test_secret_repr_is_masked():
    assert repr(Secret("x")) == "Secret(***)"
```

Defaults (`topic_id == "uploads"`, timeout `10.0`) and the secret staying secret (the password text appears neither in `repr(settings)` nor in `str(secret)`); an empty password means `None`; every problem reported in one message; a zero timeout rejected; the worker needs a bucket and the project is optional (`log_level` is upper-cased); a `Secret` prints as `Secret(***)`.

### `tests/unit/infrastructure/test_logging.py`

`tests/unit/infrastructure/test_logging.py`

```python
import json
import logging

from uploads.infrastructure.logging import JsonFormatter, configure_logging


def _format(**kwargs):
    record = logging.LogRecord("t", logging.ERROR, __file__, 1, "went %s", ("wrong",), None)
    for key, value in kwargs.items():
        setattr(record, key, value)
    return json.loads(JsonFormatter().format(record))


def test_a_record_is_one_json_object_with_severity_and_message():
    entry = _format()
    assert entry["severity"] == "ERROR"
    assert entry["message"] == "went wrong"


def test_extra_fields_become_top_level_keys():
    assert _format(message_id="42")["message_id"] == "42"


def test_exceptions_are_included_as_text():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("t", logging.ERROR, __file__, 1, "failed", None, sys.exc_info())
    assert "ValueError: boom" in json.loads(JsonFormatter().format(record))["exception"]


def test_configure_logging_is_idempotent_and_sets_the_level():
    configure_logging("WARNING")
    configure_logging("WARNING")
    root = logging.getLogger()
    assert len(root.handlers) == 1
    assert root.level == logging.WARNING
```

`_format` builds a `LogRecord` by hand and formats it. Tests: one JSON object with `severity` and the filled-in message (`"went %s"` with `("wrong",)` gives `went wrong`); extra fields become top-level keys; an exception appears as text; calling `configure_logging` twice leaves exactly one handler and sets the level.

### `tests/unit/infrastructure/test_pubsub_publisher.py`

`tests/unit/infrastructure/test_pubsub_publisher.py`

```python
import pytest
from google.api_core.exceptions import PermissionDenied

from uploads.application.ports import PublishFailed
from uploads.infrastructure.pubsub_publisher import PubSubPublisher, build_publisher
from uploads.infrastructure.settings import ApiSettings


class FakeFuture:
    def __init__(self, outcome):
        self._outcome = outcome
        self.timeout = None

    def result(self, timeout=None):
        self.timeout = timeout
        if isinstance(self._outcome, Exception):
            raise self._outcome
        return self._outcome


class FakeClient:
    def __init__(self, outcome):
        self.future = FakeFuture(outcome)
        self.calls = []
        self.stopped = False

    def publish(self, topic, data):
        self.calls.append((topic, data))
        return self.future

    def stop(self):
        self.stopped = True


def test_publish_sends_to_the_topic_and_waits_within_the_deadline():
    client = FakeClient("msg-1")
    publisher = PubSubPublisher(client, "projects/p/topics/uploads", 7.5)
    assert publisher.publish(b"x") == "msg-1"
    assert client.calls == [("projects/p/topics/uploads", b"x")]
    assert client.future.timeout == 7.5


@pytest.mark.parametrize("error", [PermissionDenied("no publisher role"), TimeoutError()])
def test_broker_errors_and_timeouts_become_publish_failed_with_the_original_text(error):
    publisher = PubSubPublisher(FakeClient(error), "projects/p/topics/uploads", 1)
    with pytest.raises(PublishFailed) as caught:
        publisher.publish(b"x")
    assert type(error).__name__ in str(caught.value)
    assert caught.value.__cause__ is error


def test_close_stops_the_client():
    client = FakeClient("1")
    PubSubPublisher(client, "t", 1).close()
    assert client.stopped


def test_build_publisher_uses_the_settings_topic(monkeypatch):
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", "localhost:1")
    settings = ApiSettings.from_env({"PROJECT_ID": "demo", "TOPIC_ID": "t1", "PUBLISH_TIMEOUT_SECONDS": "3"})
    publisher = build_publisher(settings)
    try:
        assert publisher._topic_path == "projects/demo/topics/t1"
        assert publisher._timeout == 3
    finally:
        publisher.close()
```

`FakeFuture` returns a value or raises an exception when `.result()` is called and remembers the timeout it was given. `FakeClient` records `publish` calls and whether `stop` was called. The tests: publishing sends to the topic path and waits with the configured deadline (7.5); a permission error and a timeout each become `PublishFailed` containing the original class name, with the original error attached as `__cause__`; `close` stops the client; `build_publisher` builds the topic path `projects/demo/topics/t1` and the timeout (the emulator variable prevents any credential lookup).

### `tests/unit/infrastructure/test_gcs_result_store.py`

`tests/unit/infrastructure/test_gcs_result_store.py`

```python
import pytest
import requests
from google.api_core.exceptions import Forbidden, PreconditionFailed

from uploads.application.ports import StoreFailed
from uploads.infrastructure.gcs_result_store import GcsResultStore, build_store
from uploads.infrastructure.settings import WorkerSettings


class FakeBlob:
    def __init__(self, error):
        self._error = error
        self.uploads = []

    def upload_from_string(self, content, **kwargs):
        if self._error:
            raise self._error
        self.uploads.append((content, kwargs))


class FakeBucket:
    def __init__(self, error=None):
        self.blob_instance = FakeBlob(error)
        self.names = []

    def blob(self, name):
        self.names.append(name)
        return self.blob_instance


def test_the_write_is_conditional_on_the_object_not_existing():
    bucket = FakeBucket()
    assert GcsResultStore(bucket, 12).create_if_absent("results/a.txt", "processed a\n") is True
    content, kwargs = bucket.blob_instance.uploads[0]
    assert bucket.names == ["results/a.txt"]
    assert content == "processed a\n"
    assert kwargs["if_generation_match"] == 0
    assert kwargs["timeout"] == 12


def test_an_existing_object_is_reported_not_overwritten():
    assert GcsResultStore(FakeBucket(PreconditionFailed("exists")), 1).create_if_absent("k", "v") is False


@pytest.mark.parametrize(
    "error",
    [
        Forbidden("worker-sa does not have storage.objects.create access"),
        TimeoutError(),
        requests.ConnectionError("reset"),
    ],
)
def test_other_failures_become_store_failed_keeping_the_denial_text(error):
    with pytest.raises(StoreFailed) as caught:
        GcsResultStore(FakeBucket(error), 1).create_if_absent("k", "v")
    assert type(error).__name__ in str(caught.value)
    assert caught.value.__cause__ is error


def test_build_store_uses_anonymous_credentials_for_the_emulator(monkeypatch):
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", "http://localhost:1")
    store = build_store(WorkerSettings.from_env({"BUCKET": "demo-results", "STORE_TIMEOUT_SECONDS": "4"}))
    assert store._bucket.name == "demo-results"
    assert store._timeout == 4


def test_build_store_uses_application_default_credentials_in_the_cloud(monkeypatch):
    seen = {}

    class FakeClient:
        def __init__(self, **kwargs):
            seen.update(kwargs)

        def bucket(self, name):
            return name

    monkeypatch.delenv("STORAGE_EMULATOR_HOST", raising=False)
    monkeypatch.setattr("uploads.infrastructure.gcs_result_store.storage.Client", FakeClient)
    store = build_store(WorkerSettings.from_env({"BUCKET": "demo-results", "PROJECT_ID": "demo"}))
    assert seen == {"project": "demo"}
    assert store._bucket == "demo-results"
```

`FakeBlob` raises the error it was given or records the upload; `FakeBucket.blob(name)` returns it. Tests: the write is conditional (`if_generation_match == 0`) with the configured timeout; `PreconditionFailed` means "exists" and gives `False`; `Forbidden`, `TimeoutError` and a requests connection error each become `StoreFailed` keeping the class name and the cause; `build_store` picks anonymous credentials for the emulator and application default credentials otherwise (the second test replaces `storage.Client` with a fake that records its arguments, using `monkeypatch.setattr`).

### `tests/unit/interfaces/test_api.py`

`tests/unit/interfaces/test_api.py`

```python
import logging

import pytest

from tests.unit.application.fakes import InMemoryPublisher
from uploads.application.request_upload import RequestUpload
from uploads.interfaces.api import create_app


@pytest.fixture
def publisher():
    return InMemoryPublisher()


def client_for(publisher, db_password_set=True):
    return create_app(RequestUpload(publisher), db_password_set).test_client()


def test_post_upload_publishes_and_answers_202_with_the_message_id(publisher):
    response = client_for(publisher).post("/upload", json={"name": "report-1"})
    assert response.status_code == 202
    assert response.get_json() == {"published": "1"}
    assert publisher.published == [b'{"name":"report-1"}']


@pytest.mark.parametrize("payload", [{"name": "../x"}, {}, {"name": 5}])
def test_an_invalid_name_is_a_400_and_publishes_nothing(publisher, payload):
    response = client_for(publisher).post("/upload", json=payload)
    assert response.status_code == 400
    assert "error" in response.get_json()
    assert publisher.published == []


@pytest.mark.parametrize(
    "kwargs", [{"data": "not json"}, {"json": ["a"]}, {"data": "", "content_type": "application/json"}]
)
def test_a_body_that_is_not_a_json_object_is_a_400(publisher, kwargs):
    assert client_for(publisher).post("/upload", **kwargs).status_code == 400


def test_a_publish_failure_is_a_503_and_is_logged_with_the_cause(caplog):
    broken = InMemoryPublisher(fail_with="PermissionDenied: api-sa lacks pubsub.topics.publish")
    with caplog.at_level(logging.ERROR, logger="uploads.api"):
        response = client_for(broken).post("/upload", json={"name": "a"})
    assert response.status_code == 503
    assert "api-sa lacks pubsub.topics.publish" in caplog.records[0].error
    assert "PermissionDenied" not in response.get_data(as_text=True)


@pytest.mark.parametrize("password_set", [True, False])
def test_health_says_whether_the_secret_is_set_and_never_its_value(publisher, password_set):
    response = client_for(publisher, password_set).get("/health")
    assert response.get_json() == {"db_password_set": password_set}


def test_an_oversized_body_is_refused(publisher):
    response = client_for(publisher).post("/upload", data=b"x" * 70_000, content_type="application/json")
    assert response.status_code == 413


def test_a_successful_upload_logs_at_info_without_breaking_the_response(publisher, caplog):
    # Regression: extra={"name": ...} collides with LogRecord.name and raised KeyError only when INFO was enabled.
    with caplog.at_level(logging.INFO, logger="uploads.api"):
        response = client_for(publisher).post("/upload", json={"name": "report-1"})
    assert response.status_code == 202
    assert caplog.records[0].upload_name == "report-1"
    assert caplog.records[0].message_id == "1"
```

Covers `POST /upload` and `GET /health`: 202 and the message id on success; 400 for a bad name (three payloads) and for bodies that are not JSON objects (three kinds); 503 for a publish failure, with the cause logged (`caplog.records[0].error`) but not shown to the caller; `/health` reports only whether the secret is set; 413 for a body over 64 KiB (70,000 bytes); and a regression test: an `extra` field named `name` collided with a built-in log field and raised an error only when INFO logging was on, so the code uses `upload_name`.

### `tests/unit/interfaces/test_push_envelope.py` and `test_worker.py`

`tests/unit/interfaces/test_push_envelope.py`

```python
import base64

import pytest

from uploads.interfaces.push_envelope import InvalidEnvelope, parse_push_envelope


def _envelope(data):
    return {"message": {"data": data, "messageId": "7"}, "subscription": "projects/p/subscriptions/uploads-push"}


def test_a_valid_envelope_yields_decoded_bytes_and_ids():
    pushed = parse_push_envelope(_envelope(base64.b64encode(b'{"name":"a"}').decode()))
    assert (pushed.message_id, pushed.data, pushed.subscription) == (
        "7",
        b'{"name":"a"}',
        "projects/p/subscriptions/uploads-push",
    )


@pytest.mark.parametrize(
    "body",
    [None, [], "x", {}, {"message": "x"}, {"message": {}}, {"message": {"data": 5}}, _envelope("***not base64***")],
)
def test_anything_else_is_an_invalid_envelope(body):
    with pytest.raises(InvalidEnvelope):
        parse_push_envelope(body)
```

`tests/unit/interfaces/test_worker.py`

```python
import base64
import json
import logging

import pytest

from tests.unit.application.fakes import InMemoryStore
from uploads.application.process_upload import ProcessUpload
from uploads.interfaces.worker import create_app


def push(name="report-1"):
    data = base64.b64encode(json.dumps({"name": name}).encode()).decode()
    return {"message": {"data": data, "messageId": "9"}, "subscription": "projects/p/subscriptions/uploads-push"}


def client_for(store):
    return create_app(ProcessUpload(store)).test_client()


def test_a_delivery_writes_the_result_and_acknowledges_with_204():
    store = InMemoryStore()
    response = client_for(store).post("/", json=push())
    assert response.status_code == 204
    assert store.objects == {"results/report-1.txt": "processed report-1\n"}


def test_a_redelivery_is_acknowledged_too():
    store = InMemoryStore()
    client = client_for(store)
    client.post("/", json=push())
    assert client.post("/", json=push()).status_code == 204


def test_a_failing_write_answers_500_never_2xx_and_logs_the_denial(caplog):
    denial = "Forbidden: worker-sa does not have storage.objects.create access"
    with caplog.at_level(logging.ERROR, logger="uploads.worker"):
        response = client_for(InMemoryStore(fail_with=denial)).post("/", json=push())
    assert response.status_code == 500
    assert denial in caplog.records[0].error


@pytest.mark.parametrize("body", [{}, {"message": {"data": "!!"}}, push(name="../x")])
def test_a_delivery_that_can_never_succeed_gets_a_4xx_so_it_is_dead_lettered_not_acknowledged(body):
    store = InMemoryStore()
    assert client_for(store).post("/", json=body).status_code == 400
    assert store.write_attempts == 0


def test_health_is_ok():
    assert client_for(InMemoryStore()).get("/health").status_code == 200


def test_a_processed_delivery_logs_at_info_without_breaking_the_response(caplog):
    with caplog.at_level(logging.INFO, logger="uploads.worker"):
        response = client_for(InMemoryStore()).post("/", json=push())
    assert response.status_code == 204
    assert (caplog.records[0].message_id, caplog.records[0].outcome) == ("9", "created")
```

- Envelope: a valid envelope decodes to bytes and ids; eight wrong shapes (`None`, a list, a string, `{}`, wrong nesting, no data, data not text, text that is not base64) raise `InvalidEnvelope`.
- Worker: a delivery writes the result and answers 204; a redelivery is acknowledged too; a failing write answers 500 (never a 2xx) and logs the denial text; three deliveries that can never succeed get 400 and write nothing; `/health` is 200; a processed delivery logs `message_id` and `outcome`. `push(name)` builds an envelope with `base64.b64encode`.

### `tests/unit/interfaces/test_entrypoints.py`

`tests/unit/interfaces/test_entrypoints.py`

```python
import pytest

from uploads.infrastructure.settings import ConfigError
from uploads.interfaces import api_main, worker_main


def test_the_api_factory_builds_an_app_that_reports_the_secret_without_revealing_it(monkeypatch):
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", "localhost:1")
    monkeypatch.setenv("PROJECT_ID", "demo")
    monkeypatch.setenv("DB_PASSWORD", "not-shown")
    response = api_main.create().test_client().get("/health")
    assert response.get_json() == {"db_password_set": True}
    assert "not-shown" not in response.get_data(as_text=True)


def test_the_worker_factory_builds_an_app(monkeypatch):
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", "http://localhost:1")
    monkeypatch.setenv("BUCKET", "demo-results")
    assert worker_main.create().test_client().get("/health").status_code == 200


def test_a_missing_setting_stops_startup_with_a_clear_message(monkeypatch):
    monkeypatch.delenv("BUCKET", raising=False)
    with pytest.raises(ConfigError, match="BUCKET is required"):
        worker_main.create()
```

Runs the two `create()` factories with environment variables set by `monkeypatch`: the API app reports the secret as set without revealing it; the worker app answers `/health`; a missing `BUCKET` stops startup with a clear `ConfigError`.

### `tests/unit/test_infrastructure_policy.py`

`tests/unit/test_infrastructure_policy.py`

```python
"""Guardrails over the Terraform source, checked without Terraform or Google Cloud.

These encode the lesson's rules as tests so a change that breaks one fails in CI: no keys, no project-level roles,
no broad roles, and public access only where it is asked for.
"""

import re
from pathlib import Path

import pytest

INFRA = Path(__file__).resolve().parents[2] / "infra"
SOURCES = {path: path.read_text() for path in INFRA.rglob("*.tf") if ".terraform" not in path.parts}
CODE = {path: re.sub(r"(?m)^\s*#.*$", "", text) for path, text in SOURCES.items()}


def _hits(pattern: str) -> list[str]:
    return [str(path.relative_to(INFRA)) for path, text in CODE.items() if re.search(pattern, text)]


def test_the_sources_were_found():
    assert len(SOURCES) >= 20


def test_no_service_account_key_is_ever_created():
    assert _hits(r'resource\s+"google_service_account_key"') == []


@pytest.mark.parametrize(
    "kind", ["google_project_iam_member", "google_project_iam_binding", "google_project_iam_policy"]
)
def test_no_project_level_role_is_granted(kind):
    assert _hits(rf'resource\s+"{kind}"') == []


@pytest.mark.parametrize(
    "role", ["roles/owner", "roles/editor", "roles/storage.admin", "roles/storage.objectAdmin", "roles/pubsub.admin"]
)
def test_no_broad_role_appears(role):
    assert _hits(re.escape(role)) == []


def test_all_authenticated_users_is_never_used():
    assert _hits("allAuthenticatedUsers") == []


def test_all_users_appears_only_in_the_sandbox_api_toggle():
    assert _hits('"allUsers"') == ["environments/sandbox/main.tf"]


def test_every_cloud_run_service_names_its_service_account():
    text = (INFRA / "modules/cloud-run-service/main.tf").read_text()
    assert "service_account = var.service_account_email" in text


def test_the_provider_is_pinned_in_every_root_and_module():
    for path in INFRA.rglob("versions.tf"):
        if ".terraform" in path.parts:
            continue
        assert re.search(r'version\s*=\s*"(~>|>=)\s*8', path.read_text()), path
```

The pattern-matching part was explained in `regular-expressions` terms in `iam-and-service-accounts.md`. The rules: at least 20 Terraform files were found; no `google_service_account_key`; none of the three project-level IAM kinds; none of five broad roles; no `allAuthenticatedUsers`; `"allUsers"` appears only in the sandbox environment (its public-API toggle); the Cloud Run module always names its service account; the provider is pinned everywhere.

### `tests/integration/test_pubsub_emulator.py` and `test_gcs_emulator.py`

`tests/integration/test_pubsub_emulator.py`

```python
"""The Pub/Sub adapter against the real emulator."""

import pytest
from google.cloud import pubsub_v1

from uploads.application.ports import PublishFailed
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings

pytestmark = pytest.mark.integration


def test_a_published_message_arrives_on_a_subscription_of_the_topic(emulators, unique):
    publisher_client = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    topic = publisher_client.topic_path("local-project", f"it-{unique}")
    subscription = subscriber.subscription_path("local-project", f"it-{unique}-pull")
    publisher_client.create_topic(request={"name": topic})
    subscriber.create_subscription(request={"name": subscription, "topic": topic})

    publisher = build_publisher(
        ApiSettings.from_env(
            {"PROJECT_ID": "local-project", "TOPIC_ID": f"it-{unique}", "PUBLISH_TIMEOUT_SECONDS": "10"}
        )
    )
    try:
        message_id = publisher.publish(b'{"name":"report-1"}')
    finally:
        publisher.close()

    pulled = subscriber.pull(request={"subscription": subscription, "max_messages": 1}, timeout=15)
    assert [m.message.data for m in pulled.received_messages] == [b'{"name":"report-1"}']
    assert pulled.received_messages[0].message.message_id == message_id


def test_publishing_to_a_missing_topic_is_a_publish_failed_with_the_service_error(emulators, unique):
    publisher = build_publisher(
        ApiSettings.from_env(
            {"PROJECT_ID": "local-project", "TOPIC_ID": f"missing-{unique}", "PUBLISH_TIMEOUT_SECONDS": "5"}
        )
    )
    try:
        with pytest.raises(PublishFailed, match="NotFound"):
            publisher.publish(b"x")
    finally:
        publisher.close()
```

`tests/integration/test_gcs_emulator.py`

```python
"""The Cloud Storage adapter against a fake Cloud Storage server."""

import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage

from uploads.application.ports import StoreFailed
from uploads.infrastructure.gcs_result_store import build_store
from uploads.infrastructure.settings import WorkerSettings

pytestmark = pytest.mark.integration


def _bucket(unique):
    client = storage.Client(project="local-project", credentials=AnonymousCredentials())
    return client.create_bucket(f"it-{unique}")


def test_an_object_is_created_once_and_never_overwritten(emulators, unique):
    bucket = _bucket(unique)
    store = build_store(WorkerSettings.from_env({"BUCKET": bucket.name}))

    assert store.create_if_absent("results/a.txt", "processed a\n") is True
    assert store.create_if_absent("results/a.txt", "something else\n") is False
    assert bucket.blob("results/a.txt").download_as_text() == "processed a\n"


def test_writing_to_a_missing_bucket_is_a_store_failed_with_the_service_error(emulators, unique):
    store = build_store(WorkerSettings.from_env({"BUCKET": f"missing-{unique}", "STORE_TIMEOUT_SECONDS": "5"}))
    with pytest.raises(StoreFailed, match="NotFound"):
        store.create_if_absent("results/a.txt", "x")
```

These need the emulators (`make emulators`, see `docker-compose.md`), which is why they use the `emulators` fixture and the `integration` marker. The Pub/Sub test creates a topic and a pull subscription, publishes through the real adapter, pulls the message and compares the data and the id; publishing to a missing topic raises `PublishFailed` mentioning `NotFound`. The storage test creates a bucket, writes once (`True`), writes again (`False`) and reads back the first content; writing to a missing bucket raises `StoreFailed` mentioning `NotFound`. `try/finally` closes the publisher even if an assertion fails.

### `tests/e2e/test_lesson_scenario.py`

`tests/e2e/test_lesson_scenario.py`

```python
"""The lesson's scenario against the emulators, with the real adapters on both sides.

API (Flask test client) -> Pub/Sub emulator topic -> push subscription -> worker (a real HTTP server on this machine)
-> fake Cloud Storage bucket. The failing variant swaps the worker's store for one that is denied, as in step 5.
"""

from __future__ import annotations

import socket
import threading
import time
from collections.abc import Callable, Iterator

import pytest
from google.api_core.exceptions import DeadlineExceeded
from google.auth.credentials import AnonymousCredentials
from google.cloud import pubsub_v1, storage
from werkzeug.serving import make_server

from uploads.application.ports import StoreFailed
from uploads.application.process_upload import ProcessUpload
from uploads.application.request_upload import RequestUpload
from uploads.infrastructure.gcs_result_store import GcsResultStore, build_store
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings, WorkerSettings
from uploads.interfaces import api, worker

pytestmark = pytest.mark.e2e

PROJECT = "local-project"
DENIAL = "Forbidden: worker-sa does not have storage.objects.create access to the Google Cloud Storage object."


class SwitchableStore:
    """The real store, or a denied one: the same effect as removing the worker's bucket role."""

    def __init__(self, real: GcsResultStore) -> None:
        self.real = real
        self.denied = False
        self.attempts = 0

    def create_if_absent(self, key: str, content: str) -> bool:
        self.attempts += 1
        if self.denied:
            raise StoreFailed(DENIAL)
        return self.real.create_if_absent(key, content)


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("", 0))
        return int(sock.getsockname()[1])


def _wait_for(condition: Callable[[], bool], seconds: float, what: str) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.5)
    pytest.fail(f"timed out after {seconds}s waiting for {what}")


class Stack:
    """Topics, subscriptions, a bucket, a worker server and an API client wired to the emulators."""

    def __init__(self, unique: str) -> None:
        self.bucket_name = f"e2e-{unique}"
        self.topic_id = f"e2e-{unique}"
        publisher_client = pubsub_v1.PublisherClient()
        self.subscriber = pubsub_v1.SubscriberClient()
        self.topic = publisher_client.topic_path(PROJECT, self.topic_id)
        dead_topic = publisher_client.topic_path(PROJECT, f"{self.topic_id}-dead")
        self.dead_pull = self.subscriber.subscription_path(PROJECT, f"{self.topic_id}-dead-pull")
        for name in (self.topic, dead_topic):
            publisher_client.create_topic(request={"name": name})
        self.subscriber.create_subscription(request={"name": self.dead_pull, "topic": dead_topic})

        gcs = storage.Client(project=PROJECT, credentials=AnonymousCredentials())
        self.bucket = gcs.create_bucket(self.bucket_name)
        self.store = SwitchableStore(build_store(WorkerSettings.from_env({"BUCKET": self.bucket_name})))
        self.server = make_server("0.0.0.0", _free_port(), worker.create_app(ProcessUpload(self.store)), threaded=True)  # noqa: S104
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

        self.push_subscription = self.subscriber.subscription_path(PROJECT, f"{self.topic_id}-push")
        self.topics = [self.topic, dead_topic]
        self.subscriber.create_subscription(
            request={
                "name": self.push_subscription,
                "topic": self.topic,
                "push_config": {"push_endpoint": f"http://host.docker.internal:{self.server.port}/"},
                "dead_letter_policy": {"dead_letter_topic": dead_topic, "max_delivery_attempts": 5},
                "retry_policy": {"minimum_backoff": {"seconds": 1}, "maximum_backoff": {"seconds": 2}},
                "ack_deadline_seconds": 10,
            }
        )
        publisher = build_publisher(
            ApiSettings.from_env({"PROJECT_ID": PROJECT, "TOPIC_ID": self.topic_id, "PUBLISH_TIMEOUT_SECONDS": "30"})
        )
        self.publisher = publisher
        self.api = api.create_app(RequestUpload(publisher), db_password_set=True).test_client()

    def result_exists(self, name: str) -> bool:
        return bool(self.bucket.blob(f"results/{name}.txt").exists())

    def close(self) -> None:
        """Stop the worker and delete what the test created: a push subscription to a stopped worker would be retried
        for ever and slow the emulator down for every test after it."""
        self.server.shutdown()
        self.publisher.close()
        for subscription in (self.push_subscription, self.dead_pull):
            self.subscriber.delete_subscription(request={"subscription": subscription})
        deleter = pubsub_v1.PublisherClient()
        for topic in self.topics:
            deleter.delete_topic(request={"topic": topic})
        self.bucket.delete(force=True)


@pytest.fixture
def stack(emulators, unique) -> Iterator[Stack]:
    built = Stack(unique)
    try:
        yield built
    finally:
        built.close()


def test_an_upload_request_ends_as_a_result_file_in_the_bucket(stack):
    response = stack.api.post("/upload", json={"name": "report-1"})
    assert response.status_code == 202

    _wait_for(lambda: stack.result_exists("report-1"), 60, "results/report-1.txt")
    assert stack.bucket.blob("results/report-1.txt").download_as_text() == "processed report-1\n"


def test_a_denied_worker_is_retried_then_the_message_is_dead_lettered_and_a_replay_succeeds(stack):
    stack.store.denied = True
    assert stack.api.post("/upload", json={"name": "report-2"}).status_code == 202

    _wait_for(lambda: stack.store.attempts >= 2, 60, "Pub/Sub to retry the failed delivery")
    assert not stack.result_exists("report-2")

    def dead_lettered() -> bool:
        try:
            pulled = stack.subscriber.pull(request={"subscription": stack.dead_pull, "max_messages": 1}, timeout=5)
        except DeadlineExceeded:  # nothing there yet: the emulator holds the pull open, then gives up
            return False
        return any(b"report-2" in m.message.data for m in pulled.received_messages)

    _wait_for(dead_lettered, 120, "the message in the dead-letter subscription")

    stack.store.denied = False  # the role is back
    assert stack.api.post("/upload", json={"name": "report-2"}).status_code == 202  # the replay
    _wait_for(lambda: stack.result_exists("report-2"), 60, "results/report-2.txt after the replay")
```

The whole lesson against the emulators, with the real adapters on both sides:

- `SwitchableStore` wraps the real store and can be switched to "denied", the same effect as removing the worker's bucket role.
- `_free_port()` asks the operating system for an unused port (binding to port 0). `_wait_for(condition, seconds, what)` polls a condition every half second until a deadline (`time.monotonic()` is a clock that never goes backwards) and fails with a clear message.
- `Stack` builds the whole system for one test: a topic and a dead-letter topic, a pull subscription on the dead-letter topic, a bucket, a real HTTP **server** for the worker (`werkzeug.serving.make_server`, started in a **thread**, a second line of execution inside the same program, with `daemon=True` so it dies with the test process), a push subscription that points at that server through `host.docker.internal` (the name by which a container reaches the host machine), a publisher, and the API's test client. `close()` stops the server and deletes everything it created, because a push subscription to a stopped worker would be retried for ever and slow later tests.
- Test one: post an upload, wait for the result file to appear, read it back.
- Test two: switch the store to denied, post an upload, wait until Pub/Sub has retried at least twice, check no result exists, wait until the message appears in the dead-letter subscription, switch the store back, replay by posting again, and wait for the result.

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
