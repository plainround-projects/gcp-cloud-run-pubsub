mock_provider "google" {}

variables {
  project_id     = "example-sandbox-0000"
  project_number = "000000000000"
  services       = ["run.googleapis.com", "pubsub.googleapis.com"]
}

run "no_billing_account_means_no_budget_and_no_policy_by_default" {
  command = plan

  assert {
    condition     = length(google_billing_budget.this) == 0 && length(google_org_policy_policy.no_service_account_keys) == 0
    error_message = "Defaults must create neither a budget nor an organization policy."
  }
}

run "a_billing_account_creates_one_budget_with_a_threshold_per_alert" {
  command = plan

  variables {
    billing_account = "AAAAAA-BBBBBB-CCCCCC"
  }

  assert {
    condition     = length(google_billing_budget.this) == 1 && length(google_billing_budget.this[0].threshold_rules) == 3
    error_message = "One budget with three thresholds is expected."
  }
}

run "the_key_policy_is_enforced_when_asked" {
  command = plan

  variables {
    enforce_no_service_account_keys = true
  }

  assert {
    condition     = google_org_policy_policy.no_service_account_keys[0].name == "projects/example-sandbox-0000/policies/iam.disableServiceAccountKeyCreation"
    error_message = "The policy must target iam.disableServiceAccountKeyCreation on the project."
  }
}

run "a_non_numeric_project_number_is_rejected" {
  command = plan

  variables {
    project_number = "abc"
  }

  expect_failures = [var.project_number]
}
