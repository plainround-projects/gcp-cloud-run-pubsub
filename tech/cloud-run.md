# Cloud Run

## 1. What it is

Cloud Run is Google Cloud's service for running a **container** as a web service without managing servers. A **container image** is a packed folder with a program and everything it needs. You give Cloud Run an image; it starts copies (**instances**) when requests arrive, stops them when traffic stops, and gives you an HTTPS address. Each deployed service has **revisions**: a new revision is created whenever its settings change.

## 2. Why this repository uses it

The lesson runs two small services on Cloud Run, each with its own identity: a public API and a private worker. Cloud Run makes both ideas visible: "which account does this service run as?" and "who may call it?".

## 3. Where it appears

| Path | What it does with Cloud Run |
| --- | --- |
| `infra/modules/cloud-run-service/` | A reusable Terraform module that creates one service, its settings, and who may call it. |
| `infra/environments/sandbox/main.tf` | Uses the module twice: `worker` (private) and `api` (public, with the secret). |
| `src/uploads/interfaces/gunicorn_conf.py` | Listens on `PORT`, as Cloud Run requires. |
| `scripts/build-images.sh`, `deploy.sh`, `prove.sh` | Build and push images, apply, and check identity and the 403. |

## 4. How it works underneath

- **Container contract.** Cloud Run starts your container and sets the environment variable `PORT`. Your program must listen on that port on all interfaces. When Cloud Run stops an instance it sends `SIGTERM`, waits about ten seconds, then `SIGKILL`.
- **Scaling.** With `min_instances = 0` an idle service runs nothing and costs nothing. `max_instances` caps the bill. `max_instance_request_concurrency` is how many requests one instance handles at once (20 here; Cloud Run's default is 80).
- **Request-based billing.** With `cpu_idle = true`, an instance gets CPU only while it handles a request, which is the cheapest mode.
- **Identity.** Every service runs as a **service account**. If you do not name one, it runs as the project's default Compute Engine account, which often holds the broad Editor role. This repository always names one (`api-sa`, `worker-sa`).
- **Who may call it.** Cloud Run checks IAM before your code runs. A caller needs `roles/run.invoker` on the service. `allUsers` means anyone; leaving it out makes the service private, so an unauthenticated request gets `403 Forbidden`. Pub/Sub's token (see `cloud-pubsub.md`) is checked here.
- **Secrets as environment variables.** A setting can say "fill `DB_PASSWORD` from this Secret Manager secret". Cloud Run reads it with the service's own identity at start-up. The secret needs at least one version, or the revision fails to start.
- **Ingress** says which networks may reach the service (`INGRESS_TRAFFIC_ALL` here).

## 5. Walkthrough of this repository's use

`infra/modules/cloud-run-service/main.tf`

```hcl
resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels

  ingress             = var.ingress
  deletion_protection = var.deletion_protection

  template {
    # The service's own identity. Leaving this out would run the service as the default compute account.
    service_account = var.service_account_email
    timeout         = "${var.request_timeout_seconds}s"

    max_instance_request_concurrency = var.concurrency

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
```

- `google_cloud_run_v2_service` is a **Terraform resource type** (see `terraform.md`) for a Cloud Run service. `this` is just its local name.
- `ingress` and `deletion_protection` come from variables; the sandbox sets protection off so teardown works.
- `service_account = var.service_account_email` is the line that stops the service from running as the default account. The comment above it says so.
- `timeout = "${var.request_timeout_seconds}s"`: the request timeout, 60 seconds by default.
- `max_instance_request_concurrency` and the `scaling` block set concurrency and instance bounds.

`infra/modules/cloud-run-service/main.tf`

```hcl
    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = true
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Cloud Run reads the secret with the service's own identity at start-up.
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

# Invoker access is granted on this one service. allUsers appears only when the caller asks for a public service.
```

- `image` is the container image. `ports { container_port }` is the port the container listens on.
- `resources { limits { cpu, memory }, cpu_idle = true }`: size limits per instance and request-based CPU.
- The first `dynamic "env"` block turns the plain map `var.env` into one `env { name, value }` per entry. A **dynamic block** repeats a nested block once per item of a collection.
- The second `dynamic "env"` builds the secret-backed variables: `value_source { secret_key_ref { secret, version } }` means "read this secret version". The API gets `DB_PASSWORD` this way.

The caller rules:

`infra/modules/cloud-run-service/main.tf`

```hcl
# Invoker access is granted on this one service. allUsers appears only when the caller asks for a public service.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.invoker_members

  project  = var.project_id
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
```

`for_each = var.invoker_members` creates one binding per entry. In the sandbox the worker's map holds only `pubsub-invoker`; the API's holds `allUsers` (when `api_public` is true). The role is granted on this one service, never on the project.

How the sandbox environment uses it:

`infra/environments/sandbox/main.tf`

```hcl
module "worker" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  name                  = "worker"
  location              = var.region
  image                 = var.worker_image
  service_account_email = module.worker_sa.email
  labels                = var.labels
  env = {
    BUCKET     = module.results.name
    PROJECT_ID = var.project_id
  }
  invoker_members = { pubsub = module.invoker_sa.member }

  depends_on = [module.baseline]
```

## 6. Try it yourself

```bash
cd infra/environments/sandbox && terraform init -backend=false -input=false >/dev/null && terraform validate
```
Expected: `Success! The configuration is valid.`

```bash
cd infra/modules/cloud-run-service && terraform init -backend=false -input=false >/dev/null && terraform test
```
Expected: `Success! 5 passed, 0 failed.` The tests check that the service runs as the given account, a service with no invoker members stays private, the invoker binding is only `roles/run.invoker`, secrets use `value_source`, and a bad `ingress` value is rejected.

```bash
make run
```
Expected (Docker needed): the same container image runs locally as `api` and `worker`; `make run` prints `health: {"db_password_set":true}`, two uploads and the result files.

## 7. Mistakes people make

- **Forgetting `--service-account`/`service_account`.** The service runs as the default compute account. The module requires the variable.
- **Listening on a fixed port.** Cloud Run chooses; read `PORT`.
- **Making the worker public** so that anyone can post fake messages. It has no `allUsers` binding.
- **A secret reference with no version.** The new revision fails to start. The module writes the first version before the API is created.
- **Expecting an instance to live on.** It can be stopped at any time after `SIGTERM`.

## 8. Check yourself

1. What identity does a Cloud Run service use if none is named? *The default Compute Engine service account.*
2. What status does an unauthenticated call to a private service get? *403.*
3. Which environment variable gives the port? *`PORT`.*
4. What does `min_instances = 0` cost while idle? *Nothing; no instance runs.*
5. Where is `roles/run.invoker` granted here? *On the single service, not on the project.*

## 9. Further reading

- Cloud Run documentation: <https://cloud.google.com/run/docs>
- Container runtime contract: <https://cloud.google.com/run/docs/container-contract>
- Services and authentication: <https://cloud.google.com/run/docs/authenticating/overview>
- Terraform resource `google_cloud_run_v2_service` (provider 8.x): <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service>
