# google-api-core and google-auth

## 1. What it is

Two support libraries under every Google Cloud Python client. **google-api-core** supplies the shared error classes (such as `PermissionDenied`, `NotFound`, `DeadlineExceeded`), retry helpers and gRPC plumbing. **google-auth** finds and refreshes credentials: on Cloud Run it asks the metadata server for a token; locally it can use your login. They are pinned transitively in the lock file (api-core 2.43.0, auth 2.62.0).

## 2. Why this repository uses it

The adapters translate Google's errors into the project's own named errors. To do that they import the Google classes and catch them in one place. The emulator mode also needs `AnonymousCredentials` (no sign-in).

## 3. Where it appears

| Path | Use |
| --- | --- |
| `src/uploads/infrastructure/pubsub_publisher.py` | Catches `GoogleAPIError` and `GoogleAuthError`. |
| `src/uploads/infrastructure/gcs_result_store.py` | Catches `GoogleAPIError`, `PreconditionFailed`, `GoogleAuthError`; uses `AnonymousCredentials` for the emulator. |
| `tests/unit/infrastructure/` | Raise `PermissionDenied`, `Forbidden`, `PreconditionFailed` to test the translation. |
| `tests/e2e/`, `scripts/init_emulator.py` | Catch `DeadlineExceeded`, `AlreadyExists`, `ServiceUnavailable` when talking to the emulator. |

## 4. How it works underneath

Every Google error response has an HTTP or gRPC status. api-core maps each status to a Python class in one hierarchy, all under `GoogleAPIError`: HTTP 403 and gRPC `PERMISSION_DENIED` give `Forbidden`/`PermissionDenied`, 404 gives `NotFound`, 412 gives `PreconditionFailed`, a gRPC deadline gives `DeadlineExceeded`. The error's text keeps Google's message, for example "worker-sa@... does not have storage.objects.create access".

**Application Default Credentials** is google-auth's search order for credentials: an environment variable pointing at a file, then your `gcloud` login, then the metadata server of the platform you run on. On Cloud Run the third applies, so no file exists.

## 5. Walkthrough of this repository's use

`src/uploads/infrastructure/gcs_result_store.py`

```python
def build_store(settings: WorkerSettings) -> GcsResultStore:
    """The real adapter. Credentials come from the runtime's service account, or are anonymous for the emulator."""
    if os.environ.get("STORAGE_EMULATOR_HOST"):
        client = storage.Client(project=settings.project_id or "local", credentials=AnonymousCredentials())
    else:
        client = storage.Client(project=settings.project_id)
    return GcsResultStore(client.bucket(settings.bucket), settings.store_timeout_seconds)
```

`AnonymousCredentials()` is a credentials object that signs nothing. The emulator accepts it. Without the emulator variable the client is built with no explicit credentials, so Application Default Credentials apply.

`src/uploads/infrastructure/gcs_result_store.py`

```python
        except PreconditionFailed:
            return False
        except (GoogleAPIError, GoogleAuthError, requests.RequestException, TimeoutError) as error:
            raise StoreFailed(f"{type(error).__name__}: {error}") from error
```

Order matters: `PreconditionFailed` is a subclass of `GoogleAPIError`, so it is caught first and means "already exists". The next clause catches the rest.

## 6. Try it yourself

```bash
.venv/bin/python -c "
from google.api_core import exceptions as e
print(e.PreconditionFailed.__mro__[1].__name__, e.Forbidden.code, e.NotFound.code, e.PreconditionFailed.code)"
```
Expected: the parent class name (`ClientError`) and the HTTP codes `403 404 412`.

```bash
.venv/bin/python -c "
from google.api_core.exceptions import GoogleAPIError, PermissionDenied
print(issubclass(PermissionDenied, GoogleAPIError))"
```
Expected: `True`

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_pubsub_publisher.py tests/unit/infrastructure/test_gcs_result_store.py -q -p no:cacheprovider
```
Expected: `12 passed`.

## 7. Mistakes people make

- **Catching `Exception`.** It hides programming errors. Catch the Google hierarchy.
- **Wrong clause order.** A broad `GoogleAPIError` before `PreconditionFailed` would swallow the "already exists" case.
- **Downloading a key to authenticate locally.** Use `gcloud auth application-default login` or an emulator.
- **Losing the message text.** The adapters keep it, because it names the account, permission and resource.

## 8. Check yourself

1. What is the base class of Google API errors? *`GoogleAPIError`.*
2. Which status becomes `PreconditionFailed`? *HTTP 412.*
3. Where do credentials come from on Cloud Run? *The metadata server, found by Application Default Credentials.*
4. What are `AnonymousCredentials` for here? *Talking to the emulator without signing in.*
5. Why does the order of `except` clauses matter? *The first matching class wins.*

## 9. Further reading

- google-api-core exceptions: <https://googleapis.dev/python/google-api-core/latest/exceptions.html>
- Application Default Credentials: <https://cloud.google.com/docs/authentication/application-default-credentials>
- google-auth: <https://googleapis.dev/python/google-auth/latest/>
