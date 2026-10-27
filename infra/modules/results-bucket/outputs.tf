output "name" {
  description = "Bucket name."
  value       = google_storage_bucket.this.name
}

output "url" {
  description = "gs:// URL of the bucket."
  value       = google_storage_bucket.this.url
}

output "creator_members" {
  description = "Members that may create objects."
  value       = sort(values(var.creator_members))
}
