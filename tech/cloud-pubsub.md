# Cloud Pub/Sub

## 1. What it is

Pub/Sub is Google Cloud's **message queue service**. One program (the **publisher**) sends a small message to a named **topic**. Other programs receive copies through **subscriptions** attached to that topic. The sender does not wait for the receiver and does not know it exists. A queue like this lets a slow or broken receiver fall behind without breaking the sender.

## 2. Why this repository uses it

The lesson splits one job in two: the API accepts a request and publishes a message; the worker receives the message and writes a result file. Pub/Sub sits between them, retries failed deliveries, and sets aside messages that keep failing in a **dead-letter topic**.

## 3. Where it appears

| Path | What it does with Pub/Sub |
| --- | --- |
| `infra/modules/pubsub-push/main.tf` | Creates the `uploads` topic, the `uploads-dead` topic, the push subscription, the dead-letter pull subscription, and the permissions the Pub/Sub service needs. |
| `src/uploads/infrastructure/pubsub_publisher.py` | Publishes with the Python client (`google-cloud-pubsub.md`). |
| `src/uploads/interfaces/push_envelope.py` | Reads the JSON that a push delivery contains. |
| `src/uploads/interfaces/worker.py` | Answers with the status codes that decide retry or acknowledgement. |
| `scripts/read-denial.sh`, `restore-and-replay.sh` | Pull a dead-lettered message and publish it again. |
| `docker-compose.yml`, `scripts/init_emulator.py`, `tests/` | The local Pub/Sub **emulator** (a fake service on your machine). |

## 4. How it works underneath

- **Topic**: a named place where messages are published. **Subscription**: a named delivery stream from one topic. Each subscription gets its own copy of every message.
- **Pull** subscriptions wait for a program to ask for messages. **Push** subscriptions make Pub/Sub send each message to a web address with an HTTP `POST`. This repository uses push for the worker and pull for reading dead letters.
- **Acknowledgement (ack)**: the receiver's "I handled it". For push, any `2xx` HTTP status is an ack. Anything else, or no answer inside the **ack deadline** (30 seconds here), means "try again". Unacknowledged messages are redelivered, so delivery is **at least once**: the same message can arrive twice. Receivers must tolerate duplicates (the worker writes with "create only if absent").
- **Retry policy**: Pub/Sub waits longer between attempts (exponential backoff): between a minimum (10 s) and a maximum (120 s) here.
- **Dead-letter policy**: after `max_delivery_attempts` (5 here; the allowed range is 5 to 100) failed deliveries, the message is published to the dead-letter topic. To do that, the Pub/Sub **service agent** (a Google-run identity named `service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com`) needs *publisher* on the dead-letter topic and *subscriber* on the subscription. Without those two grants, retries continue and nothing is dead-lettered.
- **Authenticated push**: the subscription names a service account (`pubsub-invoker`). Pub/Sub creates a signed **OIDC token** (a short-lived proof of identity, a JWT) for it and sends it in the `Authorization` header. Cloud Run checks it before your code runs. For Pub/Sub to sign the token, the service agent may need `roles/iam.serviceAccountTokenCreator` on that account; the module grants it.
- The push body looks like `{"message": {"data": "<base64>", "messageId": "..."}, "subscription": "projects/.../subscriptions/..."}`. The message bytes are **base64**-encoded (a way to write bytes as plain text).

## 5. Walkthrough of this repository's use

`infra/modules/pubsub-push/main.tf`

```hcl
resource "google_pubsub_subscription" "push" {
  project = var.project_id
  name    = "${var.topic_name}-push"
  topic   = google_pubsub_topic.main.id
  labels  = var.labels

  ack_deadline_seconds = var.ack_deadline_seconds

  push_config {
    push_endpoint = var.push_endpoint

    # Pub/Sub signs a token for the invoker account; Cloud Run checks it. The invoker holds run.invoker on the worker only.
    oidc_token {
      service_account_email = var.invoker_service_account_email
      audience              = var.oidc_audience
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = var.minimum_backoff
    maximum_backoff = var.maximum_backoff
  }

  expiration_policy {
    ttl = ""
  }
}
```

- `topic = google_pubsub_topic.main.id`: attach to the main topic.
- `ack_deadline_seconds = var.ack_deadline_seconds`: 30 seconds to answer.
- `push_config { push_endpoint = ... }`: where to POST. In the sandbox it is the worker's Cloud Run URL plus `/`.
- `oidc_token { service_account_email, audience }`: sign a token for the invoker account; `audience` is who the token is for. Cloud Run accepts it when the audience is the service URL.
- `dead_letter_policy`: send to `uploads-dead` after 5 attempts.
- `retry_policy`: 10 s minimum and 120 s maximum backoff.
- `expiration_policy { ttl = "" }`: an empty value means the subscription never expires (the default would delete an unused subscription after 31 days).

The three grants for the service agent:

`infra/modules/pubsub-push/main.tf`

```hcl
resource "google_pubsub_topic_iam_member" "agent_publishes_dead_letters" {
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter.name
  role    = "roles/pubsub.publisher"
  member  = local.service_agent
}

resource "google_pubsub_subscription_iam_member" "agent_acknowledges" {
  project      = var.project_id
  subscription = google_pubsub_subscription.push.name
  role         = "roles/pubsub.subscriber"
  member       = local.service_agent
}

# Needed for projects whose Pub/Sub API was enabled after April 2021: the agent mints the invoker's OIDC token.
resource "google_service_account_iam_member" "agent_signs_invoker_token" {
```

The worker's answers:

`src/uploads/interfaces/worker.py`

```python
        try:
            pushed = parse_push_envelope(request.get_json(silent=True))
            outcome = process_upload.execute(pushed.data)
        except (InvalidEnvelope, MalformedUploadMessage) as error:
            # A message that can never succeed still gets a 4xx so it is retried and dead-lettered, not acknowledged.
            logger.warning("rejected a malformed delivery", extra={"error": str(error)})
            return Response(str(error), status=400, mimetype="text/plain")
        except StoreFailed as error:
            # The full text names the service account, the permission and the resource when the cause is IAM.
            logger.error("could not store the result", extra={"error": str(error)})
            return Response("storage failed", status=500, mimetype="text/plain")
        logger.info("processed", extra={"message_id": pushed.message_id, "outcome": outcome.value})
        return Response(status=204)
```

`204` acknowledges. `400` (unusable message) and `500` (storage failed) are not 2xx, so Pub/Sub retries and finally dead-letters. Answering `200` after an error would delete the message by mistake.

Reading the envelope:

`src/uploads/interfaces/push_envelope.py`

```python
def parse_push_envelope(envelope: Any) -> PushedMessage:
    """Decode the envelope, raising `InvalidEnvelope` for anything that does not have the documented shape."""
    if not isinstance(envelope, dict) or not isinstance(envelope.get("message"), dict):
        raise InvalidEnvelope("body must be a Pub/Sub push envelope with a 'message' object")
    message = envelope["message"]
    encoded = message.get("data")
    if not isinstance(encoded, str):
        raise InvalidEnvelope("message has no base64 'data'")
    try:
        data = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise InvalidEnvelope("message data is not valid base64") from error
    return PushedMessage(
        message_id=str(message.get("messageId", "")),
        data=data,
        subscription=str(envelope.get("subscription", "")),
```

## 6. Try it yourself

No Google Cloud account is needed for the first two.

```bash
.venv/bin/python -m pytest tests/unit/interfaces/test_push_envelope.py tests/unit/interfaces/test_worker.py -q -p no:cacheprovider
```
Expected: `17 passed`. They show valid and invalid envelopes and which status each case gets.

```bash
echo -n '{"name":"report-1"}' | base64
```
Expected: `eyJuYW1lIjoicmVwb3J0LTEifQ==`. This is what appears in `message.data`.

```bash
make emulators && make test-integration
```
Expected (needs Docker; the emulator image is about 1 GB and can take minutes to start): `4 passed`. Stop it afterwards with `docker compose down -v`.

## 7. Mistakes people make

- **Answering 200 after a failure.** The message is lost. This repository answers 500.
- **Forgetting the service agent's grants.** Messages retry forever and never reach the dead-letter topic.
- **Assuming exactly-once delivery.** Pub/Sub is at-least-once; make handlers idempotent.
- **A public push endpoint.** Anyone could post fake messages. The worker allows only the invoker account.
- **Long processing before the ack deadline.** Pub/Sub redelivers while you are still working.

## 8. Check yourself

1. What is the difference between a topic and a subscription? *A topic receives messages; a subscription is one delivery stream from a topic.*
2. What counts as an ack for a push subscription? *Any 2xx response.*
3. Why can the worker see the same message twice? *Delivery is at least once.*
4. Which two roles does the service agent need for dead-lettering? *Publisher on the dead-letter topic, subscriber on the subscription.*
5. What does the OIDC token prove? *That the call comes from Pub/Sub acting for the invoker service account.*

## 9. Further reading

- Pub/Sub overview: <https://cloud.google.com/pubsub/docs/overview>
- Push subscriptions: <https://cloud.google.com/pubsub/docs/push>
- Dead-letter topics: <https://cloud.google.com/pubsub/docs/dead-letter-topics>
- Emulator: <https://cloud.google.com/pubsub/docs/emulator>
