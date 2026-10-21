# mergeWith

`mergeWith(...otherSources)` returns `merge(...otherSources)` (`operators/mergeWith.ts` 45–49). That callee is the deprecated operator in `operators/merge.ts` 22–28, not `mergeWith` reimplemented and not static `observable/merge.ts`. The operator therefore subscribes the upstream and every other source through `mergeAll(Infinity)` → `mergeMap(identity, Infinity)` → `mergeInternals` (`operators/mergeAll.ts` 64–66, `operators/mergeMap.ts` 93, `operators/mergeInternals.ts` 21–149). No concurrency argument and no scheduler argument appear in the `mergeWith` signature. A trailing `SchedulerLike` would still be popped if it were passed, because `merge` always calls `popScheduler`; the typed API does not offer that overload. The model below is unbounded concurrent merge of indices `0..n-1` with `0` the upstream.

## A. Identity, contract, and scope

| Field | Domain | Initial on `subscribe` | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| completed \| errored \| cancelled` | `idle` | Control location. |
| `inputs` | `ObservableInput[]` | `[source, ...otherSources]` | `n ≥ 1`. |
| `active` | integer | `0` | Subscribed inners. |
| `outerDone` | boolean | `false` | Higher-order array `from` has completed. |
| `slot[i]` | `pending \| active \| done` | `pending` | Subscription flag per index. |

`concurrent` is fixed at `Infinity`, so `mergeInternals`’s `buffer` stays empty: every `hoNext(i)` takes the `active < concurrent` branch (`mergeInternals.ts` 52). No scheduler field.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. `S` is `phase` times the fields above. `δ`, `λ` are the rows in C.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | Output open. Any non-empty subset of inputs may be active. |
| `completed` | All inputs completed. |
| `errored` | Some input errored. |
| `cancelled` | Downstream unsubscribed early. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | List next | `hoNext(i)` | Array `from` yields input object `i` in order. |
| 4 | List error | `hoError(e)` | Not produced by a plain array. Row reserved; no transition. |
| 5 | List complete | `hoComplete` | After the last input object. |
| 6 | Inner next | `sourceNext(i, v)` | — |
| 7 | Inner terminal | `sourceError(i, e)`, `sourceComplete(i)` | — |
| 8 | Scheduler / project | — | None. `mergeWith` does not pop a scheduler and does not project values. |

### Γ

`ε`, `sub(i)`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`. Same producers as `merge` with an empty concurrency buffer.

## C. Transition obligations

Without a scheduler the whole list is synchronous. A synchronous inner that completes does so before the next `hoNext`. A synchronous inner error stops the subscriber so later `hoNext`s do not subscribe.

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `waiting` | `sub(i)` for every `i` that is reached before the subscriber stops, in index order |
| T02 | emitting | `waiting` | `sourceNext(i, v)` | `slot[i] = active` | `waiting` | `outNext(v)` |
| T03 | per-source error | `waiting` | `sourceError(i, e)` | `slot[i] = active` | `errored` | `outError(e)`, `unsub(*)` |
| T04 | per-source complete | `waiting` | `sourceComplete(i)` | some other slot still `active` or not yet visited by the list | `waiting` | `ε`; `slot[i] := done`; `active := active-1` |
| T05 | terminal | `waiting` | `sourceComplete(i)` or `hoComplete` | every slot `done` (equivalently `outerDone && active = 0`) | `completed` | `outComplete` |
| T06 | waiting | `waiting` | `hoComplete` | `active > 0` | `waiting` | `ε`; `outerDone := true` |
| T07 | cancel | `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T08 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

`hoComplete` is the signal inside T01’s synchronous flush or, if some inner stayed open, the separate T06. T05 is the unique completion edge: it fires from the inner finalizer’s `checkComplete` (`mergeInternals.ts` 43–48, 137–141), which is either the last `sourceComplete` or `hoComplete` when nothing was active.

## D. Contract invariants

1. Every other source is subscribed during the initial flush unless an earlier index synchronously errors or the downstream synchronously unsubscribes (`mergeInternals.ts` 52, `innerFrom.ts` 77).
2. Completion requires every index, including the upstream, to complete. One completed sibling does not complete the output (JSDoc `mergeWith.ts` 11–14 matches the code).
3. The first error is forwarded and the other actives are unsubscribed (JSDoc line 14; default `OperatorSubscriber._error`).
4. No value queue and no index alignment. Contrast `zip` / `combineLatest`.
5. `mergeWith()` with no arguments is still a subscription to the upstream alone, then `outComplete` when it completes. It is not `EMPTY`.
6. Deprecation sits on `merge`, not on `mergeWith`.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two cold sync sources

`of(1).pipe(mergeWith(of(2), of(3)))`.

T01 subscribes `0`, which sync-emits `1` and completes, then `1` emits `2` and completes, then `2` emits `3` and completes, then the list completes. Because each sync source finishes before the next `hoNext`, the trace is `outNext(1), outNext(2), outNext(3), outComplete`.

### E2. Interleaving while both stay open

Upstream emits `a` then later `c`. Other emits `b` between them. Both were subscribed in T01 (neither completed sync). Trace: `outNext(a), outNext(b), outNext(c)`, then T05 only after both `sourceComplete`s. Order across indices is arrival order.

### E3. Other errors

Upstream has emitted `a`. Other signals `sourceError(1, e)` before upstream completes. T03: `outError(e)`, upstream unsubscribed. No `outComplete`. `a` is not revoked.

### E4. Cancel before the other emits

T01 subscribed both. Downstream `unsubscribe` (T07) unsubscribes both. A later `sourceNext` on either source is not an input anymore (the subscription is gone). No terminal output.

### E5. Upstream completes first

`sourceComplete(0)` while `slot[1] = active`. T04, no output. The other’s later values still pass T02. When the other completes, T05 `outComplete`. Matches JSDoc: “When all sources complete, the resulting observable will complete.”

## F. Coverage and evidence

Not executed.

Denominator = 8 (T01–T08). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: A caller who actually passes a trailing scheduler or a trailing number hits `merge`’s `popScheduler` / `popNumber` even though `mergeWith`’s types do not say so; this model does not include those pops. `ObservableInput` coercion is delegated to `innerFrom` at `sub(i)`. The parent `merge.md` model is the concurrent, scheduled generalization.
