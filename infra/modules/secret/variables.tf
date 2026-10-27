variable "project_id" {
  description = "Project that owns the secret."
  type        = string
}

variable "secret_id" {
  description = "Secret name."
  type        = string
}

variable "labels" {
  description = "Labels for the secret."
  type        = map(string)
  default     = {}
}

variable "accessor_members" {
  description = "IAM members that may read this one secret (roles/secretmanager.secretAccessor, on the secret, not the project), keyed by a fixed label."
  type        = map(string)
  default     = {}
}

variable "create_version" {
  description = "Write a first version from secret_data. Set false to add versions outside Terraform."
  type        = bool
  default     = true
}

variable "secret_data" {
  description = "The secret value. Ephemeral and sensitive: it never reaches the state file."
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
}

variable "secret_version" {
  description = "Counter that tells Terraform to write secret_data again."
  type        = number
  default     = 1
}
