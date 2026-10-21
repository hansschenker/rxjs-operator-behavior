# debounceTime

`debounceTime(dueTime, scheduler = asyncScheduler)` forwards only the latest source value after a quiet interval of `dueTime` on `scheduler`. Each `sourceNext` updates the cached value and the quiet deadline; a single scheduled action, on firing, either emits that latest value or reschedules until `scheduler.now()` reaches `lastTime + dueTime`. Source completion flushes a pending value and then completes. Source error is immediate and drops the pending value. Unsubscribe cancels the task, drops the pending value, and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, file `src/internal/operators/debounceTime.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `debounceTime<T>(dueTime: number, scheduler: SchedulerLike = asyncScheduler): MonoTypeOperatorFunction<T>` (`debounceTime.ts` 63). Single implementation; no config object.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: rate-limit by silence. At most one output `next` per quiet window, and that `next` is the latest source value whose arrival time is `lastTime` (`debounceTime.ts` 69–106). JSDoc 23–26 matches the code: complete flushes; error does not.
- Model kind: timed, not a finite Mealy machine. The quiet deadline is a clock value; `dueTime` is a parameter, not a finite control state.
- Parameter domain: `dueTime` is a number passed to `scheduler.schedule` and added to `scheduler.now()`. Documented domain is a non-negative duration in the scheduler’s unit (default milliseconds). Negative or `NaN` delays are host/scheduler-defined and excluded from the ordinary model. `scheduler` defaults to `asyncScheduler` (`debounceTime.ts` 63, import line 1).
- Payload/error domain: source values `T` (including `null`/`undefined`; the cache uses a separate `activeTask` presence test, not truthiness of `T`). Errors are forwarded as-is.
- Subscription boundary: `operate` subscribes to `source` with an `OperatorSubscriber` (`debounceTime.ts` 95–121). Output subscription is the downstream `subscriber`. No inner observable.
- Scheduler and tie ordering: assumption, not a proof: actions due at the same virtual time run in schedule order; `scheduler.now()` is that scheduler’s clock and is monotonic for the quiet-window test (`debounceTime.ts` 79–88). A `sourceNext` and a `timerFired` at the same virtual time are ordered by which action runs first. An ordered micro-trace is required whenever a timer and a notification interact.
- Callback assumptions: there is no duration selector. The only user callback is the downstream observer. A throw from `subscriber.next` inside `emit` is caught by `OperatorSubscriber._next` and becomes `destination.error` (`OperatorSubscriber.ts` 67–74). Ordinary model: no reentrancy (downstream `next`/`error`/`complete` does not call back into this operator).
- Cleanup assumptions: the scheduled task is `subscriber.add(activeTask)` (`debounceTime.ts` 88, 105), so destination unsubscribe unsubscribes it. Finalize (`debounceTime.ts` 116–119) nulls `lastValue` and `activeTask` and does not emit. `OperatorSubscriber.unsubscribe` runs `onFinalize` only if it was not already closed (`OperatorSubscriber.ts` 104–110).
- Explicit exclusions: reentrancy; interleaving with a custom scheduler whose `now()` is not the same clock used to run actions; proving `asyncScheduler`/`setTimeout` real-time ordering; `dueTime < 0` and `NaN`.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
```

This is a timed machine. Control locations are finite; the data (`lastValue`, `lastTime`, task id) and the clock are not.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Idle` | `activeTask = null`, `lastValue = null`, `lastTime = null` | No quiet window armed. Entry state after subscribe and after a successful flush. |
| `Pending(v, t)` | `activeTask` live, `lastValue = v`, `lastTime = t` | Latest value `v` arrived at scheduler time `t`; a task is armed. |
| `Stopped` | refs nulled by finalize | Terminal after complete, error, or cancel. No further `δ`. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream `subscribe` | Enters `Idle` and subscribes to source. |
| `sourceNext(v)` | yes | source | Always stores `v` and `scheduler.now()`. Arms a task only if `Idle`. |
| `sourceError(e)` | yes | source | Default `onError` (`undefined` at `debounceTime.ts` 115) is `Subscriber._error`: immediate `destination.error(e)` (`Subscriber.ts` 116–121). |
| `sourceComplete` | yes | source | Calls `emit()` then `subscriber.complete()` (`debounceTime.ts` 107–112). |
| `cancel` | yes | downstream `unsubscribe` | Teardown only. Not a notification. |
| inner next/error/complete | no | — | No inner observable. |
| `timerFired` | yes | scheduler action `emitWhenIdle` (`debounceTime.ts` 79–93) | May reschedule or flush. |
| user callback throw | yes, as fault | downstream `next` during `emit` | Becomes `outError`. Not a source error. No duration selector. |

### Γ

| Symbol | When |
| --- | --- |
| `none` | No downstream notification. |
| `next(v)` | Quiet window elapsed, or complete-flush of a pending value. |
| `error(e)` | Source error, or a throw from `emit`’s `subscriber.next`. |
| `complete` | After the complete-flush attempt. Never on cancel. |

`λ` is the notification column of section C. Ordered micro-trace: required for `Pending` × (`timerFired`, `sourceNext`, `sourceComplete`, `sourceError`, `cancel`).

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | operator applied | `none` | subscribe source; `activeTask = null` | `Idle` | ε | source may emit | S01 |
| T02 | `Idle` | `sourceNext(v)` | no `activeTask` | `none` | `lastValue=v`, `lastTime=now`, `schedule(emitWhenIdle, dueTime)`, `subscriber.add` | `Pending(v, now)` | T01 | wait `dueTime` | S01 |
| T03 | `Pending(v, t)` | `sourceNext(w)` | task already armed | `none` | overwrite `lastValue=w`, `lastTime=now`; do not schedule a second task (`debounceTime.ts` 102–106) | `Pending(w, now)` | T02 | `timerFired` | S02 |
| T04 | `Pending(v, t)` | `timerFired` | `now < t + dueTime` | `none` | replace `activeTask` with `this.schedule(undefined, t+dueTime-now)` and `subscriber.add` (`debounceTime.ts` 85–89) | `Pending(v, t)` | T03 | later `timerFired` | S02 |
| T05 | `Pending(v, t)` | `timerFired` | `now >= t + dueTime` | `next(v)` | `activeTask.unsubscribe()`, `activeTask=null`, `lastValue=null` (`debounceTime.ts` 69–77, 92) | `Idle` | T02 | another `sourceNext` can re-arm | S01 |
| T06 | `Idle` | `timerFired` | no task | — | inapplicable: action exists only while `Pending` | `Idle` | — | — | — |
| T07 | `Pending(v, t)` | `sourceComplete` | task live | `next(v)` then `complete` | `emit` unsubscribes task; then `subscriber.complete()` (`debounceTime.ts` 107–112). Remaining quiet time is not waited. | `Stopped` | T02 or T03 | none | S03 |
| T08 | `Idle` | `sourceComplete` | no task | `complete` | `emit` is a no-op because `activeTask` is null | `Stopped` | T01 or T05 | none | S04 |
| T09 | `Pending(v, t)` | `sourceError(e)` | — | `error(e)` only; `v` dropped | default error path; finalize nulls refs; task unsubscribed because it was added to `subscriber` | `Stopped` | T02 | none | S05 |
| T10 | `Idle` | `sourceError(e)` | — | `error(e)` | no pending value | `Stopped` | T01 | none | S04 |
| T11 | `Pending` or `Idle` | `cancel` | downstream unsubscribe | `none` (no `complete`) | task unsubscribed via `subscriber.add`; finalize sets `lastValue = activeTask = null` (`debounceTime.ts` 116–119) | `Stopped` | T02 | late `timerFired` must not run | S06 |
| T12 | `Stopped` | any source/timer/cancel | already torn down | `none` | inapplicable; subscriber is stopped | `Stopped` | T07–T11 | none | — |
| T13 | `Pending` | downstream throw from `next(v)` inside `emit` | `timerFired` or complete-flush | `error(throw)` after or instead of a successful `next`, per observer | `OperatorSubscriber` catch (`OperatorSubscriber.ts` 71–73) | `Stopped` | T05/T07 | none | — |
| T14 | `Idle` | inner notifier | — | — | inapplicable: no inner subscription | `Idle` | — | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | While `Pending`, `lastValue` is the most recent `sourceNext` since the last flush, not necessarily the value that first armed the task. |
| I02 | At most one scheduler task is recorded in `activeTask`. Later values do not `unsubscribe` the task; they move `lastTime` (`debounceTime.ts` 98–106). |
| I03 | A flush emits at most one value and clears `activeTask` before `subscriber.next` (`debounceTime.ts` 70–76). |
| I04 | `sourceError` never emits the cached value (`onError` omitted, line 115). |
| I05 | `sourceComplete` emits the cached value iff `activeTask` is non-null, and that `next` is strictly before `complete`. |
| I06 | `cancel` emits neither `next` nor `complete` nor `error`. |
| I07 | After a flush the location is `Idle` until the next `sourceNext` (ordinary model, no reentrancy). |
| I08 | Output `next` times are not source times; they are quiet-deadline times or the source-complete instant. |

## E. Scenario specification

### S01 Quiet window emits the only value

- Test ID: S01
- Covered row IDs: T01, T02, T05
- Starting state: not subscribed
- Reset/fixture: `dueTime = 10`, virtual scheduler, source cold
- prefix: `subscribe`
- target event: `timerFired` with `now >= lastTime + 10` after `sourceNext(a)`
- expected notifications: `next(a)`
- lifecycle: one task scheduled at `sourceNext`, unsubscribed inside `emit`
- suffix: location `Idle`; a later `sourceNext(b)` can arm again
- final state: `Idle`
- version and scheduler: 7.8.2, virtual scheduler obeying the tie assumption
- assertion type: source characterization
- oracle source: source characterization (`debounceTime.ts` 98–106, 79–92)

### S02 Later value resets the deadline without a second task

- Test ID: S02
- Covered row IDs: T03, T04, T05
- Starting state: `Pending(a, t0)`
- Reset/fixture: `dueTime = 10`; second value at `t0+4`
- prefix: T01, `sourceNext(a)`
- target event: `timerFired` at the original due time (`now = t0+10 < (t0+4)+10`)
- expected notifications: `none` on that firing; later `next(b)` when `now >= t0+4+10`
- lifecycle: same action reschedules for `6` (`debounceTime.ts` 85–88); `a` is overwritten and never emitted
- suffix: after the rescheduled firing, `Idle`
- final state: `Idle` after the second firing
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S03 Complete flushes pending then completes

- Test ID: S03
- Covered row IDs: T07
- Starting state: `Pending(a, t)`
- Reset/fixture: task not yet due
- prefix: `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `next(a)`, `complete`
- lifecycle: `emit` unsubscribes `activeTask` immediately; quiet remainder cancelled
- suffix: `Stopped`; no second `complete`
- final state: `Stopped`
- version and scheduler: 7.8.2, any `SchedulerLike`
- assertion type: source characterization
- oracle source: contract (JSDoc 23–24) and source characterization (107–112)

### S04 Idle complete and idle error

- Test ID: S04
- Covered row IDs: T08, T10
- Starting state: `Idle`
- Reset/fixture: no `sourceNext`, or a prior flush already cleared the task
- prefix: `subscribe` (and optional already-flushed value)
- target event: `sourceComplete` or `sourceError(e)`
- expected notifications: `complete` with no `next`, or `error(e)` with no `next`
- lifecycle: `emit` no-op on complete; error uses default forward
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Error drops pending

- Test ID: S05
- Covered row IDs: T09
- Starting state: `Pending(a, t)`
- Reset/fixture: task armed, not yet fired
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)` and not `next(a)`
- lifecycle: task torn down with the subscriber; finalize nulls `lastValue`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 115 plus `Subscriber.ts` 116–121)

### S06 Cancel drops pending and does not complete

- Test ID: S06
- Covered row IDs: T11
- Starting state: `Pending(a, t)`
- Reset/fixture: task armed
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: scheduled subscription unsubscribed; finalize runs; `timerFired` must not be delivered
- suffix: no `complete`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`debounceTime.ts` 104–105, 116–119)

## F. Coverage and evidence

Denominator = 14 transition rows (T01–T14). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S02 | not executed |
| T05 | S01, S02 | not executed |
| T06 | none (inapplicable) | not executed |
| T07 | S03 | not executed |
| T08 | S04 | not executed |
| T09 | S05 | not executed |
| T10 | S04 | not executed |
| T11 | S06 | not executed |
| T12 | none (terminal) | not executed |
| T13 | none | not executed |
| T14 | none (inapplicable) | not executed |

Rows with a scenario: 9/14. Rows without a dedicated scenario are inapplicable, terminal, or the downstream-throw fault.

## G. Review decision

accept with documented limits

- Limitations: no tests were run. Tie order of a `sourceNext` and `timerFired` at the same virtual time is an assumption about the scheduler queue, not a proof. Negative/`NaN` `dueTime` and non-monotonic `scheduler.now()` are out of scope. Reentrancy is excluded. The implementation does not cancel-and-reschedule on every `sourceNext`; equivalence to “reset the timer” holds only if `emitWhenIdle` observes `scheduler.now()` against `lastTime + dueTime`.
- Contract vs 7.8.2 characterization: JSDoc (lines 16–26) matches the code for latest-value, complete-flush, and error-drop. The “impossible for more than one notification in any window of `dueTime`” claim (lines 28–29) is a rate claim under a real-time reading; this model only states the quiet-deadline rule on the scheduler clock.
- Tests still required: S01–S06 on `TestScheduler`, plus same-timestamp `sourceNext`/`timerFired` ordering, `dueTime = 0`, and unsubscribe exactly when the action is due.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
