"""The Pub/Sub push request body: `{"message": {"data": <base64>, "messageId": ...}, "subscription": ...}`."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from typing import Any


class InvalidEnvelope(Exception):
    """The request body is not a Pub/Sub push envelope."""


@dataclass(frozen=True, slots=True)
class PushedMessage:
    """The parts of a push delivery the worker uses."""

    message_id: str
    data: bytes
    subscription: str


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
    )
