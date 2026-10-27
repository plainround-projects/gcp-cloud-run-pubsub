terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
  }

  # Local state is enough for a one-day sandbox. For shared use, add a gcs backend (see backend.tf.example).
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Budgets and organization policies are charged to a quota project; use the sandbox project itself.
  user_project_override = true
  billing_project       = var.project_id
}
