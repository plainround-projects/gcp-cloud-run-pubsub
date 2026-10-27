"""The Cloud Storage adapter against a fake Cloud Storage server."""

import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage

from uploads.application.ports import StoreFailed
from uploads.infrastructure.gcs_result_store import build_store
from uploads.infrastructure.settings import WorkerSettings

pytestmark = pytest.mark.integration


def _bucket(unique):
    client = storage.Client(project="local-project", credentials=AnonymousCredentials())
    return client.create_bucket(f"it-{unique}")


def test_an_object_is_created_once_and_never_overwritten(emulators, unique):
    bucket = _bucket(unique)
    store = build_store(WorkerSettings.from_env({"BUCKET": bucket.name}))

    assert store.create_if_absent("results/a.txt", "processed a\n") is True
    assert store.create_if_absent("results/a.txt", "something else\n") is False
    assert bucket.blob("results/a.txt").download_as_text() == "processed a\n"


def test_writing_to_a_missing_bucket_is_a_store_failed_with_the_service_error(emulators, unique):
    store = build_store(WorkerSettings.from_env({"BUCKET": f"missing-{unique}", "STORE_TIMEOUT_SECONDS": "5"}))
    with pytest.raises(StoreFailed, match="NotFound"):
        store.create_if_absent("results/a.txt", "x")
