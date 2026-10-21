# concat

Operator `concat` is deprecated (JSDoc: replaced by `concatWith`, removed in v8). Implementation (`operators/concat.ts` 17–21): pop a trailing scheduler, then `concatAll()(from([source, ...args], scheduler)).subscribe(subscriber)`. `concatAll` is `mergeAll(1)` (`operators/concatAll.ts` 60–62), i.e. `mergeInternals` with `concurrent = 1` (`operators/mergeAll.ts` 64–66, `operators/mergeMap.ts` 93, `operators/mergeInternals.ts` 21–149). Static `observable/concat.ts` 113–115 is the same flatten applied to its own argument list; the operator always puts the upstream first. Indices: `0` upstream, then each other input in order. Subscription is serial. Only `buffer[0]` is subscribed; the rest wait.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| completed \| errored \| cancelled` | `idle` | Control location. |
| `scheduler` | `SchedulerLike \| absent` | popped, else absent | Schedules higher-order delivery of each input object (`from.ts` 102–104, `scheduleArray.ts` 4–25). Deprecated with the operator; the overload JSDoc on the creation `concat` points at the v8 scheduler removal. |
| `inputs` | `ObservableInput[]` | `[source, ...args]` | `n ≥ 1`. |
| `cursor` | integer | `0` | Index of the active input, or `n` if finished. |
| `buffer` | queue of not-yet-subscribed inputs | `[]` | Holds every input after the one currently subscribed. |
| `active` | `0 \| 1` | `0` | `mergeInternals` active count. With `concurrent = 1` it never exceeds 1. |
| `outerDone` | boolean | `false` | Higher-order list completed. |
| `slot[i]` | `pending \| active \| done \| dropped` | `pending` | — |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Extended state is the fields in A. Rows in C are `δ` and `λ`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | Output open. At most one `slot` is `active`. |
| `completed` | Every input completed in order. |
| `errored` | The active input errored; later inputs were not subscribed. |
| `cancelled` | Downstream unsubscribed; the active input and the queued tail are dropped. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | List next | `hoNext(i)` | Yields the next `ObservableInput`. |
| 4 | List error | `hoError(e)` | Not produced by the array itself. |
| 5 | List complete | `hoComplete` | — |
| 6 | Inner next | `sourceNext(i, v)` | Only legal for `slot[i] = active`. |
| 7 | Inner terminal | `sourceError(i, e)`, `sourceComplete(i)` | Same index restriction. |
| 8 | Scheduler | `schedTick` | Only if a scheduler was popped. One tick, one list element. |

### Γ

`ε`, `sub(i)`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`.

No `outNext` is emitted for an index that is still `pending`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | no scheduler | `waiting` | `sub(0)`; `active := 1`. Later `hoNext(i)` for `i > 0` enqueue (T04) in the same turn if the array is sync. |
| T02 | init | `idle` | `subscribe` | scheduler present | `waiting` | `ε`; first `schedTick` not yet run |
| T03 | emitting | `waiting` | `sourceNext(i, v)` | `i = cursor` and `slot[i] = active` | `waiting` | `outNext(v)` |
| T04 | waiting | `waiting` | `hoNext(i)` | `active = 1` | `waiting` | `ε`; append `i` to `buffer` |
| T05 | per-source complete | `waiting` | `sourceComplete(i)` | `i = cursor` and `buffer` nonempty | `waiting` | `ε`; `active` briefly `0`, then `sub(j)` for the shifted head; `cursor := j`; `active := 1` (`mergeInternals.ts` 107–122) |
| T06 | per-source complete | `waiting` | `sourceComplete(i)` | `i = cursor`, `buffer` empty, `outerDone` | `completed` | `outComplete` |
| T07 | per-source complete | `waiting` | `sourceComplete(i)` | `i = cursor`, `buffer` empty, not `outerDone` | `waiting` | `ε`; `active := 0`. The next `hoNext` takes T08. |
| T08 | init | `waiting` | `hoNext(i)` | `active = 0` | `waiting` | `sub(i)`; `active := 1`; `cursor := i` |
| T09 | waiting | `waiting` | `hoComplete` | `active = 0` and `buffer` empty | `completed` | `outComplete` |
| T10 | waiting | `waiting` | `hoComplete` | `active = 1` or `buffer` nonempty | `waiting` | `ε`; `outerDone := true` |
| T11 | per-source error | `waiting` | `sourceError(i, e)` | `i = cursor` | `errored` | `outError(e)`, `unsub(*)`; `buffer` dropped and never subscribed |
| T12 | cancel | `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)`; tail dropped |
| T13 | scheduler | `waiting` | `schedTick` | scheduler present | `waiting` | one `hoNext` or final `hoComplete`, then the matching row above |
| T14 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

T01 plus a fully synchronous first source is the important order: `sourceComplete(0)` runs before `hoNext(1)` is delivered by `fromArrayLike`, so the machine takes T07 (`active = 0`, buffer still empty) and the immediately following `hoNext(1)` takes T08. Later sources are still subscribed only after the previous one completes; they are not subscribed “up front”. If the first source stays open, `hoNext(1..)` take T04 instead and wait in `buffer`.

## D. Contract invariants

1. At most one index is `active`. `cursor` is non-decreasing and advances only on `sourceComplete` of the current index (or on the initial `sub(0)`).
2. `outNext` values for index `i` all precede `outNext` values for index `j > i`. There is no interleaving.
3. If index `i` never completes, every `j > i` stays `pending` and the output never completes.
4. `sourceError` on the active index forbids `sub` of the tail (creation-function JSDoc `observable/concat.ts` 40–42; same `mergeInternals` error path).
5. `outComplete` iff every index completed, in order.
6. A scheduler does not schedule individual values of an input. It schedules when the input object is handed to `mergeInternals`. Prefix arrays used by `startWith` are a different nesting; see `startWith.md`.
7. An empty argument list is legal: the only input is the upstream, and the operator mirrors it.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two sync finite sources

`of(1, 2).pipe(concat(of(3)))`.

`sub(0)` emits `1`, `2`, completes (T03, T03, T07). `hoNext(1)` takes T08 `sub(1)`, emits `3`, completes. `hoComplete` takes T09 `outComplete`. Trace: `1, 2, 3, complete`. Input `1` is not subscribed until input `0` has completed.

### E2. First source hangs

Input `0` emits `1` and does not complete. `hoNext(1)` takes T04. No `sub(1)`. No `outComplete`. Trace so far: `outNext(1)`.

### E3. Error skips the tail

Input `0` emits `1` then `sourceError(0, e)`. Input `1` is either still buffered or not yet delivered. T11: `outError(e)`, input `1` never subscribed. Trace: `1, error e`.

### E4. Cancel mid-source

Input `0` has emitted `1` and is still active. Input `1` sits in `buffer`. T12 `unsubscribe`: both the active subscription and the queued input are dropped. Input `1`’s factory side effects do not run. No terminal notification.

### E5. Scheduler defers even the upstream

`concat(other$, scheduler)`. T02 leaves both inputs unsubscribed. First `schedTick` delivers `hoNext(0)` and, because `active = 0`, T08 `sub(0)`. Upstream values are then live (T03) without further ticks. Next tick delivers `other$` into `buffer` if `0` is still active (T04), or subscribes it if `0` already completed (T08). Last tick `hoComplete`. This is the deprecated scheduler overload on `operators/concat.ts` 9–12 and 18.

## F. Coverage and evidence

Not executed.

Denominator = 14 (T01–T14). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: `innerFrom` interop is not expanded per input kind. `concurrent` is the constant `1`, not a parameter. Static `concat` of an empty list completes immediately via `from([])`; this operator never builds an empty list. See `merge.md` for the `concurrent > 1` sibling.
