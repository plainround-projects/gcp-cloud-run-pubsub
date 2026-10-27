"""The lesson's scenario against the emulators, with the real adapters on both sides.

API (Flask test client) -> Pub/Sub emulator topic -> push subscription -> worker (a real HTTP server on this machine)
-> fake Cloud Storage bucket. The failing variant swaps the worker's store for one that is denied, as in step 5.
"""

from __future__ import annotations

import socket
import threading
import time
from collections.abc import Callable, Iterator

import pytest
from google.api_core.exceptions import DeadlineExceeded
from google.auth.credentials import AnonymousCredentials
from google.cloud import pubsub_v1, storage
from werkzeug.serving import make_server

from uploads.application.ports import StoreFailed
from uploads.application.process_upload import ProcessUpload
from uploads.application.request_upload import RequestUpload
from uploads.infrastructure.gcs_result_store import GcsResultStore, build_store
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings, WorkerSettings
from uploads.interfaces import api, worker

pytestmark = pytest.mark.e2e

PROJECT = "local-project"
DENIAL = "Forbidden: worker-sa does not have storage.objects.create access to the Google Cloud Storage object."


class SwitchableStore:
    """The real store, or a denied one: the same effect as removing the worker's bucket role."""

    def __init__(self, real: GcsResultStore) -> None:
        self.real = real
        self.denied = False
        self.attempts = 0

    def create_if_absent(self, key: str, content: str) -> bool:
        self.attempts += 1
        if self.denied:
            raise StoreFailed(DENIAL)
        return self.real.create_if_absent(key, content)


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("", 0))
        return int(sock.getsockname()[1])


def _wait_for(condition: Callable[[], bool], seconds: float, what: str) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.5)
    pytest.fail(f"timed out after {seconds}s waiting for {what}")


class Stack:
    """Topics, subscriptions, a bucket, a worker server and an API client wired to the emulators."""

    def __init__(self, unique: str) -> None:
        self.bucket_name = f"e2e-{unique}"
        self.topic_id = f"e2e-{unique}"
        publisher_client = pubsub_v1.PublisherClient()
        self.subscriber = pubsub_v1.SubscriberClient()
        self.topic = publisher_client.topic_path(PROJECT, self.topic_id)
        dead_topic = publisher_client.topic_path(PROJECT, f"{self.topic_id}-dead")
        self.dead_pull = self.subscriber.subscription_path(PROJECT, f"{self.topic_id}-dead-pull")
        for name in (self.topic, dead_topic):
            publisher_client.create_topic(request={"name": name})
        self.subscriber.create_subscription(request={"name": self.dead_pull, "topic": dead_topic})

        gcs = storage.Client(project=PROJECT, credentials=AnonymousCredentials())
        self.bucket = gcs.create_bucket(self.bucket_name)
        self.store = SwitchableStore(build_store(WorkerSettings.from_env({"BUCKET": self.bucket_name})))
        self.server = make_server("0.0.0.0", _free_port(), worker.create_app(ProcessUpload(self.store)), threaded=True)  # noqa: S104
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

        self.subscriber.create_subscription(
            request={
                "name": self.subscriber.subscription_path(PROJECT, f"{self.topic_id}-push"),
                "topic": self.topic,
                "push_config": {"push_endpoint": f"http://host.docker.internal:{self.server.port}/"},
                "dead_letter_policy": {"dead_letter_topic": dead_topic, "max_delivery_attempts": 5},
                "retry_policy": {"minimum_backoff": {"seconds": 1}, "maximum_backoff": {"seconds": 2}},
                "ack_deadline_seconds": 10,
            }
        )
        publisher = build_publisher(
            ApiSettings.from_env({"PROJECT_ID": PROJECT, "TOPIC_ID": self.topic_id, "PUBLISH_TIMEOUT_SECONDS": "30"})
        )
        self.publisher = publisher
        self.api = api.create_app(RequestUpload(publisher), db_password_set=True).test_client()

    def result_exists(self, name: str) -> bool:
        return bool(self.bucket.blob(f"results/{name}.txt").exists())

    def close(self) -> None:
        self.publisher.close()
        self.server.shutdown()


@pytest.fixture
def stack(emulators, unique) -> Iterator[Stack]:
    built = Stack(unique)
    try:
        yield built
    finally:
        built.close()


def test_an_upload_request_ends_as_a_result_file_in_the_bucket(stack):
    response = stack.api.post("/upload", json={"name": "report-1"})
    assert response.status_code == 202

    _wait_for(lambda: stack.result_exists("report-1"), 60, "results/report-1.txt")
    assert stack.bucket.blob("results/report-1.txt").download_as_text() == "processed report-1\n"


def test_a_denied_worker_is_retried_then_the_message_is_dead_lettered_and_a_replay_succeeds(stack):
    stack.store.denied = True
    assert stack.api.post("/upload", json={"name": "report-2"}).status_code == 202

    _wait_for(lambda: stack.store.attempts >= 2, 60, "Pub/Sub to retry the failed delivery")
    assert not stack.result_exists("report-2")

    def dead_lettered() -> bool:
        try:
            pulled = stack.subscriber.pull(request={"subscription": stack.dead_pull, "max_messages": 1}, timeout=5)
        except DeadlineExceeded:  # nothing there yet: the emulator holds the pull open, then gives up
            return False
        return any(b"report-2" in m.message.data for m in pulled.received_messages)

    _wait_for(dead_lettered, 120, "the message in the dead-letter subscription")

    stack.store.denied = False  # the role is back
    assert stack.api.post("/upload", json={"name": "report-2"}).status_code == 202  # the replay
    _wait_for(lambda: stack.result_exists("report-2"), 60, "results/report-2.txt after the replay")
