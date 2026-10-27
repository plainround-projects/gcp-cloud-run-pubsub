# requests

## 1. What it is

`requests` is the most widely used Python library for making HTTP calls. In this repository you never call it directly to fetch anything; it appears because Google's storage library uses it underneath, and its error classes can come out of a failed upload. Version 2.34.2 is pinned in the lock file; `pyproject.toml` asks for `>=2.32`.

## 2. Why this repository uses it

The Cloud Storage client sends its HTTP requests through `requests`. A dropped connection or a timeout is reported as a `requests` exception, not as a Google one. To make the worker answer with a retryable status in that case, the storage adapter has to catch it. `types-requests` is the matching type information, so `mypy` understands the library.

## 3. Where it appears

| Path | What it does with `requests` |
| --- | --- |
| `src/uploads/infrastructure/gcs_result_store.py` | Imports `requests` to catch `requests.RequestException`. |
| `tests/unit/infrastructure/test_gcs_result_store.py` | Raises `requests.ConnectionError` to prove it becomes `StoreFailed`. |
| `pyproject.toml` | Declares the dependency and `types-requests` for development. |
| `[tool.importlinter]` | Forbids `requests` in the domain and application layers. |

## 4. How it works underneath

`requests` builds an HTTP request from your arguments, opens a TCP connection (secured with TLS for `https`), sends the text of the request, and parses the reply into a `Response`. All its errors derive from `requests.RequestException`: `ConnectionError` (cannot connect or connection dropped), `Timeout` (no answer in time), and others. A **retry** is trying the same request again; the storage library does it for safe cases.

## 5. Walkthrough of this repository's use

`src/uploads/infrastructure/gcs_result_store.py`

```python
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
```

The `except` tuple lists every failure family an upload can produce: Google's API errors, Google's auth errors, any `requests` error, and `TimeoutError`. Each is turned into `StoreFailed`, so the worker answers 500 and Pub/Sub retries.

The test that proves it:

`tests/unit/infrastructure/test_gcs_result_store.py`

```python
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
```

## 6. Try it yourself

```bash
.venv/bin/python -c "from importlib.metadata import version; print(version('requests'))"
```
Expected: `2.34.2`

```bash
.venv/bin/python -c "import requests; print(issubclass(requests.ConnectionError, requests.RequestException))"
```
Expected: `True`

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_gcs_result_store.py -q -p no:cacheprovider
```
Expected: all pass (`7 passed`).

## 7. Mistakes people make

- **No timeout.** `requests` waits forever by default; here the storage call gets a timeout from settings.
- **Catching only `ConnectionError`.** Other `RequestException` subclasses exist.
- **Letting HTTP library errors reach the domain.** The import-linter contract forbids `requests` in inner layers.

## 8. Check yourself

1. What is the base class of `requests` errors? *`requests.RequestException`.*
2. Why is `requests` in this project at all? *The storage client uses it and its exceptions can escape.*
3. What turns that exception into a retry? *The adapter raises `StoreFailed`; the worker answers 500.*
4. What does `types-requests` provide? *Type information for `mypy`.*
5. What is the default timeout of a `requests` call? *None: it can wait forever.*

## 9. Further reading

- requests documentation: <https://requests.readthedocs.io/en/stable/>
- Errors and exceptions: <https://requests.readthedocs.io/en/stable/api/#exceptions>
