"""Entry point of the API container: `gunicorn "uploads.interfaces.api_main:create()"`."""

from __future__ import annotations

import atexit
import os

from flask import Flask

from uploads.application.request_upload import RequestUpload
from uploads.infrastructure.logging import configure_logging
from uploads.infrastructure.pubsub_publisher import build_publisher
from uploads.infrastructure.settings import ApiSettings
from uploads.interfaces.api import create_app


def create() -> Flask:
    """Read the settings, build the real adapters and the app; flush the publisher when the process exits."""
    settings = ApiSettings.from_env(os.environ)
    configure_logging(settings.log_level)
    publisher = build_publisher(settings)
    atexit.register(publisher.close)
    return create_app(RequestUpload(publisher), db_password_set=settings.db_password is not None)
