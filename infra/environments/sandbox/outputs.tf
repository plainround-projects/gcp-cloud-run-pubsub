output "api_url" {
  description = "URL of the API."
  value       = module.api.uri
}

output "worker_url" {
  description = "URL of the worker; a call without a token returns 403."
  value       = module.worker.uri
}

output "results_bucket" {
  description = "Bucket that receives results/NAME.txt."
  value       = module.results.name
}

output "image_prefix" {
  description = "Where scripts/build-images.sh pushes the two images."
  value       = module.registry.image_prefix
}

output "service_accounts" {
  description = "The three identities."
  value = {
    api     = module.api_sa.email
    worker  = module.worker_sa.email
    invoker = module.invoker_sa.email
  }
}

output "topic" {
  description = "Main topic and its dead-letter companions."
  value = {
    topic             = module.pipeline.topic_name
    dead_letter_topic = module.pipeline.dead_letter_topic_name
    push_subscription = module.pipeline.push_subscription_name
    dead_letter_pull  = module.pipeline.dead_letter_subscription_name
  }
}
