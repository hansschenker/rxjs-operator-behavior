# window

`window(windowBoundaries)` emits a nested `Observable` for the current window and forwards source values into it (`window.ts` 53–97). A new `Subject` is emitted as soon as the output is subscribed, before the source is subscribed (lines 55–57). Each boundary `next` completes that inner and emits a new one. Boundary `complete` is `noop`: the current inner stays open and the output does not complete. Source `complete` completes the current inner and then the output. Source `error` and boundary `error` both `error` the current inner and the output with the same `err` (59–62, 83). `cancel` unsubscribes the current `Subject` so a late inner subscriber gets `ObjectUnsubscribedError` (90–95) and does not complete the output. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/window.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `window<T>(windowBoundaries: ObservableInput<any>): OperatorFunction<T, Observable<T>>` (`window.ts` 53).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 18–23. Non-overlapping windows. The inner contract is a `Subject` exposed via `asObservable()` (`Subject.ts` 152–156): multicast to its subscribers, `next` while open, `complete` or `error` when this operator says so, and `unsubscribe` on outer cancel.
- Model kind: extended, not finite. The outer machine is finite-control plus one current subject. Inner subscribers are not a second Mealy machine; they observe the subject.
- Parameter domain: one boundary `ObservableInput`, subscribed once (78–88), after the source subscription (65–75). The first window is emitted before either subscribe (57).
- Payload/error domain: outer `next` values are `Observable<T>`. Inner payloads are source `T`. The same `err` is delivered to the inner subject and the outer subscriber (59–62).
- Subscription boundary: outer destination plus source subscriber plus boundary subscriber. The subject is not added as a subscription; teardown unsubscribes it explicitly (90–95).
- Scheduler and tie ordering: none in this file. Same-turn order of source and boundary is a producer assumption, not a proof. Micro-trace required. Ordinary model: no reentrancy. Boundary `next` completes the old subject before emitting the new one (81–83).
- Callback assumptions: no user selector. Downstream throw on outer `next(observable)` is caught by whichever subscriber is notifying. Ordinary model excludes that throw resubscribing.
- Cleanup assumptions: `cancel` runs the returned teardown: `windowSubject.unsubscribe()` then null (90–95). That is not `complete` and not `error`. Source and boundary are unsubscribed as destination children. No outer `complete`.
- Explicit exclusions: reentrancy; a full model of every inner subscriber; late subscribe after `complete` (the subject replays the terminal state via `Subject._checkFinalizedStatuses`, not re-specified here); boundary `complete` being treated as a window boundary.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open(W0) after the synchronous initial outer next
```

Inner-subject contract, stored as data: `W` accepts `next(T)` until `complete`, `error(e)`, or `unsubscribe`. Outer `Γ` does not include inner notifications.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(W)` | current `Subject<T>` | Source values go to `W`. Outer already emitted `W.asObservable()`. |
| `Stopped` | subject unsubscribed, completed, or errored | Terminal for the outer. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Emit first window, then subscribe source and boundaries (55–88). |
| `sourceNext(v)` | yes | source | `W.next(v)` only (68). No outer `next`. |
| `sourceError(e)` | yes | source | `errorHandler` (59–62, 73). |
| `sourceComplete` | yes | source | `W.complete()` then outer `complete` (69–72). |
| `cancel` | yes | unsubscribe | Teardown unsubscribes `W` (90–95). No outer `complete`. |
| `boundaryNext` | yes | boundaries | `W.complete()`; allocate `W'`; outer `next(W')` (81–83). |
| `boundaryComplete` | yes | boundaries | `noop` (85). `W` stays open. Outer stays open. |
| `boundaryError(e)` | yes | boundaries | Same `errorHandler` as source error (86). |
| `timerFired` | no | — | None. |
| user callback | no | — | No selector. |

### Γ

Outer: `none` | `next(Observable)` | `error(e)` | `complete`. Inner effects are lifecycle on the stored subject, not extra outer symbols. Micro-trace required when a boundary and a source signal share a turn: the subject that receives a source value is the one open at that step.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | outer `next(W0.asObservable())` | subject created (55–57); then source and boundaries subscribed | `Open(W0)` | ε | source values enter `W0` | S01 |
| T02 | `Open(W)` | `sourceNext(v)` | `W` not stopped | outer `none` | `W.next(v)` (68) | `Open(W)` | T01 | inner observers see `v` | S01 |
| T03 | `Open(W)` | `boundaryNext` | — | outer `next(W')` | `W.complete()` then replace (81–83). `W'` has no values yet | `Open(W')` | T02 | later source values enter `W'` only | S01 |
| T04 | `Open(W)` | `boundaryComplete` | — | outer `none` | boundary subscriber ends; `W` not completed | `Open(W)` | T02 | source values still enter `W` | S02 |
| T05 | `Open(W)` | `sourceComplete` | — | outer `complete` | `W.complete()` first (70–71), even if `W` saw no values | `Stopped` | T01 or T03 | inner gets `complete`, not `error` | S03 |
| T06 | `Open(W)` | `sourceError(e)` | — | outer `error(e)` | `W.error(e)` then outer `error` (59–62) | `Stopped` | T02 | inner does not `complete` | S04 |
| T07 | `Open(W)` | `boundaryError(e)` | — | outer `error(e)` | same `errorHandler` (86) | `Stopped` | T02 | none | S04 |
| T08 | `Open(W)` | `cancel` | — | outer `none` | teardown `W.unsubscribe()` (90–95); source and boundary unsubscribed; no outer `complete` | `Stopped` | T02 | late `W.subscribe` hits a closed subject | S05 |
| T09 | `Stopped` | source or boundary | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T10 | `Open` | inner subscriber late to a completed `W` | previous boundary already completed `W` | outer `none` | subject terminal state is the inner contract, not a new outer transition | `Open(W')` | T03 | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | The first outer `next` is synchronous during subscribe and carries an empty open window. |
| I02 | Source values are forwarded only to the current inner, never as outer values. |
| I03 | A boundary `next` completes the old inner and emits a new inner. It does not error either. |
| I04 | A boundary `complete` neither completes the inner nor the outer. |
| I05 | Source `complete` completes the inner, then the outer, including when the inner is empty. |
| I06 | Source `error` and boundary `error` error the current inner and the outer with the same error. Already completed inners are not revisited. |
| I07 | `cancel` unsubscribes the current subject and does not outer-`complete`. |
| I08 | Windows do not overlap. At most one subject is current. |

## E. Scenario specification

### S01 Boundary splits windows

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: boundaries silent until asked; inner subscribers attached to each emitted observable
- prefix: `subscribe` (outer `next(W0)`), `sourceNext(a)`
- target event: `boundaryNext`, then `sourceNext(b)`
- expected notifications: outer already has `W0`; on the boundary, outer `next(W1)`. Inner `W0` sees `a` then `complete`. Inner `W1` sees `b` only
- lifecycle: `W0.complete()` before `W1` is emitted
- suffix: `Open(W1)`
- final state: `Open(W1)`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`window.ts` 55–57, 68, 81–83)

### S02 Boundary complete is ignored

- Test ID: S02
- Covered row IDs: T04
- Starting state: `Open(W0)` after `sourceNext(a)`
- Reset/fixture: boundaries complete
- prefix: T01, T02
- target event: `boundaryComplete`
- expected notifications: outer none; `W0` does not complete
- lifecycle: boundary subscriber unsubscribed; source remains
- suffix: a later `sourceNext(b)` still enters `W0`
- final state: `Open(W0)`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 85)

### S03 Source complete closes the inner

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Open(W0)`, possibly with no inner values
- Reset/fixture: empty source and a one-value source
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: outer `complete`. Inner `complete` with either no values or the values already forwarded
- lifecycle: no new window is emitted at complete
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (69–72)

### S04 Errors hit inner and outer

- Test ID: S04
- Covered row IDs: T06, T07
- Starting state: `Open(W0)` with `a` already forwarded
- Reset/fixture: separate source-error and boundary-error runs
- prefix: `sourceNext(a)`
- target event: `sourceError(e)` or `boundaryError(e)`
- expected notifications: inner `error(e)` (not `complete`); outer `error(e)`
- lifecycle: the other upstream unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (59–62, 73, 86). Contrast `buffer`, which drops the partial instead of emitting it.

### S05 Cancel unsubscribes the subject

- Test ID: S05
- Covered row IDs: T08
- Starting state: `Open(W0)`
- Reset/fixture: an inner subscriber may already be attached
- prefix: `subscribe`, `sourceNext(a)`
- target event: `cancel`
- expected notifications: outer none; inner does not get `complete`
- lifecycle: `windowSubject.unsubscribe()` (94); source and boundaries unsubscribed
- suffix: a new subscribe to the captured observable sees a closed subject (`Subject.unsubscribe` sets `closed`, `Subject.ts` 100–103)
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (90–95)

## F. Coverage and evidence

Denominator = 10 (T01–T10). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | none | not executed |
| T10 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Inner subscribers are not modeled one by one; the subject contract is the stored data. Same-turn ordering is assumed. Reentrancy excluded. `ObjectUnsubscribedError` on use-after-unsubscribe is what `Subject` does after teardown; the exact error class is `Subject._throwIfClosed`.
- Contract vs 7.8.2 characterization: JSDoc matches boundary-`next` windowing. Boundary `complete` ignored, error mirrored into the inner, and cancel-unsubscribes-subject are source characterization.
- Tests still required: S01–S05, including an empty first window when the source completes immediately, and a boundary error after a previous window already completed.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
