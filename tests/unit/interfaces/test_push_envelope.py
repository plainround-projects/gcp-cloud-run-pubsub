import base64

import pytest

from uploads.interfaces.push_envelope import InvalidEnvelope, parse_push_envelope


def _envelope(data):
    return {"message": {"data": data, "messageId": "7"}, "subscription": "projects/p/subscriptions/uploads-push"}


def test_a_valid_envelope_yields_decoded_bytes_and_ids():
    pushed = parse_push_envelope(_envelope(base64.b64encode(b'{"name":"a"}').decode()))
    assert (pushed.message_id, pushed.data, pushed.subscription) == (
        "7",
        b'{"name":"a"}',
        "projects/p/subscriptions/uploads-push",
    )


@pytest.mark.parametrize(
    "body",
    [None, [], "x", {}, {"message": "x"}, {"message": {}}, {"message": {"data": 5}}, _envelope("***not base64***")],
)
def test_anything_else_is_an_invalid_envelope(body):
    with pytest.raises(InvalidEnvelope):
        parse_push_envelope(body)
