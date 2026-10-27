"""Structured logging that Cloud Logging understands: one JSON object per line on stdout, with `severity`."""

from __future__ import annotations

import json
import logging
import sys
from typing import Any

_RESERVED = set(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    """Format records as JSON; fields passed through `extra=` become top-level keys."""

    def format(self, record: logging.LogRecord) -> str:
        """Render one record. Cloud Run parses `severity` and `message` from the line."""
        entry: dict[str, Any] = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        entry.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: str) -> None:
    """Send every log record to stdout as JSON at `level`; safe to call twice."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
