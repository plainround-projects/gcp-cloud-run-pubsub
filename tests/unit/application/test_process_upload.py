import pytest

from tests.unit.application.fakes import InMemoryStore
from uploads.application.ports import StoreFailed
from uploads.application.process_upload import Outcome, ProcessUpload
from uploads.domain.errors import MalformedUploadMessage

MESSAGE = b'{"name":"report-1"}'


def test_a_message_creates_its_result_file():
    store = InMemoryStore()
    assert ProcessUpload(store).execute(MESSAGE) is Outcome.CREATED
    assert store.objects == {"results/report-1.txt": "processed report-1\n"}


def test_a_duplicate_delivery_is_a_success_that_changes_nothing():
    store = InMemoryStore()
    use_case = ProcessUpload(store)
    use_case.execute(MESSAGE)
    assert use_case.execute(MESSAGE) is Outcome.ALREADY_PROCESSED
    assert len(store.objects) == 1


def test_a_malformed_message_writes_nothing():
    store = InMemoryStore()
    with pytest.raises(MalformedUploadMessage):
        ProcessUpload(store).execute(b"nope")
    assert store.write_attempts == 0


def test_a_store_failure_is_not_swallowed():
    with pytest.raises(StoreFailed):
        ProcessUpload(InMemoryStore(fail_with="Forbidden")).execute(MESSAGE)
