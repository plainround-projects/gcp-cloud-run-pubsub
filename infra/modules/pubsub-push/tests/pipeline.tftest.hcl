mock_provider "google" {}

variables {
  project_id                    = "example-sandbox-0000"
  project_number                = "000000000000"
  topic_name                    = "uploads"
  push_endpoint                 = "https://worker-example.a.run.app/"
  oidc_audience                 = "https://worker-example.a.run.app"
  invoker_service_account_email = "pubsub-invoker@example-sandbox-0000.iam.gserviceaccount.com"
  publisher_members             = { api = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "push_is_authenticated_and_failures_are_dead_lettered" {
  command = plan

  assert {
    condition     = one(google_pubsub_subscription.push.push_config).oidc_token[0].service_account_email == var.invoker_service_account_email
    error_message = "The push subscription must send an OIDC token for the invoker account."
  }

  assert {
    condition     = one(google_pubsub_subscription.push.dead_letter_policy).max_delivery_attempts == 5
    error_message = "A message must be dead-lettered after 5 attempts."
  }
}

run "the_service_agent_has_the_grants_dead_lettering_needs" {
  command = plan

  assert {
    condition     = google_pubsub_topic_iam_member.agent_publishes_dead_letters.member == "serviceAccount:service-000000000000@gcp-sa-pubsub.iam.gserviceaccount.com" && google_pubsub_subscription_iam_member.agent_acknowledges.role == "roles/pubsub.subscriber"
    error_message = "The Pub/Sub service agent must publish to the dead-letter topic and subscribe on the push subscription."
  }
}

run "publishing_is_granted_on_the_topic_only" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic_iam_member.publisher) == 1
    error_message = "One publisher binding on the topic is expected."
  }
}

run "an_insecure_endpoint_is_rejected" {
  command = plan

  variables {
    push_endpoint = "http://worker.example/"
  }

  expect_failures = [var.push_endpoint]
}

run "fewer_than_five_attempts_is_rejected" {
  command = plan

  variables {
    max_delivery_attempts = 3
  }

  expect_failures = [var.max_delivery_attempts]
}
