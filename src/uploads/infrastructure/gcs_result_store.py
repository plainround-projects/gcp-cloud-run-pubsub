"""Cloud Storage adapter for the `ResultStore` port."""

from __future__ import annotations

import os
from typing import Any

import requests
from google.api_core.exceptions import GoogleAPIError, PreconditionFailed
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import GoogleAuthError
from google.cloud import storage
from google.cloud.storage.retry import DEFAULT_RETRY_IF_GENERATION_SPECIFIED

from uploads.application.ports import StoreFailed
from uploads.infrastructure.settings import WorkerSettings


class GcsResultStore:
    """Create objects only if absent.

    `if_generation_match=0` makes the write conditional on the object not existing. That keeps a duplicate delivery
    harmless and works with `roles/storage.objectCreator`, which can create objects but not overwrite or delete them.
    """

    def __init__(self, bucket: Any, timeout_seconds: float) -> None:
        """`bucket` is a `google.cloud.storage.Bucket` (or anything shaped like one)."""
        self._bucket = bucket
        self._timeout = timeout_seconds

    def create_if_absent(self, key: str, content: str) -> bool:
        """True when the object was created, False when it already existed; `StoreFailed` otherwise."""
        blob = self._bucket.blob(key)
        try:
            blob.upload_from_string(
                content,
                content_type="text/plain; charset=utf-8",
                if_generation_match=0,
                timeout=self._timeout,
                retry=DEFAULT_RETRY_IF_GENERATION_SPECIFIED,
            )
        except PreconditionFailed:
            return False
        except (GoogleAPIError, GoogleAuthError, requests.RequestException, TimeoutError) as error:
            raise StoreFailed(f"{type(error).__name__}: {error}") from error
        return True


def build_store(settings: WorkerSettings) -> GcsResultStore:
    """The real adapter. Credentials come from the runtime's service account, or are anonymous for the emulator."""
    if os.environ.get("STORAGE_EMULATOR_HOST"):
        client = storage.Client(project=settings.project_id or "local", credentials=AnonymousCredentials())
    else:
        client = storage.Client(project=settings.project_id)
    return GcsResultStore(client.bucket(settings.bucket), settings.store_timeout_seconds)
