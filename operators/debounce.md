# debounce

`debounce(durationSelector)` keeps the latest source value and subscribes to a fresh duration `ObservableInput` for every source value, unsubscribing the previous duration. The cached value is emitted only when that duration emits `next` (completion of the duration does not emit). A newer `sourceNext` drops the previous pending value. `sourceComplete` flushes a still-cached value and then completes, even if the duration already completed without a `next`. `sourceError` is immediate and does not flush. `cancel` drops the cache and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/debounce.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `debounce<T>(durationSelector: (value: T) => ObservableInput<any>): MonoTypeOperatorFunction<T>` (`debounce.ts` 66). One implementation.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 17–29. Code agrees: duration `next` emits via `emit` (`debounce.ts` 73–86, 100); duration `complete` is `noop` (line 100); source complete calls `emit()` then `subscriber.complete()` (104–108); source error handler is `undefined` (line 111) so `Subscriber._error` forwards immediately (`Subscriber.ts` 116–121).
- Model kind: extended/timed, not finite. The duration observable is an arbitrary inner sequence; only its first relevant signal is observed.
- Parameter domain: `durationSelector` must return an `ObservableInput` for each value. It is invoked once per `sourceNext`, with that value (`debounce.ts` 102). A throw, or `innerFrom` throw, is a user-callback fault, not a source error.
- Payload/error domain: cached `T` may be any value; presence is `hasValue`, not truthiness (`debounce.ts` 68–69, 79). Duration payloads are ignored (`emit` takes no value). Duration errors become output errors.
- Subscription boundary: one source `OperatorSubscriber` (`debounce.ts` 88–117). At most one `durationSubscriber`, also an `OperatorSubscriber` parented to the destination (`Subscriber.ts` 47–55), so destination unsubscribe tears it down.
- Scheduler and tie ordering: no scheduler argument. If the duration is time-based, the same virtual-time assumption applies outside this file: same-time actions run in schedule order. This is an assumption, not a proof. Synchronous duration `next` during `subscribe` is a nested micro-trace inside `sourceNext`.
- Callback assumptions: `durationSelector` runs inside the source `onNext` try/catch (`OperatorSubscriber.ts` 67–74). Duration `onNext` is `emit`; duration `onComplete` is `noop`; duration `onError` is default, so inner error is `destination.error`. Ordinary model: no reentrancy.
- Cleanup assumptions: `emit` unsubscribes the duration subscriber before `next` (`debounce.ts` 77–84). Finalize (112–115) nulls `lastValue` and `durationSubscriber` and does not emit. `cancel` does not complete.
- Explicit exclusions: reentrancy; modeling every notification of a long-lived duration after the first `next` (it is unsubscribed in `emit`); proving scheduler fairness inside user-supplied durations.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
```

Not finite: duration inputs are external.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Idle` | `hasValue = false`, `durationSubscriber = null`, `lastValue = null` | Nothing cached. |
| `Waiting(v)` | `hasValue`, `lastValue = v`, duration subscribed and not closed | Awaiting duration `next`. |
| `Held(v)` | `hasValue`, `lastValue = v`, duration subscriber closed without `emit` | Duration completed or was unsubscribed without a duration `next`. Cache retained until source complete, a new source value, or cancel. |
| `Stopped` | refs nulled | Terminal. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Subscribes source. |
| `sourceNext(v)` | yes | source | Replaces duration and cache (`debounce.ts` 91–102). |
| `sourceError(e)` | yes | source | Immediate `error(e)`, no flush (line 111). |
| `sourceComplete` | yes | source | `emit()` then `complete` (104–108). |
| `cancel` | yes | unsubscribe | Drop cache, no `complete`. |
| `durationNext` | yes | current duration | `emit` (line 100). |
| `durationComplete` | yes | current duration | `noop` then that inner subscriber unsubscribes (`OperatorSubscriber.ts` 89–100). Does not emit. Moves `Waiting` to `Held`. |
| `durationError(e)` | yes | current duration | Default error → `outError(e)`, no flush. |
| `selectorThrow(e)` / `innerFrom` throw | yes | user callback | `destination.error(e)` from the source `onNext` catch. Cache is not emitted. |
| `timerFired` | no | — | Not scheduled by this file. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. `complete` only from the source-complete path, after optional flush. Micro-trace required when `sourceNext` synchronously causes `durationNext`/`durationError`/`durationComplete`, and when `sourceComplete` races a live duration.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | source subscribed; flags false/null (`debounce.ts` 68–71) | `Idle` | ε | `sourceNext` | S01 |
| T02 | `Idle` | `sourceNext(v)` | selector returns an input | `none` | `hasValue=true`, `lastValue=v`, subscribe duration (`debounce.ts` 95–102) | `Waiting(v)` | T01 | duration signal | S01 |
| T03 | `Waiting(v)` or `Held(v)` | `sourceNext(w)` | selector returns | `none` | unsubscribe previous duration; replace cache with `w`; new duration (`debounce.ts` 95–102) | `Waiting(w)` | T02 | `v` never emitted | S02 |
| T04 | `Waiting(v)` | `durationNext` | `hasValue` | `next(v)` | unsubscribe duration; `hasValue=false`; `lastValue=null` (`debounce.ts` 73–85) | `Idle` | T02 | later source value | S01 |
| T05 | `Waiting(v)` | `durationNext` | `hasValue` already false | `none` | `emit` still unsubscribes duration (`debounce.ts` 77–79) | `Idle` | — | inapplicable under ordinary no-reentrancy after T04 | — |
| T06 | `Waiting(v)` | `durationComplete` | — | `none` | inner subscriber unsubscribes; variable still points at closed subscriber until `emit` or the next source value; `hasValue` stays true | `Held(v)` | T02 | `sourceComplete` still flushes | S03 |
| T07 | `Waiting(v)` | `durationError(e)` | — | `error(e)`; `v` dropped | default `_error`; destination teardown unsubscribes source | `Stopped` | T02 | none | S04 |
| T08 | `Waiting(v)` or `Held(v)` | `sourceComplete` | `hasValue` | `next(v)` then `complete` | `emit` then `subscriber.complete()` (104–108) | `Stopped` | T02 or T06 | none | S03 |
| T09 | `Idle` | `sourceComplete` | `!hasValue` | `complete` | `emit` no-op | `Stopped` | T01 or T04 | none | S05 |
| T10 | `Waiting`/`Held`/`Idle` | `sourceError(e)` | — | `error(e)`; pending dropped | line 111 default forward; finalize nulls refs (112–115) | `Stopped` | T02 | none | S04 |
| T11 | any non-terminal | `cancel` | — | `none` | child duration unsubscribed with destination; finalize nulls refs; no `complete` | `Stopped` | T02 | duration must not `next` | S06 |
| T12 | `Idle` or during T02 | `selectorThrow(e)` | throw before subscribe, after cache write (`debounce.ts` 96–102) | `error(e)`; no `next(v)` | source `onNext` catch | `Stopped` | T01 | none | S07 |
| T13 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T14 | `Idle` | `durationNext`/`durationComplete` | no live duration | — | inapplicable | `Idle` | — | — | — |
| T15 | `Held(v)` | `durationNext` | duration already closed | — | inapplicable; no subscription | `Held(v)` | T06 | T08 | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | At most one duration subscription is live. A new `sourceNext` unsubscribes the previous one before subscribing (`debounce.ts` 95). |
| I02 | Duration `next` emits the cached value at most once and clears `hasValue` before `subscriber.next` (lines 79–84). |
| I03 | Duration `complete` does not emit and does not clear `hasValue` (complete handler `noop`, line 100). |
| I04 | Duration `error` and `durationSelector` throw become output `error` and do not emit the cache. |
| I05 | `sourceComplete` flushes iff `hasValue`, including `Held`, then `complete`. |
| I06 | `sourceError` and `cancel` do not flush. `cancel` does not `complete`. |
| I07 | Only the first duration `next` matters; `emit` unsubscribes immediately (lines 74–78). |
| I08 | Relative to pre-v7 folklore: an empty/completing duration does not by itself release the value. Release on that path waits for `sourceComplete` (or is replaced by a newer value). |

## E. Scenario specification

### S01 Duration next emits the cached value

- Test ID: S01
- Covered row IDs: T01, T02, T04
- Starting state: unsubscribed
- Reset/fixture: `durationSelector` returns a cold observable that `next`s once then completes
- prefix: `subscribe`
- target event: `durationNext` after `sourceNext(a)`
- expected notifications: `next(a)`
- lifecycle: duration unsubscribed inside `emit` before the following duration `complete` is observed
- suffix: `Idle`; duration `complete` is not delivered after unsubscribe
- final state: `Idle`
- version and scheduler: 7.8.2; duration’s own scheduler if any
- assertion type: source characterization
- oracle source: source characterization (`debounce.ts` 73–85, 100–102)

### S02 New source value replaces duration and cache

- Test ID: S02
- Covered row IDs: T03, T04
- Starting state: `Waiting(a)`
- Reset/fixture: first duration not yet signaled
- prefix: `sourceNext(a)`
- target event: `sourceNext(b)` then the second duration’s `next`
- expected notifications: `next(b)` only
- lifecycle: first duration unsubscribed at `sourceNext(b)` (`debounce.ts` 95)
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 Complete flushes even if duration already completed silently

- Test ID: S03
- Covered row IDs: T06, T08
- Starting state: `Waiting(a)`
- Reset/fixture: duration is `EMPTY` (complete, no next) or completes without `next`
- prefix: `sourceNext(a)`, `durationComplete`
- target event: `sourceComplete`
- expected notifications: `none` on `durationComplete`; on source complete, `next(a)` then `complete`
- lifecycle: duration subscriber closed at its complete; `emit` on source complete still sees `hasValue`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (complete handler `noop` vs source complete 104–108). Differs from `audit`, which does not flush on duration complete.

### S04 Inner error and source error both drop the cache

- Test ID: S04
- Covered row IDs: T07, T10
- Starting state: `Waiting(a)`
- Reset/fixture: two runs, one duration error, one source error
- prefix: `sourceNext(a)`
- target event: `durationError(e)` or `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: destination unsubscribe tears down the other subscription; finalize nulls cache
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 100 default error; line 111)

### S05 Idle complete

- Test ID: S05
- Covered row IDs: T09
- Starting state: `Idle`
- Reset/fixture: no pending value
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `complete`
- lifecycle: `emit` no-op
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Cancel

- Test ID: S06
- Covered row IDs: T11
- Starting state: `Waiting(a)`
- Reset/fixture: live duration
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: duration unsubscribed via parent `subscriber`; finalize (112–115); no `complete`
- suffix: a late duration `next` must not be delivered
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S07 Selector throw

- Test ID: S07
- Covered row IDs: T12
- Starting state: `Idle`
- Reset/fixture: `durationSelector` throws `e`
- prefix: `subscribe`
- target event: `sourceNext(a)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: throw happens after `hasValue`/`lastValue` assignment but before a successful duration subscribe (`debounce.ts` 96–102); catch in `OperatorSubscriber.ts` 71–73
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 15 (T01–T15). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01, S02 | not executed |
| T05 | none (inapplicable) | not executed |
| T06 | S03 | not executed |
| T07 | S04 | not executed |
| T08 | S03 | not executed |
| T09 | S05 | not executed |
| T10 | S04 | not executed |
| T11 | S06 | not executed |
| T12 | S07 | not executed |
| T13 | none | not executed |
| T14 | none | not executed |
| T15 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Synchronous duration signals are specified only as a nested micro-trace, not as a reentrancy proof. User durations that `next` more than once are unsubscribed on the first `next`. Scheduler ordering is not part of this file.
- Contract vs 7.8.2 characterization: JSDoc 26–29 matches complete-flush and error-drop. JSDoc 21–25 matches “emit on duration next, drop previous on a new source value.” It does not spell out that duration `complete` without `next` leaves the value cached; that is source characterization (line 100 `noop` vs `emit` on source complete).
- Tests still required: S01–S07, including `EMPTY` duration then source complete, sync `of(0)` duration, selector throw, and cancel during `Waiting`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
