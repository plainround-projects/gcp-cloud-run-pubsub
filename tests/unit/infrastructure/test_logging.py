import json
import logging

from uploads.infrastructure.logging import JsonFormatter, configure_logging


def _format(**kwargs):
    record = logging.LogRecord("t", logging.ERROR, __file__, 1, "went %s", ("wrong",), None)
    for key, value in kwargs.items():
        setattr(record, key, value)
    return json.loads(JsonFormatter().format(record))


def test_a_record_is_one_json_object_with_severity_and_message():
    entry = _format()
    assert entry["severity"] == "ERROR"
    assert entry["message"] == "went wrong"


def test_extra_fields_become_top_level_keys():
    assert _format(message_id="42")["message_id"] == "42"


def test_exceptions_are_included_as_text():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("t", logging.ERROR, __file__, 1, "failed", None, sys.exc_info())
    assert "ValueError: boom" in json.loads(JsonFormatter().format(record))["exception"]


def test_configure_logging_is_idempotent_and_sets_the_level():
    configure_logging("WARNING")
    configure_logging("WARNING")
    root = logging.getLogger()
    assert len(root.handlers) == 1
    assert root.level == logging.WARNING
