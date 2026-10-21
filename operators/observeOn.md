# observeOn

`observeOn(scheduler, delay = 0)` reschedules every source `next`, `error`, and `complete` onto `scheduler` with the same `delay` (`observeOn.ts` 59–68). Unlike `delay`, the error is not forwarded synchronously; it is an action. Each notification is its own `executeSchedule` subscription added to the destination (`executeSchedule.ts` 26–35), so `cancel` drops actions that have not run and does not emit `complete`. There is no value queue inside the operator beyond the scheduler queue. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/observeOn.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `observeOn<T>(scheduler: SchedulerLike, delay = 0): MonoTypeOperatorFunction<T>` (`observeOn.ts` 59).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 16–30. All three notification kinds are scheduled (lines 64–66). JSDoc explicitly contrasts this with `delay`, which lets source errors pass immediately (lines 26–28). That contrast matches both files.
- Model kind: timed, not finite. The scheduler queue of pending notifications is unbounded if the source emits faster than actions run.
- Parameter domain: `scheduler` is required. `delay` defaults to 0 and is passed through to `scheduler.schedule` (`executeSchedule.ts` 23). Negative or `NaN` delay is scheduler-defined and excluded. `delay` here is not `delay()`.
- Payload/error domain: `next` payloads are unchanged. `error` payloads are unchanged but deferred. No inner observable and no `TimeoutError`.
- Subscription boundary: source is subscribed synchronously inside `operate` (`observeOn.ts` 61–68). Only the delivery of notifications is scheduled. Source teardown follows destination unsubscribe.
- Scheduler and tie ordering: assumption, not a proof: actions due at the same virtual time run in the order they were scheduled. Synchronous source `next` then `complete` therefore schedules `next`’s action before `complete`’s action, both due at `now+delay`, and they run in that order. Micro-trace required.
- Callback assumptions: no user selector. The scheduled work closes over `value` or `err`. A throw from `subscriber.next` / `error` / `complete` happens later, on the scheduler, outside the source `onNext` try/catch. Ordinary model: no reentrancy from those observer calls back into this operator.
- Cleanup assumptions: `executeSchedule` does `parentSubscription.add(scheduleSubscription)` (`executeSchedule.ts` 35). `cancel` unsubscribes those actions. Work that has not run does not run. `cancel` does not schedule `complete`. After an action starts, `executeSchedule` unsubscribes that action when `repeat` is false (lines 30–32), which is after `work()`.
- Explicit exclusions: reentrancy; using `observeOn` to chunk a synchronous flood (JSDoc 20–23 calls that an anti-pattern and it is not given a separate machine); host timer clamping; proving `animationFrameScheduler`.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Live(queue = ε)
```

The queue is the scheduler’s sequence of pending `(kind, payload)` actions due at schedule-time `+ delay`. It is not a separate buffer object in this file.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Live` | zero or more pending actions, source still subscribed | Normal. |
| `Stopped` | source and pending actions released | After delivered `error` or `complete`, or after `cancel`. |

Once a scheduled `error` or `complete` runs, the destination stops and tears down remaining actions. That teardown is part of the transition that delivers the terminal notification.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Subscribes source immediately. |
| `sourceNext(v)` | yes | source | Schedule `() => subscriber.next(v)` at `delay` (line 64). Output `none` now. |
| `sourceError(e)` | yes | source | Schedule `() => subscriber.error(e)` (line 66). Not immediate. |
| `sourceComplete` | yes | source | Schedule `() => subscriber.complete()` (line 65). |
| `timerFired(id)` | yes | the action scheduled for that notification | Delivers that one notification. |
| `cancel` | yes | unsubscribe | Drops pending actions; no `complete`. |
| inner notifications | no | — | None. |
| user callback throw | yes | observer, when the action runs | Not a source error. Not caught by this operator. Modeled as a fault at delivery, out of the ordinary transitions. |

### Γ

`none` at scheduling time. At `timerFired`: `next(v)` | `error(e)` | `complete`. Micro-trace required because scheduling and delivery are different steps, and several deliveries can share a due time.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | synchronous source subscribe (`observeOn.ts` 61) | `Live(ε)` | ε | source notifications | S01 |
| T02 | `Live` | `sourceNext(v)` | destination still open | `none` | `executeSchedule(subscriber, scheduler, next v, delay)` (line 64, `executeSchedule.ts` 26–35) | `Live` with `next(v)` queued | T01 | `timerFired` | S01 |
| T03 | `Live` | `sourceError(e)` | — | `none` now | queue `error(e)` (line 66). Source subscriber will stop after scheduling, via default `_error` finally-unsubscribe (`Subscriber.ts` 116–121), but the action is already added to the destination | `Live` with `error(e)` queued | T01 or T02 | must not deliver `error` before its delay | S02 |
| T04 | `Live` | `sourceComplete` | — | `none` now | queue `complete` (line 65); source subscriber stops after the schedule call | `Live` with `complete` queued | T02 | delivery order follows schedule order | S01 |
| T05 | `Live` | `timerFired(next v)` | action due and not unsubscribed | `next(v)` | action unsubscribes itself after work (`executeSchedule.ts` 30–32) | `Live` without that action | T02 | later queued actions remain | S01 |
| T06 | `Live` | `timerFired(error e)` | action due | `error(e)` | destination stops; later queued actions are unsubscribed with the destination and must not run | `Stopped` | T03 | no `complete` | S02 |
| T07 | `Live` | `timerFired(complete)` | action due | `complete` | destination stops; later actions dropped | `Stopped` | T04 | none | S01 |
| T08 | `Live` | `cancel` | pending actions may exist | `none` | all scheduled subscriptions unsubscribed; source unsubscribed; no `complete` | `Stopped` | T02 or T03 | due time must not deliver | S03 |
| T09 | `Stopped` | source or timer | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T10 | `Live` | inner notifier | — | — | inapplicable | `Live` | — | — | — |
| T11 | same due time | several queued actions | schedule-order assumption | deliveries in schedule order, no extra sort | not a second code path; it is the tie rule for T05–T07 | per those rows | T02 then T04 in one turn | micro-trace | S04 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Source `next`, `error`, and `complete` are all delayed by `delay` on `scheduler` (`observeOn.ts` 64–66). |
| I02 | Nothing is emitted synchronously from the source handler unless `delay` is 0 and the scheduler runs the action synchronously. Default `asyncScheduler` does not. |
| I03 | Relative order of notifications that were scheduled in a single synchronous turn is the schedule order of their actions. |
| I04 | `cancel` deletes pending deliveries and does not emit `complete`. |
| I05 | A delivered `error` or `complete` prevents later scheduled notifications from running, because they were added on the destination subscription. |
| I06 | The source’s own scheduler is unchanged (JSDoc 17–19). This operator only reschedules what the source already emitted. |
| I07 | There is no “error bypass” comparable to `delay`. |

## E. Scenario specification

### S01 Next then complete are both delayed, in order

- Test ID: S01
- Covered row IDs: T01, T02, T04, T05, T07
- Starting state: unsubscribed
- Reset/fixture: `observeOn(virtual, 10)`; source emits `a` and completes synchronously
- prefix: `subscribe`
- target event: the two actions at t=10, in schedule order
- expected notifications: `next(a)` then `complete`, both at t=10; nothing at t=0
- lifecycle: two actions; each unsubscribes after running; complete tears down anything still queued
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`observeOn.ts` 64–65, `executeSchedule.ts` 26–35)

### S02 Error is delayed

- Test ID: S02
- Covered row IDs: T03, T06
- Starting state: `Live`
- Reset/fixture: `delay = 10`; source errors synchronously with `e`, optionally after a `next` that is also queued
- prefix: `subscribe`
- target event: source error at t=0; delivery at t=10
- expected notifications: `none` at t=0; `error(e)` at t=10. If a `next` was scheduled first in the same turn, `next` then `error` at t=10 (T11)
- lifecycle: error action added to destination before the source subscriber finalizes
- suffix: `Stopped`; no `complete`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (line 66) and contract contrast (JSDoc 26–28)

### S03 Cancel drops a queued next and a queued error

- Test ID: S03
- Covered row IDs: T08
- Starting state: `Live` with a queued `next` or `error`
- Reset/fixture: `delay = 10`; cancel at t=1
- prefix: `sourceNext(a)` or `sourceError(e)`
- target event: `cancel`
- expected notifications: none
- lifecycle: `executeSchedule` subscription unsubscribed via `subscriber.add`; no `complete`
- suffix: t=10 must not deliver
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`executeSchedule.ts` 35)

### S04 Same-timestamp order

- Test ID: S04
- Covered row IDs: T11, T05, T07
- Starting state: `Live`
- Reset/fixture: synchronous `next(a)`, `next(b)`, `complete` while `delay = 5`
- prefix: those three source signals in one turn
- target event: virtual time reaches +5
- expected notifications: `next(a)`, `next(b)`, `complete`
- lifecycle: three actions scheduled in that order
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler under the tie assumption
- assertion type: source characterization
- oracle source: source characterization plus the stated schedule-order assumption

## F. Coverage and evidence

Denominator = 11 (T01–T11). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01 | not executed |
| T05 | S01, S04 | not executed |
| T06 | S02 | not executed |
| T07 | S01, S04 | not executed |
| T08 | S03 | not executed |
| T09 | none | not executed |
| T10 | none (inapplicable) | not executed |
| T11 | S04 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Same-time order is an assumption about the scheduler, not a theorem. Observer throws during a delayed delivery are outside the ordinary model. `delay < 0` is excluded.
- Contract vs 7.8.2 characterization: JSDoc and code agree, including the error-is-delayed contrast with `delay`.
- Tests still required: S01–S04 on `TestScheduler`, plus unsubscribe between schedule and due time for both `next` and `error`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
