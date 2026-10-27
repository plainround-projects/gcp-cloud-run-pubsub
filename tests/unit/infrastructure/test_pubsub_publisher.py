import pytest
from google.api_core.exceptions import PermissionDenied

from uploads.application.ports import PublishFailed
from uploads.infrastructure.pubsub_publisher import PubSubPublisher, build_publisher
from uploads.infrastructure.settings import ApiSettings


class FakeFuture:
    def __init__(self, outcome):
        self._outcome = outcome
        self.timeout = None

    def result(self, timeout=None):
        self.timeout = timeout
        if isinstance(self._outcome, Exception):
            raise self._outcome
        return self._outcome


class FakeClient:
    def __init__(self, outcome):
        self.future = FakeFuture(outcome)
        self.calls = []
        self.stopped = False

    def publish(self, topic, data):
        self.calls.append((topic, data))
        return self.future

    def stop(self):
        self.stopped = True


def test_publish_sends_to_the_topic_and_waits_within_the_deadline():
    client = FakeClient("msg-1")
    publisher = PubSubPublisher(client, "projects/p/topics/uploads", 7.5)
    assert publisher.publish(b"x") == "msg-1"
    assert client.calls == [("projects/p/topics/uploads", b"x")]
    assert client.future.timeout == 7.5


@pytest.mark.parametrize("error", [PermissionDenied("no publisher role"), TimeoutError()])
def test_broker_errors_and_timeouts_become_publish_failed_with_the_original_text(error):
    publisher = PubSubPublisher(FakeClient(error), "projects/p/topics/uploads", 1)
    with pytest.raises(PublishFailed) as caught:
        publisher.publish(b"x")
    assert type(error).__name__ in str(caught.value)
    assert caught.value.__cause__ is error


def test_close_stops_the_client():
    client = FakeClient("1")
    PubSubPublisher(client, "t", 1).close()
    assert client.stopped


def test_build_publisher_uses_the_settings_topic(monkeypatch):
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", "localhost:1")
    settings = ApiSettings.from_env({"PROJECT_ID": "demo", "TOPIC_ID": "t1", "PUBLISH_TIMEOUT_SECONDS": "3"})
    publisher = build_publisher(settings)
    try:
        assert publisher._topic_path == "projects/demo/topics/t1"
        assert publisher._timeout == 3
    finally:
        publisher.close()
