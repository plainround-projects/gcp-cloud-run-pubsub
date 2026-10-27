# The mock provider invents computed values, so the service-account modules are overridden with fixed outputs and the
# runs plan against the mock to check the wiring between modules.
mock_provider "google" {}

override_module {
  target = module.api_sa
  outputs = {
    email  = "api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/api-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.worker_sa
  outputs = {
    email  = "worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/worker-sa@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_module {
  target = module.invoker_sa
  outputs = {
    email  = "pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    member = "serviceAccount:pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
    name   = "projects/example-sandbox-0000/serviceAccounts/pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
  }
}

override_resource {
  target          = module.worker.google_cloud_run_v2_service.this
  override_during = plan
  values = {
    uri = "https://worker-example.a.run.app"
  }
}

override_resource {
  target          = module.api.google_cloud_run_v2_service.this
  override_during = plan
  values = {
    uri = "https://api-example.a.run.app"
  }
}

variables {
  project_id     = "example-sandbox-0000"
  project_number = "000000000000"
  db_password    = "placeholder" # checkov:skip=CKV_SECRET_6:placeholder in a test fixture
}

run "each_workload_has_its_own_identity" {
  command = plan

  assert {
    condition     = length(distinct(values(output.service_accounts))) == 3
    error_message = "The API, the worker and the invoker need three different service accounts."
  }
}

run "the_results_bucket_is_named_after_the_project" {
  command = plan

  assert {
    condition     = output.results_bucket == "example-sandbox-0000-results"
    error_message = "The bucket name must derive from the project id."
  }
}

run "only_the_worker_account_creates_objects_and_only_the_invoker_calls_the_worker" {
  command = plan

  assert {
    condition     = module.results.creator_members == tolist([module.worker_sa.member]) && module.worker.invoker_members == tolist([module.invoker_sa.member])
    error_message = "Bucket creator is the worker account; worker invoker is the invoker account."
  }
}

run "only_the_api_account_publishes_and_reads_the_secret" {
  command = plan

  assert {
    condition     = module.pipeline.publisher_members == tolist([module.api_sa.member]) && module.db_password.accessor_members == tolist([module.api_sa.member])
    error_message = "Publisher and secret accessor are the API account."
  }
}

run "the_push_subscription_calls_the_worker_as_the_invoker_account" {
  command = plan

  assert {
    condition     = module.worker.uri != null && module.pipeline.push_subscription_name == "uploads-push"
    error_message = "The pipeline must push to the worker."
  }
}

run "the_api_is_public_by_default" {
  command = plan

  assert {
    condition     = module.api.invoker_members == tolist(["allUsers"])
    error_message = "The exercise API is public by default."
  }
}

run "a_private_api_on_request" {
  command = plan

  variables {
    api_public = false
  }

  assert {
    condition     = length(module.api.invoker_members) == 0
    error_message = "api_public = false must remove the allUsers binding."
  }
}
