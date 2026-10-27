resource "google_secret_manager_secret" "this" {
  project   = var.project_id
  secret_id = var.secret_id
  labels    = var.labels

  replication {
    auto {}
  }
}

# The value is a write-only argument: it is sent to Secret Manager and never stored in the Terraform state or plan.
# Bump secret_version to write a new version.
resource "google_secret_manager_secret_version" "this" {
  count = var.create_version ? 1 : 0

  secret                 = google_secret_manager_secret.this.id
  secret_data_wo         = var.secret_data
  secret_data_wo_version = var.secret_version
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.accessor_members

  project   = var.project_id
  secret_id = google_secret_manager_secret.this.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}
