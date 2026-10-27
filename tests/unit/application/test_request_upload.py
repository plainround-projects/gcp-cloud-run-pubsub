import pytest

from tests.unit.application.fakes import InMemoryPublisher
from uploads.application.ports import PublishFailed
from uploads.application.request_upload import RequestUpload
from uploads.domain.errors import InvalidUploadName


def test_a_valid_request_publishes_one_message_and_returns_its_id():
    publisher = InMemoryPublisher()
    receipt = RequestUpload(publisher).execute({"name": "report-1"})
    assert receipt.message_id == "1"
    assert publisher.published == [b'{"name":"report-1"}']


def test_an_invalid_name_publishes_nothing():
    publisher = InMemoryPublisher()
    with pytest.raises(InvalidUploadName):
        RequestUpload(publisher).execute({"name": "../x"})
    assert publisher.published == []


def test_a_broker_failure_propagates_as_the_named_port_error():
    with pytest.raises(PublishFailed, match="PermissionDenied"):
        RequestUpload(InMemoryPublisher(fail_with="PermissionDenied: no publisher role")).execute({"name": "a"})
