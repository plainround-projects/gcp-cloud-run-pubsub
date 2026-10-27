resource "google_storage_bucket" "this" {
  #checkov:skip=CKV_GCP_62:A one-day sandbox needs no separate access-log bucket; Cloud Audit Logs record administrative activity. Add a log bucket before real use
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

# objectCreator creates objects but cannot read, overwrite or delete them. The bucket is the only place it is granted.
resource "google_storage_bucket_iam_member" "creator" {
  for_each = var.creator_members

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectCreator"
  member = each.value
}
