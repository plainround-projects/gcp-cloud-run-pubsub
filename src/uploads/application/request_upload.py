"""Use case of the API: turn an upload request into a published message."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from uploads.application.ports import MessagePublisher
from uploads.domain.upload import UploadRequested


@dataclass(frozen=True, slots=True)
class Receipt:
    """Proof that the broker accepted the message."""

    message_id: str


class RequestUpload:
    """Validate the request, publish it, return the broker's message id."""

    def __init__(self, publisher: MessagePublisher) -> None:
        """Create the use case around a publisher port."""
        self._publisher = publisher

    def execute(self, body: Mapping[str, Any]) -> Receipt:
        """Raise `InvalidUploadName` for a bad request and `PublishFailed` when the broker refuses."""
        event = UploadRequested.from_request_body(body)
        return Receipt(message_id=self._publisher.publish(event.encode()))
