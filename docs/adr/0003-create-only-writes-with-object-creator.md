# 3. Create-only writes with `roles/storage.objectCreator`

Status: accepted, 2026-10-27

## Context

The lesson grants the worker `roles/storage.objectCreator`, which can create objects but not read, overwrite or delete them. Pub/Sub delivers at least once, so the worker will sometimes see a message it has already processed. Overwriting an object needs `storage.objects.delete` as well as `create`, so a plain upload of a duplicate would be denied and the worker would return 500 for a message that was in fact done.

## Decision

The result store writes with `if_generation_match=0`. If the object exists, Cloud Storage answers `412 Precondition Failed`, the adapter returns `False`, and the use case reports `ALREADY_PROCESSED` and acknowledges the message.

## Consequences

- A duplicate delivery is a success that changes nothing, with the narrowest role.
- A result cannot be updated by the worker. If a future version must update, grant `objectUser` on the bucket and define the overwrite rule first.
- The retry of a failed write is safe: the conditional write is idempotent, so the client library may retry it.
