import pytest
import requests
from google.api_core.exceptions import Forbidden, PreconditionFailed

from uploads.application.ports import StoreFailed
from uploads.infrastructure.gcs_result_store import GcsResultStore, build_store
from uploads.infrastructure.settings import WorkerSettings


class FakeBlob:
    def __init__(self, error):
        self._error = error
        self.uploads = []

    def upload_from_string(self, content, **kwargs):
        if self._error:
            raise self._error
        self.uploads.append((content, kwargs))


class FakeBucket:
    def __init__(self, error=None):
        self.blob_instance = FakeBlob(error)
        self.names = []

    def blob(self, name):
        self.names.append(name)
        return self.blob_instance


def test_the_write_is_conditional_on_the_object_not_existing():
    bucket = FakeBucket()
    assert GcsResultStore(bucket, 12).create_if_absent("results/a.txt", "processed a\n") is True
    content, kwargs = bucket.blob_instance.uploads[0]
    assert bucket.names == ["results/a.txt"]
    assert content == "processed a\n"
    assert kwargs["if_generation_match"] == 0
    assert kwargs["timeout"] == 12


def test_an_existing_object_is_reported_not_overwritten():
    assert GcsResultStore(FakeBucket(PreconditionFailed("exists")), 1).create_if_absent("k", "v") is False


@pytest.mark.parametrize(
    "error",
    [
        Forbidden("worker-sa does not have storage.objects.create access"),
        TimeoutError(),
        requests.ConnectionError("reset"),
    ],
)
def test_other_failures_become_store_failed_keeping_the_denial_text(error):
    with pytest.raises(StoreFailed) as caught:
        GcsResultStore(FakeBucket(error), 1).create_if_absent("k", "v")
    assert type(error).__name__ in str(caught.value)
    assert caught.value.__cause__ is error


def test_build_store_uses_anonymous_credentials_for_the_emulator(monkeypatch):
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", "http://localhost:1")
    store = build_store(WorkerSettings.from_env({"BUCKET": "demo-results", "STORE_TIMEOUT_SECONDS": "4"}))
    assert store._bucket.name == "demo-results"
    assert store._timeout == 4


def test_build_store_uses_application_default_credentials_in_the_cloud(monkeypatch):
    seen = {}

    class FakeClient:
        def __init__(self, **kwargs):
            seen.update(kwargs)

        def bucket(self, name):
            return name

    monkeypatch.delenv("STORAGE_EMULATOR_HOST", raising=False)
    monkeypatch.setattr("uploads.infrastructure.gcs_result_store.storage.Client", FakeClient)
    store = build_store(WorkerSettings.from_env({"BUCKET": "demo-results", "PROJECT_ID": "demo"}))
    assert seen == {"project": "demo"}
    assert store._bucket == "demo-results"
