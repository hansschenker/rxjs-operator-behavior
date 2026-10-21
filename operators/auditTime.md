# auditTime

`auditTime(duration, scheduler = asyncScheduler)` is `audit(() => timer(duration, scheduler))` (`auditTime.ts` 53–55). Each audit window subscribes to a fresh cold `timer` that emits `0` and completes. The inherited `audit` machine therefore takes the duration-`next` path (`endDuration`), which emits the latest pending source value, and not the duration-complete drop path. Source error is still immediate and drops the pending value. Source complete while a timer is armed waits for that timer, then emits the pending value and completes. `cancel` clears the timer via the `audit` child subscription and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/auditTime.ts` delegating to `audit.ts` and `timer.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `auditTime<T>(duration: number, scheduler: SchedulerLike = asyncScheduler): MonoTypeOperatorFunction<T>` (`auditTime.ts` 53).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 16–24. After a value opens a window, ignore further values for `duration`, then emit the most recent one. Implementation does not reimplement the state machine; it fixes the duration selector (`auditTime.ts` 54).
- Model kind: timed, not finite. Control state is `audit`’s; time is the scheduler clock.
- Parameter domain: `duration` is `timer`’s `dueTime` (`timer.ts` 133–163). Documented domain: non-negative scheduler units. `timer` clamps `due < 0` to `0` (`timer.ts` 161–163). `NaN` is not clamped (`NaN < 0` is false) and is excluded. The selector ignores the opening value (`() => timer(...)`), but `timer` is called once per window, inside the selector, so each window gets its own cold subscription. It is not one shared hot clock.
- Payload/error domain: same as `audit`. `timer`’s `next(0)` is ignored by `endDuration`. `timer` then `complete`s; `endDuration` has already unsubscribed (`audit.ts` 61), so `cleanupDuration` typically does not also run for that signal.
- Subscription boundary: identical to `audit` after the selector returns. `timer`’s schedule subscription is a child of the duration subscriber, which is a child of the destination.
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. `timer` schedules `due` from the moment the duration is subscribed, which is the opening `sourceNext` (synchronously, ordinary model). A source value arriving in the same virtual instant as the timer is ordered by queue order. Micro-trace required.
- Callback assumptions: no user duration selector. Downstream throw from `subscriber.next` in `endDuration` is an `OperatorSubscriber` fault. Ordinary model: no reentrancy.
- Cleanup assumptions: `cancel` unsubscribes the destination, which unsubscribes the duration subscriber and therefore the `timer` action. `endDuration` is not invoked by cancel. No `complete`.
- Explicit exclusions: reentrancy; real-time `setTimeout` proofs; `NaN` duration; modeling `audit` duration-complete drop as the `auditTime` success path (it is not, because `timer` `next`s first).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
```

`δ`/`λ` are `audit`’s transitions with the duration alphabet specialized to `timerFired` = `timer`’s `next`, followed by an unsubscribed `complete`.

### S

Same locations as `audit`: `Idle`, `Open(v)`, `OpenDone(v)`, `Stopped`. The stale-`hasValue` location after a silent duration `complete` is not reachable through `timer`, because `timer` always `next`s `0` before `complete` (`timer.ts` 170–181) unless unsubscribed or the subscriber is closed.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | — |
| `sourceNext(v)` | yes | source | Opens `timer(duration)` iff no duration subscriber (`audit.ts` 80–86). |
| `sourceError(e)` | yes | source | Immediate; drop pending. |
| `sourceComplete` | yes | source | Wait iff a timer is open and a value is pending (`audit.ts` 89–91). |
| `cancel` | yes | unsubscribe | Clears timer; no `complete`. |
| `timerFired` | yes | `timer` `next(0)` | Maps to `audit` `durationNext` / `endDuration`. |
| `timerComplete` | yes but usually dropped | `timer` after `next` | `endDuration` unsubscribes first (`audit.ts` 61), so this signal is not delivered in the ordinary timer path. |
| inner error | no for `timer` itself | `timer` does not error | Inapplicable for the stock selector. |
| selector throw | no | selector is `() => timer(...)` | `timer(...)` factory does not throw for a numeric duration. |
| user callback throw | yes | downstream `next` | Becomes `outError`. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required at the timer boundary.

## C. Transition obligations

Primary machine (stock `timer` duration). Rows that `audit` has but `timer` cannot produce are marked inapplicable for this operator.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `audit` flags reset | `Idle` | ε | source | S01 |
| T02 | `Idle` | `sourceNext(v)` | — | `none` | subscribe `timer(duration, scheduler)` (`auditTime.ts` 54, `timer.ts` 169–184) | `Open(v)` | T01 | wait `duration` | S01 |
| T03 | `Open(v)` | `sourceNext(w)` | timer still open | `none` | `lastValue=w`; timer not restarted (`audit.ts` 83) | `Open(w)` | T02 | `timerFired` emits `w` | S02 |
| T04 | `Open(v)` | `timerFired` | `hasValue` | `next(v)` | `endDuration` unsubscribes timer before `next`; slot cleared; `timer` `complete` not observed | `Idle` | T02 or T03 | output remains open | S01 |
| T05 | `Open(v)` | `sourceComplete` | pending and timer open | `none` | `isComplete=true` (`audit.ts` 89–91) | `OpenDone(v)` | T02 | wait for timer | S03 |
| T06 | `OpenDone(v)` | `timerFired` | — | `next(v)` then `complete` | `endDuration` lines 63–69 | `Stopped` | T05 | none | S03 |
| T07 | `Idle` | `sourceComplete` | no open timer | `complete` | includes the case `hasValue` stale; not produced by `timer` after T04 because T04 clears `hasValue` | `Stopped` | T01 or T04 | none | S04 |
| T08 | `Open` or `Idle` | `sourceError(e)` | — | `error(e)`; pending dropped | default error; timer unsubscribed with destination | `Stopped` | T02 | none | S05 |
| T09 | `Open` or `Idle` | `cancel` | — | `none` | timer action unsubscribed; no `complete` | `Stopped` | T02 | `timerFired` must not run | S06 |
| T10 | `Open` | silent duration `complete` (no `next`) | — | — | inapplicable for `timer`: `timer` emits `0` first (`timer.ts` 173–181) | — | — | — | — |
| T11 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T12 | `Idle` | `timerFired` | no window | — | inapplicable | `Idle` | — | — | — |
| T13 | `Open` | `duration < 0` clamped | `timer` sets due to 0 (`timer.ts` 161–163) | `next(v)` when the 0-delay action runs | still a scheduled action, not a synchronous call inside `timer`’s subscribe unless the scheduler flushes sync | `Idle` | T02 | scheduler-dependent micro-trace | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Window length is one `timer` due, measured from the opening `sourceNext`, not from later values. |
| I02 | The emitted value is the latest `sourceNext` in the open window (`audit.ts` 81–82, 63–67). |
| I03 | Because `timer` `next`s before `complete`, `auditTime` flushes on the timer. It does not take `audit`’s drop-on-duration-complete path. |
| I04 | A new window cannot start until `endDuration` clears `durationSubscriber`. Values that arrive after the flush open a new timer. |
| I05 | `sourceError` does not flush. `sourceComplete` during `Open` flushes on the subsequent `timerFired` and then completes. |
| I06 | `cancel` clears the timer and emits nothing, including no `complete`. |
| I07 | `durationSelector` does not observe the source value (`auditTime.ts` 54). |

## E. Scenario specification

### S01 Single value emitted when the timer fires

- Test ID: S01
- Covered row IDs: T01, T02, T04
- Starting state: unsubscribed
- Reset/fixture: `duration = 10`, virtual scheduler
- prefix: `subscribe`
- target event: `timerFired` 10 units after `sourceNext(a)`
- expected notifications: `next(a)`
- lifecycle: one `timer` subscription, unsubscribed inside `endDuration`
- suffix: `Idle`; output not completed
- final state: `Idle`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`auditTime.ts` 53–55, `audit.ts` 60–70, `timer.ts` 169–181)

### S02 Intermediate values only update the pending value

- Test ID: S02
- Covered row IDs: T03, T04
- Starting state: `Open(a)` at time t
- Reset/fixture: `duration = 10`; `b` arrives at t+3
- prefix: `sourceNext(a)`
- target event: `timerFired` at t+10
- expected notifications: `next(b)` once; not `a`; not a second timer from `b`
- lifecycle: original timer remains the only task
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S03 Complete while open flushes on the timer then completes

- Test ID: S03
- Covered row IDs: T05, T06
- Starting state: `Open(a)`
- Reset/fixture: timer not yet fired
- prefix: `sourceNext(a)`
- target event: `sourceComplete`, then `timerFired`
- expected notifications: `next(a)`, `complete` on the firing; nothing at `sourceComplete`
- lifecycle: source subscription ends at source complete; timer stays until `endDuration`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`audit.ts` 89–91 and 60–69)

### S04 Idle complete

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Idle`
- Reset/fixture: no pending window
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `complete`
- lifecycle: no timer
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Error drops pending

- Test ID: S05
- Covered row IDs: T08
- Starting state: `Open(a)`
- Reset/fixture: timer armed
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: timer unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Cancel

- Test ID: S06
- Covered row IDs: T09
- Starting state: `Open(a)`
- Reset/fixture: timer armed
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: `timer` action disposed; no `complete`
- suffix: advancing virtual time must not emit
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 13 (T01–T13). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01, S02 | not executed |
| T05 | S03 | not executed |
| T06 | S03 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | S06 | not executed |
| T10 | none (inapplicable for `timer`) | not executed |
| T11 | none | not executed |
| T12 | none | not executed |
| T13 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: behavior of a thrown or erroring duration is inherited from `audit` but is not on the stock `timer` path. `duration < 0` becomes 0 only inside `timer`. Same-time tie order is assumed. No tests run.
- Contract vs 7.8.2 characterization: the one-line delegation matches the JSDoc success path because `timer` emits a `next`. Do not copy `audit`’s “duration complete drops the value” row onto `auditTime` without replacing `timer`.
- Tests still required: S01–S06 on `TestScheduler`, including complete-during-window and unsubscribe-during-window.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
