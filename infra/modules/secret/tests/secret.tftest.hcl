mock_provider "google" {}

variables {
  project_id       = "example-sandbox-0000"
  secret_id        = "db-password"
  secret_data      = "placeholder" # checkov:skip=CKV_SECRET_6:placeholder in a test fixture
  accessor_members = { api = "serviceAccount:api-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "the_value_is_written_as_a_write_only_argument" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret_version.this) == 1
    error_message = "The first version must be written through secret_data_wo."
  }
}

run "access_is_granted_on_the_secret_to_the_listed_members_only" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 1 && alltrue([for b in google_secret_manager_secret_iam_member.accessor : b.role == "roles/secretmanager.secretAccessor"])
    error_message = "One secretAccessor binding on the secret is expected."
  }
}

run "no_version_when_the_caller_adds_one_by_hand" {
  command = plan

  variables {
    create_version = false
  }

  assert {
    condition     = length(google_secret_manager_secret_version.this) == 0
    error_message = "create_version = false must create no version."
  }
}
