variable "project_id" {
  description = "Project that owns the service."
  type        = string
}

variable "name" {
  description = "Service name."
  type        = string
}

variable "location" {
  description = "Region."
  type        = string
}

variable "image" {
  description = "Container image to run."
  type        = string
}

variable "service_account_email" {
  description = "Identity the service runs as. Required: the default compute account is never used."
  type        = string
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Environment variables filled from Secret Manager: name => { secret, version }."
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}

variable "invoker_members" {
  description = "Members that may call the service, keyed by a fixed label. Empty keeps it private to IAM; allUsers makes it public."
  type        = map(string)
  default     = {}
}

variable "ingress" {
  description = "Ingress setting of the service."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.ingress)
    error_message = "ingress must be INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU limit per instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance."
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Instances kept warm. Zero scales to zero and costs nothing idle."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Upper bound on instances, which also bounds the bill."
  type        = number
  default     = 3
}

variable "concurrency" {
  description = "Requests one instance handles at once."
  type        = number
  default     = 20
}

variable "request_timeout_seconds" {
  description = "Request timeout."
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Refuse to delete the service. False in a sandbox so the teardown works."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels for the service."
  type        = map(string)
  default     = {}
}
