# Git (and .gitignore)

## 1. What it is

Git is a **version control** system: it records the history of a project as a chain of **commits**, each a snapshot with a message, an author and a date. A **repository** is the project folder plus its hidden `.git` history. A **branch** is a movable name for a line of commits (`main` here). `.gitignore` lists file patterns that Git must never track.

## 2. Why this repository uses it

Each project folder is its own repository so that it can be pushed to GitHub later as a separate project. The history shows the work in meaningful steps, and a clean working tree proves nothing was left out. Nothing here was pushed.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `.git/` | The history (created with `git init`). |
| `.gitignore` | Keeps build output, local state, the virtual environment and real settings files out of history. |
| `.github/workflows/ci.yml` | Runs on `push` and `pull_request` once the repository is on GitHub. |

## 4. How it works underneath

Git stores content as **objects** identified by a hash of their bytes. A commit points to a tree of files and to its parent commit. `git add` copies changes into the **index** (the staging area); `git commit` records the index as a new commit. `git status` compares the working folder, the index and the last commit. Files matching `.gitignore` are invisible to `git status` and `git add`, unless they were already tracked.

## 5. Walkthrough of this repository's use

`.gitignore`

```text
.venv/
__pycache__/
*.pyc
*.egg-info/
build/
dist/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.import_linter_cache/
.coverage
.env
.DS_Store
logs/
.omc/

# Terraform: providers, local state and the files that hold your project's values
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
crash.log
infra/modules/**/.terraform.lock.hcl
```

Read it in groups:

- Python leftovers: `.venv/`, `__pycache__/`, `*.pyc`, `*.egg-info/`, `build/`, `dist/`: generated, huge or machine-specific.
- Tool caches: `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, `.import_linter_cache/`, `.coverage`.
- `.env`: your real settings (the committed `.env.example` shows the names without values).
- `.DS_Store`, `logs/`, `.omc/`: operating-system and tool noise.
- Terraform: `.terraform/` (downloaded providers), `*.tfstate` (state can contain secrets), `*.tfvars` (your real values) but `!*.tfvars.example` keeps the examples; module lock files are ignored while the environment's `.terraform.lock.hcl` is tracked on purpose.

The `!` at the start of a pattern means "except this".

The history is built from semantic commit messages (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `build:`, `chore:`), each ending with a `Co-Authored-By` line.

## 6. Try it yourself

```bash
git log --oneline | head -5
```
Expected: the latest commit messages, newest first.

```bash
git status --short; echo "files: $(git status --short | wc -l)"
```
Expected: `files: 0` (a clean tree; nothing untracked).

```bash
git check-ignore -v .venv .env example.tfvars 2>/dev/null; git check-ignore -v infra/environments/*/.terraform.lock.hcl || echo "lock file is tracked"
```
Expected: lines showing which `.gitignore` rule matches each ignored path; the environment's lock file is *not* ignored.

```bash
git log --stat -1 | head -12
```
Expected: the last commit with the files it touched.

## 7. Mistakes people make

- **Committing secrets or state.** `.env`, `*.tfstate` and real `*.tfvars` are ignored.
- **Committing generated files** (`.venv`, caches). They bloat the history.
- **Ignoring the lock file.** Lock files must be committed so builds repeat.
- **Huge mixed commits.** Small commits with clear messages make the history readable.
- **Believing `.gitignore` removes a tracked file.** It only affects untracked ones.

## 8. Check yourself

1. What is a commit? *A recorded snapshot with a message and a parent.*
2. What does `git add` do? *Stages changes in the index.*
3. Why is `.env` ignored but `.env.example` tracked? *The first holds real values; the second shows the variable names.*
4. What does `!*.tfvars.example` mean? *Track this pattern even though `*.tfvars` is ignored.*
5. What shows a clean tree? *`git status --short` prints nothing.*

## 9. Further reading

- Pro Git book: <https://git-scm.com/book/en/v2>
- gitignore patterns: <https://git-scm.com/docs/gitignore>
