# Cloud Storage (and the Python client, and the fake server)

## 1. What it is

Cloud Storage is Google Cloud's **object store**. You keep **objects** (files plus a name and some details) in **buckets** (named containers). There are no real folders: `results/report-1.txt` is one flat name that contains slashes. This repository also uses the Python library `google-cloud-storage` (pinned 3.17.1) and, for local runs, `fake-gcs-server` (image `fsouza/fake-gcs-server:1.52.2`), a small program that imitates the service.

## 2. Why this repository uses it

The worker writes one result file per processed message. The lesson also practices giving the worker only the right to *create* objects.

## 3. Where it appears

| Path | What it does with Cloud Storage |
| --- | --- |
| `src/uploads/infrastructure/gcs_result_store.py` | Creates `results/NAME.txt` only if it is absent. |
| `infra/modules/results-bucket/main.tf` | Creates the bucket (private, versioned, with a retention rule) and grants `objectCreator`. |
| `docker-compose.yml` | Runs `fake-gcs-server` as the `gcs` service. |
| `tests/integration/test_gcs_emulator.py`, `tests/e2e/` | Run the real adapter against the fake server. |
| `scripts/local-demo.sh` | Lists the fake bucket's objects with `curl`. |

## 4. How it works underneath

- A write is an HTTP request to `storage.googleapis.com`. Each object has a **generation number** that changes whenever the object is replaced. A **precondition** is a rule attached to a request: `ifGenerationMatch=0` means "only do this if no live object with this name exists". If the rule is false Cloud Storage answers `412 Precondition Failed` and changes nothing.
- Permissions are **roles** made of **permissions**. `roles/storage.objectCreator` contains `storage.objects.create` only: it cannot read, list, overwrite or delete. Replacing an existing object needs `storage.objects.delete` as well. So a plain write of a duplicate result would be *denied*, but a conditional create is just answered 412 and can be treated as "already done".
- **Uniform bucket-level access** turns off per-object ACLs so that only IAM decides. **Public access prevention** blocks public sharing. **Versioning** keeps old generations; the lifecycle rules delete old results after 30 days and non-current versions after 7 days after they become non-current.
- The library retries failures. For uploads it retries only when a precondition makes a repeat safe: `DEFAULT_RETRY_IF_GENERATION_SPECIFIED`.
- If `STORAGE_EMULATOR_HOST` is set, the library talks to that address (here `http://localhost:4443`, the fake server) with no credentials.

## 5. Walkthrough of this repository's use

`src/uploads/infrastructure/gcs_result_store.py`

```python
class GcsResultStore:
    """Create objects only if absent.

    `if_generation_match=0` makes the write conditional on the object not existing. That keeps a duplicate delivery
    harmless and works with `roles/storage.objectCreator`, which can create objects but not overwrite or delete them.
    """

    def __init__(self, bucket: Any, timeout_seconds: float) -> None:
        """`bucket` is a `google.cloud.storage.Bucket` (or anything shaped like one)."""
        self._bucket = bucket
        self._timeout = timeout_seconds

    def create_if_absent(self, key: str, content: str) -> bool:
        """True when the object was created, False when it already existed; `StoreFailed` otherwise."""
        blob = self._bucket.blob(key)
        try:
            blob.upload_from_string(
                content,
                content_type="text/plain; charset=utf-8",
                if_generation_match=0,
                timeout=self._timeout,
                retry=DEFAULT_RETRY_IF_GENERATION_SPECIFIED,
            )
        except PreconditionFailed:
            return False
        except (GoogleAPIError, GoogleAuthError, requests.RequestException, TimeoutError) as error:
            raise StoreFailed(f"{type(error).__name__}: {error}") from error
        return True
```

- `self._bucket.blob(key)` makes a handle for the object name; nothing is sent yet.
- `upload_from_string(content, content_type=..., if_generation_match=0, timeout=..., retry=...)` sends the write: the text, its type, the precondition, a time limit, and the retry rule.
- `except PreconditionFailed: return False` means "the file was already there": the use case reports `ALREADY_PROCESSED`, and the worker still acknowledges the message.
- Any other Google, auth, network or timeout error becomes `StoreFailed` with the original text. When the worker's role is removed, that text is the 403 naming the service account, the permission `storage.objects.create` and the resource.

`src/uploads/infrastructure/gcs_result_store.py`

```python
def build_store(settings: WorkerSettings) -> GcsResultStore:
    """The real adapter. Credentials come from the runtime's service account, or are anonymous for the emulator."""
    if os.environ.get("STORAGE_EMULATOR_HOST"):
        client = storage.Client(project=settings.project_id or "local", credentials=AnonymousCredentials())
    else:
        client = storage.Client(project=settings.project_id)
    return GcsResultStore(client.bucket(settings.bucket), settings.store_timeout_seconds)
```

With the emulator variable set, the client is built with `AnonymousCredentials` (no sign-in) so it works without Google.

The bucket and its single grant:

`infra/modules/results-bucket/main.tf`

```hcl
resource "google_storage_bucket" "this" {
  #checkov:skip=CKV_GCP_62:A one-day sandbox needs no separate access-log bucket; Cloud Audit Logs record administrative activity. Add a log bucket before real use
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

# objectCreator creates objects but cannot read, overwrite or delete them. The bucket is the only place it is granted.
resource "google_storage_bucket_iam_member" "creator" {
  for_each = var.creator_members

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectCreator"
```

`uniform_bucket_level_access = true`, `public_access_prevention = "enforced"` and `versioning` are the safety settings. The `lifecycle_rule` blocks delete results after `retention_days` and old versions after 7 days. The `#checkov:skip` comment records a reviewed exception (no separate log bucket in a one-day sandbox).

## 6. Try it yourself

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_gcs_result_store.py -v -p no:cacheprovider 2>&1 | grep -E "PASSED|passed"
```
Expected: `7 passed`: conditional create, `412` giving `False`, Forbidden/timeout/connection errors becoming `StoreFailed`, and the emulator and cloud paths of `build_store`.

```bash
grep -n "if_generation_match" -r src tests | head
```
Expected: the adapter and the tests that assert it equals `0`.

```bash
make emulators && make test-integration
```
Expected (Docker needed): the object is created once and `False` the second time; writing to a missing bucket raises `StoreFailed` containing `NotFound`.

## 7. Mistakes people make

- **Giving the worker `objectAdmin` "to make it work".** Then the break in step 5 shows nothing.
- **Overwriting without thinking.** `objectCreator` cannot; the code uses create-if-absent.
- **Reading a missing object as an empty one.** Buckets have no folders or defaults.
- **Using the project id where the bucket name is needed.** Bucket names are global; the sandbox names it `PROJECT_ID-results`.
- **Trusting the fake server for permissions.** It does not check IAM.

## 8. Check yourself

1. What does `ifGenerationMatch=0` mean? *Only write if the object does not exist.*
2. Which status says the precondition failed? *412.*
3. What can `roles/storage.objectCreator` do? *Create objects only.*
4. Why return `False` instead of raising on 412? *A duplicate delivery is a success that changes nothing.*
5. What does the emulator variable do? *Points the client at the fake server without credentials.*

## 9. Further reading

- Cloud Storage: <https://cloud.google.com/storage/docs>
- Request preconditions: <https://cloud.google.com/storage/docs/request-preconditions>
- IAM roles for Storage: <https://cloud.google.com/storage/docs/access-control/iam-roles>
- Python client 3.x: <https://cloud.google.com/python/docs/reference/storage/latest>
- fake-gcs-server: <https://github.com/fsouza/fake-gcs-server>
