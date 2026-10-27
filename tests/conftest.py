"""Shared fixtures. Integration and end-to-end tests use the emulators of docker-compose.yml (`make emulators`)."""

from __future__ import annotations

import socket
import uuid

import pytest

PUBSUB_HOST = "localhost:8085"
GCS_URL = "http://localhost:4443"


def _reachable(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


@pytest.fixture
def emulators(monkeypatch: pytest.MonkeyPatch) -> None:
    """Point the Google client libraries at the emulators; fail loudly, not silently, when they are not running."""
    if not (_reachable("localhost", 8085) and _reachable("localhost", 4443)):
        pytest.fail("the emulators are not running: start them with `make emulators`")
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", PUBSUB_HOST)
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", GCS_URL)


@pytest.fixture
def unique() -> str:
    """A short unique suffix so repeated runs never meet each other's topics, buckets or objects."""
    return uuid.uuid4().hex[:10]
