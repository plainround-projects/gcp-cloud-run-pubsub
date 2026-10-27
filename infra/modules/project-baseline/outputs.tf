output "enabled_services" {
  description = "APIs enabled by this module."
  value       = sort([for s in google_project_service.enabled : s.service])
}

output "budget_name" {
  description = "Resource name of the budget, or null when no billing account was given."
  value       = one(google_billing_budget.this[*].name)
}

output "key_creation_blocked" {
  description = "Whether the organization policy that blocks service account keys is enforced by this module."
  value       = var.enforce_no_service_account_keys
}
