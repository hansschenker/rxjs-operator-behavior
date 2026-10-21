# throttleTime

`throttleTime(duration, scheduler = asyncScheduler, config?)` is `throttle(() => duration$, config)` where `duration$ = timer(duration, scheduler)` is allocated once (`throttleTime.ts` 55–61). Each throttle window subscribes to that same cold `timer` observable, so each subscription schedules its own delay; the observable is shared, the execution is not. `timer` emits `0` then completes, and `throttle`’s `endThrottling` unsubscribes on `next`, so the trailing decision follows duration `next`, not the silent-complete path. Defaults remain `{ leading: true, trailing: false }`. Source error does not flush trailing. Source complete does only when trailing is pending and the timer is still open. `cancel` clears the timer and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/throttleTime.ts` plus `throttle.ts` and `timer.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `throttleTime<T>(duration: number, scheduler?: SchedulerLike, config?: ThrottleConfig)` (`throttleTime.ts` 55–59). `scheduler` defaults to `asyncScheduler`. `config` defaults inside `throttle`.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 15–22 describes the default leading timer. `config` is passed through unchanged (line 61). There is no second implementation.
- Model kind: timed, not finite. State is `throttle`’s; the clock is `scheduler`.
- Parameter domain: `duration` is `timer` due time. `timer` clamps negative due to 0 (`timer.ts` 161–163). `NaN` is excluded. `config.leading` / `config.trailing` default true / false (`throttle.ts` 86).
- Payload/error domain: same as `throttle`. `timer` does not error. Its `next` value is ignored by `endThrottling`.
- Subscription boundary: `throttle` subscribes per window via `innerFrom(duration$).subscribe` (`throttle.ts` 107). Cold `timer` (`timer.ts` 155–184) schedules on that subscribe.
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. The timer is armed synchronously during the leading `send` or the trailing-only `startThrottle`, for `duration` units from that instant. Micro-trace required when a source notification and the timer share a timestamp.
- Callback assumptions: the selector `() => duration$` does not throw and ignores the source value. Downstream throw during leading `next` is still possible before `startThrottle`. Ordinary model: no reentrancy.
- Cleanup assumptions: `cancel` and `endThrottling` unsubscribe the timer. `timer`’s later `complete` is not observed after that unsubscribe. No output `complete` on cancel.
- Explicit exclusions: hot-observable sharing (this `timer` is cold); `NaN` duration; reentrancy; real-time proofs for `asyncScheduler`.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
parameters L, R as in throttle
```

### S

`Idle`, `Throttled(v | ⊥)`, `ThrottledDone(v)`, `Stopped`. Same as `throttle`. Silent duration-complete is not how `timer` ends a window.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Builds one `timer` observable, then `throttle`. |
| `sourceNext(v)` | yes | source | `throttle.ts` 131–134. |
| `sourceError(e)` | yes | source | Immediate; no trailing flush. |
| `sourceComplete` | yes | source | Trailing wait only under the line 138 guard. |
| `cancel` | yes | unsubscribe | Clears timer; no `complete`. |
| `timerFired` | yes | `timer` `next(0)` | `endThrottling`. |
| `timerComplete` | usually dropped | `timer` after `next` | Unsubscribed inside `endThrottling` before complete is delivered (`throttle.ts` 93). |
| selector throw | no | arrow returns a stored observable | Inapplicable. |
| duration error | no | `timer` does not error | Inapplicable on the stock path. |
| user callback throw | yes | downstream observer | Fault, not source error. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required at timer boundaries.

## C. Transition obligations

Stock `timer` path. `L`/`R` are the config bits.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `duration$ = timer(duration, scheduler)` once (`throttleTime.ts` 60–61) | `Idle` | ε | source | S01 |
| T02 | `Idle` | `sourceNext(v)` | `L` (default) | `next(v)` | then subscribe `duration$`; timer armed for `duration` | `Throttled(⊥)` | T01 | suppress until timer | S01 |
| T03 | `Idle` | `sourceNext(v)` | `!L` | `none` | subscribe `duration$` with pending `v` | `Throttled(v)` | T01 | timer will trail if `R` | S02 |
| T04 | `Throttled` | `sourceNext(w)` | timer open | `none` | overwrite pending; do not reschedule | `Throttled(w)` | T02 | — | S03 |
| T05 | `Throttled(⊥)` | `timerFired` | `!R` or `!hasValue` | `none` | unsubscribe timer; no `send` if `!R` or nothing pending | `Idle` | T02 and no suppressed value | next value may lead | S01 |
| T06 | `Throttled(w)` | `timerFired` | `R && hasValue && !isComplete` | `next(w)` | `send` then `startThrottle(w)`: a new timer starts immediately (`throttle.ts` 119) | `Throttled(⊥)` | T04 | no extra leading `next` | S03 |
| T07 | `Throttled(w)` | `timerFired` | `!R && hasValue` | `none`; `w` dropped | slot cleared; `hasValue` left true but idle | `Idle` | T04 | next idle source value leads if `L` | S04 |
| T08 | `Throttled(w)` | `sourceComplete` | `R && hasValue && timer open` | `none` yet | `isComplete=true` | `ThrottledDone(w)` | T04 | wait timer | S05 |
| T09 | `ThrottledDone(w)` | `timerFired` | `R` | `next(w)` then `complete` | no new timer (`isComplete`) | `Stopped` | T08 | none | S05 |
| T10 | `Throttled` or `Idle` | `sourceComplete` | trailing guard false | `complete`; no flush | default-config complete during the timer is this row | `Stopped` | T02 | none | S04 |
| T11 | any non-terminal | `sourceError(e)` | even if trailing pending | `error(e)`; no flush | timer unsubscribed with destination | `Stopped` | T04 | none | S06 |
| T12 | any non-terminal | `cancel` | — | `none` | timer unsubscribed; no `complete` | `Stopped` | T02 | virtual time must not emit | S07 |
| T13 | `Open` | `timer` silent complete | — | — | inapplicable: `timer` `next`s first (`timer.ts` 173–181) and `endThrottling` unsubscribes | — | — | — | — |
| T14 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T15 | `duration < 0` | `sourceNext` that arms timer | `timer` clamps due to 0 | leading/trailing as usual when the 0-delay action runs | still scheduled, not a special branch in `throttleTime` | per T02–T07 | T01 | scheduler flush order | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Default output is leading-only. Suppressed values are dropped when the timer fires (T07) and when the source completes during the timer (T10). |
| I02 | With `trailing: true`, the timer `next` emits the latest suppressed value, if any. |
| I03 | With both flags true, a trailing emit re-arms `timer(duration)` immediately and does not emit a second leading for that same value. |
| I04 | The selector ignores source values; every window subscribes again to the same cold `timer` observable. |
| I05 | `sourceError` does not emit a trailing value. `sourceComplete` does only under `throttle.ts` 138. |
| I06 | `cancel` clears the scheduled timer and does not complete. |
| I07 | Negative `duration` is clamped to 0 by `timer`, not by `throttleTime`. |

## E. Scenario specification

### S01 Default: emit leading, ignore the timer’s value

- Test ID: S01
- Covered row IDs: T01, T02, T05
- Starting state: unsubscribed
- Reset/fixture: `throttleTime(10)`, virtual scheduler, no config
- prefix: `subscribe`
- target event: `sourceNext(a)` then `timerFired` at +10 with no further source values
- expected notifications: `next(a)` only, at the source event
- lifecycle: one timer subscription, unsubscribed in `endThrottling`
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`throttleTime.ts` 60–61, `throttle.ts` 92–98, 131–134)

### S02 Trailing only

- Test ID: S02
- Covered row IDs: T03, T06
- Starting state: `Idle`
- Reset/fixture: `{ leading: false, trailing: true }`, `duration = 10`
- prefix: `subscribe`
- target event: `sourceNext(a)` then `timerFired`
- expected notifications: `none` at `sourceNext`; `next(a)` at the timer; a new timer is armed because `!isComplete`
- lifecycle: two timer subscriptions in sequence if the second is not cancelled
- suffix: `Throttled(⊥)`
- final state: `Throttled(⊥)`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S03 Both true: leading then a different trailing

- Test ID: S03
- Covered row IDs: T02, T04, T06
- Starting state: `Idle`
- Reset/fixture: `{ leading: true, trailing: true }`
- prefix: `sourceNext(a)` → `next(a)`, timer armed
- target event: `sourceNext(b)` during the window, then `timerFired`
- expected notifications: `next(a)`, later `next(b)`, then a new silent window
- lifecycle: first timer unsubscribed; second timer scheduled from the trailing `send`
- suffix: `Throttled(⊥)`
- final state: `Throttled(⊥)`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S04 Default drops the suppressed value on timer and on complete

- Test ID: S04
- Covered row IDs: T04, T07, T10
- Starting state: `Throttled(⊥)` after leading `a`
- Reset/fixture: default config; `b` arrives before the timer
- prefix: `next(a)` already observed
- target event: either `timerFired` or `sourceComplete` before the timer
- expected notifications: not `next(b)`. Timer path: `none`. Complete path: `complete`
- lifecycle: timer cleared on complete via destination teardown
- suffix: `Idle` or `Stopped`
- final state: as suffix
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S05 Trailing flush after complete

- Test ID: S05
- Covered row IDs: T08, T09
- Starting state: `Throttled(b)`, `R=true`
- Reset/fixture: timer still armed
- prefix: pending `b`
- target event: `sourceComplete` then `timerFired`
- expected notifications: `next(b)`, `complete`
- lifecycle: no reschedule after flush
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S06 Error drops trailing

- Test ID: S06
- Covered row IDs: T11
- Starting state: `Throttled(b)`, `R=true`
- Reset/fixture: timer armed
- prefix: pending trailing value
- target event: `sourceError(e)`
- expected notifications: `error(e)`, not `next(b)`
- lifecycle: timer disposed with the subscriber
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S07 Cancel

- Test ID: S07
- Covered row IDs: T12
- Starting state: `Throttled(⊥)`
- Reset/fixture: timer armed
- prefix: leading value already emitted
- target event: `cancel`
- expected notifications: none
- lifecycle: timer action unsubscribed; advancing the scheduler must not `next` or `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 15 (T01–T15). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01, S03 | not executed |
| T03 | S02 | not executed |
| T04 | S03, S04 | not executed |
| T05 | S01 | not executed |
| T06 | S02, S03 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | S05 | not executed |
| T10 | S04 | not executed |
| T11 | S06 | not executed |
| T12 | S07 | not executed |
| T13 | none (inapplicable) | not executed |
| T14 | none | not executed |
| T15 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Sharing `duration$` is safe only because `timer` is cold; that is source characterization of `timer.ts`, not a comment in `throttleTime.ts`. Tie order is assumed. The `throttle` silent-complete row is inapplicable for this timer.
- Contract vs 7.8.2 characterization: JSDoc matches the default leading path. Trailing behavior is entirely delegated and must be read from `throttle.ts`.
- Tests still required: S01–S07 on `TestScheduler`, including both flags, complete-during-window, error-during-window, and unsubscribe-during-window.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
