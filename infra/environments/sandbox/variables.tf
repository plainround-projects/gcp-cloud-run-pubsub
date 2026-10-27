variable "project_id" {
  description = "Id of the sandbox project (created by scripts/create-project.sh)."
  type        = string
}

variable "project_number" {
  description = "Number of the sandbox project."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and the bucket."
  type        = string
  default     = "europe-west1"
}

variable "billing_account" {
  description = "Billing account id for the budget alert. Empty skips the budget."
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget in whole units of the billing account's currency."
  type        = number
  default     = 10
}

variable "enforce_no_service_account_keys" {
  description = "Enforce the organization policy that blocks key creation. Needs an organization."
  type        = bool
  default     = false
}

variable "api_image" {
  description = "Image of the API. The placeholder lets the first apply succeed before your image exists."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "worker_image" {
  description = "Image of the worker. The placeholder lets the first apply succeed before your image exists."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_public" {
  description = "Let anyone call the API (the exercise does). The worker is never public."
  type        = bool
  default     = true
}

variable "db_password" {
  description = "Throwaway value for the db-password secret. Ephemeral: it is written to Secret Manager and not kept in the state."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "labels" {
  description = "Labels applied to every resource that supports them."
  type        = map(string)
  default = {
    environment = "sandbox"
    project     = "gcp-cloud-run-pubsub"
    managed-by  = "terraform"
  }
}
