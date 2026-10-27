# google-cloud-pubsub (the Python client library)

## 1. What it is

A **library** is code written by someone else that you import. `google-cloud-pubsub` is Google's Python library for Cloud Pub/Sub (see `cloud-pubsub.md` for the service). It hides the network details: you call `publish(...)` and it sends messages over **gRPC** (a fast binary protocol built on HTTP/2) with sign-in, batching and retries handled for you. The pinned version is 2.43.0.

## 2. Why this repository uses it

The API must publish one message per upload. The tests also use the same library to create topics and read messages from the emulator.

## 3. Where it appears

| Path | What it does with the library |
| --- | --- |
| `src/uploads/infrastructure/pubsub_publisher.py` | The only production file that imports it: wraps `PublisherClient` behind the `MessagePublisher` port. |
| `tests/integration/test_pubsub_emulator.py` | Creates a topic and subscription, publishes, pulls. |
| `tests/e2e/test_lesson_scenario.py` | Creates a push subscription with a dead-letter policy. |
| `scripts/init_emulator.py` | Creates topics and subscriptions in the local emulator. |

## 4. How it works underneath

`pubsub_v1.PublisherClient()` opens a connection to `pubsub.googleapis.com`. It finds **credentials** by itself (see `iam-and-service-accounts.md`): on Cloud Run it asks the platform's metadata server for a short-lived token for the service's account. No key file is involved.

`client.publish(topic, data)` does not send immediately. It adds the message to a **batch** and returns a **future** at once. A future is a placeholder for a result that will exist later. A background thread sends the batch after a few milliseconds or when it is full. `future.result(timeout=...)` blocks until the service confirms and returns the **message id**, or raises the error. `client.stop()` flushes pending batches and stops the thread.

If the environment variable `PUBSUB_EMULATOR_HOST` is set (for example `localhost:8085`), the library connects there without TLS and without credentials. That is how the same code runs against the emulator.

## 5. Walkthrough of this repository's use

`src/uploads/infrastructure/pubsub_publisher.py`

```python
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
```

- The adapter's constructor takes the client, the full **topic path** (`projects/PROJECT/topics/TOPIC`) and a timeout, so tests can hand it a fake client.
- `self._client.publish(self._topic_path, data).result(timeout=self._timeout)` publishes and waits for the confirmation for at most the timeout.
- The `except` catches three families: `GoogleAPIError` (any error response from Google, such as permission denied or topic not found), `GoogleAuthError` (no usable credentials) and `TimeoutError` (the future did not complete). Each becomes our own `PublishFailed`, keeping the original message text, because that text names the account and permission when the cause is IAM. `raise ... from error` keeps the original attached.
- `close()` calls `stop()`, and `api_main.py` registers it with `atexit` so it runs at shutdown.

`src/uploads/infrastructure/pubsub_publisher.py`

```python
def build_publisher(settings: ApiSettings) -> PubSubPublisher:
    """The real adapter. Credentials come from the runtime's service account (or the emulator host variable)."""
    client = pubsub_v1.PublisherClient()
    return PubSubPublisher(
        client,
        client.topic_path(settings.project_id, settings.topic_id),
        settings.publish_timeout_seconds,
```

`client.topic_path(project, topic)` builds the long name string. No credentials appear in the code.

## 6. Try it yourself

```bash
.venv/bin/python -c "from importlib.metadata import version; print(version('google-cloud-pubsub'))"
```
Expected: `2.43.0`

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_pubsub_publisher.py -q -p no:cacheprovider
```
Expected: `5 passed`. The cases: publish succeeds within the deadline; `PermissionDenied` and `TimeoutError` each become `PublishFailed` with the original text; `close` stops the client; `build_publisher` builds the right topic path.

```bash
PUBSUB_EMULATOR_HOST=localhost:1 .venv/bin/python -c "
from google.cloud import pubsub_v1
print(pubsub_v1.PublisherClient().topic_path('demo-project', 'uploads'))"
```
Expected: `projects/demo-project/topics/uploads` (the emulator variable stops the client from looking for credentials).

## 7. Mistakes people make

- **Forgetting `.result()`.** The publish may fail silently; the future is the only place the error appears.
- **No timeout on `.result()`.** The call can wait for a long time. The adapter sets one.
- **Creating a client per request.** A client owns threads and connections; create it once at start-up.
- **Not calling `stop()` on exit.** Pending batches can be lost.
- **Catching only one error type.** Network, auth and API errors are different classes.

## 8. Check yourself

1. What does `publish` return? *A future; `.result()` gives the message id.*
2. Where do credentials come from on Cloud Run? *The platform gives the service's own service account token; no key file.*
3. What does `PUBSUB_EMULATOR_HOST` change? *The client talks to that address without credentials.*
4. Why wrap Google's errors in `PublishFailed`? *So the use case and web layer do not depend on Google's classes.*
5. What does `stop()` do? *Flushes pending batches and stops background threads.*

## 9. Further reading

- Python client documentation: <https://cloud.google.com/python/docs/reference/pubsub/latest> (this repository pins 2.43.0)
- Publishing guide: <https://cloud.google.com/pubsub/docs/publisher>
- Emulator environment variable: <https://cloud.google.com/pubsub/docs/emulator>
