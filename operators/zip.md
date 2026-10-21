# zip

Deprecated operator (JSDoc: replaced by `zipWith`, removed in v8). `operators/zip.ts` 22–25 does `zipStatic(source, ...sources).subscribe(subscriber)`. Static `zip` (`observable/zip.ts` 53–117) pops a trailing project with `popResultSelector` (`util/args.ts` 9–11), unwraps one array argument via `argsOrArgArray`, and if the resulting list is empty returns `EMPTY`. The operator always passes the upstream, so the list is never empty. Each input gets a FIFO buffer. A next is pushed, and if every buffer is non-empty the implementation shifts one value from each, emits that tuple (or `project(...tuple)`), then completes if any buffer is now empty and that same index is already marked completed. A source complete marks the flag and completes immediately when that buffer is already empty. Leftover values in longer buffers are not flushed. There is no scheduler.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| completed \| errored \| cancelled` | `idle` | — |
| `n` | integer ≥ 1 | number of sources passed to static `zip` | Index `0` is the upstream. |
| `buffers[i]` | FIFO | `n` empty arrays (`observable/zip.ts` 62) | Values not yet paired. |
| `completed[i]` | boolean | `false` (`observable/zip.ts` 67) | Set on `sourceComplete(i)` before the empty-buffer check. |
| `project` | function or absent | trailing function, if the last operator argument is a function | Called as `project(...tuple)`, not with the array (`observable/zip.ts` 89). |

`emitting` is the T03/T04 output, not a resting location.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Symbolic state is the buffers plus the completed flags.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | All reached inputs are subscribed; output open. Some buffers may hold unpaired values. |
| `completed` | A pair is no longer possible, or every source completed in a way that closed the zip. |
| `errored` | An input or the project errored. |
| `cancelled` | Downstream unsubscribed; buffers released (`observable/zip.ts` 70–72 and 112–114). |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Upstream next | `sourceNext(0, v)` | Pushes `buffers[0]`. |
| 4 | Upstream error | `sourceError(0, e)` | Default forward. |
| 5 | Upstream complete | `sourceComplete(0)` | — |
| 6 | Other next | `sourceNext(i, v)`, `i ≥ 1` | Pushes `buffers[i]`. |
| 7 | Other terminal | `sourceError(i, e)`, `sourceComplete(i)`, `i ≥ 1` | — |
| 8 | Project | applied inside T04 | No scheduler symbol. |

### Γ

`ε`, `sub(i)`, `unsub(*)`, `outNext(tuple)`, `outNext(project(...tuple))`, `outError(e)`, `outComplete`.

`tuple` is index order `[buffers[0].shift(), ..., buffers[n-1].shift()]`.

## C. Transition obligations

The subscribe loop stops when `subscriber.closed` (`observable/zip.ts` 76). A synchronous error or complete can therefore skip later `sub`.

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | subscriber stays open | `waiting` | `sub(i)` for `i = 0 .. n-1` in order |
| T02 | waiting | `waiting` | `sourceNext(i, v)` | after push, some buffer is still empty | `waiting` | `ε`; `buffers[i]` appends `v` |
| T03 | emitting | `waiting` | `sourceNext(i, v)` | after push, every buffer is non-empty; no project; no completed-empty buffer after the shift | `waiting` | append `v`; `outNext(shifted tuple)`; those heads are removed |
| T04 | emitting | `waiting` | `sourceNext(i, v)` | every buffer non-empty and `project` returns | `waiting` | `outNext(project(...tuple))` |
| T05 | terminal | `waiting` | `sourceNext(i, v)` | a full tuple was just shifted and some `buffers[k]` is now empty with `completed[k]` | `completed` | the `outNext` of T03 or T04, then `outComplete` (`observable/zip.ts` 93–95) |
| T06 | per-source complete | `waiting` | `sourceComplete(i)` | `buffers[i]` is empty | `completed` | `ε` from the complete handler besides `outComplete` (`observable/zip.ts` 98–105). Unpaired values in other buffers are dropped. |
| T07 | per-source complete | `waiting` | `sourceComplete(i)` | `buffers[i]` is non-empty | `waiting` | `ε`; `completed[i] := true`. Those buffered values can still be paired. |
| T08 | per-source error | `waiting` | `sourceError(i, e)` | — | `errored` | `outError(e)`, `unsub(*)`; all buffers dropped |
| T09 | per-source error | `waiting` | project throws `e` on T04 | — | `errored` | `outError(e)` (`OperatorSubscriber.ts` 67–74). The shifts have already happened. |
| T10 | cancel | `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)`; buffers set to null |
| T11 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

T05 is one transition with two outputs in order: the pair, then complete. No further pair is attempted after that complete.

Index pairing: the `k`-th `outNext` is built from the `k`-th value of each input (1-based), not from the latest value. Values that arrive early sit in the FIFO.

## D. Contract invariants

1. Let `c_i` be the number of `sourceNext(i, _)` observed before a terminal. The number of `outNext` tuples is `min_i c_i'` where `c_i'` counts only values that were actually pushed before the output completed. Completion cuts the min off as soon as one index cannot supply another pair.
2. If index `i` completes while `buffers[i]` is empty, the output completes even if other buffers still hold values. Those leftovers are not emitted (T06).
3. If index `i` completes while it still has unpaired values, the output stays open until those values are consumed by later pairs or until another index completes empty (T07 then T03/T05/T06).
4. The tuple order is the argument order, upstream first. The project, when present, replaces the array; it does not receive the array as one argument.
5. There is no time-based joining and no scheduler. A fast input only grows its FIFO.
6. Error from any subscribed input is terminal and does not emit a partial tuple.
7. Static `zip()` with no sources returns `EMPTY` (`observable/zip.ts` 58 and 116). This operator cannot hit that branch.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Equal finite lengths

Index `0` emits `1` then `2`. Index `1` emits `'a'` then `'b'`. Assume `0` emits both first: T02 stores `[1, 2]`. `'a'` makes both buffers non-empty: T03 `outNext([1, 'a'])`, buffers `[[2], []]`. `'b'` : T03 `outNext([2, 'b'])`. Both completes with empty buffers: the first complete with an empty buffer is T06 `outComplete` (the second source does not need to complete for that). Trace: `[1, 'a']`, `[2, 'b']`, `complete`.

### E2. Longer source’s tail is dropped

Index `0` emits `1, 2, 3` and completes. Index `1` emits `'a'` and completes. After `outNext([1, 'a'])`, `buffers[0] = [2, 3]`, `buffers[1] = []`. The complete of index `1` sees an empty buffer: T06 `outComplete`. `2` and `3` are not emitted. If index `0`’s complete is processed while `[2, 3]` is still buffered and index `1` has not completed, T07 only sets the flag; the drop still happens when index `1` completes empty, or earlier if index `1` never emits a second value and completes.

### E3. Complete with no value

Index `1` completes before any next. `buffers[1]` is empty: T06 `outComplete` during init if this is synchronous, and index `0` may already have pushed values. Those values are dropped. No `outNext`. No `EmptyError`.

### E4. Project

`zip(other$, (a, b) => a + b)` via the operator’s pass-through into `popResultSelector`. Values `2` and `3` become one pair. T04 `outNext(5)`, not `outNext([2, 3])`. A throw is T09.

### E5. One source only

`source.pipe(zip())`. `n = 1`. Every upstream value `v` finds the only buffer non-empty after the push, so T03 `outNext([v])` immediately. Upstream complete with the buffer empty (the value was already shifted) is T06 `outComplete`. The operator does not return `EMPTY`.

## F. Coverage and evidence

Not executed.

Denominator = 11 (T01–T11). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: `innerFrom` interop is not expanded. A project that synchronously unsubscribes is ordinary downstream reentrancy and is excluded; the buffers may already have been shifted. `zipWith` does not document a project but calls this operator, so a trailing function still hits `popResultSelector` at runtime (`zipWith.md`).
