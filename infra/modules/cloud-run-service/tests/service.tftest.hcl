mock_provider "google" {}

variables {
  project_id            = "example-sandbox-0000"
  name                  = "worker"
  location              = "europe-west1"
  image                 = "europe-west1-docker.pkg.dev/example-sandbox-0000/uploads/worker:1"
  service_account_email = "worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
  labels                = { environment = "sandbox" }
}

run "the_service_runs_as_the_given_account_with_labels" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].service_account == var.service_account_email && google_cloud_run_v2_service.this.labels["environment"] == "sandbox"
    error_message = "The service must run as the given account and carry its labels."
  }
}

run "a_private_service_has_no_invoker_bindings" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "With no invoker members the service must stay private."
  }
}

run "the_invoker_binding_is_on_the_service" {
  command = plan

  variables {
    invoker_members = { pubsub = "serviceAccount:pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com" }
  }

  assert {
    condition     = alltrue([for b in google_cloud_run_v2_service_iam_member.invoker : b.role == "roles/run.invoker"])
    error_message = "Only roles/run.invoker is granted."
  }
}

run "secrets_are_referenced_not_copied" {
  command = plan

  variables {
    secret_env = {
      DB_PASSWORD = { secret = "db-password", version = "latest" } # checkov:skip=CKV_SECRET_6:a secret name, not a value
    }
  }

  assert {
    condition     = length([for e in google_cloud_run_v2_service.this.template[0].containers[0].env : e if length(e.value_source) > 0]) == 1
    error_message = "The secret must be wired through value_source, not as a plain value."
  }
}

run "an_unknown_ingress_value_is_rejected" {
  command = plan

  variables {
    ingress = "EVERYWHERE"
  }

  expect_failures = [var.ingress]
}
