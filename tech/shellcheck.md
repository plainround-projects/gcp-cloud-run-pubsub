# ShellCheck

## 1. What it is

ShellCheck is a **linter for shell scripts**: it reads `.sh` files and reports bugs and bad habits without running them (an unquoted variable, a command that may not run, a `cd` that is not checked). Each finding has a code such as `SC2086`.

## 2. Why this repository uses it

The runbook scripts are the commands a person runs against real cloud projects. A subtle shell mistake (an unquoted variable that splits on a space) can do the wrong thing there, so the scripts are linted on every `make lint`.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `.shellcheckrc` | Tells ShellCheck to follow `source` lines and where to look for them. |
| `Makefile` | `make lint-python` runs `shellcheck scripts/*.sh`. |
| `scripts/*.sh` | The checked files; a few carry `# shellcheck ...` comments (directives). |

## 4. How it works underneath

ShellCheck parses the script into a syntax tree and applies rules. It cannot know the value of a variable that is computed at run time, so for `source "$(dirname "$0")/lib.sh"` it needs to be told where the file really is. A comment `# shellcheck source=lib.sh` placed on the line above says so; `.shellcheckrc` makes the search relative to each script's own folder (`SCRIPTDIR`).

## 5. Walkthrough of this repository's use

`.shellcheckrc`

```ini
external-sources=true
source-path=SCRIPTDIR
```

- `external-sources=true` lets ShellCheck read files that a script `source`s.
- `source-path=SCRIPTDIR` looks for them relative to the script that names them.

Examples of directives in the scripts:

```bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
```
tells it which file is being sourced, and

```bash
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
```
(in `lib.sh`) accepts the warning "variable appears unused" because other scripts use those variables. A `disable` always carries its reason in the comment next to it.

## 6. Try it yourself

```bash
shellcheck scripts/*.sh && echo clean
```
Expected: `clean`.

```bash
printf '#!/usr/bin/env bash\nrm -rf $DIR/*\n' > /tmp/bad.sh && shellcheck /tmp/bad.sh; rm -f /tmp/bad.sh
```
Expected: findings such as `SC2086 (info): Double quote to prevent globbing and word splitting` for `$DIR`.

```bash
shellcheck --version | head -2
```
Expected: `ShellCheck - shell script analysis tool` and a version number (0.9 or newer is fine).

## 7. Mistakes people make

- **Disabling a warning without a reason.** Always say why next to the directive.
- **Ignoring "info" level findings.** They are often real bugs (quoting).
- **Linting only some scripts.** The Makefile uses a glob so new scripts are covered.
- **Assuming ShellCheck runs the script.** It only reads it.

## 8. Check yourself

1. Does ShellCheck run your script? *No; it analyzes the text.*
2. Why `# shellcheck source=lib.sh`? *The sourced path is computed at run time, so it names the file.*
3. What does `SC2086` warn about? *An unquoted variable that can split or expand.*
4. What does `SCRIPTDIR` mean in `source-path`? *The folder containing the script being checked.*
5. Where is the check run in this repository? *In `make lint-python`, and therefore in CI.*

## 9. Further reading

- ShellCheck wiki: <https://www.shellcheck.net/wiki/>
- Directives: <https://github.com/koalaman/shellcheck/wiki/Directive>
