"""Ports: what the use cases need from a message broker and an object store, as narrow protocols."""

from __future__ import annotations

from typing import Protocol


class PublishFailed(Exception):
    """The broker did not accept the message (permission, topic missing, timeout)."""


class StoreFailed(Exception):
    """The object store refused or could not complete the write (permission, bucket missing, timeout)."""


class MessagePublisher(Protocol):
    """Publishes one message and returns the broker's id for it."""

    def publish(self, data: bytes) -> str:
        """Publish `data`; raise `PublishFailed` when the broker does not confirm."""
        ...


class ResultStore(Protocol):
    """Stores result files without ever overwriting one."""

    def create_if_absent(self, key: str, content: str) -> bool:
        """Create `key` holding `content`. Return False, changing nothing, when it already exists.

        Raise `StoreFailed` for every other failure, including a missing permission.
        """
        ...
