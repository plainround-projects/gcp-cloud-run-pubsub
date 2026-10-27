# Bash

## 1. What it is

Bash is a **shell**: a program that reads commands you type (or that a file contains) and runs other programs for you. A **shell script** is a text file of such commands. A **command** is a program name followed by **arguments** (the words after it) and **flags** (arguments that start with `-`). Bash also has variables, `if`, `for` and functions, so a script can make decisions. The scripts here need Bash (the macOS one is fine, version 3.2 or newer).

## 2. Why this repository uses it

The lesson's runbook is a list of `gcloud` and `terraform` commands that a person runs in order: create the project, deploy, prove each requirement, break a permission, read the evidence, replay, tear down. Putting them in scripts makes them exact, repeatable and checkable (with `shellcheck`).

## 3. Where it appears

| Path | What the script does |
| --- | --- |
| `scripts/lib.sh` | Shared by the others (`source`d): loads `.env`, sets names, defines `check`, `api_url`, `worker_url`. |
| `scripts/create-project.sh` | Creates the project, links billing, writes `sandbox.tfvars`. |
| `scripts/build-images.sh` | Builds and pushes both images; writes `images.auto.tfvars`. |
| `scripts/deploy.sh` | Two Terraform passes around the image build. |
| `scripts/prove.sh` | One PASS/FAIL line per "Done when" check. |
| `scripts/break-permission.sh`, `read-denial.sh`, `restore-and-replay.sh` | Steps 5 and 6. |
| `scripts/teardown.sh` | Deletes the budget and the project after you type the project id. |
| `scripts/local-demo.sh` | The local flow on your machine: upload twice, list the result files. |

## 4. How it works underneath

- Bash starts a program as a new **process** and waits for it. Each process has an **exit status**, a number: `0` means success, anything else means failure. `$?` holds the last one.
- **Variables** hold text. `NAME=value` sets one; `"$NAME"` reads it. **Always put quotes around expansions**: without them Bash splits the text at spaces and expands `*`.
- `$(command)` runs a command and substitutes its output. `|` (a **pipe**) sends one program's output into the next program's input. `>file` writes output to a file; `>/dev/null` throws it away; `2>&1` sends error output where normal output goes.
- `source file` runs another file's lines in the *current* shell, so its variables and functions become available. That is how `lib.sh` works.
- `[[ ... ]]` is Bash's test: `-f path` (file exists), `-n text` (not empty), `==` (text equals; the right side can be a pattern).
- Environment variables are copied into child processes if they are **exported**. `set -a` makes every variable assigned afterwards exported automatically.

## 5. Walkthrough of this repository's use

### The shared header

`scripts/lib.sh`

```bash
#!/usr/bin/env bash
# Shared by the runbook scripts: loads .env and sets the variables the lesson uses in every command.
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT/infra/environments/sandbox"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"
REGION="${REGION:-europe-west1}"
BUCKET="$PROJECT_ID-results"
API_SA="api-sa@$PROJECT_ID.iam.gserviceaccount.com"
WORKER_SA="worker-sa@$PROJECT_ID.iam.gserviceaccount.com"
INVOKER_SA="pubsub-invoker@$PROJECT_ID.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID" --quiet >/dev/null
```

- `#!/usr/bin/env bash` (the **shebang**) tells the system to run the file with Bash found on the PATH.
- `set -euo pipefail` makes the script strict. `-e`: stop at the first command that fails. `-u`: using an unset variable is an error, not an empty string. `-o pipefail`: a pipe fails if *any* stage fails, not only the last.
- `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`: `BASH_SOURCE[0]` is this file's path; `dirname` takes its folder; `/..` goes up to the repository root; `cd ... && pwd` prints the absolute path. The script therefore works from any current folder.
- The `if [[ -f "$ROOT/.env" ]]; then set -a; source ...; set +a; fi` block loads `.env` and exports its variables. The `# shellcheck disable=SC1091` comment tells the linter not to complain that it cannot follow a file chosen at run time.
- `: "${PROJECT_ID:?set PROJECT_ID in .env ...}"` stops with that message if `PROJECT_ID` is empty. `${REGION:-europe-west1}` supplies a default.
- The names (`API_SA`, `BUCKET`, ...) are built from `PROJECT_ID` exactly as the lesson's shell variables are.

### The PASS/FAIL helper

`scripts/lib.sh`

```bash
# check "what is proved" command...: runs the command and prints PASS or FAIL for the Done when line it proves.
check() {
  local what="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $what"
  else
    echo "FAIL  $what"
    FAILED=1
  fi
}
FAILED=0
```

`check` takes a description, then `shift` removes that first argument so `"$@"` is the command to run (with its own arguments kept intact). `if "$@" >/dev/null 2>&1; then` runs it silently and branches on its exit status. `FAILED=1` records a failure; `prove.sh` ends with `exit "$FAILED"`.

### A script that proves requirements

`scripts/prove.sh`

```bash
echo "== Step 2: one identity each, no project-level role"
for account in "$API_SA" "$WORKER_SA" "$INVOKER_SA"; do
  check "$account holds no project-level role" test -z "$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$account" --format='value(bindings.role)')"
done
check "the topic lists only the API account as publisher" test "$(gcloud pubsub topics get-iam-policy uploads --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the secret lists only the API account" test "$(gcloud secrets get-iam-policy db-password --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the bucket lists only the worker account as object creator" test "$(gcloud storage buckets get-iam-policy "gs://$BUCKET" --flatten='bindings[].members' --filter='bindings.role:roles/storage.objectCreator' --format='value(bindings.members)')" = "serviceAccount:$WORKER_SA"
```

- `--flatten='bindings[].members' --filter="bindings.members:serviceAccount:$account" --format='value(bindings.role)'` asks `gcloud` for the project policy, makes one row per member, keeps rows for that account and prints only roles. `test -z "..."` passes when the output is empty, meaning the account holds no project-level role.
- The `for account in ...; do ... done` loop repeats it for the three accounts.

The worker must answer 403 to a call with no token:

`scripts/prove.sh`

```bash
check "a direct call to the worker without a token returns 403" test "$(curl -s -o /dev/null -w '%{http_code}' "$WORKER_URL")" = "403"
```

`curl -s -o /dev/null -w '%{http_code}'` prints only the HTTP status (`-s` quiet, `-o /dev/null` drop the body, `-w` print the status).

### Writing a file from a script

`scripts/build-images.sh`

```bash
cat >"$ENV_DIR/images.auto.tfvars" <<VARS
api_image    = "$PREFIX/api:$TAG"
worker_image = "$PREFIX/worker:$TAG"
VARS
echo "wrote $ENV_DIR/images.auto.tfvars"
```

A **here-document** (`<<VARS` ... `VARS`) feeds the lines between the markers to `cat`, which writes them to the file. Unquoted `VARS` means `$PREFIX` and `$TAG` are replaced first.

### A guarded dangerous action

`scripts/teardown.sh`

```bash
read -r -p "Delete project $PROJECT_ID? Type the project id to confirm: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "not confirmed"; exit 1; }

if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  BUDGET="$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --filter="displayName:$PROJECT_ID-budget" --format='value(name)')"
  [[ -z "$BUDGET" ]] || gcloud billing budgets delete "$BUDGET"
fi
gcloud projects delete "$PROJECT_ID" --quiet
```

`read -r -p "prompt" answer` waits for you to type; `-r` keeps backslashes literal. The `[[ ... ]] || { echo ...; exit 1; }` line exits unless you typed the exact project id.

### The local demo

`scripts/local-demo.sh`

```bash
RUN="demo-$(date +%s)"

health="$(curl -fsS "$API/health")"
echo "health: $health"
[[ "$health" == '{"db_password_set":true}' ]] || { echo "the API did not receive its secret" >&2; exit 1; }

for n in 1 2; do
  reply="$(curl -fsS -X POST "$API/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$RUN-$n\"}")"
  echo "upload $RUN-$n: $reply"
done

files=""
for _ in $(seq 1 60); do
  files="$(curl -fsS "$GCS/storage/v1/b/local-results/o" | python3 -c 'import json,sys; print(" ".join(sorted(i["name"] for i in json.load(sys.stdin).get("items", []))))')"
  [[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] && break
  sleep 1
done
echo "results in gs://local-results: $files"
[[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] || { echo "the worker did not write both results" >&2; exit 1; }
```

`for _ in $(seq 1 60)` retries up to sixty times; `seq 1 60` prints numbers 1 to 60 and `_` is a throwaway variable name. `curl -fsS` fails on HTTP errors (`-f`), stays quiet (`-s`) but shows errors (`-S`). The Python one-liner reads JSON from the pipe and prints the object names sorted. `[[ "$files" == *"results/$RUN-1.txt"* ]]` is a pattern match: the text must contain the file name.

## Every script, whole, in the order you run them

Words used in the scripts, explained once. A **comment** starts with `#`. The first line `#!/usr/bin/env bash` is the **shebang**: it tells the system which program runs the file. A script must be **executable** (`chmod +x`, already done) to be started as `scripts/deploy.sh`. A **variable in capitals** such as `ORG_ID` is by convention an environment variable or a constant. **Standard output** is where a program prints normal text, **standard error** is where it prints complaints (`>&2` sends text there). An **exit status** is the number a program returns: 0 means success.

Every script except `local-demo.sh` starts with `source "$(dirname "$0")/lib.sh"`. `$0` is the path the script was started with, `dirname` takes its folder, `$(...)` substitutes the result, and `source` runs `lib.sh` as if its lines were written here. The comment above it, `# shellcheck source=lib.sh`, tells the linter which file `source` loads.

### `scripts/lib.sh`

`scripts/lib.sh`

```bash
#!/usr/bin/env bash
# Shared by the runbook scripts: loads .env and sets the variables the lesson uses in every command.
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT/infra/environments/sandbox"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"
REGION="${REGION:-europe-west1}"
BUCKET="$PROJECT_ID-results"
API_SA="api-sa@$PROJECT_ID.iam.gserviceaccount.com"
WORKER_SA="worker-sa@$PROJECT_ID.iam.gserviceaccount.com"
INVOKER_SA="pubsub-invoker@$PROJECT_ID.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID" --quiet >/dev/null

api_url() { gcloud run services describe api --region="$REGION" --format='value(status.url)'; }
worker_url() { gcloud run services describe worker --region="$REGION" --format='value(status.url)'; }

# check "what is proved" command...: runs the command and prints PASS or FAIL for the Done when line it proves.
check() {
  local what="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $what"
  else
    echo "FAIL  $what"
    FAILED=1
  fi
}
FAILED=0
```

- `set -euo pipefail`, `ROOT=...`, the `.env` loading and `: "${PROJECT_ID:?...}"` were explained above. `REGION="${REGION:-europe-west1}"` is the variable or a default.
- `BUCKET`, `API_SA`, `WORKER_SA`, `INVOKER_SA` build the names of the lesson's resources. `gcloud config set project "$PROJECT_ID" --quiet >/dev/null` points every later `gcloud` call at the sandbox project, silently.
- `api_url() { gcloud run services describe api ... --format='value(status.url)'; }` is a one-line **function**: a named group of commands you can call like a command. `--format='value(status.url)'` prints only the service's URL.
- `check` takes a description, then `shift` removes that first argument so `"$@"` is the command to run, each word kept intact. `local` makes the variable private to the function. `if "$@" >/dev/null 2>&1; then` runs it silently and branches on its exit status; `FAILED=1` records a failure.

### `scripts/create-project.sh`: step 1, first half

`scripts/create-project.sh`

```bash
#!/usr/bin/env bash
# Step 1, first half: create the project, link billing, and write the Terraform variables file.
# The budget and the key-creation policy are Terraform (modules/project-baseline).
# Needs BILLING_ACCOUNT (and optionally ORG_ID) in .env.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT in .env (gcloud billing accounts list)}"

gcloud projects create "$PROJECT_ID" ${ORG_ID:+--organization="$ORG_ID"} --labels=purpose=sandbox
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

cat >"$ENV_DIR/sandbox.tfvars" <<VARS
project_id                      = "$PROJECT_ID"
project_number                  = "$PROJECT_NUMBER"
region                          = "$REGION"
billing_account                 = "$BILLING_ACCOUNT"
budget_amount                   = ${BUDGET_AMOUNT:-10}
enforce_no_service_account_keys = $([[ -n "${ORG_ID:-}" ]] && echo true || echo false)
VARS
echo "wrote $ENV_DIR/sandbox.tfvars"
```

`${ORG_ID:+--organization="$ORG_ID"}` expands to the flag only when `ORG_ID` is set (`:+` means "use this if the variable is non-empty"). The project number is read back with `--format='value(projectNumber)'`. The **here-document** `<<VARS ... VARS` writes `sandbox.tfvars` with the values substituted; inside it `${BUDGET_AMOUNT:-10}` is the variable or 10, and `$([[ -n "${ORG_ID:-}" ]] && echo true || echo false)` prints `true` when an organization is set and `false` otherwise (`-n` tests "not empty"; `&&` runs the next command if the first succeeded, `||` if it failed).

### `scripts/build-images.sh`: build and push the two images

`scripts/build-images.sh`

```bash
#!/usr/bin/env bash
# Build both images for linux/amd64 (Cloud Run's platform, also on an Apple-silicon Mac), push them to Artifact Registry
# and write the image names where Terraform reads them. Tags are unique because the repository's tags are immutable.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

PREFIX="$REGION-docker.pkg.dev/$PROJECT_ID/uploads"
TAG="$(date -u +%Y%m%d%H%M%S)"

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
for target in api worker; do
  docker build --platform linux/amd64 --target "$target" -t "$PREFIX/$target:$TAG" "$ROOT"
  docker push "$PREFIX/$target:$TAG"
done

cat >"$ENV_DIR/images.auto.tfvars" <<VARS
api_image    = "$PREFIX/api:$TAG"
worker_image = "$PREFIX/worker:$TAG"
VARS
echo "wrote $ENV_DIR/images.auto.tfvars"
```

`TAG="$(date -u +%Y%m%d%H%M%S)"` is the current UTC time as digits, a unique tag each run (the repository's tags are immutable). `gcloud auth configure-docker HOST` lets Docker log in to Artifact Registry. The `for target in api worker; do ... done` loop builds each stage of the Dockerfile (`--target`) for the platform Cloud Run uses (`--platform linux/amd64`, also on an Apple-silicon Mac), then pushes it (see `docker.md`). The here-document writes `images.auto.tfvars`; Terraform loads any file ending in `.auto.tfvars` by itself.

### `scripts/deploy.sh`: steps 2 to 4, in two passes

`scripts/deploy.sh`

```bash
#!/usr/bin/env bash
# Steps 2-4 in two Terraform passes: (1) everything, with Google's placeholder image so Cloud Run can start;
# (2) the same configuration with your two images. Terraform asks for confirmation before each apply.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# The database password is a throwaway. It is written to Secret Manager as a write-only value and never kept in state.
TF_VAR_db_password="${TF_VAR_db_password:-$(openssl rand -base64 18)}"
export TF_VAR_db_password

cd "$ENV_DIR" || exit 1
rm -f images.auto.tfvars
terraform init
terraform apply -var-file=sandbox.tfvars

"$ROOT/scripts/build-images.sh"
terraform apply -var-file=sandbox.tfvars

terraform output
```

`TF_VAR_db_password="${TF_VAR_db_password:-$(openssl rand -base64 18)}"` keeps a value you already set or makes a random throwaway one (`openssl rand -base64 18` prints 18 random bytes as text); `export` makes it an environment variable so Terraform sees it (any variable `TF_VAR_name` fills the Terraform variable `name`). `cd "$ENV_DIR" || exit 1` stops if the folder is missing. `rm -f images.auto.tfvars` removes a leftover from an earlier run so the first pass uses the placeholder image. Pass one applies everything with Google's placeholder image so Cloud Run can start; `build-images.sh` then builds and writes the image names; pass two applies again with your images.

### `scripts/prove.sh`: the checks for steps 1 to 4

`scripts/prove.sh`

```bash
#!/usr/bin/env bash
# Done when lines of steps 1-4, one check each. Exit status 1 if any check fails.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
API_URL="$(api_url)"
WORKER_URL="$(worker_url)"
NAME="report-$(date +%s)"

echo "== Step 1: budget and keys"
if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  check "a budget exists on the billing account" test -n "$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --filter="displayName:$PROJECT_ID-budget" --format='value(name)')"
fi
# Must be refused. Without an organization the constraint is not enforced; then the rule is "never create a key".
if gcloud iam service-accounts keys create /dev/null --iam-account="$API_SA" 2>/dev/null; then
  echo "FAIL  a key was created: delete it with 'gcloud iam service-accounts keys delete' and enable the policy"
  FAILED=1
else
  echo "PASS  creating a service account key is refused"
fi

echo "== Step 2: one identity each, no project-level role"
for account in "$API_SA" "$WORKER_SA" "$INVOKER_SA"; do
  check "$account holds no project-level role" test -z "$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$account" --format='value(bindings.role)')"
done
check "the topic lists only the API account as publisher" test "$(gcloud pubsub topics get-iam-policy uploads --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the secret lists only the API account" test "$(gcloud secrets get-iam-policy db-password --flatten='bindings[].members' --format='value(bindings.members)')" = "serviceAccount:$API_SA"
check "the bucket lists only the worker account as object creator" test "$(gcloud storage buckets get-iam-policy "gs://$BUCKET" --flatten='bindings[].members' --filter='bindings.role:roles/storage.objectCreator' --format='value(bindings.members)')" = "serviceAccount:$WORKER_SA"

echo "== Step 3: the API"
check "the API runs as api-sa, not the default account" test "$(gcloud run services describe api --region="$REGION" --format='value(spec.template.spec.serviceAccountName)')" = "$API_SA"
check "/health reports the secret is set" test "$(curl -fsS "$API_URL/health")" = '{"db_password_set":true}'
check "POST /upload publishes a message" bash -c "curl -fsS -X POST '$API_URL/upload' -H 'Content-Type: application/json' -d '{\"name\":\"$NAME\"}' | grep -q published"

echo "== Step 4: the worker"
check "the worker runs as worker-sa" test "$(gcloud run services describe worker --region="$REGION" --format='value(spec.template.spec.serviceAccountName)')" = "$WORKER_SA"
check "a direct call to the worker without a token returns 403" test "$(curl -s -o /dev/null -w '%{http_code}' "$WORKER_URL")" = "403"
check "the upload produced results/$NAME.txt" bash -c "for _ in \$(seq 1 30); do gcloud storage ls 'gs://$BUCKET/results/$NAME.txt' && exit 0; sleep 2; done; exit 1"

echo "(project number $PROJECT_NUMBER)"
exit "$FAILED"
```

- Each `check "what is proved" command...` prints PASS or FAIL. `test -n "..."` succeeds if the text is not empty, `test -z "..."` if it is empty, `test A = B` if two texts are equal.
- Step 1: a budget exists (listed with `--filter="displayName:..."`); creating a key is refused (the command must fail; `2>/dev/null` hides its message, `/dev/null` is a file that discards everything written to it).
- Step 2: for each of the three accounts, `get-iam-policy --flatten='bindings[].members' --filter=... --format='value(bindings.role)'` turns the project's policy into one line per member and keeps the lines for that account; the output must be empty. Then the topic, the secret and the bucket must list exactly the expected account.
- Step 3: the API runs as `api-sa`; `curl -fsS URL` fetches a web address (`-f` fail on an HTTP error, `-s` quiet, `-S` but show errors) and `/health` must answer exactly `{"db_password_set":true}`; a POST to `/upload` (`-X POST`, `-H` a header, `-d` the body) must answer something containing `published`. `bash -c "..."` runs a string as a small script because `check` needs one command, and `\"` keeps a quote for the inner shell.
- Step 4: the worker runs as `worker-sa`; a direct call without a token must give HTTP 403 (`-o /dev/null -w '%{http_code}'` throws the body away and prints only the status code); the result file must appear: the loop `for _ in $(seq 1 30)` tries up to 30 times, `sleep 2` between tries, `exit 0` on the first success.
- The last lines print the project number and `exit "$FAILED"` reports the verdict.

### `scripts/break-permission.sh`: step 5

`scripts/break-permission.sh`

```bash
#!/usr/bin/env bash
# Step 5: remove the worker's bucket role and send a request. Wait about a minute for the removal to apply first.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
NAME="${1:-report-2}"

gcloud storage buckets remove-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$WORKER_SA" --role=roles/storage.objectCreator
echo "waiting 60 seconds for the removal to apply"
sleep 60
curl -fsS -X POST "$(api_url)/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$NAME\"}"
echo
echo "Pub/Sub now retries with backoff and dead-letters the message after 5 attempts. Run scripts/read-denial.sh in a few minutes."
```

`NAME="${1:-report-2}"` takes the first argument or `report-2`. It removes the worker's bucket role, waits 60 seconds (there is no signal to poll), then posts an upload; the message will now fail in the worker, be retried, and be dead-lettered after 5 attempts.

### `scripts/read-denial.sh`: step 5's evidence

`scripts/read-denial.sh`

```bash
#!/usr/bin/env bash
# Step 5, the evidence: the permission-denied entry in the worker's log, and the message in the dead-letter subscription.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

echo "== the denial in the worker's log (account, permission, resource)"
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="worker" AND severity>=ERROR' \
  --limit=5 --freshness=1h --format='value(jsonPayload.error)'

echo "== the message in the dead-letter subscription (source subscription and delivery attempts)"
gcloud pubsub subscriptions pull uploads-dead-pull --limit=1 \
  --format='value(message.attributes.CloudPubSubDeadLetterSourceSubscription, message.deliveryAttempt, message.data)'
echo "(not acknowledged here, so scripts/restore-and-replay.sh can still read it)"
```

The first command reads the worker's error logs (`severity>=ERROR`) and prints the `error` field our logger wrote, which names the account, the permission and the resource. The second pulls (reads) one message from the dead-letter subscription without acknowledging it, printing the source subscription, the delivery attempts and the data.

### `scripts/restore-and-replay.sh`: step 6

`scripts/restore-and-replay.sh`

```bash
#!/usr/bin/env bash
# Step 6: put the role back (Terraform owns it), then replay the dead-lettered message by publishing its payload again.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$WORKER_SA" --role=roles/storage.objectCreator
echo "waiting 60 seconds for the grant to apply"
sleep 60

DATA="$(gcloud pubsub subscriptions pull uploads-dead-pull --auto-ack --limit=1 --format='value(message.data)')"
: "${DATA:?no message in the dead-letter subscription}"
# The CLI prints the payload decoded; publish it again to the main topic.
gcloud pubsub topics publish uploads --message="$DATA"
sleep 15
gcloud storage ls "gs://$BUCKET/results/"
```

Puts the role back, waits, pulls the dead-lettered message with `--auto-ack` (acknowledge it, so it is removed from the subscription), checks it is not empty (`: "${DATA:?...}"`), publishes the payload again to the main topic, waits 15 seconds and lists the results.

### `scripts/teardown.sh`: the end

`scripts/teardown.sh`

```bash
#!/usr/bin/env bash
# Step 6, the end: delete the project. Deletion takes 30 days to complete and can be undone in that time
# (gcloud projects undelete). A budget lives on the billing account, outside the project: delete it too.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

read -r -p "Delete project $PROJECT_ID? Type the project id to confirm: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "not confirmed"; exit 1; }

if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  BUDGET="$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --filter="displayName:$PROJECT_ID-budget" --format='value(name)')"
  [[ -z "$BUDGET" ]] || gcloud billing budgets delete "$BUDGET"
fi
gcloud projects delete "$PROJECT_ID" --quiet
gcloud projects describe "$PROJECT_ID" --format='value(lifecycleState)'   # DELETE_REQUESTED
```

The typed project id is the confirmation. A budget lives on the billing account, outside the project, so it is deleted first (`[[ -z "$BUDGET" ]] || gcloud ...` means: if there is no budget, do nothing, otherwise delete it). Then the project is deleted and its state printed (`DELETE_REQUESTED`).

### `scripts/local-demo.sh`: the lesson on your own machine

`scripts/local-demo.sh`

```bash
#!/usr/bin/env bash
# The lesson's flow on this machine: upload twice through the local API, let the emulator push to the worker,
# and list the result files in the fake bucket. Start the stack first with `make up`.
# Names carry the time of the run, so a file left by an earlier run can never satisfy this one.
set -euo pipefail

API=http://localhost:8080
GCS=http://localhost:4443
RUN="demo-$(date +%s)"

health="$(curl -fsS "$API/health")"
echo "health: $health"
[[ "$health" == '{"db_password_set":true}' ]] || { echo "the API did not receive its secret" >&2; exit 1; }

for n in 1 2; do
  reply="$(curl -fsS -X POST "$API/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$RUN-$n\"}")"
  echo "upload $RUN-$n: $reply"
done

files=""
for _ in $(seq 1 60); do
  files="$(curl -fsS "$GCS/storage/v1/b/local-results/o" | python3 -c 'import json,sys; print(" ".join(sorted(i["name"] for i in json.load(sys.stdin).get("items", []))))')"
  [[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] && break
  sleep 1
done
echo "results in gs://local-results: $files"
[[ "$files" == *"results/$RUN-1.txt"* && "$files" == *"results/$RUN-2.txt"* ]] || { echo "the worker did not write both results" >&2; exit 1; }
```

It does not source `lib.sh`: no cloud is involved. `RUN="demo-$(date +%s)"` makes names that carry the time, so an old file cannot satisfy this run. It checks `/health`, posts two uploads to the local API, then polls the fake bucket's list endpoint up to 60 times, one second apart. The Python one-liner (`python3 -c '...'`) reads the JSON that the server returns on standard input (`-` of a pipe) and prints the sorted object names. `[[ "$files" == *"results/$RUN-1.txt"* && ... ]]` uses `*` as a wildcard: "contains this text". `>&2` sends a complaint to standard error.

### `.dockerignore`

`.dockerignore`

```text
.git
.venv
.github
infra
docs
tests
scripts
**/__pycache__
.pytest_cache
.mypy_cache
.ruff_cache
.coverage
.env
```

Lists what `docker build` must not copy into the build: the Git history, the virtual environment, the workflow files, the infrastructure code, the docs, the tests, the scripts, caches, and `.env` (private settings). Each line is a path or a pattern (`**/__pycache__` matches that folder at any depth). A smaller build context is faster, and nothing private can end up in an image.

## 6. Try it yourself

```bash
bash -n scripts/lib.sh && echo "syntax ok"
```
Expected: `syntax ok` (`-n` parses without running).

```bash
shellcheck scripts/*.sh && echo clean
```
Expected: `clean` (no output from shellcheck itself).

```bash
bash -c 'set -euo pipefail; echo before; false; echo after'; echo "exit=$?"
```
Expected: `before` then `exit=1`. `after` never prints, which is what `-e` does.

```bash
bash -c 'x=; : "${x:?x must be set}"' ; echo "exit=$?"
```
Expected: the message `x: x must be set` and a non-zero exit status (`exit=127` in Bash 5; the exact number differs between shells).

```bash
bash -c 'check() { local w="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $w"; else echo "FAIL  $w"; fi; }; check "a file exists" test -f Makefile; check "no such file" test -f nope'
```
Expected: `PASS  a file exists` then `FAIL  no such file`.

## 7. Mistakes people make

- **Unquoted variables** (`rm $DIR/*`) split on spaces and can delete the wrong thing. Quote everything.
- **No `set -euo pipefail`.** Scripts keep going after an error and report success.
- **Using `cd` without checking it worked.** Scripts here use `cd ... || exit 1`.
- **Parsing `ls` output.** Use globs and loops.
- **Putting secrets on the command line.** They show up in process lists. Secrets here travel in environment variables or files.
- **Relying on the current folder.** `lib.sh` computes `ROOT` from the script's own path.

## 8. Check yourself

1. What does `set -e` do? *Stops the script at the first failing command.*
2. What does `"$@"` mean in `check`? *All remaining arguments, each kept as one word.*
3. What does `${VAR:?msg}` do? *Stops with `msg` if `VAR` is empty or unset.*
4. What does `source lib.sh` do differently from running `./lib.sh`? *It runs in the current shell, so variables and functions stay available.*
5. What does `curl -o /dev/null -w '%{http_code}'` print? *Only the HTTP status code.*

## 9. Further reading

- GNU Bash manual (Bash 5.2; the scripts also run on macOS's 3.2): <https://www.gnu.org/software/bash/manual/bash.html>
- Shell parameter expansion (`:?`, `:-`): <https://www.gnu.org/software/bash/manual/bash.html#Shell-Parameter-Expansion>
- The set builtin (`-e`, `-u`, `pipefail`): <https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin>
- ShellCheck wiki: <https://www.shellcheck.net/wiki/>
