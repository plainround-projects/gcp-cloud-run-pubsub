# Mermaid diagrams

## 1. What it is

Mermaid is a small language for drawing diagrams with text. You write boxes and arrows as lines of text inside a Markdown code block marked `mermaid`, and a renderer draws the picture. GitHub renders such blocks in README and other Markdown files automatically. The advantage over a picture file is that the diagram is text: it can be reviewed in a pull request, searched, and kept in step with the code.

## 2. Why this repository uses it

The lesson shows a diagram of the API, the topic, the worker and the bucket, and the repository rule says the lesson's diagram and `ARCHITECTURE.md` must agree on component names. The diagram in `ARCHITECTURE.md` is the repository's version: the client, the API, the secret, the topic, the worker, the bucket and the dead-letter path.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `ARCHITECTURE.md` | One `mermaid` block in the section "Data flow". |

## 4. How it works underneath

Nothing is installed or run in the repository. When a page is shown, the renderer in your browser (GitHub includes one) reads the block and draws SVG shapes. A diagram starts with its type and direction: `flowchart LR` is a flow chart laid out left to right (`TB` would be top to bottom). After that:

- `id["label"]` declares a node (a box). `id` is a short name used in the lines below; the text in quotes is shown. `<br/>` inside a label is a line break.
- `a --> b` draws an arrow from `a` to `b`. `a -->|text| b` puts text on the arrow. `a -. "text" .-> b` draws a dotted arrow with text.
- `subgraph name["title"] ... end` draws a box around the nodes listed inside.

## 5. Walkthrough of this repository's use

`ARCHITECTURE.md`

```mermaid
flowchart LR
    client([Client]) -->|1. POST /upload| api["API<br/>Cloud Run, api-sa"]
    secret[(Database password<br/>Secret Manager)] -.->|at start-up, api-sa| api
    api -->|2. publish| topic[[Pub/Sub topic<br/>uploads]]
    topic -->|3. push + OIDC token<br/>pubsub-invoker| worker["Worker<br/>Cloud Run, worker-sa<br/>private"]
    worker -->|4. create if absent| bucket[(Results bucket<br/>results/NAME.txt)]
    topic -. "after 5 failed attempts" .-> dlt[[Dead-letter topic<br/>uploads-dead]]
    dlt --> dlpull[/Pull subscription<br/>uploads-dead-pull/]
```

- `flowchart LR` sets the type and the direction: left to right.
- `client([Client])`: the shape `([ ])` is a **stadium** (a rounded pill), used for the outside caller. `api["API<br/>Cloud Run, api-sa"]` is a plain box.
- `secret[(Database password<br/>Secret Manager)]`: `[( )]` is a **cylinder**, Mermaid's symbol for stored data. The dotted arrow `-.->|at start-up, api-sa|` shows the secret is read once, when the API starts.
- `api -->|2. publish| topic[[Pub/Sub topic<br/>uploads]]`: `[[ ]]` is a box with double sides, used for the topic. The numbers in the arrow labels (1 to 4) are the order of the main path.
- `topic -->|3. push + OIDC token<br/>pubsub-invoker| worker[...]`: Pub/Sub pushes to the private worker with a signed token. `worker -->|4. create if absent| bucket[(...)]` writes the result.
- `topic -. "after 5 failed attempts" .-> dlt[[...]]` is a dotted arrow with text: the failure path to the dead-letter topic. `dlt --> dlpull[/Pull subscription<br/>uploads-dead-pull/]`: `[/ /]` is a parallelogram, used here for the subscription you read dead letters from.

## 6. Try it yourself

```bash
grep -n -A2 "^flowchart" ARCHITECTURE.md | cut -c1-60
```
Expected: the line number of `flowchart LR` and the next two lines, the `client(...)` node and the next one.

```bash
awk '/^flowchart/,/dlpull/' ARCHITECTURE.md | grep -c -- '-->'
```
Expected: `5`, the number of lines that contain a solid arrow.

Open `ARCHITECTURE.md` on GitHub (or in an editor with a Markdown preview that supports Mermaid) and look at the drawing; then change a label in a copy of the block and watch the picture change.

## 7. Mistakes people make

- **A label with special characters** (quotes, brackets) not wrapped in `"..."`.
- **Reusing a node id** for two different things; the second silently changes the first.
- **A diagram too big to read.** Split it; the steps are numbered in the labels.
- **A diagram that no longer matches the code.** The component names are checked by hand against the lesson's diagram when the repository is built.

## 8. Check yourself

1. How does a Mermaid block start? *Three backticks followed by the word `mermaid`.*
2. What does `TB` mean? *Top to bottom.*
3. How do you label an arrow? *`a -->|text| b`.*
4. What does `subgraph ... end` do? *Draws a box around the nodes inside.*
5. Why keep the diagram as text? *It can be reviewed and changed like code.*

## 9. Further reading

- Mermaid documentation, flowcharts: <https://mermaid.js.org/syntax/flowchart.html>
- GitHub: creating diagrams: <https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams>
