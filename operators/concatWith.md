# concatWith

`concatWith(...otherSources)` returns `concat(...otherSources)` (`operators/concatWith.ts` 44–48). The callee is the deprecated operator `operators/concat.ts` 17–21, which is `concatAll()(from([source, ...otherSources]))`. `concatAll` is `mergeAll(1)` (`operators/concatAll.ts` 60–62) and therefore `mergeInternals` with `concurrent = 1` (`operators/mergeInternals.ts` 21–149). The public signature has no scheduler and no project function. Behavior is serial subscription: the upstream (index `0`) is subscribed immediately; each later index is subscribed only after the previous one completes. JSDoc (`concatWith.ts` 5–8, 39–42) matches that control flow.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| completed \| errored \| cancelled` | `idle` | Control location. |
| `inputs` | `ObservableInput[]` | `[source, ...otherSources]` | `n ≥ 1`. `concatWith()` alone mirrors the source. |
| `cursor` | integer | `0` | Active index. |
| `buffer` | queue of indices | `[]` | Indices whose `hoNext` arrived while `active = 1`. |
| `active` | `0 \| 1` | `0` | — |
| `outerDone` | boolean | `false` | — |
| `slot[i]` | `pending \| active \| done \| dropped` | `pending` | — |

No scheduler field. Emission is not a resting phase.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Symbolic state is A. Transition rows are `δ` / `λ`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | Output open, at most one active input. |
| `completed` | All inputs completed in order. |
| `errored` | Active input errored; tail not subscribed. |
| `cancelled` | Downstream cancelled; tail dropped. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | List next | `hoNext(i)` | Input object `i`, index order. |
| 4 | List error | `hoError(e)` | Not produced by the array. No row. |
| 5 | List complete | `hoComplete` | — |
| 6 | Inner next | `sourceNext(i, v)` | Active index only. |
| 7 | Inner terminal | `sourceError(i, e)`, `sourceComplete(i)` | Active index only. |
| 8 | Scheduler / project | — | Not part of `concatWith`. Inherited `popScheduler` inside `concat` is out of this model (see limits). |

### Γ

`ε`, `sub(i)`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `waiting` | `sub(0)`; `active := 1`; `cursor := 0` |
| T02 | emitting | `waiting` | `sourceNext(i, v)` | `i = cursor` | `waiting` | `outNext(v)` |
| T03 | waiting | `waiting` | `hoNext(i)` | `i > 0` and `active = 1` | `waiting` | `ε`; enqueue `i` |
| T04 | per-source complete | `waiting` | `sourceComplete(cursor)` | `buffer` nonempty | `waiting` | `sub(next buffer head)`; `cursor` advances; `active` stays `1` after the shift |
| T05 | per-source complete | `waiting` | `sourceComplete(cursor)` | `buffer` empty and not `outerDone` | `waiting` | `ε`; `active := 0` |
| T06 | init | `waiting` | `hoNext(i)` | `active = 0` | `waiting` | `sub(i)`; `cursor := i`; `active := 1` |
| T07 | terminal | `waiting` | `sourceComplete(cursor)` or `hoComplete` | `buffer` empty and every index `done` | `completed` | `outComplete` |
| T08 | waiting | `waiting` | `hoComplete` | `active = 1` or `buffer` nonempty | `waiting` | `ε`; `outerDone := true` |
| T09 | per-source error | `waiting` | `sourceError(cursor, e)` | — | `errored` | `outError(e)`, `unsub(*)`; tail `dropped` |
| T10 | cancel | `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)`; tail `dropped` |
| T11 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

Synchronous upstream completion still happens before the next `hoNext` is processed, so a sync upstream takes T05 and the following `hoNext(1)` takes T06 in the same turn. That still subscribes serially: index `1`’s subscribe is ordered after index `0`’s complete callback. It is not an up-front merge.

## D. Contract invariants

1. `sub(i)` happens only after `sourceComplete(k)` for every `k < i`, or `i = 0` at init.
2. Values are forwarded unchanged, one active source at a time (JSDoc `concatWith.ts` 5–8).
3. Output completion is the completion of the last index, and only if every earlier index completed.
4. An error is terminal for the chain. Later `otherSources` are not subscribed, so their subscription side effects do not run.
5. Unsubscribing does not complete the output and does not flush the tail.
6. `concat(a$, b$, c$)` as a creation function is the same order as `a$.pipe(concatWith(b$, c$))` only because both put `a$` first and then use `concurrent = 1`. The operator path always receives the upstream as index `0` via `from([source, ...args])`.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Click then moves (JSDoc shape)

Upstream emits one value `click` and completes. The other source then emits `move` values. T01 `sub(0)`, T02 `outNext(click)`, T05/T06 `sub(1)` only after that complete, then T02 for each `move`. The other source is not subscribed during the click. No `outComplete` until the move source completes.

### E2. Sync pair

`of('a', 'b').pipe(concatWith(of('c')))`. Trace: `a`, `b`, then subscribe to the second of, `c`, `outComplete`. The second `of` does not run before `b`.

### E3. Error on the upstream

Upstream errors `e` after `a`. T09. The `concatWith` argument is never subscribed. Trace: `a`, `error e`.

### E4. Error on a later source

Upstream completes after `a`. Second source emits `b` then errors `e`. Trace: `a`, `b`, `error e`. A third source, if present, stays `dropped`.

### E5. Cancel during the second source

Upstream already completed (`a` forwarded) and the second source is active and has forwarded `b`. T10 unsubscribes the second source. A third buffered source is dropped. No `outComplete`. Trace: `a`, `b`, then silence.

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
- limits: If a trailing `SchedulerLike` is actually passed, `concat`’s `popScheduler` will treat it as a scheduler even though `concatWith` does not document one. This file’s model excludes that. `innerFrom` coercion of each input is not expanded. Parent detail lives in `concat.md`.
