"""The API service: `POST /upload` publishes a message, `GET /health` reports whether the secret arrived."""

from __future__ import annotations

import logging

from flask import Flask, Response, jsonify, request

from uploads.application.ports import PublishFailed
from uploads.application.request_upload import RequestUpload
from uploads.domain.errors import InvalidUploadName

logger = logging.getLogger("uploads.api")

_MAX_BODY_BYTES = 64 * 1024


def create_app(request_upload: RequestUpload, db_password_set: bool) -> Flask:
    """Build the Flask app around the use case; nothing here reaches Google Cloud directly."""
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = _MAX_BODY_BYTES

    @app.post("/upload")
    def upload() -> tuple[Response, int]:
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            return jsonify(error='body must be a JSON object such as {"name": "report-1"}'), 400
        try:
            receipt = request_upload.execute(body)
        except InvalidUploadName as error:
            return jsonify(error=str(error)), 400
        except PublishFailed as error:
            logger.error("publish failed", extra={"error": str(error)})
            return jsonify(error="could not publish the message"), 503
        logger.info("upload requested", extra={"upload_name": body["name"], "message_id": receipt.message_id})
        return jsonify(published=receipt.message_id), 202

    @app.get("/health")
    def health() -> Response:
        # Only whether the secret is present, never the value.
        return jsonify(db_password_set=db_password_set)

    return app
