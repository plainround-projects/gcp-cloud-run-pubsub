variable "project_id" {
  description = "Id of the existing project to prepare."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "project_number" {
  description = "Number of the project (gcloud projects describe PROJECT_ID --format='value(projectNumber)'); the budget filters on it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must contain digits only."
  }
}

variable "services" {
  description = "APIs to enable."
  type        = list(string)
}

variable "billing_account" {
  description = "Billing account id for the budget (gcloud billing accounts list). Empty skips the budget."
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget in whole units of budget_currency."
  type        = number
  default     = 10

  validation {
    condition     = var.budget_amount > 0 && floor(var.budget_amount) == var.budget_amount
    error_message = "budget_amount must be a positive whole number."
  }
}

variable "budget_currency" {
  description = "ISO 4217 currency code of the billing account."
  type        = string
  default     = "USD"
}

variable "budget_thresholds" {
  description = "Fractions of the budget that send an alert (0.5 is 50 percent)."
  type        = list(number)
  default     = [0.5, 0.9, 1.0]

  validation {
    condition     = alltrue([for t in var.budget_thresholds : t > 0 && t <= 1.5])
    error_message = "Each threshold must be above 0 and at most 1.5."
  }
}

variable "enforce_no_service_account_keys" {
  description = "Enforce iam.disableServiceAccountKeyCreation on the project. Requires an organization; without one, leave false and follow the rule by hand."
  type        = bool
  default     = false
}
