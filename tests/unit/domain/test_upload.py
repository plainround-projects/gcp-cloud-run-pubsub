import json

import pytest

from uploads.domain.errors import InvalidUploadName, MalformedUploadMessage
from uploads.domain.upload import UploadName, UploadRequested, UploadResult


@pytest.mark.parametrize("name", ["report-1", "a", "Report_2.v3", "x" * 128, "2026-10-26.csv"])
def test_accepts_names_that_are_safe_object_name_parts(name):
    assert str(UploadName(name)) == name


@pytest.mark.parametrize(
    "name",
    ["", " ", "../etc", "a/b", "a..b", "-leading", ".hidden", "x" * 129, "white space", "ünïcode", None, 7, ["a"]],
)
def test_rejects_names_that_could_escape_the_results_prefix_or_are_not_text(name):
    with pytest.raises(InvalidUploadName):
        UploadName(name)


def test_event_is_built_from_a_request_body_and_round_trips_through_bytes():
    event = UploadRequested.from_request_body({"name": "report-1", "ignored": True})
    assert event.encode() == b'{"name":"report-1"}'
    assert UploadRequested.decode(event.encode()) == event


def test_request_body_without_a_name_is_invalid():
    with pytest.raises(InvalidUploadName):
        UploadRequested.from_request_body({})


@pytest.mark.parametrize(
    "data",
    [b"not json", b"\xff\xfe", b"[]", b'"text"', b"{}", json.dumps({"name": "../x"}).encode(), b'{"name": 5}'],
)
def test_decoding_a_message_that_is_not_an_upload_request_raises_a_named_error(data):
    with pytest.raises(MalformedUploadMessage):
        UploadRequested.decode(data)


def test_result_file_is_under_results_with_the_lessons_body():
    result = UploadResult.for_request(UploadRequested(UploadName("report-1")))
    assert result.key == "results/report-1.txt"
    assert result.body == "processed report-1\n"
