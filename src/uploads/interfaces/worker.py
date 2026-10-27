"""The worker service: receives Pub/Sub push deliveries and writes one result file per message.

Pub/Sub acknowledges a delivery only for a 2xx response. Every failure below therefore answers with an error status,
so the message is retried and, after the subscription's attempt limit, dead-lettered rather than lost.
"""

from __future__ import annotations

import logging

from flask import Flask, Response, request

from uploads.application.ports import StoreFailed
from uploads.application.process_upload import ProcessUpload
from uploads.domain.errors import MalformedUploadMessage
from uploads.interfaces.push_envelope import InvalidEnvelope, parse_push_envelope

logger = logging.getLogger("uploads.worker")

_MAX_BODY_BYTES = 256 * 1024


def create_app(process_upload: ProcessUpload) -> Flask:
    """Build the Flask app around the use case; nothing here reaches Google Cloud directly."""
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = _MAX_BODY_BYTES

    @app.post("/")
    def receive() -> Response:
        try:
            pushed = parse_push_envelope(request.get_json(silent=True))
            outcome = process_upload.execute(pushed.data)
        except (InvalidEnvelope, MalformedUploadMessage) as error:
            # A message that can never succeed still gets a 4xx so it is retried and dead-lettered, not acknowledged.
            logger.warning("rejected a malformed delivery", extra={"error": str(error)})
            return Response(str(error), status=400, mimetype="text/plain")
        except StoreFailed as error:
            # The full text names the service account, the permission and the resource when the cause is IAM.
            logger.error("could not store the result", extra={"error": str(error)})
            return Response("storage failed", status=500, mimetype="text/plain")
        logger.info("processed", extra={"message_id": pushed.message_id, "outcome": outcome.value})
        return Response(status=204)

    @app.get("/health")
    def health() -> Response:
        return Response("ok", status=200, mimetype="text/plain")

    return app
