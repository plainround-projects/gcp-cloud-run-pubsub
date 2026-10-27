# No google_service_account_key anywhere in this repository: workloads use the credentials the platform gives them.
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}
