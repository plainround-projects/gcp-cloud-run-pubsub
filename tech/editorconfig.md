# EditorConfig

## 1. What it is

`.editorconfig` is a small settings file that most code editors read, so everyone who edits the project gets the same basic formatting: file encoding, line endings, tabs or spaces, and how wide an indent is. It is not a program; your editor (or a plug-in) applies it as you type.

## 2. Why this repository uses it

Different editors default to different habits, which causes noisy changes. One file at the root fixes the habits for every contributor. It also protects the one place where the character matters: a Makefile recipe line must start with a Tab.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `.editorconfig` | The settings for the whole repository. |

## 4. How it works underneath

When you open a file, the editor looks for `.editorconfig` in the file's folder and each parent folder. Sections in square brackets match file names with patterns. Later sections win over earlier ones. `root = true` stops the search at this file.

## 5. Walkthrough of this repository's use

`.editorconfig`

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{yml,yaml,json,toml}]
indent_size = 2

[Makefile]
indent_style = tab

[*.md]
trim_trailing_whitespace = false
```

- `root = true`: do not look in parent folders.
- `[*]` applies to every file. `charset = utf-8` fixes the text encoding. `end_of_line = lf` uses Unix line endings (no Windows `\r\n`). `insert_final_newline = true` ends each file with one blank line break, as Unix tools expect. `trim_trailing_whitespace = true` removes spaces at the end of lines. `indent_style = space` and `indent_size = 4` mean four spaces per level (Python's habit).
- `[*.{yml,yaml,json,toml}]` overrides the indent to two spaces for those formats.
- `[Makefile]` sets `indent_style = tab`: Make requires a Tab at the start of a recipe line.
- `[*.md]` turns off whitespace trimming, because two spaces at the end of a line mean "line break" in Markdown.

## 6. Try it yourself

```bash
head -8 .editorconfig
```
Expected: the first lines quoted above.

```bash
grep -c "$(printf '\t')" Makefile
```
Expected: a number greater than zero: the count of Makefile lines that contain a Tab (every recipe line starts with one).

```bash
file --mime-encoding Makefile README.md
```
Expected: `Makefile: us-ascii` and `README.md: utf-8` or `us-ascii` (ASCII is a subset of UTF-8).

## 7. Mistakes people make

- **Assuming the file enforces anything by itself.** The editor must support it.
- **Mixing tabs and spaces** in a Makefile or YAML. The file prevents this in editors that honor it.
- **Trimming whitespace in Markdown** and losing hard line breaks.

## 8. Check yourself

1. Which files must use tabs? *Makefiles.*
2. What does `root = true` do? *Stops the editor searching parent folders for more settings.*
3. Why is Markdown excluded from trimming? *Trailing double spaces are a line break.*
4. What indent do YAML files get? *Two spaces.*
5. Does `.editorconfig` check anything at commit time? *No; it only guides editors.*

## 9. Further reading

- EditorConfig: <https://editorconfig.org/>
- Supported properties: <https://spec.editorconfig.org/>
