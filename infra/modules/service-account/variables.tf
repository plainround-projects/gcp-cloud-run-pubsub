variable "project_id" {
  description = "Project that owns the service account."
  type        = string
}

variable "account_id" {
  description = "Account id, the part before the @ (6-30 characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "account_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "display_name" {
  description = "Human-readable name."
  type        = string
}

variable "description" {
  description = "What this identity is for and what it may touch."
  type        = string
}
