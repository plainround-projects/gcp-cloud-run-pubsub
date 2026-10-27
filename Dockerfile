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

COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-deps .

RUN useradd --system --uid 10001 --no-create-home app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['PORT'] + '/health', timeout=3)"]

FROM base AS api
CMD ["gunicorn", "-c", "python:uploads.interfaces.gunicorn_conf", "uploads.interfaces.api_main:create()"]

FROM base AS worker
CMD ["gunicorn", "-c", "python:uploads.interfaces.gunicorn_conf", "uploads.interfaces.worker_main:create()"]
