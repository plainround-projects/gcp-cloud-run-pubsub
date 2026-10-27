mock_provider "google" {}

variables {
  project_id      = "example-sandbox-0000"
  name            = "example-sandbox-0000-results"
  location        = "europe-west1"
  creator_members = { worker = "serviceAccount:worker-sa@example-sandbox-0000.iam.gserviceaccount.com" }
}

run "bucket_is_private_and_uniform" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access && google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "The bucket must use uniform access and block public access."
  }
}

run "only_the_creator_role_is_granted_and_only_to_the_given_members" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_member.creator) == 1 && alltrue([for b in google_storage_bucket_iam_member.creator : b.role == "roles/storage.objectCreator"])
    error_message = "Exactly one binding with roles/storage.objectCreator is expected."
  }
}

run "no_members_means_no_bindings" {
  command = plan

  variables {
    creator_members = {}
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.creator) == 0
    error_message = "An empty member list must create no bindings."
  }
}

run "a_bad_bucket_name_is_rejected" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}
