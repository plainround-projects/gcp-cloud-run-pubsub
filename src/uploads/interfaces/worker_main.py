"""Entry point of the worker container: `gunicorn "uploads.interfaces.worker_main:create()"`."""

from __future__ import annotations

import os

from flask import Flask

from uploads.application.process_upload import ProcessUpload
from uploads.infrastructure.gcs_result_store import build_store
from uploads.infrastructure.logging import configure_logging
from uploads.infrastructure.settings import WorkerSettings
from uploads.interfaces.worker import create_app


def create() -> Flask:
    """Read the settings and build the real adapters and the app."""
    settings = WorkerSettings.from_env(os.environ)
    configure_logging(settings.log_level)
    return create_app(ProcessUpload(build_store(settings)))
