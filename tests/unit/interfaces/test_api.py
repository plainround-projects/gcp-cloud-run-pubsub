import logging

import pytest

from tests.unit.application.fakes import InMemoryPublisher
from uploads.application.request_upload import RequestUpload
from uploads.interfaces.api import create_app


@pytest.fixture
def publisher():
    return InMemoryPublisher()


def client_for(publisher, db_password_set=True):
    return create_app(RequestUpload(publisher), db_password_set).test_client()


def test_post_upload_publishes_and_answers_202_with_the_message_id(publisher):
    response = client_for(publisher).post("/upload", json={"name": "report-1"})
    assert response.status_code == 202
    assert response.get_json() == {"published": "1"}
    assert publisher.published == [b'{"name":"report-1"}']


@pytest.mark.parametrize("payload", [{"name": "../x"}, {}, {"name": 5}])
def test_an_invalid_name_is_a_400_and_publishes_nothing(publisher, payload):
    response = client_for(publisher).post("/upload", json=payload)
    assert response.status_code == 400
    assert "error" in response.get_json()
    assert publisher.published == []


@pytest.mark.parametrize(
    "kwargs", [{"data": "not json"}, {"json": ["a"]}, {"data": "", "content_type": "application/json"}]
)
def test_a_body_that_is_not_a_json_object_is_a_400(publisher, kwargs):
    assert client_for(publisher).post("/upload", **kwargs).status_code == 400


def test_a_publish_failure_is_a_503_and_is_logged_with_the_cause(caplog):
    broken = InMemoryPublisher(fail_with="PermissionDenied: api-sa lacks pubsub.topics.publish")
    with caplog.at_level(logging.ERROR, logger="uploads.api"):
        response = client_for(broken).post("/upload", json={"name": "a"})
    assert response.status_code == 503
    assert "api-sa lacks pubsub.topics.publish" in caplog.records[0].error
    assert "PermissionDenied" not in response.get_data(as_text=True)


@pytest.mark.parametrize("password_set", [True, False])
def test_health_says_whether_the_secret_is_set_and_never_its_value(publisher, password_set):
    response = client_for(publisher, password_set).get("/health")
    assert response.get_json() == {"db_password_set": password_set}


def test_an_oversized_body_is_refused(publisher):
    response = client_for(publisher).post("/upload", data=b"x" * 70_000, content_type="application/json")
    assert response.status_code == 413


def test_a_successful_upload_logs_at_info_without_breaking_the_response(publisher, caplog):
    # Regression: logging extra={"name": ...} collides with LogRecord.name and raised KeyError only when INFO was enabled.
    with caplog.at_level(logging.INFO, logger="uploads.api"):
        response = client_for(publisher).post("/upload", json={"name": "report-1"})
    assert response.status_code == 202
    assert caplog.records[0].upload_name == "report-1"
    assert caplog.records[0].message_id == "1"
