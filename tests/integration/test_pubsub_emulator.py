"""The Pub/Sub adapter against the real emulator."""

import pytest
from google.cloud import pubsub_v1

from uploads.application.ports import PublishFailed
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings

pytestmark = pytest.mark.integration


def test_a_published_message_arrives_on_a_subscription_of_the_topic(emulators, unique):
    publisher_client = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    topic = publisher_client.topic_path("local-project", f"it-{unique}")
    subscription = subscriber.subscription_path("local-project", f"it-{unique}-pull")
    publisher_client.create_topic(request={"name": topic})
    subscriber.create_subscription(request={"name": subscription, "topic": topic})

    publisher = build_publisher(
        ApiSettings.from_env(
            {"PROJECT_ID": "local-project", "TOPIC_ID": f"it-{unique}", "PUBLISH_TIMEOUT_SECONDS": "10"}
        )
    )
    try:
        message_id = publisher.publish(b'{"name":"report-1"}')
    finally:
        publisher.close()

    pulled = subscriber.pull(request={"subscription": subscription, "max_messages": 1}, timeout=15)
    assert [m.message.data for m in pulled.received_messages] == [b'{"name":"report-1"}']
    assert pulled.received_messages[0].message.message_id == message_id


def test_publishing_to_a_missing_topic_is_a_publish_failed_with_the_service_error(emulators, unique):
    publisher = build_publisher(
        ApiSettings.from_env(
            {"PROJECT_ID": "local-project", "TOPIC_ID": f"missing-{unique}", "PUBLISH_TIMEOUT_SECONDS": "5"}
        )
    )
    try:
        with pytest.raises(PublishFailed, match="NotFound"):
            publisher.publish(b"x")
    finally:
        publisher.close()
