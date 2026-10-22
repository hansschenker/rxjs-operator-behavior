# Diagram method

How a `diagrams/<operator>.md` and its `diagrams/<operator>.mmd` are derived
from the Mealy analysis in `operators/<operator>.md`. The analysis stays the
source of truth. The diagram file adds two views of its section C: a
state × input matrix that shows δ and λ together, and a Mermaid state diagram.
Worked examples: [diagrams/audit.md](../diagrams/audit.md) and
[diagrams/auditTime.md](../diagrams/auditTime.md).

## 1. Scaffold

```sh
scripts/new-diagram.sh <operator>
```

copies [diagram-template.md](diagram-template.md) to `diagrams/<operator>.md`
with `[operator]` filled in. It refuses to overwrite and requires
`operators/<operator>.md` to exist. Every remaining `[bracketed]` field is
yours to replace.

## 2. States

Take S from section B of the analysis.

- Keep the control states. Write stored data as a parameter: `Open(v)`,
  `Buffer(xs)`, `Waiting(n)`.
- Drop a location that section B itself describes as "represented as the
  transition" (audit's `IdleDone`). It is an edge, not a node.
- Merge two locations only if you can argue, input by input, that every input
  in Σ has the same next state and output from both. Write that argument as a
  Conventions bullet (audit's stale-`hasValue` `Idle`).
- `Stopped` is the single absorbing terminal state: error delivered, complete
  delivered, or cancelled.

The State legend maps each state to the variable values that define it, with
source line numbers.

## 3. Inputs

Take Σ from section B.

- One column per input marked "yes". Keep the analysis' names:
  `sourceNext(w)`, `durationNext`, `timerFired`, `innerComplete(id)`.
- Fold a user-callback outcome into the input that triggers it, as a guard
  inside the cell: `selector throws e: Stopped / error(e) · T13`.
- Keep an input that the analysis marks "yes but never delivered" as a column
  of `—` cells with a cell note. Such a column is often the visible difference
  between two operators (auditTime's `timerComplete`).
- Leave out inputs marked "no".

## 4. Fill the matrix

For every state × input cell write `next state / output · row`.

- Copy next state and notifications from the C row. Output order is delivery
  order. `none` is no downstream notification.
- A C row that names several states ("any non-terminal", "Open or Idle") fills
  every cell it names.
- A pair that C marks inapplicable gets `—` and the row ID.
- A pair that is reachable but has no C row: fill it from the source handler,
  mark it `†`, and explain it in Cell notes, naming the closest C row. Do not
  silently extend C. Examples: audit `OpenDone(v)` × `durationError(e)`,
  auditTime `OpenDone(v)` × `cancel`.
- The `Stopped` row is all `—` with the absorbing row ID.

## 5. Cell notes

One bullet per cell whose behavior is not obvious from the cell text: the
order of the handler's statements with line numbers, the guard and why it
passes or fails, why an inapplicable pair cannot occur. Always include a
`cancel` bullet (what is disposed, what is not run) and a bullet for every `†`
cell. Note same-instant tie assumptions where a scheduler is involved.

## 6. Diagram

Generate the diagram from the finished matrix, not the other way round.

- Group filled cells by (state, next state). One edge per pair. Stack the
  pair's transitions on the label with `<br>`, in column order of the table.
- Label format: `input [guard] / output · row`. No colons in labels; Mermaid
  uses the colon as the separator.
- `direction LR`. Declare states whose display name has parentheses with
  `state "Open(v)" as Open`.
- `[*] --> Idle : subscribe / none · T01` and `Stopped --> [*]`.
- One note on the state that carries the fact a reader must not miss; one note
  `Absorbing (Txx)` on `Stopped`.
- Lifecycle effects stay in the cell notes. The edge shows notifications only.

One edge per pair is a layout rule, not a modeling choice. One Mermaid edge per
transition made labels collide around states with self-loops in every layout
tried (left-right, top-down, composite states).

## 7. Coverage

Every C row must appear where the Coverage table says: initial edge, one or
more cells, `—` cells, or a note for rows that are not transitions
(parameter-domain rows such as auditTime's T13). List the `†` cells in the
last row.

## 8. Sync the .mmd

```sh
scripts/sync-mmd.sh <operator>   # write diagrams/<operator>.mmd from the block
scripts/sync-mmd.sh --check      # verify every .mmd equals its block
```

The markdown block is the source; the `.mmd` is a copy for tools. A diagram
file has exactly one ```` ```mermaid ```` block.

## 9. Render check

Paste the `.mmd` into <https://mermaid.live> or open it in a Mermaid preview
and confirm that it parses and no labels overlap. GitHub renders the block
natively after push. Verified on Mermaid 11: parentheses, brackets, `·`, `=`
and `,` are safe in labels; `<br>` makes a line break.

## 10. Link and commit

- Add `Companion: [state transition diagram and table](../diagrams/<operator>.md).`
  as its own paragraph after the intro paragraph of `operators/<operator>.md`.
- Add the operator to the `diagrams/` row of the README.
- Commit: `docs: add state transition diagram and table for <operator>`.

## Done criteria

- Every `[bracketed]` field replaced.
- Every C row in the Coverage table.
- Every `†` cell has a note.
- `scripts/sync-mmd.sh --check` passes.
- Diagram rendered once without overlapping labels.
- Companion link and README row added.

## GitHub quirks

Verified 2026-10-22 on the rendered pages of this repository.

- The "Copy mermaid code" button on a rendered diagram does not copy. Use the
  Code tab of the `.md` file, or the Raw button.
- A `.mmd` file is rendered. Its Code and Blame tabs are empty and `?plain=1`
  is ignored. The Raw button and the pencil (Edit) button show the text.
