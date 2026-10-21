# delay

`delay(due, scheduler = asyncScheduler)` is `delayWhen(() => duration)` where `duration = timer(due, scheduler)` is created once (`delay.ts` 62–65). Each source value subscribes to that cold timer, so a numeric `due` delays that value by `due` from the time it is emitted, and a `Date` holds the value until that absolute time (`timer.ts` 159–163 clamps a past date to due `0`). In-flight values are concurrent. Source `complete` waits until those timers flush. Source `error` is not delayed: it is immediate and drops values still in flight. `cancel` clears the timers and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/delay.ts` delegating to `delayWhen.ts` and `timer.ts`. Not deprecated. There is no `subscriptionDelay` on this wrapper.

## A. Identity, contract, and scope

- Operator/overload: `delay<T>(due: number | Date, scheduler: SchedulerLike = asyncScheduler): MonoTypeOperatorFunction<T>` (`delay.ts` 62).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: numeric `due` time-shifts each item (JSDoc 15–17). `Date` is implemented as “each value’s timer is due at that date,” computed at each inner subscription (`timer.ts` 159). The source is subscribed immediately. JSDoc 19–20 says a `Date` “time shifts the start of the Observable execution”; the code does not delay the source subscription. Code wins for the subscription boundary; values that arrive before the date are emitted at the date, in schedule order, and later values are delayed by 0.
- Model kind: timed, not finite. In-flight set is unbounded.
- Parameter domain: `due` number or valid `Date` (`isValidDate`, `isDate.ts` 8–10). Invalid `Date` fails `isValidDate` and is treated by `timer` as a numeric due (`timer.ts` 159); excluded. Negative numeric due is clamped to 0 by `timer` (161–163). `scheduler` defaults to `asyncScheduler`. `timer`’s own limitation applies: a `Date` plus a scheduler whose `now()` is not epoch-based is wrong (`timer.ts` 74–78).
- Payload/error domain: output payloads are source values (`delayWhen` `mapTo`). `timer` emits `0` then completes; `take(1)` turns that into one release. `timer` does not error.
- Subscription boundary: `delayWhen` without a gate (`delay.ts` 64 calls the one-argument form). `mergeMap` subscribes to source immediately and to `timer` per value. The shared `duration` observable is cold: each subscribe schedules independently (`timer.ts` 155–184).
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. Numeric delays of equal length therefore preserve source order. A `Date` schedules each subscription for `max(0, +date - scheduler.now())` at that subscribe. Micro-trace required when complete, error, or cancel meets due timers.
- Callback assumptions: selector `() => duration` does not throw. No per-value user callback. Downstream throw is an observer fault. Ordinary model: no reentrancy.
- Cleanup assumptions: source error and `cancel` unsubscribe in-flight `timer` actions via the `mergeMap` subscriber tree. Those timers must not emit. `cancel` does not complete. Source complete does not cancel in-flight timers; it waits for them.
- Explicit exclusions: reentrancy; `subscriptionDelay` (not exposed here); invalid `Date`; non-epoch `scheduler.now()` with a `Date`; real-time `setTimeout` range limits (`timer.ts` 73).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Live(active = ∅)
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Live` | source open; set of in-flight values with due times | Accepting. |
| `Draining` | source completed; in-flight set non-empty | Output not yet complete. |
| `Stopped` | terminal | — |

`Gated` from deprecated `delayWhen` is not reachable: `delay` does not pass `subscriptionDelay`.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Source subscribed now, even for a future `Date`. |
| `sourceNext(v)` | yes | source | Subscribe `timer(due)` (`delay.ts` 63–64, `delayWhen.ts` 102). |
| `sourceError(e)` | yes | source | Immediate `error(e)`. Not scheduled. In-flight dropped. |
| `sourceComplete` | yes | source | Delayed until in-flight timers settle (`mergeInternals.ts` 43–48). |
| `cancel` | yes | unsubscribe | Timers cleared; no `complete`. |
| `timerFired(v)` | yes | that value’s `timer` `next` | Output `next(v)` then that inner completes. |
| duration error | no | stock `timer` | Inapplicable. |
| selector throw | no | constant selector | Inapplicable. |
| `gate*` | no | not used | Inapplicable. |
| user callback | no selector | downstream throw only | Fault. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. `error` is not delayed. `complete` is delayed by remaining in-flight work. Micro-trace required.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | create one cold `timer` observable; subscribe source immediately (`delay.ts` 62–64) | `Live(∅)` | ε | source | S01 |
| T02 | `Live` | `sourceNext(v)` | `due` is a number | `none` | schedule `timer` for `max(0, due)` from now (`timer.ts` 159–163) | `Live` + `v` | T01 | `timerFired(v)` | S01 |
| T03 | `Live` | `sourceNext(v)` | `due` is a valid `Date` | `none` | due delay `max(0, +date - scheduler.now())` at this subscription (`timer.ts` 159–163) | `Live` + `v` | T01 | fire at the date, or asap if past | S02 |
| T04 | `Live` or `Draining` | `timerFired(v)` | inner still subscribed | `next(v)` | `take(1)` completes inner; timer’s following `complete` is not observed after unsubscribe; `active--` | `Live` or completion via T07 | T02 or T03 | other in-flight timers unchanged | S01 |
| T05 | `Live`, nothing in flight | `sourceComplete` | `active=0` | `complete` | `checkComplete` | `Stopped` | T01 or after flushes | none | S03 |
| T06 | `Live`, in flight | `sourceComplete` | `active>0` | `none` | enter drain; timers stay armed | `Draining` | T02 | T04 then T07 | S01 |
| T07 | `Draining` | last `timerFired` or last inner settles | `active` hits 0 | `next` of that value (if the timer `next`s) then `complete` | `checkComplete` (`mergeInternals.ts` 47–48) | `Stopped` | T06 | none | S01 |
| T08 | `Live` or `Draining` | `sourceError(e)` | — | `error(e)` immediately; no delayed `next` | unsubscribe all timers | `Stopped` | T02 | due time must not emit | S04 |
| T09 | any non-terminal | `cancel` | — | `none` | unsubscribe timers; no `complete` | `Stopped` | T02 | due time must not emit | S05 |
| T10 | past `Date` or negative number | `sourceNext(v)` | due clamped to 0 | `next(v)` when the 0-delay action runs, not necessarily synchronously inside `sourceNext` | still a scheduled action (`timer.ts` 170) | per T04 | T03 | scheduler flush | S02 |
| T11 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T12 | any | `subscriptionDelay` / selector throw / timer error | — | — | inapplicable on this wrapper | — | — | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Numeric `due` shifts each value by `due` from its own `sourceNext`, not from subscription, except the clamp of negatives to 0. |
| I02 | Relative gaps between values are preserved for a constant numeric `due` under schedule-order of equal delays. They are not preserved for a `Date` (pre-date values collapse onto that date). |
| I03 | Source subscription is not delayed, including for a `Date`. |
| I04 | Source `error` is not delayed and drops in-flight values. |
| I05 | Source `complete` is delayed until every in-flight `timer` has emitted (or been clamped and flushed). |
| I06 | `cancel` clears timers and does not complete. |
| I07 | Each value uses its own `timer` subscription even though the `Observable` instance is shared (`delay.ts` 63). |

## E. Scenario specification

### S01 Numeric delay flushes on complete

- Test ID: S01
- Covered row IDs: T01, T02, T04, T06, T07
- Starting state: unsubscribed
- Reset/fixture: `delay(10)`, virtual scheduler
- prefix: `subscribe` at t=0, `sourceNext(a)` at t=0, `sourceComplete` at t=0
- target event: `timerFired(a)` at t=10
- expected notifications: `next(a)` at t=10, then `complete` at t=10; nothing at t=0 except subscription
- lifecycle: one timer; unsubscribed after its `next` by `take(1)`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`delay.ts` 62–64, `mergeInternals.ts` 43–48, `timer.ts` 169–181)

### S02 Date due, including a past date

- Test ID: S02
- Covered row IDs: T03, T04, T10
- Starting state: `Live`
- Reset/fixture: `due = someDate`; `scheduler.now()` comparable with `+someDate`
- prefix: `subscribe` (source already subscribed)
- target event: `sourceNext(a)` while now is before the date, and a separate run where now is after the date
- expected notifications: before: `next(a)` when the scheduled due elapses; after: `next(a)` on the 0-delay action, not by skipping the scheduler
- lifecycle: due computed at inner subscribe (`timer.ts` 159–163)
- suffix: `Live` if the source is still open
- final state: `Live` after the flush
- version and scheduler: 7.8.2, virtual scheduler with epoch-like `now()`
- assertion type: source characterization
- oracle source: source characterization. JSDoc 19–20 does not describe this per-value date hold.

### S03 Immediate complete

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Live(∅)`
- Reset/fixture: no values
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `complete` with no delay
- lifecycle: no timer subscriptions
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S04 Error is immediate

- Test ID: S04
- Covered row IDs: T08
- Starting state: `Live` with `a` scheduled
- Reset/fixture: `delay(10)`, error at t=1, timer due at t=10
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)` at t=1, not `next(a)` at t=10
- lifecycle: timer unsubscribed
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (contrast `observeOn`, which schedules errors)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T09
- Starting state: `Live` with `a` scheduled
- Reset/fixture: timer not yet due
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: timer action unsubscribed; no `complete`
- suffix: due time must not emit
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 12 (T01–T12). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01, S02 | not executed |
| T05 | S03 | not executed |
| T06 | S01 | not executed |
| T07 | S01 | not executed |
| T08 | S04 | not executed |
| T09 | S05 | not executed |
| T10 | S02 | not executed |
| T11 | none | not executed |
| T12 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Order preservation for equal numeric delays is the schedule-order assumption. `Date` behavior is per emission, not a delayed subscribe. Past dates and negative numbers still go through the scheduler at delay 0. No tests of `timer`’s non-epoch `now()` warning.
- Contract vs 7.8.2 characterization: numeric JSDoc matches. Date JSDoc (“shifts the start of execution”) does not match the immediate source subscription. Error-is-immediate and complete-is-delayed are inherited from `delayWhen`/`mergeInternals`/`timer`, and they match the `observeOn` JSDoc contrast in `observeOn.ts` 26–28.
- Tests still required: S01–S05, two values with the same numeric delay (order), two values around a `Date`, error while a timer is armed, unsubscribe while a timer is armed.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
