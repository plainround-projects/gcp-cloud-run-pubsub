variable "project_id" {
  description = "Project that owns the repository."
  type        = string
}

variable "location" {
  description = "Region of the repository."
  type        = string
}

variable "repository_id" {
  description = "Repository name."
  type        = string
}

variable "keep_count" {
  description = "Number of most recent image versions the cleanup policy always keeps."
  type        = number
  default     = 5
}

variable "labels" {
  description = "Labels for the repository."
  type        = map(string)
  default     = {}
}
