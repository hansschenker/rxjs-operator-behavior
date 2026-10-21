# delayWhen

`delayWhen(delayDurationSelector, subscriptionDelay?)` delays each source value until the observable returned for that value emits a `next`. Only a duration `next` releases the value; a duration that completes without `next` swallows it. Duration `error` becomes output `error`. The implementation is `mergeMap` to `delayDurationSelector(value, index).pipe(take(1), mapTo(value))` (`delayWhen.ts` 102), so in-flight delays run concurrently and source `complete` waits until those inners finish, while source `error` is immediate and drops in-flight values. The optional `subscriptionDelay` argument is deprecated and will be removed in v8 (`delayWhen.ts` 10–14, 96–99): the source is subscribed only after that observable emits one value or completes. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/delayWhen.ts`, with `mergeInternals.ts` for completion and error.

## A. Identity, contract, and scope

- Operator/overload: two call signatures (`delayWhen.ts` 11–15). Implementation 92–103. Deprecated path: `concat(subscriptionDelay.pipe(take(1), ignoreElements()), source.pipe(delayWhen(selector)))` (96–99).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 34–48. A duration `next` emits the source value and unsubscribes the duration (`take(1)`). Duration complete without `next` swallows the value (explicit v7 change, lines 38–46). Duration error propagates (lines 47–48). `subscriptionDelay` gates source subscription (lines 50–55).
- Model kind: extended/timed, not finite. Concurrent in-flight delays are an unbounded multiset.
- Parameter domain: selector `(value, index) => ObservableInput`. `index` is `mergeInternals`’s per-subscription index (`mergeInternals.ts` 71). `subscriptionDelay`, if passed and truthy, is an `Observable<any>` (deprecated).
- Payload/error domain: output values are the source values, via deprecated `mapTo(value)` (`delayWhen.ts` 102, `mapTo.ts` 3–9). Duration payloads are discarded by `mapTo`. Inner errors and selector throws become output errors.
- Subscription boundary: without `subscriptionDelay`, `mergeMap` subscribes to the source immediately (`mergeInternals.ts` 136–141) and to each duration on `sourceNext`. Concurrency limit is the default `Infinity` (`mergeMap.ts` 84). With `subscriptionDelay`, `concat` subscribes to the gate first and to the delayed source only after the gate completes.
- Scheduler and tie ordering: no scheduler argument. If durations are timers, same-virtual-time actions run in schedule order — assumption, not a proof. `mergeMap` does not reorder by source index; an inner that `next`s first is emitted first. Equal delays preserve source order only under that schedule-order assumption. Micro-trace required when several durations are due together, and when source complete overlaps in-flight inners.
- Callback assumptions: selector throw happens inside `project` called from outer `onNext`, so `OperatorSubscriber` turns it into `destination.error` (`OperatorSubscriber.ts` 67–74). That is not a source error. `take(1)` completes the duration subscription after the first `next` (`take.ts` 55–66). Ordinary model: no reentrancy.
- Cleanup assumptions: source `error` uses `mergeInternals`’s default error path (`mergeInternals.ts` 136–141, `onError` omitted) so `destination.error` unsubscribes active inners. Those inners do not emit after that. `cancel` unsubscribes the destination and therefore every active duration. No synthetic `complete`.
- Explicit exclusions: reentrancy; proving order for unequal durations; the deprecated `mapTo` removal timeline beyond the v8/v9 notes in `mapTo.ts`; `subscriptionDelay` after v8.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Live(active = ∅, sourceOpen = true)
```

Not finite: `active` is a multiset of in-flight `(value, duration subscription)` pairs.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Gated` | deprecated path only; source not subscribed | Waiting for `subscriptionDelay` to `next` or `complete`. |
| `Live` | `active` set, source not completed | Accepting source values. |
| `Draining` | source completed, `active` non-empty | Waiting for inners to finish before output `complete` (`mergeInternals.ts` 43–48, 137–140). |
| `Stopped` | terminal | — |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Enters `Live`, or `Gated` if `subscriptionDelay` is set. |
| `gateNext` / `gateComplete` | yes, deprecated | `subscriptionDelay` | `take(1)` plus `ignoreElements` (`delayWhen.ts` 99): first `next` or a bare `complete` completes the gate; the `next` payload is ignored. |
| `gateError(e)` | yes, deprecated | `subscriptionDelay` | Output `error`; source never subscribed. |
| `sourceNext(v)` | yes | source | Starts one inner. |
| `sourceError(e)` | yes | source | Immediate output `error`; in-flight dropped (`mergeInternals` default error). |
| `sourceComplete` | yes | source | Enter `Draining` or `complete` if `active` is empty. |
| `cancel` | yes | unsubscribe | Drop in-flight; no `complete`. |
| `durationNext` | yes | that value’s duration | After `take(1)`/`mapTo`, output `next(v)` and inner completes. |
| `durationComplete` (no `next`) | yes | duration | Inner completes with no output value; value swallowed (JSDoc 44–46). |
| `durationError(e)` | yes | duration | `mergeInternals` inner `onError` omitted (line 94) → output `error`; other inners unsubscribed. |
| `selectorThrow(e)` | yes | user callback | Output `error`; that value not released. Not a source error. |
| `timerFired` | no | — | Only if the user’s duration uses a scheduler. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Output `complete` is delayed until `active` is empty after source complete. Micro-trace required for concurrent durations and for complete-versus-inner signals.

## C. Transition obligations

Primary path (no `subscriptionDelay`). Deprecated gate rows follow.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | no gate | `none` | source subscribed (`mergeInternals.ts` 136) | `Live(∅)` | ε | source | S01 |
| T02 | `Live` | `sourceNext(v)` | selector returns an input | `none` | `active++`; subscribe `innerFrom(selector(v, index)).pipe(take(1), mapTo(v))` (`delayWhen.ts` 102, `mergeInternals.ts` 55–71) | `Live` with `v` in flight | T01 | duration signal | S01 |
| T03 | `Live` or `Draining` | `durationNext` for `v` | inner still active | `next(v)` | `take(1)` completes the inner; `active--`; duration unsubscribed (`take.ts` 64–65) | if source still open, `Live`; if source done and `active=0`, go to T08 | T02 | order vs other inners is completion order | S01 |
| T04 | `Live` or `Draining` | `durationComplete` without `next` | — | `none`; `v` swallowed | inner finalizer `active--` and `checkComplete` (`mergeInternals.ts` 95–125) | `Live` or, if draining and `active=0`, output `complete` | T02 | value never appears | S02 |
| T05 | `Live` or `Draining` | `durationError(e)` | — | `error(e)` | other inners unsubscribed with destination; their values dropped | `Stopped` | T02 | none | S03 |
| T06 | `Live` | `selectorThrow(e)` | throw in project | `error(e)`; `v` not queued | catch around source `onNext` | `Stopped` | T01 | none | S03 |
| T07 | `Live`, `active` empty | `sourceComplete` | `!active` | `complete` | `isComplete=true`; `checkComplete` (`mergeInternals.ts` 137–140, 43–48) | `Stopped` | T01 or after T03 cleared the set | none | S04 |
| T08 | `Live`, `active` non-empty | `sourceComplete` | in flight | `none` yet | `isComplete=true`; do not complete while `active>0` | `Draining` | T02 | each inner still runs T03 or T04 | S01 |
| T09 | `Draining`, `active` becomes 0 | last inner finishes after emitting or swallowing | — | `complete` (after any `next` from that inner) | `checkComplete` | `Stopped` | T08 | none | S01 |
| T10 | `Live` or `Draining` | `sourceError(e)` | — | `error(e)`; in-flight not flushed | default outer error; unsubscribe inners | `Stopped` | T02 | none | S05 |
| T11 | any non-terminal | `cancel` | — | `none` | all inners unsubscribed; no `complete` | `Stopped` | T02 | durations must not `next` | S06 |
| T12 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T13 | ∅ | `subscribe` | `subscriptionDelay` truthy | `none` | subscribe gate only (`delayWhen.ts` 96–99) | `Gated` | ε | gate signal | S07 |
| T14 | `Gated` | `gateNext` or `gateComplete` | — | `none` | `take(1)`+`ignoreElements` completes the gate; `concat` subscribes to `source.pipe(delayWhen(selector))` | `Live(∅)` | T13 | same as T02 onward | S07 |
| T15 | `Gated` | `gateError(e)` | — | `error(e)` | source not subscribed | `Stopped` | T13 | none | S07 |
| T16 | `Gated` | `sourceNext` | source not subscribed | — | inapplicable | `Gated` | T13 | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | A source value is output only if its duration emits `next`. Completion of the duration without `next` swallows it (JSDoc 43–46, `take(1)`). |
| I02 | The first duration `next` wins; `take(1)` unsubscribes, so later duration values are ignored. |
| I03 | In-flight delays are concurrent (`mergeMap`, not `concatMap`). Emission order is inner-completion order, not a sort by index. |
| I04 | Source `complete` does not itself emit values. It waits until every in-flight inner has settled, then `complete`s (`mergeInternals.ts` 43–48). |
| I05 | Source `error` does not wait and does not emit in-flight values. |
| I06 | Duration `error` and selector throw are output errors and abandon other in-flight values. |
| I07 | `cancel` does not `complete`. |
| I08 | Deprecated gate: source subscription begins only after `subscriptionDelay`’s first `next` or its `complete`, whichever comes first. A gate `error` skips the source. |

## E. Scenario specification

### S01 Concurrent delay, complete waits for the in-flight next

- Test ID: S01
- Covered row IDs: T01, T02, T03, T08, T09
- Starting state: unsubscribed
- Reset/fixture: no `subscriptionDelay`; selector returns a cold timer of 10 for every value; virtual scheduler
- prefix: `subscribe`, `sourceNext(a)`, `sourceComplete` before the timer
- target event: `durationNext` for `a`
- expected notifications: `none` at source complete; then `next(a)`, `complete`
- lifecycle: one inner, `active` returns to 0, `checkComplete`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler for the duration
- assertion type: source characterization
- oracle source: source characterization (`delayWhen.ts` 102, `mergeInternals.ts` 43–48, 137–140)

### S02 Empty duration swallows the value

- Test ID: S02
- Covered row IDs: T02, T04
- Starting state: `Live`
- Reset/fixture: selector returns `EMPTY`
- prefix: `subscribe`
- target event: `sourceNext(a)` (sync complete of `EMPTY`)
- expected notifications: none
- lifecycle: inner completes inside subscribe; `active` returns to 0; source stays open
- suffix: later `sourceComplete` is T07 (`complete` only)
- final state: `Live` after the swallow; `Stopped` if the suffix is included
- version and scheduler: 7.8.2
- assertion type: contract
- oracle source: contract (JSDoc 38–46) and source characterization (`take(1)` on an empty source)

### S03 Duration error and selector throw

- Test ID: S03
- Covered row IDs: T05, T06
- Starting state: `Live`
- Reset/fixture: two runs; second duration would have emitted `b` and is in flight in the error run
- prefix: `sourceNext(a)` in flight
- target event: `durationError(e)` of `a`, or a later `sourceNext` whose selector throws
- expected notifications: `error(e)`; `b` not emitted if it was only in flight
- lifecycle: destination unsubscribe drops other inners
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`mergeInternals.ts` 94; `OperatorSubscriber.ts` 71–73)

### S04 Complete with nothing in flight

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Live(∅)`
- Reset/fixture: no pending durations
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `complete`
- lifecycle: `checkComplete` succeeds immediately
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Source error drops in-flight values

- Test ID: S05
- Covered row IDs: T10
- Starting state: `Live` with `a` in flight
- Reset/fixture: duration not yet signaled
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: inner unsubscribed
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (outer subscriber has no error handler, `mergeInternals.ts` 137)

### S06 Cancel

- Test ID: S06
- Covered row IDs: T11
- Starting state: `Live` with `a` in flight
- Reset/fixture: timer armed
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: duration unsubscribed; no `complete`
- suffix: timer must not emit
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S07 Deprecated subscription gate

- Test ID: S07
- Covered row IDs: T13, T14, T15
- Starting state: unsubscribed
- Reset/fixture: `delayWhen(selector, gate$)` with gate that `next`s once, and a separate run where gate errors
- prefix: `subscribe`
- target event: `gateNext` or `gateError(e)`
- expected notifications: gate `next` produces `none` and then source behavior; gate `error` produces `error(e)` and no source subscription
- lifecycle: `concat` + `take(1)` + `ignoreElements` (`delayWhen.ts` 99)
- suffix: after a successful gate, state is `Live(∅)`
- final state: `Live` or `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization. Deprecated, removed in v8 (line 10).

## F. Coverage and evidence

Denominator = 16 (T01–T16). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01, S02 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S03 | not executed |
| T07 | S04 | not executed |
| T08 | S01 | not executed |
| T09 | S01 | not executed |
| T10 | S05 | not executed |
| T11 | S06 | not executed |
| T12 | none | not executed |
| T13 | S07 | not executed |
| T14 | S07 | not executed |
| T15 | S07 | not executed |
| T16 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Cross-duration order is not a stable function of source order unless the durations’ signals are ordered. The gate path is deprecated. `mapTo` inside the implementation is itself deprecated. Reentrancy excluded.
- Contract vs 7.8.2 characterization: JSDoc 38–48 matches `take(1)` plus error propagation. Complete-waits-for-in-flight is `mergeMap`/`mergeInternals` characterization, not restated as clearly in the `delayWhen` JSDoc, but it is the implementation.
- Tests still required: S01–S07, including two unequal durations that complete out of source order, `EMPTY` duration, source error with an in-flight timer, and the deprecated gate.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
