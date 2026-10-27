"""Gunicorn settings for Cloud Run: one process, a few threads, shutdown inside Cloud Run's 10-second SIGTERM window."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"  # the container must listen on all interfaces
workers = 1
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
timeout = 0  # Cloud Run enforces the request timeout; gunicorn must not kill a slow request first
graceful_timeout = 8  # on SIGTERM finish in-flight requests, then exit before Cloud Run's SIGKILL
accesslog = None
