"""In-memory stand-ins for the ports: deterministic, no network."""

from __future__ import annotations

from uploads.application.ports import PublishFailed, StoreFailed


class InMemoryPublisher:
    """Records published payloads and hands out sequential ids."""

    def __init__(self, fail_with: str | None = None) -> None:
        self.published: list[bytes] = []
        self._fail_with = fail_with

    def publish(self, data: bytes) -> str:
        if self._fail_with:
            raise PublishFailed(self._fail_with)
        self.published.append(data)
        return str(len(self.published))


class InMemoryStore:
    """A bucket in a dict, with create-only semantics like the real adapter."""

    def __init__(self, fail_with: str | None = None) -> None:
        self.objects: dict[str, str] = {}
        self.write_attempts = 0
        self._fail_with = fail_with

    def create_if_absent(self, key: str, content: str) -> bool:
        self.write_attempts += 1
        if self._fail_with:
            raise StoreFailed(self._fail_with)
        if key in self.objects:
            return False
        self.objects[key] = content
        return True
