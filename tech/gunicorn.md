# Gunicorn

## 1. What it is

Gunicorn ("Green Unicorn") is a **WSGI HTTP server** for Python. A server is a program that waits on a network port. Gunicorn accepts HTTP connections, reads requests, calls your Python web app (a Flask object) and sends the answer back. It also starts and watches worker processes and threads. This repository pins version 26.2.0.

## 2. Why this repository uses it

Flask's own server is for development only. Cloud Run needs a program that listens on the port given in the `PORT` environment variable, handles several requests at once, and shuts down cleanly when Cloud Run asks. Gunicorn does all three.

## 3. Where it appears

| Path | What it does with Gunicorn |
| --- | --- |
| `src/uploads/interfaces/gunicorn_conf.py` | The settings file: port, workers, threads, timeouts. |
| `Dockerfile` | The `CMD` of the `api` and `worker` targets starts Gunicorn. |
| `pyproject.toml`, `requirements.lock` | Pin `gunicorn==26.2.0`. |
| `docker-compose.yml` | Builds the same image for the local stack. |

## 4. How it works underneath

Gunicorn has one **master process** and some **worker processes**. The master does not serve requests; it starts workers, restarts any that die, and reacts to **signals**. A signal is a tiny message the operating system sends to a process. `SIGTERM` means "please stop"; `SIGKILL` cannot be caught and ends the process at once.

Each worker here is of type `gthread`: one process with a pool of **threads**. A thread is a separate line of execution inside one process; while one thread waits for the network, another can run. That suits this app, which spends most of its time waiting for Google's services.

When Cloud Run wants to stop an instance, it sends `SIGTERM`, waits about ten seconds, then sends `SIGKILL`. On `SIGTERM` Gunicorn stops accepting new connections and gives running requests `graceful_timeout` seconds to finish.

## 5. Walkthrough of this repository's use

`src/uploads/interfaces/gunicorn_conf.py`

```python
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"  # the container must listen on all interfaces
workers = 1
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
timeout = 0  # Cloud Run enforces the request timeout; gunicorn must not kill a slow request first
graceful_timeout = 8  # on SIGTERM finish in-flight requests, then exit before Cloud Run's SIGKILL
accesslog = None
control_socket_disable = True  # gunicorn 26 opens an admin socket under $HOME; the container user has no home
```

- A Gunicorn config file is ordinary Python; every top-level variable is a setting.
- `bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"`: listen on all network interfaces (`0.0.0.0`) on the port from `PORT`, defaulting to 8080. Cloud Run sets `PORT`. Inside a container you must not bind to `127.0.0.1` only, or nothing outside could reach you.
- `workers = 1`, `threads = 8`: one process, eight threads. Cloud Run scales by starting more instances, so one process per instance is enough. `GUNICORN_THREADS` can change the thread count.
- `timeout = 0` turns off Gunicorn's own per-request kill timer. Cloud Run already enforces a request timeout (60 seconds in `infra/modules/cloud-run-service`), and a second timer could kill a request the platform still allows.
- `graceful_timeout = 8`: finish running requests for at most eight seconds after `SIGTERM`, which fits inside Cloud Run's ten.
- `accesslog = None`: Cloud Run already logs every request; Gunicorn adds nothing.
- `control_socket_disable = True`: Gunicorn 26 can open an administration socket in the user's home directory. The container user is created with `--no-create-home`, so Gunicorn logged `Permission denied: '/home/app'`. Turning the feature off removes the error. (This was found by running the container.)

The start command, from the Dockerfile:

`Dockerfile`

```dockerfile
FROM base AS api
CMD ["gunicorn", "-c", "python:uploads.interfaces.gunicorn_conf", "uploads.interfaces.api_main:create()"]
```

- `-c python:uploads.interfaces.gunicorn_conf` loads the config **as a Python module** (the `python:` prefix) rather than from a file path.
- `uploads.interfaces.api_main:create()` is the app to run. The `()` makes Gunicorn **call** `create` and use the returned Flask object, which is how our factory pattern works.

## 6. Try it yourself

```bash
.venv/bin/gunicorn --version
```
Expected: `gunicorn (version 26.2.0)`

```bash
PORT=9000 .venv/bin/gunicorn -c python:uploads.interfaces.gunicorn_conf --print-config "uploads.interfaces.worker_main:create()" 2>&1 | grep -E '^(bind|workers|threads|timeout|graceful_timeout|control_socket_disable) '
```
Expected:
```text
bind                               = ['0.0.0.0:9000']
control_socket_disable             = True
graceful_timeout                   = 8
threads                            = 8
timeout                            = 0
workers                            = 1
```

```bash
STORAGE_EMULATOR_HOST=http://localhost:1 BUCKET=demo .venv/bin/gunicorn -c python:uploads.interfaces.gunicorn_conf --check-config "uploads.interfaces.worker_main:create()"; echo "exit=$?"
```
Expected: no output except `exit=0`. It loads the app (which needs `BUCKET`) and checks it imports, without starting a server.

## 7. Mistakes people make

- **Binding to `127.0.0.1` in a container.** The port is then unreachable from outside. Use `0.0.0.0`.
- **Too many worker processes on a small instance.** Each one loads the whole app; Cloud Run scales out instead.
- **A Gunicorn timeout shorter than the platform's.** It kills requests the platform would allow.
- **Ignoring `SIGTERM`.** An app that does not stop in time is killed mid-request. `graceful_timeout` stays under Cloud Run's limit.
- **Starting the app at import time** so that `--check-config` fails without secrets. Here `create()` runs only when called.

## 8. Check yourself

1. What is the master process for? *Starting, restarting and signalling workers; it serves no requests.*
2. Why `0.0.0.0`? *Listen on every interface so the container's published port works.*
3. What do the `()` in `api_main:create()` mean? *Call the factory and use the returned app.*
4. Which signal asks a process to stop politely? *`SIGTERM`.*
5. Why is `timeout = 0` safe here? *Cloud Run enforces the request timeout itself.*

## 9. Further reading

- Gunicorn documentation (version 26): <https://docs.gunicorn.org/en/stable/>
- Settings reference: <https://docs.gunicorn.org/en/stable/settings.html>
- Cloud Run container contract (port, SIGTERM): <https://cloud.google.com/run/docs/container-contract>
