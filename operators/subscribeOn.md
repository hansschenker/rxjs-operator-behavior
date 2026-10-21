# subscribeOn

`subscribeOn(scheduler, delay = 0)` schedules only the act of subscribing to `source` (`subscribeOn.ts` 63–66). It does not reschedule `next`, `error`, or `complete`. Those are delivered whenever the source delivers them, which for a synchronous source is inside the scheduled subscribe action. Unsubscribe is not scheduled: if it happens before the action runs, the action is disposed and the source is never subscribed; if it happens after, teardown is the normal synchronous subscriber chain. `cancel` does not emit `complete`. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/subscribeOn.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `subscribeOn<T>(scheduler: SchedulerLike, delay: number = 0): MonoTypeOperatorFunction<T>` (`subscribeOn.ts` 63).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 5–11 and the example (36–52): subscription of this source is deferred onto `scheduler`, so a synchronous sibling can emit first. The implementation is one `scheduler.schedule(() => source.subscribe(subscriber), delay)` added to `subscriber` (line 65).
- Model kind: timed only for the subscribe instant. After subscribe, this operator adds no clock. Not a finite machine if `delay` and the source’s own time are included, but the operator’s own control state is tiny.
- Parameter domain: `scheduler` required. `delay` defaults to 0 and is passed to `schedule`. Negative/`NaN` delay is scheduler-defined and excluded.
- Payload/error domain: unchanged from `source`. This operator does not wrap errors.
- Subscription boundary: the downstream subscriber is passed directly to `source.subscribe` when the action runs (line 65). Source notifications are not passed through `observeOn` or `executeSchedule`. The schedule subscription is a child of `subscriber`, so destination unsubscribe disposes it.
- Scheduler and tie ordering: assumption, not a proof: the subscribe action runs with other actions due at the same virtual time in schedule order. That is why `merge(of(1).pipe(subscribeOn(async)), of(2))` can emit `2` first in the JSDoc example: `of(2)` subscribes synchronously, while `a`’s subscribe is queued. Micro-trace required only for the subscribe action versus `cancel` or versus sibling work scheduled at the same time. This file does not define sibling scheduling.
- Callback assumptions: no user selector. No reentrancy in the ordinary model. A synchronous source may `next`, `error`, or `complete` inside the scheduled `source.subscribe` call; those are source signals that happen to run on the scheduler turn, not separately scheduled notifications.
- Cleanup assumptions: unsubscribe before the action runs prevents `source.subscribe` (the scheduled `Subscription` is unsubscribed). Unsubscribe does not call `scheduler.schedule` itself. There is no “schedule the unsubscribe” line in this file. After subscribe, unsubscribing the destination unsubscribes the source because `source.subscribe(subscriber)` chains teardown onto that subscriber (`Subscriber` constructor adds child subscriptions the source registers). `cancel` does not emit `complete`.
- Explicit exclusions: older RxJS behavior that scheduled unsubscribe on the same scheduler (not present in 7.8.2); `observeOn`-style delay of each notification; reentrancy; negative delay.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Scheduled
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Scheduled` | one subscribe action, source not subscribed | Initial after downstream subscribe. |
| `Subscribed` | action has run; source subscription live | Notifications are the source’s. |
| `Stopped` | never subscribed, or source terminated, or cancelled | Terminal for this operator’s own lifecycle. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Queues the subscribe action (line 65). Does not call `source.subscribe` now. |
| `timerFired(subscribe)` | yes | scheduler | Calls `source.subscribe(subscriber)`. |
| `cancel` | yes | unsubscribe | Before fire: drop the action. After fire: unsubscribe source. No `complete` from this operator. |
| `sourceNext(v)` | yes, passed through | source, only in `Subscribed` | Delivered immediately to `subscriber`, on whatever turn the source uses. |
| `sourceError(e)` | yes, passed through | source | Immediate relative to the source signal. Not re-delayed. |
| `sourceComplete` | yes, passed through | source | Same. |
| inner notifications | no | — | None introduced here. |
| user callback | no | — | No selector. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`, all of the last three being source notifications observed without an extra queue. Micro-trace required between `subscribe`, `cancel`, and `timerFired(subscribe)`.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `subscriber.add(scheduler.schedule(subscribe source, delay))` (`subscribeOn.ts` 65) | `Scheduled` | ε | wait `delay` | S01 |
| T02 | `Scheduled` | `timerFired(subscribe)` | action not disposed | `none` from this operator itself | `source.subscribe(subscriber)` (line 65). A sync source may then emit as nested signals | `Subscribed`, or `Stopped` if the source terminated during subscribe | T01 | source signals | S01 |
| T03 | `Scheduled` | `cancel` | action not yet run | `none` | schedule subscription unsubscribed; `source.subscribe` never called; no `complete` | `Stopped` | T01 | due time must not subscribe | S02 |
| T04 | `Subscribed` | `sourceNext(v)` | source emits | `next(v)` | no extra schedule | `Subscribed` | T02 | — | S01 |
| T05 | `Subscribed` | `sourceError(e)` | — | `error(e)` now, not after `delay` | source and destination stop | `Stopped` | T02 | none | S03 |
| T06 | `Subscribed` | `sourceComplete` | — | `complete` now | source and destination stop | `Stopped` | T02 | none | S01 |
| T07 | `Subscribed` | `cancel` | — | `none` | source unsubscribed synchronously; unsubscribe is not passed to `scheduler.schedule`; no `complete` | `Stopped` | T02 | source must not emit | S04 |
| T08 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T09 | `Scheduled` | `sourceNext` | source not subscribed | — | inapplicable | `Scheduled` | T01 | — | — |
| T10 | any | scheduled unsubscribe | — | — | inapplicable: no such action in 7.8.2 | — | — | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | `source.subscribe` runs on the scheduler after `delay`, not in the downstream subscribe turn, unless the scheduler itself runs delay 0 synchronously. |
| I02 | `next`, `error`, and `complete` are not each wrapped in `schedule`. A synchronous source emits them inside T02. |
| I03 | `error` is not given an extra delay after the source has been subscribed. |
| I04 | `cancel` before T02 prevents subscription and emits nothing. |
| I05 | `cancel` after T02 unsubscribes the source without scheduling that unsubscribe and without emitting `complete`. |
| I06 | This operator does not by itself reorder notifications of a single source. Reordering versus other sources comes from delaying subscription (JSDoc example 46–52). |

## E. Scenario specification

### S01 Deferred subscribe of a synchronous source

- Test ID: S01
- Covered row IDs: T01, T02, T04, T06
- Starting state: unsubscribed
- Reset/fixture: `subscribeOn(virtual, 10)`, source `of(a)` which emits and completes synchronously when subscribed
- prefix: downstream `subscribe` at t=0
- target event: subscribe action at t=10
- expected notifications: `none` at t=0; `next(a)`, `complete` at t=10, during the action, not as separate delayed actions
- lifecycle: one schedule subscription; source subscribed inside it
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`subscribeOn.ts` 65) and contract (JSDoc example 36–52)

### S02 Cancel before subscribe

- Test ID: S02
- Covered row IDs: T03
- Starting state: `Scheduled`
- Reset/fixture: `delay = 10`; cancel at t=1
- prefix: T01
- target event: `cancel`
- expected notifications: none
- lifecycle: scheduled action disposed; source subscription count stays 0; no `complete`
- suffix: t=10 does not call `source.subscribe`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (line 65 `subscriber.add`)

### S03 Error is not additionally delayed

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Subscribed`
- Reset/fixture: source errors synchronously inside subscribe
- prefix: T02 begins `source.subscribe`
- target event: `sourceError(e)` nested in that subscribe
- expected notifications: `error(e)` on the same scheduler turn as subscribe, not at `+delay` again
- lifecycle: destination stopped from the source error
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (no `executeSchedule` around error)

### S04 Cancel after subscribe does not schedule unsubscribe

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Subscribed`
- Reset/fixture: source is a live interval or subject; `delay` already elapsed
- prefix: T02
- target event: `cancel`
- expected notifications: none
- lifecycle: source unsubscribed on the caller’s turn, not via `scheduler.schedule`; no `complete`
- suffix: source must not emit
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (the file contains a single `schedule` call, line 65)

## F. Coverage and evidence

Denominator = 10 (T01–T10). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01 | not executed |
| T05 | S03 | not executed |
| T06 | S01 | not executed |
| T07 | S04 | not executed |
| T08 | none | not executed |
| T09 | none (inapplicable) | not executed |
| T10 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. “Usually unsubscribes on the scheduler” is false for this version: unsubscribe is synchronous. Same-time ordering versus other scheduled work is an assumption. Synchronous emission inside T02 is source behavior, not a second queue.
- Contract vs 7.8.2 characterization: JSDoc matches deferred subscription. It does not claim that each notification is scheduled; `observeOn` is the operator that does that.
- Tests still required: S01–S04, plus a merge with a synchronous sibling as in the JSDoc example, on `TestScheduler`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
