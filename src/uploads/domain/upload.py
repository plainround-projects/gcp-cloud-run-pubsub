"""The upload request and the result it produces: immutable values with no knowledge of Pub/Sub or Cloud Storage."""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from uploads.domain.errors import InvalidUploadName, MalformedUploadMessage

_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
_RESULT_PREFIX = "results/"


@dataclass(frozen=True, slots=True)
class UploadName:
    """A client-chosen name, restricted to characters that cannot climb out of the `results/` prefix."""

    value: str

    def __post_init__(self) -> None:
        """Reject anything that is not a short, path-free name."""
        if not isinstance(self.value, str) or _NAME_PATTERN.fullmatch(self.value) is None:
            raise InvalidUploadName(
                "name must be 1-128 characters: letters, digits, dot, underscore or hyphen, "
                "starting with a letter or digit"
            )
        if ".." in self.value:
            raise InvalidUploadName("name must not contain '..'")

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True, slots=True)
class UploadRequested:
    """The fact that a client asked for `name` to be processed; this is the body of the queued message."""

    name: UploadName

    @classmethod
    def from_request_body(cls, body: Mapping[str, Any]) -> UploadRequested:
        """Build the event from the API's JSON body, raising `InvalidUploadName` when `name` is unusable."""
        return cls(UploadName(body.get("name", "")))

    def encode(self) -> bytes:
        """Serialize to the message data that is published."""
        return json.dumps({"name": self.name.value}, separators=(",", ":")).encode("utf-8")

    @classmethod
    def decode(cls, data: bytes) -> UploadRequested:
        """Parse message data, raising `MalformedUploadMessage` for anything that is not an upload request."""
        try:
            payload = json.loads(data)
        except (UnicodeDecodeError, ValueError) as error:
            raise MalformedUploadMessage("message data is not JSON") from error
        if not isinstance(payload, dict) or "name" not in payload:
            raise MalformedUploadMessage("message data has no 'name'")
        try:
            return cls(UploadName(payload["name"]))
        except InvalidUploadName as error:
            raise MalformedUploadMessage(str(error)) from error


@dataclass(frozen=True, slots=True)
class UploadResult:
    """The file the worker writes for one processed upload."""

    key: str
    body: str

    @classmethod
    def for_request(cls, event: UploadRequested) -> UploadResult:
        """The result of processing `event`: `results/<name>.txt` holding `processed <name>`."""
        return cls(key=f"{_RESULT_PREFIX}{event.name}.txt", body=f"processed {event.name}\n")
