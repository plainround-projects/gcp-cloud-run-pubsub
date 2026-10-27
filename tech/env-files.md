# `.env` files (environment variables from a file)

## 1. What it is

An **environment variable** is a named piece of text that the system hands to every program a shell starts, like a note stuck to the program: `ORG_ID=123456789012`. Programs read them to learn settings without the settings being written into their code. A **`.env` file** is a plain text file of `NAME=value` lines that holds such settings for one project, so you do not have to type them each time. The convention is: the real file `.env` is private and never committed; a template `.env.example` with placeholder values is committed so a newcomer knows which names to fill in.

## 2. Why this repository uses it

The scripts need your project id, your billing account and a few optional settings. These are personal, differ per person, and must not be in the repository. A `.env` file keeps them out of the code and out of Git, and every script and the Makefile read the same file.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `.env.example` | The committed template: the names to set, with example values. |
| `.env` | Your private copy (not in the repository; `.gitignore` excludes it). |
| `.gitignore` | The line `.env` keeps the private file out of Git. |
| `scripts/lib.sh` | Loads `.env` into every runbook script. |
| `Makefile` | `-include .env` and `export` pass the values to the commands `make` starts. |

## 4. How it works underneath

A running program has a table of environment variables, copied from its parent when it starts. A shell variable that is not **exported** stays inside the shell; an exported one is copied to every child. `set -a` in Bash means "export everything assigned from now on", so `source .env` inside `set -a` ... `set +a` exports every line of the file. `source` runs the file's lines as if they were typed, which is why the values must follow Bash rules: no spaces around `=`, and quotes around anything with a space.

`make` has its own syntax but `NAME=value` is valid in both, so one file serves both programs. `-include` means "read this file if it exists, and do not complain if it does not".

Anything in the file is plain text on disk. That is why it holds no passwords or keys in this repository: only identifiers (a project id, a billing account id). If a file like this ever held a secret, it must be listed in `.gitignore` before the first commit, and a secret that was committed once must be treated as leaked.

## 5. Walkthrough of this repository's use

How the scripts load it:

`scripts/lib.sh`

```bash
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"
```

- `[[ -f "$ROOT/.env" ]]` is true if the file exists. Inside, `set -a`, `source "$ROOT/.env"` and `set +a` load and export everything.
- `: "${PROJECT_ID:?set PROJECT_ID in .env (see .env.example)}"` stops the script with that message if the variable is still empty after loading. A missing setting fails early and says where to put it.

The variables the scripts read, and which script needs which:

| Name | Needed by | Meaning |
| --- | --- | --- |
| `PROJECT_ID` | every cloud script (`lib.sh`) | The sandbox project's id. |
| `BILLING_ACCOUNT` | `create-project.sh`; `prove.sh` and `teardown.sh` (optional) | The billing account id (`gcloud billing accounts list`); when set, the budget is checked and deleted too. |
| `ORG_ID` | `create-project.sh` (optional) | The organization to create the project under; when set, the key-creation policy is enforced. |
| `REGION` | scripts (optional) | Defaults to `europe-west1`. |
| `BUDGET_AMOUNT` | `create-project.sh` (optional) | Budget in whole units; defaults to 10. |
| `TF_VAR_db_password` | `deploy.sh` (optional) | The throwaway password; if unset the script makes a random one. |

The Docker Compose file also reads `DB_PASSWORD` from the environment: `make up` sets it to a random value for that one command.

And the Makefile:

`Makefile`

```make
-include .env
export
```

The `export` line without a name exports every variable `make` knows to the commands it starts.

## 6. Try it yourself

```bash
git check-ignore -v .env
```
Expected: a line naming `.gitignore` and the rule `.env`: the private file would be ignored.

```bash
git ls-files | grep -c '^\.env'
```
Expected: `1`. Only the template is tracked.

```bash
env -u PROJECT_ID bash -c 'source scripts/lib.sh'; echo "exit=$?"
```
Expected: `scripts/lib.sh: line 16: PROJECT_ID: set PROJECT_ID in .env (see .env.example)` and `exit=1` (this works when you have no `.env`; with one, its values are loaded first).

```bash
bash -c 'set -a; X=1; set +a; Y=2; bash -c "echo X=\$X Y=\$Y"'
```
Expected: `X=1 Y=`. `X` was exported by `set -a`; `Y` was not, so the child shell does not see it.

## 7. Mistakes people make

- **Committing the real file.** `.gitignore` has `.env` for that reason; check with `git status` before every commit.
- **Spaces around `=`** (`PROJECT_ID = demo`). Bash reads that as a command called `PROJECT_ID`.
- **Forgetting to quote a value with a space.**
- **Putting secrets in it** "just for now". Nothing here needs one.
- **Expecting a change in `.env` to reach an already running program.** Variables are copied at start; run the script again.
- **Editing the template and forgetting the real file.** The template is only a guide; the scripts read `.env`.

## 8. Check yourself

1. What is an environment variable? *A named text the system hands to a program when it starts.*
2. What does `set -a` do? *Exports every variable assigned afterwards.*
3. Why is `.env` in `.gitignore` and `.env.example` not? *The real file is private; the template shows the names.*
4. What does `: "${PROJECT_ID:?message}"` do? *Stops with the message if the variable is empty.*
5. Why does one file serve both Bash and make? *`NAME=value` is valid in both.*

## 9. Further reading

- Bash `set` builtin (`-a`): <https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin>
- GNU make, `include`: <https://www.gnu.org/software/make/manual/make.html#Include>
- Environment variables in the Bash manual: <https://www.gnu.org/software/bash/manual/bash.html#Environment>
