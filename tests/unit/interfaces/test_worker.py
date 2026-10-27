import base64
import json
import logging

import pytest

from tests.unit.application.fakes import InMemoryStore
from uploads.application.process_upload import ProcessUpload
from uploads.interfaces.worker import create_app


def push(name="report-1"):
    data = base64.b64encode(json.dumps({"name": name}).encode()).decode()
    return {"message": {"data": data, "messageId": "9"}, "subscription": "projects/p/subscriptions/uploads-push"}


def client_for(store):
    return create_app(ProcessUpload(store)).test_client()


def test_a_delivery_writes_the_result_and_acknowledges_with_204():
    store = InMemoryStore()
    response = client_for(store).post("/", json=push())
    assert response.status_code == 204
    assert store.objects == {"results/report-1.txt": "processed report-1\n"}


def test_a_redelivery_is_acknowledged_too():
    store = InMemoryStore()
    client = client_for(store)
    client.post("/", json=push())
    assert client.post("/", json=push()).status_code == 204


def test_a_failing_write_answers_500_never_2xx_and_logs_the_denial(caplog):
    denial = "Forbidden: worker-sa does not have storage.objects.create access"
    with caplog.at_level(logging.ERROR, logger="uploads.worker"):
        response = client_for(InMemoryStore(fail_with=denial)).post("/", json=push())
    assert response.status_code == 500
    assert denial in caplog.records[0].error


@pytest.mark.parametrize("body", [{}, {"message": {"data": "!!"}}, push(name="../x")])
def test_a_delivery_that_can_never_succeed_gets_a_4xx_so_it_is_dead_lettered_not_acknowledged(body):
    store = InMemoryStore()
    assert client_for(store).post("/", json=body).status_code == 400
    assert store.write_attempts == 0


def test_health_is_ok():
    assert client_for(InMemoryStore()).get("/health").status_code == 200
