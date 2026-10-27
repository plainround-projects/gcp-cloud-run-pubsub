# 2. Ports and adapters around Pub/Sub and Cloud Storage

Status: accepted, 2026-10-27

## Context

The system has two outward boundaries, a message broker and an object store. Tests of the rules (what a valid name is, that a duplicate delivery is harmless, that a failure is never acknowledged) must run without Google Cloud, and the adapters must still be tested against something real.

## Decision

Two ports in `application/ports.py`: `MessagePublisher.publish(data) -> id` and `ResultStore.create_if_absent(key, content) -> bool`, with named errors `PublishFailed` and `StoreFailed`. Adapters in `infrastructure/` translate every Google exception into the named error and keep its text. Unit tests use in-memory fakes; integration tests run the adapters against the Pub/Sub emulator and a fake Cloud Storage server. import-linter forbids `google`, `flask` and `requests` in `domain` and `application`.

## Consequences

- The use cases are covered at 100 percent without a network.
- The adapters are small enough to be covered by a handful of integration tests.
- A new boundary (for example Eventarc) is a new adapter, not a change to the rules.
