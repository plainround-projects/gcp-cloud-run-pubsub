# Docker (and the Dockerfile)

## 1. What it is

Docker packages a program together with everything it needs to run (the right Python, the libraries, the settings) into an **image**. Running an image starts a **container**: an isolated process that sees its own small file system and its own network. The same image behaves the same on your laptop and on Cloud Run. A **Dockerfile** is the text recipe that builds an image, one instruction per line. Docker 24 was used here.

## 2. Why this repository uses it

Cloud Run runs containers, so the API and worker must be images. The Dockerfile also shows the production rules: a pinned base image, no root user, no key inside.

## 3. Where it appears

| Path | What it does with Docker |
| --- | --- |
| `Dockerfile` | One recipe with three stages (`base`, `api`, `worker`). |
| `.dockerignore` | Lists files that must not be sent to the build. |
| `docker-compose.yml` | Builds and runs the images locally (see `docker-compose.md`). |
| `Makefile` | `docker-build` builds both targets. |
| `scripts/build-images.sh` | Builds for `linux/amd64` and pushes to Artifact Registry. |

## 4. How it works underneath

- An image is a stack of read-only **layers**. Each instruction that changes files adds a layer. Docker caches layers: if an instruction and everything above it are unchanged, the cached layer is reused. So put things that change rarely (installing libraries) before things that change often (your source).
- A **multi-stage** Dockerfile has several `FROM` lines. A stage can be built on its own with `--target`. Here the `api` and `worker` stages both start from `base` and differ only in the start command.
- The **build context** is the folder sent to the Docker engine. `.dockerignore` keeps `.git`, `.venv`, `tests` and similar out of it.
- A container shares the host's kernel, but its **processes**, **file system** and **users** are separate. `USER app` makes the main process run as an unprivileged user, so a bug in the app cannot act as root inside the container.
- Pinning the base image by **digest** (`@sha256:...`) fixes the exact bytes; a tag such as `3.12.8-slim-bookworm` could be re-pointed.

## 5. Walkthrough of this repository's use

`Dockerfile`

```dockerfile
# One image definition, two targets: `--target api` and `--target worker`. Both run as a non-root user; neither contains a key.
#   docker build --target api -t uploads-api:dev .
FROM python:3.12.8-slim-bookworm@sha256:2199a62885a12290dc9c5be3ca0681d367576ab7bf037da120e564723292a2f0 AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8080

WORKDIR /app
COPY requirements.lock ./
RUN pip install --require-hashes -r requirements.lock

# The application is plain source on the path: nothing to build, so the image needs no network after the lock file.
COPY src ./src
ENV PYTHONPATH=/app/src

RUN useradd --system --uid 10001 --no-create-home app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['PORT'] + '/health', timeout=8)"]
```

- Lines starting with `#` are comments.
- `FROM python:3.12.8-slim-bookworm@sha256:... AS base`: start from the official slim Python 3.12.8 image on Debian "bookworm", pinned by digest; name this stage `base`.
- `ENV A=1 \ B=2` sets environment variables for all later steps and for the running container. `PYTHONDONTWRITEBYTECODE=1` stops `.pyc` files; `PYTHONUNBUFFERED=1` makes output appear at once in logs; `PIP_NO_CACHE_DIR=1` keeps the image small; `PIP_DISABLE_PIP_VERSION_CHECK=1` removes a needless network call; `PORT=8080` is the default port (Cloud Run overrides it).
- `WORKDIR /app` creates the folder and makes it the current folder.
- `COPY requirements.lock ./` then `RUN pip install --require-hashes -r requirements.lock`: copy only the lock file and install from it **before** copying the source, so this slow layer is reused until the lock file changes. `--require-hashes` makes pip refuse any package whose hash is not listed.
- `COPY src ./src` and `ENV PYTHONPATH=/app/src` put the code on Python's import path. There is no `pip install .` step: the project is plain source, so nothing needs building. (An earlier version ran `pip install .`, which stalled for a long time on a busy machine.)
- `RUN useradd --system --uid 10001 --no-create-home app` creates the unprivileged account, and `USER app` switches to it. No home directory means the process cannot write there, which is why Gunicorn's control socket is disabled.
- `EXPOSE 8080` documents the port; it does not publish it.
- `HEALTHCHECK ... CMD [...]` tells Docker how to test health: run a short Python program that requests `/health` on the local port. `--interval`, `--timeout`, `--start-period`, `--retries` tune how often and how patient. Cloud Run ignores it; Docker and Compose use it.

`Dockerfile`

```dockerfile
FROM base AS api
CMD ["gunicorn", "-c", "python:uploads.interfaces.gunicorn_conf", "uploads.interfaces.api_main:create()"]

FROM base AS worker
CMD ["gunicorn", "-c", "python:uploads.interfaces.gunicorn_conf", "uploads.interfaces.worker_main:create()"]
```

Each final stage sets only the **start command** (`CMD`) in the exec (JSON list) form, so the process receives signals directly. `docker build --target api` stops at that stage.

## 6. Try it yourself

Needs Docker; skip if the machine is busy.

```bash
docker build --target api -t uploads-api:dev .
```
Expected: ends with a line naming the image `uploads-api:dev` (first build downloads layers and can take minutes).

```bash
docker run --rm uploads-api:dev id
```
Expected: `uid=10001(app) gid=10001(app) groups=10001(app)` — not root.

```bash
docker run --rm uploads-api:dev python -c "import sys; print(sys.path[:3])"
```
Expected: a list that includes `/app/src`.

```bash
docker history uploads-api:dev | head -8
```
Expected: the layers, newest first, including the `pip install` layer.

## 7. Mistakes people make

- **Copying the source before installing dependencies.** Every code change reinstalls everything.
- **Running as root.** Anything that breaks out of the app has full rights in the container.
- **Using `latest` tags.** The image changes under you. This one is pinned by digest.
- **Putting secrets in `ENV` or `COPY`.** They stay in the layers forever. This image holds no key.
- **Building on an Apple-silicon Mac and deploying to Cloud Run unchanged.** The CPU type differs; use `--platform linux/amd64`.
- **Shell-form `CMD`.** Signals reach the shell, not your app.

## 8. Check yourself

1. Why is `requirements.lock` copied before `src`? *So the installation layer is cached until the lock file changes.*
2. What does `USER app` do? *Runs later steps and the container's main process as the unprivileged `app` user.*
3. What does `--target api` build? *The stages up to and including the `api` stage.*
4. What is a digest pin? *The exact content hash of the base image, which cannot be re-pointed.*
5. Does `EXPOSE` open the port? *No, it only documents it.*

## 9. Further reading

- Dockerfile reference: <https://docs.docker.com/reference/dockerfile/>
- Multi-stage builds: <https://docs.docker.com/build/building/multi-stage/>
- Best practices: <https://docs.docker.com/build/building/best-practices/>
- Official Python image: <https://hub.docker.com/_/python>
