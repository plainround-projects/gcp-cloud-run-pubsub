# Small command-line tools used by the scripts: curl, grep, sed, seq, base64, openssl

## 1. What it is

These are small programs that ship with macOS and Linux. Each does one job; the shell connects them. **curl** sends HTTP requests. **grep** finds lines that match a pattern. **sed** edits text as it flows through. **seq** prints numbers. **base64** converts bytes to and from text. **openssl** is a toolbox of cryptography commands; here it only makes random bytes.

## 2. Why this repository uses it

The scripts and the Makefile stay short by using these tools: call the API, filter the help text, generate a throwaway password, retry a loop.

## 3. Where it appears

| Path | Tool and use |
| --- | --- |
| `scripts/local-demo.sh`, `prove.sh`, `break-permission.sh` | `curl` calls the API and the worker. |
| `Makefile` (`help`) | `grep` and `sed` build the target list. |
| `Makefile` (`up`) | `openssl rand -hex 12` makes the local throwaway password. |
| `scripts/local-demo.sh` | `seq 1 60` drives a retry loop. |
| `scripts/prove.sh` | `grep -q published` tests the API's reply. |

## 4. How it works underneath

Each tool reads **standard input** (text piped in or typed), writes **standard output**, and returns an **exit status** (0 means success; `grep` returns 1 when nothing matched). That is why they combine: `cmd1 | cmd2` sends the output of the first into the second.

## 5. Walkthrough of this repository's use

`scripts/local-demo.sh`

```bash
health="$(curl -fsS "$API/health")"
echo "health: $health"
[[ "$health" == '{"db_password_set":true}' ]] || { echo "the API did not receive its secret" >&2; exit 1; }

for n in 1 2; do
  reply="$(curl -fsS -X POST "$API/upload" -H 'Content-Type: application/json' -d "{\"name\":\"$RUN-$n\"}")"
  echo "upload $RUN-$n: $reply"
```

- `curl -fsS URL` fetches a URL. `-f` fails (non-zero exit) on an HTTP error status; `-s` hides the progress bar; `-S` still shows an error message when `-s` is on.
- `-X POST` chooses the HTTP method; `-H 'Content-Type: application/json'` adds a header; `-d '{"name":"..."}'` is the request body.
- `$(...)` captures the reply into a variable, which the script compares with the exact expected text.

From the Makefile:

`Makefile`

```make
help: ## list the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```

- `grep -E '^[a-z0-9-]+:.*## ' FILES` keeps lines that start with a target name, a colon, anything, then `## `. `-E` enables extended patterns (`+`, `.`, `[a-z]`).
- `sed -E 's/:.*## /\t/'` replaces the text from the first colon through `## ` with a tab. `s/old/new/` is substitute; `\t` is a tab.
- `sort` orders the lines alphabetically.

From the Makefile's `up`:

`Makefile`

```make
	DB_PASSWORD=$$(openssl rand -hex 12) $(COMPOSE) --profile apps up -d --build --wait --wait-timeout 900
```

`openssl rand -hex 12` prints 12 random bytes as 24 hexadecimal characters, a fresh password for every start. The variable is set only for that one command, so it is not stored anywhere.

From `prove.sh`: `curl ... | grep -q published` — `-q` (quiet) prints nothing and only sets the exit status; the check passes if the reply contains the word.

## 6. Try it yourself

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://www.google.com/generate_204
```
Expected: `204` (needs internet; `-w` prints the status).

```bash
printf 'a\nb\n' | grep -c b
```
Expected: `1`.

```bash
echo 'build: ## compile' | sed -E 's/:.*## /\t/'
```
Expected: `build<TAB>compile` (a tab between the two words).

```bash
seq 1 3
```
Expected: `1`, `2`, `3` on separate lines.

```bash
openssl rand -hex 12
```
Expected: 24 random hexadecimal characters, different each time.

```bash
echo -n 'hello' | base64 && echo 'aGVsbG8=' | base64 -d; echo
```
Expected: `aGVsbG8=` then `hello`.

## 7. Mistakes people make

- **`grep` returning 1 and `set -e` stopping the script.** In a condition (`if grep -q ...`) that is intended; elsewhere add `|| true` deliberately.
- **`sed -i` differs between macOS and Linux.** On macOS `sed -i ''` is required; the scripts avoid in-place edits.
- **`curl` without `-f`.** It exits 0 even on a 500 reply.
- **Using these for secrets on the command line.** The password above lives in an environment variable for one command.
- **`echo` adds a newline.** Use `echo -n` or `printf` when exact bytes matter (base64 of the message).

## 8. Check yourself

1. What does `curl -f` change? *It fails on HTTP error statuses.*
2. What does `grep -q` print? *Nothing; only the exit status.*
3. What does `openssl rand -hex 12` output? *24 hexadecimal characters.*
4. What does the pipe `|` connect? *One program's output to the next program's input.*
5. Why is `echo -n` used before `base64`? *To avoid encoding an extra newline.*

## 9. Further reading

- curl: <https://curl.se/docs/manpage.html>
- GNU grep: <https://www.gnu.org/software/grep/manual/grep.html>
- GNU sed: <https://www.gnu.org/software/sed/manual/sed.html>
- OpenSSL `rand`: <https://docs.openssl.org/master/man1/openssl-rand/>
