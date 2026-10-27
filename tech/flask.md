# Flask

## 1. What it is

Flask is a Python **web framework**: a library that turns incoming HTTP requests into calls to your Python functions, and turns what those functions return back into HTTP responses. **HTTP** is the text conversation a browser or `curl` has with a server: "POST /upload with this body" and "202 Accepted with that body". Flask 3.1.3 is pinned in `pyproject.toml` and `requirements.lock`.

## 2. Why this repository uses it

The lesson's API and worker are Flask apps. Flask is small enough that every line of the web layer fits on one screen, which keeps the lesson about identity and queues, not about the framework.

## 3. Where it appears

| Path | What it does with Flask |
| --- | --- |
| `src/uploads/interfaces/api.py` | `create_app(...)` builds the API: `POST /upload`, `GET /health`. |
| `src/uploads/interfaces/worker.py` | `create_app(...)` builds the worker: `POST /` (the Pub/Sub push endpoint), `GET /health`. |
| `src/uploads/interfaces/api_main.py`, `worker_main.py` | `create()` returns the finished Flask app for Gunicorn. |
| `tests/unit/interfaces/` | Use `app.test_client()` to call routes without starting a server. |

## 4. How it works underneath

A Flask application is a Python object that follows **WSGI**, a simple standard: a server (here Gunicorn) calls the app with a description of the request and gets back a status, headers and a body. Flask keeps a **routing table**: a list of "this method and path goes to that function". When a request arrives, Flask looks up the function, calls it, and converts the return value into a response. A returned tuple `(body, 202)` means body plus status code.

`request` is a **context-local** object: it looks like a global but always refers to the request being handled right now in this thread. `request.get_json(silent=True)` parses the body as JSON and returns `None` instead of raising when the body is not JSON.

Nothing here runs as a long-lived Flask process of its own. In production Gunicorn owns the process, listens on the port, and calls the Flask object.

## 5. Walkthrough of this repository's use

### The application factory

`src/uploads/interfaces/api.py`

```python
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

- `create_app` is a **factory**: a function that builds and returns the app. It takes its collaborators (`request_upload`, a flag) as arguments. Nothing is created at import time, so tests can build an app with a fake and production can build one with the real publisher.
- `Flask(__name__)` creates the app. `__name__` is the module's name; Flask uses it to find resources.
- `app.config["MAX_CONTENT_LENGTH"] = _MAX_BODY_BYTES` makes Flask refuse bodies over 64 KiB with `413 Payload Too Large` before any of our code reads them. It is an input limit at the boundary.
- `@app.post("/upload")` is a decorator that adds this function to the routing table for the POST method. `@app.get("/health")` does the same for GET.
- The function returns `tuple[Response, int]`. `jsonify(...)` builds a JSON response; the number is the status. `400` means "your request is wrong", `503` means "a service I depend on failed", `202` means "accepted for processing" (the work is not done yet; the message is only queued).
- The body-shape check `isinstance(body, dict)` rejects JSON such as a list or a bare string with `400`.
- Domain errors are mapped to statuses here, in the web layer: `InvalidUploadName` becomes `400`, `PublishFailed` becomes `503`. The use case itself knows nothing of HTTP.
- `/health` returns only whether the secret exists. It never returns the value.

### The worker's route and why the status codes matter

`src/uploads/interfaces/worker.py`

```python
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
```

Pub/Sub counts only a **2xx** reply as "message handled". `Response(status=204)` (no content) acknowledges. A `400` for a message that can never succeed, and a `500` for a storage failure, both make Pub/Sub retry and eventually dead-letter, instead of losing the message. `return Response("storage failed", status=500, ...)` is deliberately not a 200.

### Entry points that Gunicorn calls

`src/uploads/interfaces/api_main.py`

```python
def create() -> Flask:
    """Read the settings, build the real adapters and the app; flush the publisher when the process exits."""
    settings = ApiSettings.from_env(os.environ)
    configure_logging(settings.log_level)
    publisher = build_publisher(settings)
    atexit.register(publisher.close)
    return create_app(RequestUpload(publisher), db_password_set=settings.db_password is not None)
```

Gunicorn is told `uploads.interfaces.api_main:create()`; it calls `create()` once per worker process and uses the returned Flask object. The function reads settings, configures logging, builds the real publisher, registers its shutdown, and returns the app.

## 6. Try it yourself

```bash
.venv/bin/python - <<'PY'
from uploads.application.request_upload import RequestUpload
from uploads.interfaces.api import create_app
class FakePublisher:
    def publish(self, data): print("published", data); return "42"
c = create_app(RequestUpload(FakePublisher()), db_password_set=True).test_client()
print(c.post("/upload", json={"name": "report-1"}).status_code)
print(c.post("/upload", json={"name": "../x"}).get_json())
print(c.get("/health").get_json())
PY
```
Expected:
```text
published b'{"name":"report-1"}'
202
{'error': 'name must be 1-128 characters: letters, digits, dot, underscore or hyphen, starting with a letter or digit'}
{'db_password_set': True}
```

```bash
.venv/bin/python -m pytest tests/unit/interfaces -q -p no:cacheprovider
```
Expected: all pass (`32 passed`).

```bash
.venv/bin/python -c "from importlib.metadata import version; print(version('flask'))"
```
Expected: `3.1.3`. (`flask.__version__` also works but prints a deprecation warning: Flask 3.2 removes it.)

## 7. Mistakes people make

- **Returning 200 after an error in a queue consumer.** The message is lost. The worker returns 4xx/5xx.
- **Trusting the body.** Always check type and content; the API validates the name through `UploadName`.
- **Logging with `extra={"name": ...}`.** `name` collides with a reserved logging attribute. The API logs `upload_name`.
- **Running Flask's built-in server in production.** It is for development. Gunicorn runs the app.
- **Creating the app at import time.** That makes testing and configuration harder; the factory pattern avoids it.

## 8. Check yourself

1. What does the status `202` tell a client? *The request was accepted for processing; the result is not ready.*
2. Why is `create_app` a function? *So collaborators are injected and tests can build apps with fakes.*
3. What makes Pub/Sub retry a push delivery? *Any response that is not 2xx.*
4. What does `MAX_CONTENT_LENGTH` do? *Makes Flask reject larger bodies with 413 before the handler runs.*
5. What does `request.get_json(silent=True)` return for a non-JSON body? *`None`, which the API turns into a 400.*

## 9. Further reading

- Flask 3.1 documentation: <https://flask.palletsprojects.com/en/stable/>
- Application factories: <https://flask.palletsprojects.com/en/stable/patterns/appfactories/>
- Testing: <https://flask.palletsprojects.com/en/stable/testing/>
- WSGI: <https://wsgi.readthedocs.io/>
