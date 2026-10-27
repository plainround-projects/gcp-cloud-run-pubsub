output "uri" {
  description = "HTTPS URL of the service."
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  description = "Service name."
  value       = google_cloud_run_v2_service.this.name
}

output "service_account_email" {
  description = "Identity the service runs as."
  value       = var.service_account_email
}

output "invoker_members" {
  description = "Members granted roles/run.invoker on this service."
  value       = sort(values(var.invoker_members))
}
