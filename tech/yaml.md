# YAML

## 1. What it is

YAML is a plain-text format for structured data, designed to be easy for people to read. It has three building blocks: **mappings** (`key: value` pairs), **sequences** (lists, one `- item` per line) and **scalars** (text, numbers, `true`/`false`). **Indentation with spaces** shows nesting; tabs are not allowed. Lines starting with `#` are comments.

## 2. Why this repository uses it

Two tools take their instructions in YAML: Docker Compose (the local stack) and GitHub Actions (CI). The checkov scan configuration is YAML too.

## 3. Where it appears

| Path | What it holds |
| --- | --- |
| `docker-compose.yml` | The local services (see `docker-compose.md`). |
| `.github/workflows/ci.yml` | The CI jobs (see `github-actions.md`). |
| `.checkov.yaml` | Which scanners to run (see `checkov.md`). |

## 4. How it works underneath

A program reads the text and builds data in memory: a mapping becomes a dictionary, a sequence becomes a list. The indentation is the structure, so one wrong space changes the meaning. Two traps: YAML parsers guess types (in older YAML rules `no`, `yes` and `on` become booleans and `8085:8085` can become a number), and a value that contains `: ` or begins with `*` or `{` needs quotes.

Inline forms exist too: `[a, b]` is a list and `{x: 1}` a mapping on one line. A `|` after a key starts a block of literal lines (used for multi-line shell commands).

## 5. Walkthrough of this repository's use

The Compose file's skeleton:

`docker-compose.yml`

```yaml
services:
  pubsub:
    image: gcr.io/google.com/cloudsdktool/google-cloud-cli:590.0.1-emulators
    command: gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 --project=local-project
    ports:
      - "8085:8085"
    # Lets the emulator push to a worker running on the host (the end-to-end tests do that).
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
```

- `services:` is a mapping. Its keys (`pubsub`, `gcs`, ...) are names the user chooses.
- `image:` is a scalar. `command:` here is one string; in `gcs` it is a list: `["-scheme", "http", ...]`, each item one program argument.
- `ports:` is a sequence of strings: `- "8085:8085"`. The quotes matter: unquoted `8085:8085` could be read as a number in base 60 by old YAML rules.
- `healthcheck:` is a nested mapping (indent two more spaces). Its `test:` is a list whose first item (`CMD`) tells Docker how to run the rest.

The workflow's skeleton:

`.github/workflows/ci.yml`

```yaml
jobs:
  python:
    name: Format, lint, types, import rules, unit tests with coverage, dependency audit
    runs-on: ubuntu-latest
    steps:
```

`python:` is a job name (a key). Under `steps:` each item begins with `- ` and is a mapping (`uses:`, `with:` or `run:`).

The scanner config uses a list for each key, for example `framework:` followed by `- terraform`.

## 6. Try it yourself

```bash
docker compose config --services
```
Expected (Docker parses the file; no container starts): the two always-on services, `gcs` and `pubsub`.

```bash
docker compose --profile apps config --services
```
Expected: four names (`pubsub`, `api`, `gcs`, `worker`): the profile adds the two application services.

```bash
docker compose config --quiet && echo "compose parses"
```
Expected: `compose parses`.

```bash
actionlint .github/workflows/ci.yml && echo "workflow parses"
```
Expected: `workflow parses`.

## 7. Mistakes people make

- **Tabs for indentation.** Not allowed.
- **Inconsistent indentation** moving a key to the wrong parent.
- **Unquoted special values** (`yes`, `no`, `1.10`, `8085:8085`, version numbers). Quote them.
- **Forgetting the space after the colon** (`key:value` is a plain string).
- **Confusing a string with a list** (`command: a b` vs `command: [a, b]`). Check what the tool expects.

## 8. Check yourself

1. What shows nesting in YAML? *Indentation with spaces.*
2. How do you write a list item? *A line starting with `- `.*
3. Why quote `"8085:8085"`? *To make sure it is read as text.*
4. What is the difference between `command: a b` and `command: [a, b]`? *A single string versus a list of two arguments.*
5. How do you comment a line? *Start it with `#`.*

## 9. Further reading

- YAML 1.2 specification: <https://yaml.org/spec/1.2.2/>
- Compose file reference: <https://docs.docker.com/reference/compose-file/>
- Workflow syntax: <https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions>
