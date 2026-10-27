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
