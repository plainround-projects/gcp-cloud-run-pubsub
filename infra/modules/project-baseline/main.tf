resource "google_project_service" "enabled" {
  for_each = toset(var.services)

  project = var.project_id
  service = each.value

  # Leaving an API enabled on destroy avoids breaking other things in a shared project.
  disable_on_destroy = false
}

resource "google_billing_budget" "this" {
  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account
  display_name    = "${var.project_id}-budget"

  budget_filter {
    projects = ["projects/${var.project_number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_thresholds
    content {
      threshold_percent = threshold_rules.value
    }
  }

  depends_on = [google_project_service.enabled]
}

# Blocks the creation of downloadable service account keys. Needs the project to sit under an organization.
resource "google_org_policy_policy" "no_service_account_keys" {
  count = var.enforce_no_service_account_keys ? 1 : 0

  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.enabled]
}
