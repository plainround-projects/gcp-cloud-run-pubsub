variable "project_id" {
  description = "Project that owns the bucket."
  type        = string
}

variable "name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters: lowercase letters, digits, dot, underscore and hyphen."
  }
}

variable "location" {
  description = "Bucket location, for example europe-west1."
  type        = string
}

variable "labels" {
  description = "Labels for the bucket."
  type        = map(string)
  default     = {}
}

variable "creator_members" {
  description = "IAM members that may create objects in this bucket and nothing else, keyed by a fixed label (the keys must be known at plan time, the members need not be)."
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Days after which result files are deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "force_destroy" {
  description = "Delete the bucket even when it holds objects. True only for a sandbox."
  type        = bool
  default     = false
}
