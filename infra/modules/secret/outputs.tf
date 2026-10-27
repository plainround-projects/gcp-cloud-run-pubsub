output "secret_id" {
  description = "Secret name, as Cloud Run refers to it."
  value       = google_secret_manager_secret.this.secret_id
}

output "id" {
  description = "Full resource id, projects/PROJECT/secrets/NAME."
  value       = google_secret_manager_secret.this.id
}

output "accessor_members" {
  description = "Members granted access to this secret."
  value       = sort(values(var.accessor_members))
}
