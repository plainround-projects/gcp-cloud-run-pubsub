locals {
  # The Pub/Sub service agent publishes dead letters and acknowledges deliveries on the subscription's behalf.
  service_agent = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "main" {
  #checkov:skip=CKV_GCP_83:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project = var.project_id
  name    = var.topic_name
  labels  = var.labels
}

resource "google_pubsub_topic" "dead_letter" {
  #checkov:skip=CKV_GCP_83:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project = var.project_id
  name    = "${var.topic_name}-dead"
  labels  = var.labels
}

# Pull subscription on the dead-letter topic so a failed message can be read and replayed.
resource "google_pubsub_subscription" "dead_letter_pull" {
  project = var.project_id
  name    = "${var.topic_name}-dead-pull"
  topic   = google_pubsub_topic.dead_letter.id
  labels  = var.labels

  message_retention_duration = "604800s"
  ack_deadline_seconds       = 20

  expiration_policy {
    ttl = "" # never expires
  }
}

resource "google_pubsub_subscription" "push" {
  project = var.project_id
  name    = "${var.topic_name}-push"
  topic   = google_pubsub_topic.main.id
  labels  = var.labels

  ack_deadline_seconds = var.ack_deadline_seconds

  push_config {
    push_endpoint = var.push_endpoint

    # Pub/Sub signs a token for the invoker account; Cloud Run checks it. The invoker holds run.invoker on the worker only.
    oidc_token {
      service_account_email = var.invoker_service_account_email
      audience              = var.oidc_audience
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = var.minimum_backoff
    maximum_backoff = var.maximum_backoff
  }

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = var.publisher_members

  project = var.project_id
  topic   = google_pubsub_topic.main.name
  role    = "roles/pubsub.publisher"
  member  = each.value
}

resource "google_pubsub_topic_iam_member" "agent_publishes_dead_letters" {
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter.name
  role    = "roles/pubsub.publisher"
  member  = local.service_agent
}

resource "google_pubsub_subscription_iam_member" "agent_acknowledges" {
  project      = var.project_id
  subscription = google_pubsub_subscription.push.name
  role         = "roles/pubsub.subscriber"
  member       = local.service_agent
}

# Needed for projects whose Pub/Sub API was enabled after April 2021: the agent mints the invoker's OIDC token.
resource "google_service_account_iam_member" "agent_signs_invoker_token" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.invoker_service_account_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.service_agent
}
