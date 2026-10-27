output "topic_name" {
  description = "Name of the main topic."
  value       = google_pubsub_topic.main.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead-letter topic."
  value       = google_pubsub_topic.dead_letter.name
}

output "push_subscription_name" {
  description = "Name of the push subscription."
  value       = google_pubsub_subscription.push.name
}

output "dead_letter_subscription_name" {
  description = "Name of the pull subscription on the dead-letter topic."
  value       = google_pubsub_subscription.dead_letter_pull.name
}

output "publisher_members" {
  description = "Members granted the publisher role on the main topic."
  value       = sort(values(var.publisher_members))
}
