output "image_prefix" {
  description = "Prefix for image names: LOCATION-docker.pkg.dev/PROJECT/REPOSITORY."
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}

output "repository_id" {
  description = "Repository name."
  value       = google_artifact_registry_repository.this.repository_id
}
