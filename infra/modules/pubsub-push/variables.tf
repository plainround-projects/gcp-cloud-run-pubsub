variable "project_id" {
  description = "Project that owns the topics and subscriptions."
  type        = string
}

variable "project_number" {
  description = "Project number; the Pub/Sub service agent's email contains it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must contain digits only."
  }
}

variable "topic_name" {
  description = "Name of the main topic; the dead-letter topic and the subscriptions derive their names from it."
  type        = string
}

variable "push_endpoint" {
  description = "HTTPS URL that receives each message."
  type        = string

  validation {
    condition     = startswith(var.push_endpoint, "https://")
    error_message = "push_endpoint must be an https URL."
  }
}

variable "oidc_audience" {
  description = "Audience claim of the OIDC token; for Cloud Run, the service URL."
  type        = string
}

variable "invoker_service_account_email" {
  description = "Account whose OIDC token Pub/Sub sends. Give it roles/run.invoker on the receiving service only."
  type        = string
}

variable "publisher_members" {
  description = "IAM members that may publish to the main topic (granted on the topic, not the project), keyed by a fixed label."
  type        = map(string)
  default     = {}
}

variable "max_delivery_attempts" {
  description = "Attempts before a message goes to the dead-letter topic (5 to 100)."
  type        = number
  default     = 5

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100."
  }
}

variable "ack_deadline_seconds" {
  description = "Seconds the worker has to answer before Pub/Sub redelivers."
  type        = number
  default     = 30
}

variable "minimum_backoff" {
  description = "Shortest wait before a retry."
  type        = string
  default     = "10s"
}

variable "maximum_backoff" {
  description = "Longest wait before a retry."
  type        = string
  default     = "120s"
}

variable "labels" {
  description = "Labels for topics and subscriptions."
  type        = map(string)
  default     = {}
}
