output "email" {
  description = "Service account email."
  value       = google_service_account.this.email
}

output "member" {
  description = "IAM member string, serviceAccount:EMAIL."
  value       = "serviceAccount:${google_service_account.this.email}"
}

output "name" {
  description = "Full resource name, projects/PROJECT/serviceAccounts/EMAIL."
  value       = google_service_account.this.name
}
