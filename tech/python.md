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
