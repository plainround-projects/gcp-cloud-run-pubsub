# Python

## 1. What it is

Python is a programming language. You write text files that end in `.py`, and a program called the **interpreter** reads them and runs them line by line. This repository needs Python 3.12 or newer (`requires-python = ">=3.12"` in `pyproject.toml`) and was tested with 3.13. A **type hint** is a note such as `name: str` that says what kind of value something holds. Python itself ignores hints when it runs. A separate tool, `mypy`, reads them and complains when they do not fit together.

## 2. Why this repository uses it

The lesson gives two small web services in Python. This repository keeps that language but splits the code into layers, adds type hints everywhere, and makes every part testable without Google Cloud.

## 3. Where it appears

| Path | What it does with Python |
| --- | --- |
| `src/uploads/domain/` | Plain values and rules: `UploadName`, `UploadRequested`, `UploadResult`, and the error classes. |
| `src/uploads/application/` | The two use cases, `RequestUpload` and `ProcessUpload`, and the two ports (interfaces) they depend on. |
| `src/uploads/infrastructure/` | Code that talks to Google Cloud, reads settings from the environment, and writes logs. |
| `src/uploads/interfaces/` | The two web apps and the entry points that wire everything together. |
| `tests/` | Tests, also written in Python (see `pytest.md`). |
| `scripts/init_emulator.py` | A script that creates the topic and bucket in the local emulators. |

## 4. How it works underneath

When you run `python file.py` the interpreter turns your text into **bytecode** (a compact list of instructions) and runs it in a loop. Every name you create lives in a **namespace**, a dictionary from names to objects. When you write `import uploads.domain.upload`, Python finds the file `uploads/domain/upload.py` by searching a list of folders called `sys.path`. In the Docker image that list contains `/app/src` because the Dockerfile sets `PYTHONPATH=/app/src`. On your machine, `pip install -e .` adds `src/` to the path for the virtual environment.

A **virtual environment** (`.venv/`) is a private folder holding one copy of Python's packages for this project, so two projects can use different versions of the same library.

Everything is an **object** with a type. Types are checked when the program runs ("dynamic typing"), which is why the separate `mypy` check exists.

## 5. Walkthrough of this repository's use

### Postponed type hints

Almost every file starts with:

```python
from __future__ import annotations
```

It tells Python to store type hints as text and not evaluate them when the file loads. That lets a class mention itself in a hint (for example `-> UploadRequested` inside `UploadRequested`) and keeps start-up cheap.

### Immutable value objects with `dataclass`

`src/uploads/domain/upload.py`

```python
@dataclass(frozen=True, slots=True)
class UploadName:
    """A client-chosen name, restricted to characters that cannot climb out of the `results/` prefix."""

    value: str

    def __post_init__(self) -> None:
        """Reject anything that is not a short, path-free name."""
        if not isinstance(self.value, str) or _NAME_PATTERN.fullmatch(self.value) is None:
            raise InvalidUploadName(
                "name must be 1-128 characters: letters, digits, dot, underscore or hyphen, "
                "starting with a letter or digit"
            )
        if ".." in self.value:
            raise InvalidUploadName("name must not contain '..'")

    def __str__(self) -> str:
        return self.value
```

- `@dataclass` is a **decorator**: a function that takes the class below it and adds methods. `dataclass` writes `__init__`, `__repr__` and `__eq__` for you from the field list (`value: str`).
- `frozen=True` forbids changing a field after creation. Assigning `n.value = "b"` raises `FrozenInstanceError`. This is what the lesson means by an *immutable value object*: once built and checked, it cannot be broken later.
- `slots=True` stores fields in a fixed slot instead of a per-object dictionary. It uses less memory and rejects typos such as `n.vlaue = 1`.
- `__post_init__` is a hook that runs right after `__init__`. It is where the check lives: a name that does not match the pattern raises `InvalidUploadName`. So an `UploadName` that exists is always valid.
- `_NAME_PATTERN.fullmatch(...)` is a **regular expression** (a mini-language for text patterns). `fullmatch` demands the whole string match, not just a part.
- The two string literals inside `raise InvalidUploadName(...)` sit side by side; Python joins neighbouring literals into one string.
- `__str__` says how the object turns into text, so `f"{name}"` gives the raw value.

### Named errors

`src/uploads/domain/errors.py`

```python
class DomainError(Exception):
    """Base class for every error the domain raises."""


class InvalidUploadName(DomainError):
    """The upload name is missing, not text, or not safe to use as part of an object name."""


class MalformedUploadMessage(DomainError):
```

A class that lists another class in brackets **inherits** from it. `InvalidUploadName` is a kind of `DomainError`, which is a kind of `Exception`. Callers can catch the narrow error or the whole family. The name tells the reader what went wrong without reading a message.

### Chaining errors

`src/uploads/domain/upload.py`

```python
    def decode(cls, data: bytes) -> UploadRequested:
        """Parse message data, raising `MalformedUploadMessage` for anything that is not an upload request."""
        try:
            payload = json.loads(data)
        except (UnicodeDecodeError, ValueError) as error:
            raise MalformedUploadMessage("message data is not JSON") from error
        if not isinstance(payload, dict) or "name" not in payload:
            raise MalformedUploadMessage("message data has no 'name'")
        try:
            return cls(UploadName(payload["name"]))
        except InvalidUploadName as error:
            raise MalformedUploadMessage(str(error)) from error
```

`except ... as error` catches an exception and names it. `raise X from error` throws a new exception but remembers the old one as its `__cause__`, so a log shows both. The tuple `(UnicodeDecodeError, ValueError)` catches either type. (`json.loads` raises `ValueError` for bad JSON.)

### Interfaces without inheritance: `Protocol`

`src/uploads/application/ports.py`

```python
class MessagePublisher(Protocol):
    """Publishes one message and returns the broker's id for it."""

    def publish(self, data: bytes) -> str:
        """Publish `data`; raise `PublishFailed` when the broker does not confirm."""
        ...
```

A `Protocol` describes a shape: "anything with a `publish(data: bytes) -> str` method". A class does not have to say it implements it. This is **structural typing**. The real Pub/Sub adapter and the in-memory fake in the tests both fit, so the use case never knows which one it has. The three dots `...` are the Python value `Ellipsis`; here they mean "the body is intentionally empty".

### Enumerations

`src/uploads/application/process_upload.py`

```python
class Outcome(Enum):
    """What processing one message did."""

    CREATED = "created"
    ALREADY_PROCESSED = "already_processed"
```

An `Enum` is a fixed set of named values. Using `Outcome.CREATED` instead of the string `"created"` stops typos and lets `mypy` check every place that uses it. `.value` gives back the text for logs.

### Environment-based settings and a secret that hides itself

`src/uploads/infrastructure/settings.py`

```python
class Secret:
    """A secret value that never appears in a repr, a log line or a traceback."""

    _value: str = field(repr=False)

    def reveal(self) -> str:
        """The value; call only where it is used."""
        return self._value

    def __repr__(self) -> str:
        return "Secret(***)"

    def __str__(self) -> str:
        return "***"
```

`field(repr=False)` removes the field from the generated `__repr__`. The class then overrides `__repr__` and `__str__` to print `***`, so a stray `print(settings)` or a log line cannot reveal the password. `reveal()` is the one deliberate way to read it.

`os.environ` (a mapping of environment variables) is passed into `ApiSettings.from_env(env)` as an argument rather than read inside. That is **dependency injection**: tests pass a plain dictionary. The function collects every problem into a list and raises one `ConfigError` that lists all of them.

### Structured logging

`src/uploads/infrastructure/logging.py`

```python
class JsonFormatter(logging.Formatter):
    """Format records as JSON; fields passed through `extra=` become top-level keys."""

    def format(self, record: logging.LogRecord) -> str:
        """Render one record. Cloud Run parses `severity` and `message` from the line."""
        entry: dict[str, Any] = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        entry.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)
```

Python's standard `logging` module turns calls like `logger.info("message", extra={...})` into **records**. A **formatter** turns a record into text. This one builds a dictionary and prints it as one line of JSON. Cloud Run reads the `severity` and `message` keys from such a line. `vars(record)` is the record's attribute dictionary; names Python itself uses (the `_RESERVED` set) are skipped so that custom fields from `extra=` become extra keys. Using a key from that reserved set in `extra` raises `KeyError`; the project hit exactly that with `"name"` and renamed it `upload_name`.

### Other features you will meet

- `X | None` means "an X or nothing" (Python 3.10 and later).
- `dict[str, Any]`, `list[str]`, `tuple[str, ...]` are generic type hints (3.9 and later).
- `atexit.register(publisher.close)` in `api_main.py` asks Python to call `close` when the process ends, so the Pub/Sub client flushes cleanly.
- `async` is **not** used. Gunicorn runs a few threads instead (see `gunicorn.md`).

## Every module, in the order a request travels

The sections above explain Python's features one at a time. This part goes through every file of the package, whole, so that nothing is skipped. The package lives in `src/uploads/`. The folders are layers (see `import-linter.md`): `domain` knows nothing about the web or Google Cloud, `application` combines domain pieces into jobs, `infrastructure` talks to Google Cloud and the environment, `interfaces` talks to HTTP.

First, a few words you will meet in every file.

- A **terminal** is a window where you type a command and press Return. The program prints its answer in the same window. A **command** such as `.venv/bin/python -m pytest` is a program's path followed by **arguments**.
- A **directory** is a folder. A **path** is the text that names a file, such as `src/landing_zone/domain/design.py`. A path that does not start with a slash is **relative**: it starts from the folder you are in.
- A **virtual environment** is a private folder (here `.venv/`) that holds its own copy of Python and of the libraries this project needs, so installing them cannot disturb anything else on your computer. `.venv/bin/python` is that private Python.
- A **docstring** is a text in triple quotes as the first thing in a file, class or function. Python keeps it as the thing's documentation; tools and `help()` show it. A class or function whose body is only a docstring is a valid, empty one.
- An **exception** is Python's way of stopping normal flow when something went wrong. `raise` starts one; `except` catches it. If nobody catches it, the program stops and prints a **traceback** (the list of calls that led to the error).

### `__init__.py` files

Each folder under `src/uploads/` has an `__init__.py`; its presence turns the folder into a **package**, so `import uploads.domain` works. The top one holds only a docstring: `"""An upload API and a Pub/Sub push worker for Cloud Run."""`. The test folders have empty ones so pytest gives each test file a unique name.

### `domain/errors.py`

`src/uploads/domain/errors.py`

```python
"""Named errors of the domain: each says what was wrong with the input, never how it was transported."""


class DomainError(Exception):
    """Base class for every error the domain raises."""


class InvalidUploadName(DomainError):
    """The upload name is missing, not text, or not safe to use as part of an object name."""


class MalformedUploadMessage(DomainError):
    """A queued message does not decode into an upload request."""
```

`DomainError` inherits from `Exception` ("is a kind of"); the two others inherit from it, so one `except DomainError` catches both. `InvalidUploadName` is a bad client name; `MalformedUploadMessage` is a queued message that does not decode. Each has only a docstring as its body.

### `domain/upload.py`: the request, the message and the result

`src/uploads/domain/upload.py`

```python
"""The upload request and the result it produces: immutable values with no knowledge of Pub/Sub or Cloud Storage."""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from uploads.domain.errors import InvalidUploadName, MalformedUploadMessage

_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
_RESULT_PREFIX = "results/"


@dataclass(frozen=True, slots=True)
class UploadName:
    """A client-chosen name, restricted to characters that cannot climb out of the `results/` prefix."""

    value: str

    def __post_init__(self) -> None:
        """Reject anything that is not a short, path-free name."""
        if not isinstance(self.value, str) or _NAME_PATTERN.fullmatch(self.value) is None:
            raise InvalidUploadName(
                "name must be 1-128 characters: letters, digits, dot, underscore or hyphen, "
                "starting with a letter or digit"
            )
        if ".." in self.value:
            raise InvalidUploadName("name must not contain '..'")

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True, slots=True)
class UploadRequested:
    """The fact that a client asked for `name` to be processed; this is the body of the queued message."""

    name: UploadName

    @classmethod
    def from_request_body(cls, body: Mapping[str, Any]) -> UploadRequested:
        """Build the event from the API's JSON body, raising `InvalidUploadName` when `name` is unusable."""
        return cls(UploadName(body.get("name", "")))

    def encode(self) -> bytes:
        """Serialize to the message data that is published."""
        return json.dumps({"name": self.name.value}, separators=(",", ":")).encode("utf-8")

    @classmethod
    def decode(cls, data: bytes) -> UploadRequested:
        """Parse message data, raising `MalformedUploadMessage` for anything that is not an upload request."""
        try:
            payload = json.loads(data)
        except (UnicodeDecodeError, ValueError) as error:
            raise MalformedUploadMessage("message data is not JSON") from error
        if not isinstance(payload, dict) or "name" not in payload:
            raise MalformedUploadMessage("message data has no 'name'")
        try:
            return cls(UploadName(payload["name"]))
        except InvalidUploadName as error:
            raise MalformedUploadMessage(str(error)) from error


@dataclass(frozen=True, slots=True)
class UploadResult:
    """The file the worker writes for one processed upload."""

    key: str
    body: str

    @classmethod
    def for_request(cls, event: UploadRequested) -> UploadResult:
        """The result of processing `event`: `results/<name>.txt` holding `processed <name>`."""
        return cls(key=f"{_RESULT_PREFIX}{event.name}.txt", body=f"processed {event.name}\n")
```

- `import json` and `import re` bring in the JSON module (`json.md`) and the regular-expression module. `Mapping` is a type meaning "anything shaped like a dictionary"; `Any` means "any type".
- `_NAME_PATTERN` is `[A-Za-z0-9][A-Za-z0-9._-]{0,127}`: a letter or digit first, then up to 127 letters, digits, dots, underscores or hyphens. No slash is possible, so a name cannot climb out of the `results/` prefix. `_RESULT_PREFIX` is a constant.
- `UploadName.__post_init__` runs after the automatic constructor: `isinstance(self.value, str)` guards against a number or a list, `fullmatch(...) is None` means "does not match the whole pattern", and a second rule rejects `..` anywhere (a dot-dot is two dots, which the pattern allows, and it means "parent folder" in a path). `__str__` makes `str(name)` return the text.
- `UploadRequested` is the fact that a client asked for a name. `@classmethod` marks a method called on the class, not on an object: `from_request_body(cls, body)` builds the event from the API's JSON body (`body.get("name", "")` is the value or an empty text, which the name rule then rejects). `-> UploadRequested` works thanks to `from __future__ import annotations`.
- `encode` writes the message data: `json.dumps({"name": ...}, separators=(",", ":"))` produces compact JSON with no spaces, `.encode("utf-8")` turns the text into **bytes** (what Pub/Sub carries).
- `decode` is the reverse and is strict: bytes that are not JSON (`UnicodeDecodeError` or `ValueError`) or JSON without a `name` raise `MalformedUploadMessage`; a bad name inside is converted to the same error with `from error` keeping the original attached.
- `UploadResult` is the file the worker writes: a `key` (`results/<name>.txt`) and a `body` (`processed <name>` and a line break). `for_request` builds it with f-strings.

### `application/ports.py`: what the use cases ask for

`src/uploads/application/ports.py`

```python
"""Ports: what the use cases need from a message broker and an object store, as narrow protocols."""

from __future__ import annotations

from typing import Protocol


class PublishFailed(Exception):
    """The broker did not accept the message (permission, topic missing, timeout)."""


class StoreFailed(Exception):
    """The object store refused or could not complete the write (permission, bucket missing, timeout)."""


class MessagePublisher(Protocol):
    """Publishes one message and returns the broker's id for it."""

    def publish(self, data: bytes) -> str:
        """Publish `data`; raise `PublishFailed` when the broker does not confirm."""
        ...


class ResultStore(Protocol):
    """Stores result files without ever overwriting one."""

    def create_if_absent(self, key: str, content: str) -> bool:
        """Create `key` holding `content`. Return False, changing nothing, when it already exists.

        Raise `StoreFailed` for every other failure, including a missing permission.
        """
        ...
```

- `PublishFailed` and `StoreFailed` are exceptions the adapters raise, so the use cases never see Google's own error classes.
- `class MessagePublisher(Protocol):` is a **port**: any object with a method `publish(data: bytes) -> str` counts, whether or not it says so. The `...` body is Python's empty body. `ResultStore.create_if_absent(key, content) -> bool` says in its docstring: create, return `False` and change nothing if it exists, raise `StoreFailed` otherwise.

### `application/request_upload.py`: the API's job

`src/uploads/application/request_upload.py`

```python
"""Use case of the API: turn an upload request into a published message."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from uploads.application.ports import MessagePublisher
from uploads.domain.upload import UploadRequested


@dataclass(frozen=True, slots=True)
class Receipt:
    """Proof that the broker accepted the message."""

    message_id: str


class RequestUpload:
    """Validate the request, publish it, return the broker's message id."""

    def __init__(self, publisher: MessagePublisher) -> None:
        """Create the use case around a publisher port."""
        self._publisher = publisher

    def execute(self, body: Mapping[str, Any]) -> Receipt:
        """Raise `InvalidUploadName` for a bad request and `PublishFailed` when the broker refuses."""
        event = UploadRequested.from_request_body(body)
        return Receipt(message_id=self._publisher.publish(event.encode()))
```

`Receipt` holds the broker's message id. `RequestUpload.__init__` stores the publisher; `execute` builds the event from the body (this validates the name), encodes it and publishes it. The docstring lists the two errors it can raise. There is no web code and no Google code here.

### `application/process_upload.py`: the worker's job

`src/uploads/application/process_upload.py`

```python
"""Use case of the worker: write the result file for one queued upload request."""

from __future__ import annotations

from enum import Enum

from uploads.application.ports import ResultStore
from uploads.domain.upload import UploadRequested, UploadResult


class Outcome(Enum):
    """What processing one message did."""

    CREATED = "created"
    ALREADY_PROCESSED = "already_processed"


class ProcessUpload:
    """Decode a message and store its result once.

    Pub/Sub delivers at least once, so a repeat of a processed message is a success that changes nothing.
    The worker's role may create objects but not delete them, which is also why it cannot overwrite one.
    """

    def __init__(self, store: ResultStore) -> None:
        """Create the use case around a store port."""
        self._store = store

    def execute(self, data: bytes) -> Outcome:
        """Raise `MalformedUploadMessage` for a bad message and `StoreFailed` when the write fails."""
        result = UploadResult.for_request(UploadRequested.decode(data))
        created = self._store.create_if_absent(result.key, result.body)
        return Outcome.CREATED if created else Outcome.ALREADY_PROCESSED
```

`Outcome` is an enum with two members. `execute` decodes the message into an event, builds the result file and calls `create_if_absent`. A message delivered twice finds the object already there and reports `ALREADY_PROCESSED`, which is a success: Pub/Sub delivers **at least once**, so repeats are normal. `Outcome.CREATED if created else Outcome.ALREADY_PROCESSED` is a conditional expression.

### `infrastructure/settings.py`: configuration from the environment

`src/uploads/infrastructure/settings.py`

```python
"""Configuration from the environment (twelve-factor), validated once at startup."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field


class ConfigError(Exception):
    """One or more settings are missing or invalid; the message lists all of them."""


@dataclass(frozen=True, slots=True)
class Secret:
    """A secret value that never appears in a repr, a log line or a traceback."""

    _value: str = field(repr=False)

    def reveal(self) -> str:
        """The value; call only where it is used."""
        return self._value

    def __repr__(self) -> str:
        return "Secret(***)"

    def __str__(self) -> str:
        return "***"


@dataclass(frozen=True, slots=True)
class ApiSettings:
    """Settings of the API service."""

    project_id: str
    topic_id: str
    publish_timeout_seconds: float
    log_level: str
    db_password: Secret | None

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> ApiSettings:
        """Read `PROJECT_ID`, `TOPIC_ID`, `PUBLISH_TIMEOUT_SECONDS`, `LOG_LEVEL` and `DB_PASSWORD`."""
        problems: list[str] = []
        project_id = _required(env, "PROJECT_ID", problems)
        timeout = _positive_float(env, "PUBLISH_TIMEOUT_SECONDS", 10.0, problems)
        level = _log_level(env, problems)
        if problems:
            raise ConfigError("; ".join(problems))
        password = env.get("DB_PASSWORD")
        return cls(
            project_id=project_id,
            topic_id=env.get("TOPIC_ID", "uploads"),
            publish_timeout_seconds=timeout,
            log_level=level,
            db_password=Secret(password) if password else None,
        )


@dataclass(frozen=True, slots=True)
class WorkerSettings:
    """Settings of the worker service."""

    bucket: str
    project_id: str | None
    store_timeout_seconds: float
    log_level: str

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> WorkerSettings:
        """Read `BUCKET`, `PROJECT_ID` (optional), `STORE_TIMEOUT_SECONDS` and `LOG_LEVEL`."""
        problems: list[str] = []
        bucket = _required(env, "BUCKET", problems)
        timeout = _positive_float(env, "STORE_TIMEOUT_SECONDS", 30.0, problems)
        level = _log_level(env, problems)
        if problems:
            raise ConfigError("; ".join(problems))
        return cls(
            bucket=bucket,
            project_id=env.get("PROJECT_ID") or None,
            store_timeout_seconds=timeout,
            log_level=level,
        )


def _required(env: Mapping[str, str], name: str, problems: list[str]) -> str:
    value = env.get(name, "").strip()
    if not value:
        problems.append(f"{name} is required")
    return value


def _positive_float(env: Mapping[str, str], name: str, default: float, problems: list[str]) -> float:
    raw = env.get(name)
    if raw is None:
        return default
    try:
        value = float(raw)
    except ValueError:
        problems.append(f"{name} must be a number, got {raw!r}")
        return default
    if value <= 0:
        problems.append(f"{name} must be greater than zero, got {raw!r}")
        return default
    return value


def _log_level(env: Mapping[str, str], problems: list[str]) -> str:
    level = env.get("LOG_LEVEL", "INFO").upper()
    if level not in {"DEBUG", "INFO", "WARNING", "ERROR"}:
        problems.append(f"LOG_LEVEL must be DEBUG, INFO, WARNING or ERROR, got {level!r}")
    return level
```

- An **environment variable** is a named text the system hands to a program when it starts (`env-files.md` explains how they reach the scripts). `from_env(env)` takes a mapping (in production `os.environ`, in tests a plain dictionary), so no test needs to change the real environment.
- `ConfigError` lists every problem in one message (`"; ".join(problems)`), so a person fixes all of them in one pass.
- `Secret` wraps a text so it cannot leak: `field(repr=False)` hides it from the automatic `repr`, and `__repr__` and `__str__` return `Secret(***)` and `***`. `reveal()` is the only way out, called only where the value is used.
- `ApiSettings` reads `PROJECT_ID` (required), `TOPIC_ID` (default `uploads`), `PUBLISH_TIMEOUT_SECONDS` (default 10.0), `LOG_LEVEL` (default INFO) and `DB_PASSWORD` (optional: `Secret(password) if password else None`). `WorkerSettings` reads `BUCKET` (required), `PROJECT_ID` (optional: `env.get("PROJECT_ID") or None`), `STORE_TIMEOUT_SECONDS` (default 30.0) and `LOG_LEVEL`.
- `_required` strips spaces and records a problem when empty. `_positive_float` returns the default when the variable is absent, records a problem for text that is not a number (`float(raw)` raises `ValueError`) or not above zero. `_log_level` upper-cases the text and accepts four words. Each helper appends to the shared `problems` list and returns a usable value, so the loader can report all problems together.

### `infrastructure/logging.py`: logs Cloud Logging can read

`src/uploads/infrastructure/logging.py`

```python
"""Structured logging that Cloud Logging understands: one JSON object per line on stdout, with `severity`."""

from __future__ import annotations

import json
import logging
import sys
from typing import Any

_RESERVED = set(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    """Format records as JSON; fields passed through `extra=` become top-level keys."""

    def format(self, record: logging.LogRecord) -> str:
        """Render one record. Cloud Run parses `severity` and `message` from the line."""
        entry: dict[str, Any] = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        entry.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: str) -> None:
    """Send every log record to stdout as JSON at `level`; safe to call twice."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
```

- A **log record** is what Python's `logging` module creates for each message. A **formatter** turns it into text. `JsonFormatter.format` returns one JSON object per line with `severity` (the level name), `message`, `logger`, any extra fields, and `exception` when there is a traceback. Cloud Run reads standard output line by line and understands `severity` and `message` (see `cloud-logging.md`).
- `_RESERVED` is the set of names every record already has; `vars(logging.makeLogRecord({}))` lists them. The dictionary comprehension keeps only fields the caller added with `extra={...}`, which become top-level JSON keys. `default=str` in `json.dumps` turns anything that is not JSON-friendly into text instead of failing.
- `configure_logging(level)` sends all records to standard output (`sys.stdout`) with this formatter. `root.handlers[:] = [handler]` replaces the handler list in place, so calling it twice does not duplicate lines.

### `infrastructure/pubsub_publisher.py`

`src/uploads/infrastructure/pubsub_publisher.py`

```python
"""Pub/Sub adapter for the `MessagePublisher` port."""

from __future__ import annotations

from typing import Protocol

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from google.cloud import pubsub_v1

from uploads.application.ports import PublishFailed
from uploads.infrastructure.settings import ApiSettings


class _Future(Protocol):
    def result(self, timeout: float | None = None) -> str: ...


class _Client(Protocol):
    def publish(self, topic: str, data: bytes) -> _Future: ...

    def stop(self) -> None: ...


class PubSubPublisher:
    """Publish to one topic and wait for the broker's acknowledgement within a deadline."""

    def __init__(self, client: _Client, topic_path: str, timeout_seconds: float) -> None:
        """`client` is a `pubsub_v1.PublisherClient` (or anything shaped like one)."""
        self._client = client
        self._topic_path = topic_path
        self._timeout = timeout_seconds

    def publish(self, data: bytes) -> str:
        """Return the message id, or raise `PublishFailed` with the broker's own error text."""
        try:
            return self._client.publish(self._topic_path, data).result(timeout=self._timeout)
        except (GoogleAPIError, GoogleAuthError, TimeoutError) as error:
            raise PublishFailed(f"{type(error).__name__}: {error}") from error

    def close(self) -> None:
        """Flush and stop the client's background threads; call on shutdown."""
        self._client.stop()


def build_publisher(settings: ApiSettings) -> PubSubPublisher:
    """The real adapter. Credentials come from the runtime's service account (or the emulator host variable)."""
    client = pubsub_v1.PublisherClient()
    return PubSubPublisher(
        client,
        client.topic_path(settings.project_id, settings.topic_id),
        settings.publish_timeout_seconds,
    )
```

Covered line by line in `google-cloud-pubsub.md`. Here: `_Future` and `_Client` are tiny protocols describing just the parts of Google's client the adapter uses, so tests pass a fake. The `except` catches three families of errors and re-raises them as `PublishFailed(f"{type(error).__name__}: {error}")`, keeping the class name and the original message.

### `infrastructure/gcs_result_store.py`

`src/uploads/infrastructure/gcs_result_store.py`

```python
"""Cloud Storage adapter for the `ResultStore` port."""

from __future__ import annotations

import os
from typing import Any

import requests
from google.api_core.exceptions import GoogleAPIError, PreconditionFailed
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import GoogleAuthError
from google.cloud import storage
from google.cloud.storage.retry import DEFAULT_RETRY_IF_GENERATION_SPECIFIED

from uploads.application.ports import StoreFailed
from uploads.infrastructure.settings import WorkerSettings


class GcsResultStore:
    """Create objects only if absent.

    `if_generation_match=0` makes the write conditional on the object not existing. That keeps a duplicate delivery
    harmless and works with `roles/storage.objectCreator`, which can create objects but not overwrite or delete them.
    """

    def __init__(self, bucket: Any, timeout_seconds: float) -> None:
        """`bucket` is a `google.cloud.storage.Bucket` (or anything shaped like one)."""
        self._bucket = bucket
        self._timeout = timeout_seconds

    def create_if_absent(self, key: str, content: str) -> bool:
        """True when the object was created, False when it already existed; `StoreFailed` otherwise."""
        blob = self._bucket.blob(key)
        try:
            blob.upload_from_string(
                content,
                content_type="text/plain; charset=utf-8",
                if_generation_match=0,
                timeout=self._timeout,
                retry=DEFAULT_RETRY_IF_GENERATION_SPECIFIED,
            )
        except PreconditionFailed:
            return False
        except (GoogleAPIError, GoogleAuthError, requests.RequestException, TimeoutError) as error:
            raise StoreFailed(f"{type(error).__name__}: {error}") from error
        return True


def build_store(settings: WorkerSettings) -> GcsResultStore:
    """The real adapter. Credentials come from the runtime's service account, or are anonymous for the emulator."""
    if os.environ.get("STORAGE_EMULATOR_HOST"):
        client = storage.Client(project=settings.project_id or "local", credentials=AnonymousCredentials())
    else:
        client = storage.Client(project=settings.project_id)
    return GcsResultStore(client.bucket(settings.bucket), settings.store_timeout_seconds)
```

Covered in `cloud-storage.md`. In short: `if_generation_match=0` makes the write succeed only if the object does not exist; `PreconditionFailed` (the object exists) becomes `False`; every other error becomes `StoreFailed`. `build_store` chooses anonymous credentials when `STORAGE_EMULATOR_HOST` is set (the local fake server) and the runtime's own credentials otherwise.

### `interfaces/api.py`

`src/uploads/interfaces/api.py`

```python
"""The API service: `POST /upload` publishes a message, `GET /health` reports whether the secret arrived."""

from __future__ import annotations

import logging

from flask import Flask, Response, jsonify, request

from uploads.application.ports import PublishFailed
from uploads.application.request_upload import RequestUpload
from uploads.domain.errors import InvalidUploadName

logger = logging.getLogger("uploads.api")

_MAX_BODY_BYTES = 64 * 1024


def create_app(request_upload: RequestUpload, db_password_set: bool) -> Flask:
    """Build the Flask app around the use case; nothing here reaches Google Cloud directly."""
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = _MAX_BODY_BYTES

    @app.post("/upload")
    def upload() -> tuple[Response, int]:
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            return jsonify(error='body must be a JSON object such as {"name": "report-1"}'), 400
        try:
            receipt = request_upload.execute(body)
        except InvalidUploadName as error:
            return jsonify(error=str(error)), 400
        except PublishFailed as error:
            logger.error("publish failed", extra={"error": str(error)})
            return jsonify(error="could not publish the message"), 503
        logger.info("upload requested", extra={"upload_name": body["name"], "message_id": receipt.message_id})
        return jsonify(published=receipt.message_id), 202

    @app.get("/health")
    def health() -> Response:
        # Only whether the secret is present, never the value.
        return jsonify(db_password_set=db_password_set)

    return app
```

Covered in `flask.md`. `create_app` builds the web application around the use case; `app.post("/upload")` and `app.get("/health")` are **decorators** that register the functions as routes. A function defined inside another (`upload` inside `create_app`) can use the outer function's variables (`request_upload`); that is a **closure**. Status codes: 400 for a bad body, 503 when the broker refuses, 202 (accepted) when published. `MAX_CONTENT_LENGTH` rejects bodies over 64 KiB.

### `interfaces/push_envelope.py`

`src/uploads/interfaces/push_envelope.py`

```python
"""The Pub/Sub push request body: `{"message": {"data": <base64>, "messageId": ...}, "subscription": ...}`."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from typing import Any


class InvalidEnvelope(Exception):
    """The request body is not a Pub/Sub push envelope."""


@dataclass(frozen=True, slots=True)
class PushedMessage:
    """The parts of a push delivery the worker uses."""

    message_id: str
    data: bytes
    subscription: str


def parse_push_envelope(envelope: Any) -> PushedMessage:
    """Decode the envelope, raising `InvalidEnvelope` for anything that does not have the documented shape."""
    if not isinstance(envelope, dict) or not isinstance(envelope.get("message"), dict):
        raise InvalidEnvelope("body must be a Pub/Sub push envelope with a 'message' object")
    message = envelope["message"]
    encoded = message.get("data")
    if not isinstance(encoded, str):
        raise InvalidEnvelope("message has no base64 'data'")
    try:
        data = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise InvalidEnvelope("message data is not valid base64") from error
    return PushedMessage(
        message_id=str(message.get("messageId", "")),
        data=data,
        subscription=str(envelope.get("subscription", "")),
    )
```

Pub/Sub pushes a JSON **envelope**: `{"message": {"data": "<base64>", "messageId": "..."}, "subscription": "..."}`. **Base64** is a way to write bytes using only letters, digits, `+`, `/` and `=`, so binary data fits in JSON text. `parse_push_envelope` checks each level of the shape with `isinstance`, decodes with `base64.b64decode(encoded, validate=True)` (`validate=True` refuses stray characters) and raises `InvalidEnvelope` for any problem. `PushedMessage` holds the three parts the worker uses.

### `interfaces/worker.py`

`src/uploads/interfaces/worker.py`

```python
"""The worker service: receives Pub/Sub push deliveries and writes one result file per message.

Pub/Sub acknowledges a delivery only for a 2xx response. Every failure below therefore answers with an error status,
so the message is retried and, after the subscription's attempt limit, dead-lettered rather than lost.
"""

from __future__ import annotations

import logging

from flask import Flask, Response, request

from uploads.application.ports import StoreFailed
from uploads.application.process_upload import ProcessUpload
from uploads.domain.errors import MalformedUploadMessage
from uploads.interfaces.push_envelope import InvalidEnvelope, parse_push_envelope

logger = logging.getLogger("uploads.worker")

_MAX_BODY_BYTES = 256 * 1024


def create_app(process_upload: ProcessUpload) -> Flask:
    """Build the Flask app around the use case; nothing here reaches Google Cloud directly."""
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = _MAX_BODY_BYTES

    @app.post("/")
    def receive() -> Response:
        try:
            pushed = parse_push_envelope(request.get_json(silent=True))
            outcome = process_upload.execute(pushed.data)
        except (InvalidEnvelope, MalformedUploadMessage) as error:
            # A message that can never succeed still gets a 4xx so it is retried and dead-lettered, not acknowledged.
            logger.warning("rejected a malformed delivery", extra={"error": str(error)})
            return Response(str(error), status=400, mimetype="text/plain")
        except StoreFailed as error:
            # The full text names the service account, the permission and the resource when the cause is IAM.
            logger.error("could not store the result", extra={"error": str(error)})
            return Response("storage failed", status=500, mimetype="text/plain")
        logger.info("processed", extra={"message_id": pushed.message_id, "outcome": outcome.value})
        return Response(status=204)

    @app.get("/health")
    def health() -> Response:
        return Response("ok", status=200, mimetype="text/plain")

    return app
```

Covered in `flask.md` and `cloud-pubsub.md`. The status codes carry meaning: any 2xx acknowledges the message; 400 or 500 makes Pub/Sub retry and eventually dead-letter it. A malformed message gets a 4xx on purpose, so it ends in the dead-letter topic where a person can look at it, rather than disappearing.

### `interfaces/api_main.py` and `worker_main.py`: the entry points

`src/uploads/interfaces/api_main.py`

```python
"""Entry point of the API container: `gunicorn "uploads.interfaces.api_main:create()"`."""

from __future__ import annotations

import atexit
import os

from flask import Flask

from uploads.application.request_upload import RequestUpload
from uploads.infrastructure.logging import configure_logging
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings
from uploads.interfaces.api import create_app


def create() -> Flask:
    """Read the settings, build the real adapters and the app; flush the publisher when the process exits."""
    settings = ApiSettings.from_env(os.environ)
    configure_logging(settings.log_level)
    publisher = build_publisher(settings)
    atexit.register(publisher.close)
    return create_app(RequestUpload(publisher), db_password_set=settings.db_password is not None)
```

`src/uploads/interfaces/worker_main.py`

```python
"""Entry point of the worker container: `gunicorn "uploads.interfaces.worker_main:create()"`."""

from __future__ import annotations

import os

from flask import Flask

from uploads.application.process_upload import ProcessUpload
from uploads.infrastructure.gcs_result_store import build_store
from uploads.infrastructure.logging import configure_logging
from uploads.infrastructure.settings import WorkerSettings
from uploads.interfaces.worker import create_app


def create() -> Flask:
    """Read the settings and build the real adapters and the app."""
    settings = WorkerSettings.from_env(os.environ)
    configure_logging(settings.log_level)
    return create_app(ProcessUpload(build_store(settings)))
```

Each file builds the real thing: read the settings from `os.environ`, configure logging, build the adapter, build the app. `atexit.register(publisher.close)` registers a function to run when the process exits normally, so the publisher flushes its pending messages. Gunicorn calls `create()` (see `gunicorn.md`).

### `interfaces/gunicorn_conf.py`

`src/uploads/interfaces/gunicorn_conf.py`

```python
"""Gunicorn settings for Cloud Run: one process, a few threads, shutdown inside Cloud Run's 10-second SIGTERM window."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"  # the container must listen on all interfaces
workers = 1
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
timeout = 0  # Cloud Run enforces the request timeout; gunicorn must not kill a slow request first
graceful_timeout = 8  # on SIGTERM finish in-flight requests, then exit before Cloud Run's SIGKILL
accesslog = None
control_socket_disable = True  # gunicorn 26 opens an admin socket under $HOME; the container user has no home
```

A Python file whose variable names are Gunicorn settings. Each line is explained in `gunicorn.md`.

### `scripts/init_emulator.py`: set up the local emulators

`scripts/init_emulator.py`

```python
"""Create the topic, dead-letter topic, push subscription and bucket in the local emulators (idempotent).

Run through `make up`. The API and worker containers reach the emulators by service name; this script runs on the host.
"""

from __future__ import annotations

import os
import time

os.environ.setdefault("PUBSUB_EMULATOR_HOST", "localhost:8085")
os.environ.setdefault("STORAGE_EMULATOR_HOST", "http://localhost:4443")

from google.api_core.exceptions import AlreadyExists, DeadlineExceeded, ServiceUnavailable
from google.auth.credentials import AnonymousCredentials
from google.cloud import pubsub_v1, storage

PROJECT = "local-project"
WORKER_URL = os.environ.get("WORKER_PUSH_URL", "http://worker:8080/")
BUCKET = "local-results"


def main() -> None:
    """Create everything the stack needs; existing resources are left alone."""
    publisher = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    topic = publisher.topic_path(PROJECT, "uploads")
    dead = publisher.topic_path(PROJECT, "uploads-dead")
    for name in (topic, dead):
        _ignore_exists(lambda name=name: publisher.create_topic(request={"name": name}))
    _ignore_exists(
        lambda: subscriber.create_subscription(
            request={
                "name": subscriber.subscription_path(PROJECT, "uploads-push"),
                "topic": topic,
                "push_config": {"push_endpoint": WORKER_URL},
                "dead_letter_policy": {"dead_letter_topic": dead, "max_delivery_attempts": 5},
            }
        )
    )
    _ignore_exists(
        lambda: subscriber.create_subscription(
            request={"name": subscriber.subscription_path(PROJECT, "uploads-dead-pull"), "topic": dead}
        )
    )
    client = storage.Client(project=PROJECT, credentials=AnonymousCredentials())
    _ignore_exists(lambda: client.create_bucket(BUCKET))
    print(f"ready: {topic}, {dead}, push to {WORKER_URL}, gs://{BUCKET}")


def _ignore_exists(action) -> None:  # type: ignore[no-untyped-def]
    """Run `action`; an existing resource is fine, and a cold emulator gets a few more tries."""
    for attempt in range(1, 6):
        try:
            action()
            return
        except AlreadyExists:
            return
        except (DeadlineExceeded, ServiceUnavailable):
            if attempt == 5:
                raise
            time.sleep(5 * attempt)
        except Exception as error:  # fake-gcs-server answers 409 with its own exception type
            if "409" in str(error) or "already" in str(error).lower():
                return
            raise


if __name__ == "__main__":
    main()
```

- The file runs **on your computer**, not in a container (the docstring says so). The two `os.environ.setdefault(...)` lines come *before* the Google imports on purpose: the client libraries read `PUBSUB_EMULATOR_HOST` and `STORAGE_EMULATOR_HOST` when they are created, and `setdefault` sets a variable only if you have not set it yourself. The result is that the clients talk to `localhost:8085` and `http://localhost:4443` (see `cloud-pubsub.md` and `cloud-storage.md` for the emulators).
- `main()` creates a topic `uploads`, a dead-letter topic `uploads-dead`, a **push subscription** `uploads-push` whose `push_endpoint` is the worker's address inside the Compose network (`http://worker:8080/`) with `dead_letter_policy` after 5 delivery attempts, a pull subscription `uploads-dead-pull` on the dead-letter topic (so you can read dead letters), and the bucket `local-results`. `request={...}` dictionaries are how Google's library takes arguments.
- `lambda name=name: ...` is a small anonymous function; `name=name` fixes the loop variable's current value into it, otherwise every function would see the last value.
- `_ignore_exists(action)` runs an action up to five times. `AlreadyExists` means "fine, it is there"; `DeadlineExceeded` or `ServiceUnavailable` means the emulator is still starting, so it waits `5 * attempt` seconds and tries again; the last `except Exception` handles the fake storage server, which reports "already exists" with its own error type containing `409`. The comment `# type: ignore[no-untyped-def]` silences one `mypy` complaint about the missing annotation.
- `if __name__ == "__main__": main()` runs `main` only when the file is started as a program.

### `tests/conftest.py`: fixtures for the tests that need the emulators

`tests/conftest.py`

```python
"""Shared fixtures. Integration and end-to-end tests use the emulators of docker-compose.yml (`make emulators`)."""

from __future__ import annotations

import socket
import uuid

import pytest

PUBSUB_HOST = "localhost:8085"
GCS_URL = "http://localhost:4443"


def _reachable(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


@pytest.fixture
def emulators(monkeypatch: pytest.MonkeyPatch) -> None:
    """Point the Google client libraries at the emulators; fail loudly, not silently, when they are not running."""
    if not (_reachable("localhost", 8085) and _reachable("localhost", 4443)):
        pytest.fail("the emulators are not running: start them with `make emulators`")
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", PUBSUB_HOST)
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", GCS_URL)


@pytest.fixture
def unique() -> str:
    """A short unique suffix so repeated runs never meet each other's topics, buckets or objects."""
    return uuid.uuid4().hex[:10]
```

- `_reachable(host, port)` tries to open a network connection (`socket.create_connection`) with a one-second timeout and answers true or false; a **port** is the numbered door on a computer where a program listens (here 8085 for Pub/Sub and 4443 for storage).
- `emulators` is a fixture: if the two ports do not answer, `pytest.fail` stops the test with a message that tells you to run `make emulators` (failing loudly, not silently skipping). Otherwise `monkeypatch.setenv` sets the two emulator variables for this test only and undoes them afterwards.
- `unique` gives a random 10-character text (`uuid.uuid4().hex[:10]`), so repeated runs never meet each other's topics or buckets.

### `tests/unit/application/fakes.py`: in-memory stand-ins for the ports

`tests/unit/application/fakes.py`

```python
"""In-memory stand-ins for the ports: deterministic, no network."""

from __future__ import annotations

from uploads.application.ports import PublishFailed, StoreFailed


class InMemoryPublisher:
    """Records published payloads and hands out sequential ids."""

    def __init__(self, fail_with: str | None = None) -> None:
        self.published: list[bytes] = []
        self._fail_with = fail_with

    def publish(self, data: bytes) -> str:
        if self._fail_with:
            raise PublishFailed(self._fail_with)
        self.published.append(data)
        return str(len(self.published))


class InMemoryStore:
    """A bucket in a dict, with create-only semantics like the real adapter."""

    def __init__(self, fail_with: str | None = None) -> None:
        self.objects: dict[str, str] = {}
        self.write_attempts = 0
        self._fail_with = fail_with

    def create_if_absent(self, key: str, content: str) -> bool:
        self.write_attempts += 1
        if self._fail_with:
            raise StoreFailed(self._fail_with)
        if key in self.objects:
            return False
        self.objects[key] = content
        return True
```

`InMemoryPublisher` records the payloads in a list and returns the count as the message id (`"1"`, `"2"`...), or raises `PublishFailed` when built with `fail_with`. `InMemoryStore` keeps a dictionary of objects, counts write attempts, raises `StoreFailed` when told to, and returns `False` for a key that exists: the same contract as the real store, with no network.

## 6. Try it yourself

Run these from the repository root after `make install`.

```bash
.venv/bin/python --version
```
Expected: `Python 3.13.12` (or your 3.12/3.13).

```bash
.venv/bin/python -c "from uploads.domain.upload import UploadName; UploadName('../x')"
```
Expected last line: `uploads.domain.errors.InvalidUploadName: name must be 1-128 characters: letters, digits, dot, underscore or hyphen, starting with a letter or digit`

```bash
.venv/bin/python -c "from uploads.domain.upload import UploadRequested; e=UploadRequested.from_request_body({'name':'report-1'}); print(e); print(e.encode())"
```
Expected: `UploadRequested(name=UploadName(value='report-1'))` then `b'{"name":"report-1"}'` (the `b` means bytes).

```bash
.venv/bin/python -c "from uploads.domain.upload import UploadName; n=UploadName('a'); n.value='b'" 2>&1 | tail -1
```
Expected: `dataclasses.FrozenInstanceError: cannot assign to field 'value'`

```bash
.venv/bin/python -c "from uploads.infrastructure.settings import ApiSettings; print(ApiSettings.from_env({'PROJECT_ID':'demo-project','DB_PASSWORD':'hunter2'}))"
```
Expected: the settings print with `db_password=Secret(***)`; the word `hunter2` never appears.

## 7. Mistakes people make

- **Mutable default arguments** (`def f(x=[])`) share one list between calls. This repository has none; the domain values are frozen.
- **Catching `Exception` everywhere** hides bugs. Here adapters catch only the Google error types and re-raise a named error.
- **Putting secrets in `repr`/logs.** `Secret` prevents it.
- **Using `==` to compare to `None`.** Use `is None`.
- **Reading `os.environ` deep inside code.** Settings are read once at start-up and passed in.

## 8. Check yourself

1. What does `frozen=True` do on a dataclass? *It forbids assigning to fields after creation.*
2. What is `__post_init__` for here? *It validates the value right after construction.*
3. Why does `ports.py` use `Protocol` and not a base class? *So any object with the right methods fits, including test fakes, without inheriting.*
4. What does `raise X from error` keep that a plain `raise X` loses? *The original exception as `__cause__`.*
5. Why is `os.environ` passed in as an argument? *So tests can supply a dictionary; the code has no hidden global input.*

## 9. Further reading

- Python 3.12 documentation: <https://docs.python.org/3.12/>
- Tutorial: <https://docs.python.org/3.12/tutorial/>
- `dataclasses`: <https://docs.python.org/3.12/library/dataclasses.html>
- `typing.Protocol`: <https://docs.python.org/3.12/library/typing.html#typing.Protocol>
- `logging`: <https://docs.python.org/3.12/library/logging.html>
