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
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.invoker_members

  project  = var.project_id
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
