"""Use case of the worker: write the result file for one queued upload request."""

from __future__ import annotations

from enum import Enum

from uploads.application.ports import ResultStore
from uploads.domain.upload import UploadRequested, UploadResult


class Outcome(Enum):
    """What processing one message did."""

    CREATED = "created"
    ALREADY_PROCESSED = "already_processed"


class ProcessUpload:
    """Decode a message and store its result once.

    Pub/Sub delivers at least once, so a repeat of a processed message is a success that changes nothing.
    The worker's role may create objects but not delete them, which is also why it cannot overwrite one.
    """

    def __init__(self, store: ResultStore) -> None:
        """Create the use case around a store port."""
        self._store = store

    def execute(self, data: bytes) -> Outcome:
        """Raise `MalformedUploadMessage` for a bad message and `StoreFailed` when the write fails."""
        result = UploadResult.for_request(UploadRequested.decode(data))
        created = self._store.create_if_absent(result.key, result.body)
        return Outcome.CREATED if created else Outcome.ALREADY_PROCESSED
