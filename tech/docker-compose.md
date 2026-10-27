# Docker Compose

## 1. What it is

Docker Compose runs several containers together from one file, `docker-compose.yml`. Each entry under `services:` is one container; Compose creates a private network where services reach each other by service name (`http://worker:8080`). You start everything with `docker compose up` and remove it with `docker compose down`. The `docker compose` command (version 2) is part of Docker.

## 2. Why this repository uses it

The lesson needs Pub/Sub and Cloud Storage, which are Google services. Compose runs fakes of them on your machine so the code, including retries and the dead-letter flow, can be tested with no cloud account: the Pub/Sub **emulator**, a **fake Cloud Storage server**, and optionally the API and worker images themselves.

## 3. Where it appears

| Path | What it does with Compose |
| --- | --- |
| `docker-compose.yml` | Defines `pubsub`, `gcs` (always) and `api`, `worker` (profile `apps`). |
| `Makefile` | `emulators`, `up`, `run`, `down`, `test-integration`, `test-e2e` call `docker compose`. |
| `scripts/init_emulator.py` | Creates the topic, subscriptions and bucket after the stack starts. |
| `tests/conftest.py` | Expects the emulators on `localhost:8085` and `localhost:4443`. |

## 4. How it works underneath

Compose reads the YAML (see `yaml.md`), turns each service into `docker run` options, creates a network named after the project (`gcp-cloud-run-pubsub_default`), and starts the containers. A **health check** is a command Docker runs repeatedly inside a container; its status is `starting`, `healthy` or `unhealthy`. `up --wait` waits until services with a health check are healthy (or fails). A **profile** hides a service unless you ask for it with `--profile apps`. **Published ports** (`"8085:8085"`, host:container) make a container's port reachable from your machine as `localhost`.

## 5. Walkthrough of this repository's use

`docker-compose.yml`

```yaml
name: gcp-cloud-run-pubsub

services:
  pubsub:
    image: gcr.io/google.com/cloudsdktool/google-cloud-cli:590.0.1-emulators
    command: gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 --project=local-project
    ports:
      - "8085:8085"
    # Lets the emulator push to a worker running on the host (the end-to-end tests do that).
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
      # A TCP connect, not an HTTP request: the emulator's HTTP/1 handler is only there for this kind of probe and can stall.
      test: ["CMD", "python3", "-c", "import socket; socket.create_connection(('127.0.0.1', 8085), 3).close()"]
      interval: 5s
      timeout: 10s
      retries: 60
```

- `name: gcp-cloud-run-pubsub` fixes the project name (and therefore the network and container names).
- `pubsub.image: gcr.io/google.com/cloudsdktool/google-cloud-cli:590.0.1-emulators` is Google's image that contains the emulator, pinned to a version. `command: gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 --project=local-project` starts it and makes it listen on all interfaces on port 8085. (It is about 1 GB, and its Java process can take minutes to start on a busy machine.)
- `ports: ["8085:8085"]` publishes it on your machine.
- `extra_hosts: ["host.docker.internal:host-gateway"]` makes the name `host.docker.internal` point at your computer from inside the container, so the emulator can push messages to a worker running on your machine (the end-to-end test does this).
- `healthcheck.test: ["CMD", "python3", "-c", "import socket; socket.create_connection(('127.0.0.1', 8085), 3).close()"]` tries a plain TCP connection to the port. It is deliberately not an HTTP request: the emulator's HTTP/1 handler stalled under repeated probes. `interval`, `timeout`, `retries` and `start_period` give the Java process time to start (failures during `start_period` are not counted).

`docker-compose.yml`

```yaml
  gcs:
    image: fsouza/fake-gcs-server:1.52.2
    command: ["-scheme", "http", "-port", "4443", "-backend", "memory", "-public-host", "localhost:4443"]
    ports:
      - "4443:4443"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:4443/storage/v1/b"]
      interval: 3s
      timeout: 3s
      retries: 30
```

- `fsouza/fake-gcs-server:1.52.2` is the fake Cloud Storage. Its `command` list gives program arguments: plain HTTP (`-scheme http`), port 4443, keep data in memory (`-backend memory`), and the host name clients should use in links (`-public-host localhost:4443`).
- Its health check is `wget` fetching the bucket list; `CMD` runs the program directly (not through a shell).

`docker-compose.yml`

```yaml
  api:
    profiles: ["apps"]
    build:
      context: .
      target: api
    environment:
      PROJECT_ID: local-project
      TOPIC_ID: uploads
      DB_PASSWORD: ${DB_PASSWORD:-} # make up generates a throwaway; empty makes /health report false
      PUBSUB_EMULATOR_HOST: pubsub:8085
    ports:
      - "8080:8080"
    depends_on:
      pubsub:
        condition: service_healthy

  worker:
    profiles: ["apps"]
    build:
      context: .
      target: worker
    environment:
      PROJECT_ID: local-project
      BUCKET: local-results
      STORAGE_EMULATOR_HOST: http://gcs:4443
    ports:
      - "8081:8080"
    depends_on:
      gcs:
        condition: service_healthy
```

- `profiles: ["apps"]` keeps `api` and `worker` out of a plain `docker compose up`.
- `build: { context: ., target: api }` builds the repository's Dockerfile up to the `api` stage.
- `environment:` sets the variables the app reads. `PUBSUB_EMULATOR_HOST: pubsub:8085` points the client at the other service by name. `DB_PASSWORD: ${DB_PASSWORD:-}` takes the value from your shell, or empty if unset; `make up` generates a throwaway one with `openssl rand -hex 12`, so no password is stored in the file.
- `depends_on: { pubsub: { condition: service_healthy } }` starts the API only after the emulator is healthy. The worker waits for `gcs`.
- Worker port `8081:8080` avoids clashing with the API's `8080:8080` on your machine.

How the Makefile drives it:

`Makefile`

```make
emulators: ## start the Pub/Sub emulator and a fake Cloud Storage server
	$(COMPOSE) up -d --wait --wait-timeout 900 pubsub gcs

test-integration: $(STAMP) emulators ## adapters against the emulators
	$(PY) -m pytest tests/integration -m integration

test-e2e: $(STAMP) emulators ## the lesson's scenario: API -> topic -> push -> worker -> bucket, and the failing variant
	$(PY) -m pytest tests/e2e -m e2e

up: ## build and start the emulators, the API and the worker as containers
	DB_PASSWORD=$$(openssl rand -hex 12) $(COMPOSE) --profile apps up -d --build --wait --wait-timeout 900
	$(PY) scripts/init_emulator.py

run: $(STAMP) up ## upload twice through the local stack and list the result files
	scripts/local-demo.sh
```

## 6. Try it yourself

Needs Docker and some patience (first start pulls about 1 GB). Only run one stack at a time on a shared machine.

```bash
docker compose config --quiet && echo valid
```
Expected: `valid` (the file parses and every variable resolves).

```bash
make emulators && docker compose ps --format '{{.Name}} {{.Status}}'
```
Expected: `gcp-cloud-run-pubsub-gcs-1 ... (healthy)` and `gcp-cloud-run-pubsub-pubsub-1 ... (healthy)`.

```bash
make test-integration
```
Expected: `4 passed`.

```bash
make down
```
Expected: the containers and the network are removed (`docker compose down -v`).

## 7. Mistakes people make

- **Leaving stacks running.** On a shared machine they eat memory; end every session with `down`.
- **Using `localhost` between containers.** Inside a container `localhost` is itself. Use the service name.
- **Confusing `EXPOSE`/`ports`.** Only `ports` publishes to your machine.
- **A health check that is too strict or too short.** A slow Java process then looks "unhealthy".
- **Hard-coding secrets in the file.** Use `${VAR}` and set it at start.

## 8. Check yourself

1. How does `worker` reach `gcs`? *By the service name `gcs` on the Compose network.*
2. What does `profiles: ["apps"]` do? *Starts those services only with `--profile apps`.*
3. What does `up --wait` wait for? *Services with a health check to become healthy.*
4. Why `extra_hosts` on the `pubsub` service? *So the emulator can reach a worker on the host.*
5. Where does `DB_PASSWORD` come from? *Your shell; `make up` generates one.*

## 9. Further reading

- Compose file reference: <https://docs.docker.com/reference/compose-file/>
- Compose CLI (`up --wait`): <https://docs.docker.com/reference/cli/docker/compose/up/>
- Pub/Sub emulator: <https://cloud.google.com/pubsub/docs/emulator>
