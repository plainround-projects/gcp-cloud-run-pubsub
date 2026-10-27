# Cloud Logging

## 1. What it is

Cloud Logging is Google Cloud's log store. Anything a Cloud Run container writes to its standard output or standard error becomes a log entry, searchable by service, time and severity. If the line is a JSON object, Logging parses it into fields; the keys `severity` and `message` are used as the entry's level and text.

## 2. Why this repository uses it

Step 5 of the lesson is to find the permission-denied entry that names the account, the permission and the resource. That needs logs the services write well and a way to query them.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `src/uploads/infrastructure/logging.py` | Writes one JSON object per line with `severity`, `message`, `logger`, and any extra fields. |
| `src/uploads/interfaces/worker.py` | Logs `could not store the result` at ERROR with the full Google error text in the `error` field. |
| `scripts/read-denial.sh` | `gcloud logging read` with a filter for the worker's ERROR entries. |
| `infra/environments/sandbox/main.tf` | Enables `logging.googleapis.com` among the project's APIs. |

## 4. How it works underneath

Cloud Run captures the container's output stream and sends each line to Logging with the resource labels (`resource.type="cloud_run_revision"`, `resource.labels.service_name="worker"`). For a JSON line, each key is placed in `jsonPayload`; `severity` maps to a level (`DEBUG` to `ERROR`). A **filter** is a small query language: `resource.type="cloud_run_revision" AND resource.labels.service_name="worker" AND severity>=ERROR`. Log lines must never contain secrets, because anyone who can read logs sees them.

## 5. Walkthrough of this repository's use

`src/uploads/infrastructure/logging.py`

```python
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

- `record.getMessage()` fills in the message template.
- The `entry` dictionary starts with `severity`, `message`, `logger`; then every extra attribute of the record not in `_RESERVED` is added (that is what `extra={"error": ...}` does).
- An exception, if present, is added as text under `exception`.
- `default=str` makes `json.dumps` convert unknown objects to text instead of failing.

The call that produces the denial entry:

`src/uploads/interfaces/worker.py`

```python
        except StoreFailed as error:
            # The full text names the service account, the permission and the resource when the cause is IAM.
            logger.error("could not store the result", extra={"error": str(error)})
            return Response("storage failed", status=500, mimetype="text/plain")
```

The log line carries `"error": "Forbidden: 403 POST ...: worker-sa@... does not have storage.objects.create access..."`; the response body is just `storage failed`, so internal detail stays in the logs and out of HTTP replies.

The query:

`scripts/read-denial.sh`

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="worker" AND severity>=ERROR' \
  --limit=5 --freshness=1h --format='value(jsonPayload.error)'
```

`--freshness=1h` only looks at the last hour; `--format='value(jsonPayload.error)'` prints the `error` field.

## 6. Try it yourself

```bash
.venv/bin/python - <<'PY'
import logging
from uploads.infrastructure.logging import configure_logging
configure_logging("INFO")
logging.getLogger("demo").error("could not store", extra={"error": "Forbidden: worker-sa lacks storage.objects.create"})
PY
```
Expected: one line of JSON such as `{"severity": "ERROR", "message": "could not store", "logger": "demo", "error": "Forbidden: worker-sa lacks storage.objects.create"}`.

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_logging.py -q -p no:cacheprovider
```
Expected: `4 passed`.

## 7. Mistakes people make

- **Plain text logs.** Severity is lost; every line looks like INFO.
- **Logging secrets or full request bodies.**
- **Reserved names in `extra`.** `name`, `message` and others collide with the logging internals.
- **Searching without a time limit.** Add `--freshness`.
- **Putting internal error text into HTTP responses.** Keep it in the log.

## 8. Check yourself

1. Which JSON keys does Cloud Run's logging read specially? *`severity` and `message`.*
2. Where does a container's output go? *Cloud Logging, with the service's resource labels.*
3. Why is the Google error text logged but not returned? *It names internals; callers need not see it.*
4. What does `--freshness=1h` do? *Limits the read to entries from the last hour.*
5. What happens if `extra` contains `name`? *Python raises `KeyError`.*

## 9. Further reading

- Cloud Logging: <https://cloud.google.com/logging/docs>
- Structured logging: <https://cloud.google.com/logging/docs/structured-logging>
- Query language: <https://cloud.google.com/logging/docs/view/logging-query-language>
