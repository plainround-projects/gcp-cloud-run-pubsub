"""Pub/Sub adapter for the `MessagePublisher` port."""

from __future__ import annotations

from typing import Protocol

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from google.cloud import pubsub_v1

from uploads.application.ports import PublishFailed
from uploads.infrastructure.settings import ApiSettings


class _Future(Protocol):
    def result(self, timeout: float | None = None) -> str: ...


class _Client(Protocol):
    def publish(self, topic: str, data: bytes) -> _Future: ...

    def stop(self) -> None: ...


class PubSubPublisher:
    """Publish to one topic and wait for the broker's acknowledgement within a deadline."""

    def __init__(self, client: _Client, topic_path: str, timeout_seconds: float) -> None:
        """`client` is a `pubsub_v1.PublisherClient` (or anything shaped like one)."""
        self._client = client
        self._topic_path = topic_path
        self._timeout = timeout_seconds

    def publish(self, data: bytes) -> str:
        """Return the message id, or raise `PublishFailed` with the broker's own error text."""
        try:
            return self._client.publish(self._topic_path, data).result(timeout=self._timeout)
        except (GoogleAPIError, GoogleAuthError, TimeoutError) as error:
            raise PublishFailed(f"{type(error).__name__}: {error}") from error

    def close(self) -> None:
        """Flush and stop the client's background threads; call on shutdown."""
        self._client.stop()


def build_publisher(settings: ApiSettings) -> PubSubPublisher:
    """The real adapter. Credentials come from the runtime's service account (or the emulator host variable)."""
    client = pubsub_v1.PublisherClient()
    return PubSubPublisher(
        client,
        client.topic_path(settings.project_id, settings.topic_id),
        settings.publish_timeout_seconds,
    )
