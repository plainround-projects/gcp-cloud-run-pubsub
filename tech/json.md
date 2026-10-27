# JSON

## 1. What it is

JSON (JavaScript Object Notation) is a text format for data made of objects (`{"key": value}`), lists (`[1, 2]`), strings, numbers, `true`, `false` and `null`. Almost every web service speaks it. Keys must be in double quotes; there are no comments.

## 2. Why this repository uses it

JSON is the language between the pieces: the API's request body, the message published to Pub/Sub, the Pub/Sub push envelope, the API's responses, and the structured log lines that Cloud Logging reads.

## 3. Where it appears

| Path | What is JSON |
| --- | --- |
| `src/uploads/domain/upload.py` | `UploadRequested.encode()` and `decode()`: the message body `{"name":"report-1"}`. |
| `src/uploads/interfaces/api.py` | Request body in, `{"published": "<id>"}` or `{"error": "..."}` out, via `jsonify`. |
| `src/uploads/interfaces/push_envelope.py` | The push request `{"message": {"data": "<base64>", "messageId": "..."}, "subscription": "..."}`. |
| `src/uploads/infrastructure/logging.py` | One JSON object per log line. |
| `scripts/local-demo.sh` | Reads the fake bucket's JSON object list. |

## 4. How it works underneath

Programs convert between text and in-memory data: `json.dumps(obj)` makes text, `json.loads(text)` makes data. In Python an object becomes a `dict`, a list a `list`, `null` becomes `None`. Bytes are not a JSON type, which is why Pub/Sub's `data` field is **base64** text: the message bytes are encoded as letters and digits to travel inside JSON.

## 5. Walkthrough of this repository's use

`src/uploads/domain/upload.py`

```python
    def encode(self) -> bytes:
        """Serialize to the message data that is published."""
        return json.dumps({"name": self.name.value}, separators=(",", ":")).encode("utf-8")

    @classmethod
    def decode(cls, data: bytes) -> UploadRequested:
        """Parse message data, raising `MalformedUploadMessage` for anything that is not an upload request."""
        try:
            payload = json.loads(data)
        except (UnicodeDecodeError, ValueError) as error:
            raise MalformedUploadMessage("message data is not JSON") from error
        if not isinstance(payload, dict) or "name" not in payload:
            raise MalformedUploadMessage("message data has no 'name'")
```

- `json.dumps({"name": ...}, separators=(",", ":"))` writes the compact form `{"name":"report-1"}` (no spaces), and `.encode("utf-8")` turns the text into bytes for publishing.
- `json.loads(data)` accepts bytes or text. A bad document raises `ValueError`; invalid UTF-8 raises `UnicodeDecodeError`. Both become `MalformedUploadMessage`.
- The checks `isinstance(payload, dict)` and `"name" not in payload` reject valid JSON of the wrong shape (a list, a string, an object without `name`).

The envelope:

`src/uploads/interfaces/push_envelope.py`

```python
def parse_push_envelope(envelope: Any) -> PushedMessage:
    """Decode the envelope, raising `InvalidEnvelope` for anything that does not have the documented shape."""
    if not isinstance(envelope, dict) or not isinstance(envelope.get("message"), dict):
        raise InvalidEnvelope("body must be a Pub/Sub push envelope with a 'message' object")
    message = envelope["message"]
    encoded = message.get("data")
    if not isinstance(encoded, str):
        raise InvalidEnvelope("message has no base64 'data'")
    try:
        data = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise InvalidEnvelope("message data is not valid base64") from error
    return PushedMessage(
        message_id=str(message.get("messageId", "")),
        data=data,
        subscription=str(envelope.get("subscription", "")),
```

`base64.b64decode(encoded, validate=True)` rejects characters outside the base64 alphabet instead of silently skipping them.

## 6. Try it yourself

```bash
echo -n '{"name":"report-1"}' | base64
```
Expected: `eyJuYW1lIjoicmVwb3J0LTEifQ==`

```bash
echo 'eyJuYW1lIjoicmVwb3J0LTEifQ==' | base64 -d; echo
```
Expected: `{"name":"report-1"}`

```bash
.venv/bin/python -c "import json; print(json.dumps({'name': 'a'}, separators=(',', ':')))"
```
Expected: `{"name":"a"}`

```bash
.venv/bin/python -m pytest tests/unit/domain/test_upload.py -q -p no:cacheprovider
```
Expected: all pass, including the cases for non-JSON bytes, JSON lists, and objects without `name`.

## 7. Mistakes people make

- **Trailing commas or single quotes.** Not valid JSON.
- **Assuming the right shape.** Valid JSON can still be a list when you expected an object; always check.
- **Treating base64 as encryption.** It is only a way to write bytes as text.
- **Putting secrets in logs** because logs are JSON now. The formatter never includes the password.

## 8. Check yourself

1. Can JSON contain comments? *No.*
2. What is `message.data` in a push body? *The message bytes, base64-encoded.*
3. What does `json.loads` raise for bad text? *`ValueError`.*
4. Why `isinstance(payload, dict)` after parsing? *Valid JSON may be a list or a string.*
5. Why does Cloud Logging like one JSON object per line? *It can read `severity` and `message` from it.*

## 9. Further reading

- JSON: <https://www.json.org/>
- Python `json`: <https://docs.python.org/3.12/library/json.html>
- Structured logging on Google Cloud: <https://cloud.google.com/logging/docs/structured-logging>
