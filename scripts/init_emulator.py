"""Create the topic, dead-letter topic, push subscription and bucket in the local emulators (idempotent).

Run through `make up`. The API and worker containers reach the emulators by service name; this script runs on the host.
"""

from __future__ import annotations

import os
import time

os.environ.setdefault("PUBSUB_EMULATOR_HOST", "localhost:8085")
os.environ.setdefault("STORAGE_EMULATOR_HOST", "http://localhost:4443")

from google.api_core.exceptions import AlreadyExists, DeadlineExceeded, ServiceUnavailable
from google.auth.credentials import AnonymousCredentials
from google.cloud import pubsub_v1, storage

PROJECT = "local-project"
WORKER_URL = os.environ.get("WORKER_PUSH_URL", "http://worker:8080/")
BUCKET = "local-results"


def main() -> None:
    """Create everything the stack needs; existing resources are left alone."""
    publisher = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    topic = publisher.topic_path(PROJECT, "uploads")
    dead = publisher.topic_path(PROJECT, "uploads-dead")
    for name in (topic, dead):
        _ignore_exists(lambda name=name: publisher.create_topic(request={"name": name}))
    _ignore_exists(
        lambda: subscriber.create_subscription(
            request={
                "name": subscriber.subscription_path(PROJECT, "uploads-push"),
                "topic": topic,
                "push_config": {"push_endpoint": WORKER_URL},
                "dead_letter_policy": {"dead_letter_topic": dead, "max_delivery_attempts": 5},
            }
        )
    )
    _ignore_exists(
        lambda: subscriber.create_subscription(
            request={"name": subscriber.subscription_path(PROJECT, "uploads-dead-pull"), "topic": dead}
        )
    )
    client = storage.Client(project=PROJECT, credentials=AnonymousCredentials())
    _ignore_exists(lambda: client.create_bucket(BUCKET))
    print(f"ready: {topic}, {dead}, push to {WORKER_URL}, gs://{BUCKET}")


def _ignore_exists(action) -> None:  # type: ignore[no-untyped-def]
    """Run `action`; an existing resource is fine, and a cold emulator gets a few more tries."""
    for attempt in range(1, 6):
        try:
            action()
            return
        except AlreadyExists:
            return
        except (DeadlineExceeded, ServiceUnavailable):
            if attempt == 5:
                raise
            time.sleep(5 * attempt)
        except Exception as error:  # fake-gcs-server answers 409 with its own exception type
            if "409" in str(error) or "already" in str(error).lower():
                return
            raise


if __name__ == "__main__":
    main()
