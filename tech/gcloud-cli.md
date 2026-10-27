# gcloud (the Google Cloud command-line tool)

## 1. What it is

`gcloud` is a program you run in a terminal to control Google Cloud: create projects, read logs, change permissions. Each command is a sentence made of nouns and a verb, for example `gcloud pubsub topics publish`. It signs in as you (or as a service account) and sends the matching requests to Google's APIs.

## 2. Why this repository uses it

Terraform builds the infrastructure. `gcloud` is what the owner types to **prove** and **break** it: check who may do what, remove a permission, read a log entry, replay a message. The lesson's steps are written as `gcloud` commands, so the runbook scripts keep them.

## 3. Where it appears

| Path | What it does with gcloud |
| --- | --- |
| `scripts/lib.sh` | Sets the active project; helper functions to look up service URLs. |
| `scripts/create-project.sh` | `gcloud projects create`, `gcloud billing projects link`, `gcloud projects describe`. |
| `scripts/build-images.sh` | `gcloud auth configure-docker`. |
| `scripts/prove.sh` | Reads policies and settings; calls the API. |
| `scripts/break-permission.sh`, `read-denial.sh`, `restore-and-replay.sh` | Remove and restore a role; read logs; pull and publish messages. |
| `scripts/teardown.sh` | Deletes the budget and the project. |

None of these ran against a real project when the repository was built.

## 4. How it works underneath

- **Configuration.** `gcloud config set project ID` stores a default project in a file under your home directory. Later commands use it unless you pass `--project`.
- **Credentials.** `gcloud auth login` stores your login; commands then send your token. `--impersonate-service-account=EMAIL` asks Google for a token *as* that service account if you hold the right to do so (token creator).
- **Output control.** `--format='value(status.url)'` prints just one field, ready to use in a shell variable. `--filter` selects rows. `--flatten` turns a list field into one row per item, which is how the IAM policy checks work.
- **Exit status.** A failed command exits non-zero, which scripts use to decide pass or fail.

## 5. Walkthrough of this repository's use

`scripts/lib.sh`

```bash
: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"
REGION="${REGION:-europe-west1}"
BUCKET="$PROJECT_ID-results"
API_SA="api-sa@$PROJECT_ID.iam.gserviceaccount.com"
WORKER_SA="worker-sa@$PROJECT_ID.iam.gserviceaccount.com"
INVOKER_SA="pubsub-invoker@$PROJECT_ID.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID" --quiet >/dev/null

api_url() { gcloud run services describe api --region="$REGION" --format='value(status.url)'; }
worker_url() { gcloud run services describe worker --region="$REGION" --format='value(status.url)'; }
```

- `: "${PROJECT_ID:?set PROJECT_ID ...}"`: the `:` command does nothing; the `${VAR:?message}` expansion stops the script with the message if the variable is empty.
- `gcloud config set project "$PROJECT_ID" --quiet >/dev/null`: select the project and hide the output.
- `api_url()` and `worker_url()` run `gcloud run services describe NAME --region=... --format='value(status.url)'` to read a service's URL.

Removing the worker's right to write, the break in step 5:

`scripts/break-permission.sh`

```bash
gcloud storage buckets remove-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$WORKER_SA" --role=roles/storage.objectCreator
echo "waiting 60 seconds for the removal to apply"
sleep 60
curl -fsS -X POST "$(api_url)/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$NAME\"}"
```

`remove-iam-policy-binding` edits the bucket's policy: take this member's role away. The script waits 60 seconds because IAM changes take a moment to spread. Then it posts an upload.

Reading the evidence:

`scripts/read-denial.sh`

```bash
echo "== the denial in the worker's log (account, permission, resource)"
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="worker" AND severity>=ERROR' \
  --limit=5 --freshness=1h --format='value(jsonPayload.error)'

echo "== the message in the dead-letter subscription (source subscription and delivery attempts)"
gcloud pubsub subscriptions pull uploads-dead-pull --limit=1 \
  --format='value(message.attributes.CloudPubSubDeadLetterSourceSubscription, message.deliveryAttempt, message.data)'
```

`gcloud logging read 'FILTER' --limit --freshness --format` queries Cloud Logging. The filter picks error logs of the Cloud Run revisions of the service `worker`. `gcloud pubsub subscriptions pull uploads-dead-pull --limit=1` reads one message from the dead-letter subscription without acknowledging it, so the next script can still read it.

## 6. Try it yourself

You can read the commands without an account:

```bash
grep -rhn "gcloud " scripts/*.sh | head -20
```
Expected: the commands above, one per line.

With an account (your own project):

```bash
gcloud config list
gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)'
```
Expected: your configuration, then the number of your project. These calls change nothing.

```bash
shellcheck scripts/*.sh && echo clean
```
Expected: `clean`.

## 7. Mistakes people make

- **Running against the wrong project.** Check `gcloud config list` first; the scripts set the project from `.env`.
- **Not waiting after an IAM change.** A test that "still works" right after removing a role proves nothing; wait.
- **Parsing human-readable output.** Use `--format` (`value(...)`, `json`).
- **Leaving credentials around.** Use `gcloud auth revoke` on shared machines.
- **Typing `gcloud projects delete` casually.** The teardown script asks you to type the project id.

## 8. Check yourself

1. What does `--format='value(status.url)'` do? *Prints only that field, without labels.*
2. What does `--impersonate-service-account` change? *The token comes from that service account, not from you.*
3. What does `${VAR:?message}` do in Bash? *Stops with the message when `VAR` is empty or unset.*
4. Why does a script wait after `remove-iam-policy-binding`? *IAM changes need a short time to take effect.*
5. How does a script know a gcloud call failed? *Non-zero exit status.*

## 9. Further reading

- gcloud CLI overview: <https://cloud.google.com/sdk/gcloud>
- Reference (all commands): <https://cloud.google.com/sdk/gcloud/reference>
- Formatting output: <https://cloud.google.com/sdk/gcloud/reference/topic/formats>
- Filters: <https://cloud.google.com/sdk/gcloud/reference/topic/filters>
