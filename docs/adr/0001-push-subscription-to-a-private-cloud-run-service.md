# 1. Push subscription to a private Cloud Run service

Status: accepted, 2026-10-27

## Context

The worker must process each upload message. Two delivery models exist: the worker pulls from the subscription, or Pub/Sub pushes each message to an HTTPS endpoint. The lesson asks for a Cloud Run worker, a dedicated invoker account and a 403 for callers without a token.

## Decision

Use a push subscription to a Cloud Run service that allows no unauthenticated calls. The subscription carries an OIDC token for `pubsub-invoker`, which holds `roles/run.invoker` on the worker only. The audience is the service URL.

## Consequences

- Cloud Run scales to zero and wakes on delivery; no process polls.
- Authentication is done by the platform before the container sees the request, so the worker has no token-checking code to get wrong.
- Retries, backoff and dead-lettering belong to the subscription (`max_delivery_attempts = 5`, backoff 10 s to 120 s).
- A job longer than the acknowledgement deadline (30 s here) needs a different model: a pull worker or Cloud Tasks.
- The Pub/Sub service agent needs three grants (publisher on the dead-letter topic, subscriber on the subscription, token creator on the invoker); `modules/pubsub-push` makes them.
