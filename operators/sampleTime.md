# sampleTime

`sampleTime(period, scheduler = asyncScheduler)` is `sample(interval(period, scheduler))` (`sampleTime.ts` 49–50). `interval` emits `0, 1, 2, ...` starting after one `period`, not at subscribe time, and it does not complete (`interval.ts` 50–56, via `timer(period, period, scheduler)`). Each of those `next`s is a `sample` notifier `next`: the latest source value since the previous tick is emitted once, or nothing is emitted if the slot is empty. The interval never takes `sample`’s notifier-complete path. Source `complete` completes immediately and drops an unsampled value. Source `error` is immediate and drops it. `cancel` unsubscribes the interval and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/sampleTime.ts` plus `sample.ts` and `interval.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `sampleTime<T>(period: number, scheduler: SchedulerLike = asyncScheduler): MonoTypeOperatorFunction<T>` (`sampleTime.ts` 49).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 15–20. Sampling starts at subscription; the first look is after one period because that is when `interval` first emits (`interval.ts` 16–18).
- Model kind: timed, not finite. The sample slot is finite control data; the tick index is unbounded.
- Parameter domain: `period` is passed to `interval`. `period < 0` is coerced to `0` (`interval.ts` 51–53). `period = 0` is a 0-delay repeating timer (`timer.ts` 175–178). `NaN` is excluded (`NaN < 0` is false, so it is not coerced).
- Payload/error domain: identical to `sample`. Interval payloads are ignored. `interval`/`timer` does not error on the stock path.
- Subscription boundary: `sample` subscribes to the source first, then to `interval` (`sample.ts` 51–70). The interval’s scheduler action is a child of that notifier subscriber, hence of the destination.
- Scheduler and tie ordering: assumption, not a proof: actions at the same virtual time run in schedule order. A `sourceNext` scheduled at the same instant as a tick is ordered by queue order relative to the interval action. Micro-trace required.
- Callback assumptions: no user selector. Downstream throw on sampled `next` is an observer fault. Ordinary model: no reentrancy.
- Cleanup assumptions: `cancel` unsubscribes the destination, which unsubscribes source and interval. Pending ticks do not fire. No `complete`.
- Explicit exclusions: notifier-complete behavior of raw `sample` (this notifier does not complete); real-time `setInterval` drift proofs (`AsyncAction` reschedules, not modeled here beyond “a tick every `period`”); `NaN` period.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Empty
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Empty` | `hasValue = false` | No source value since subscribe or the last tick that sampled. |
| `Held(v)` | `hasValue = true`, `lastValue = v` | Eligible for the next tick. |
| `Stopped` | terminal | — |

Ticks continue in `Empty` and `Held` until stop. The tick counter is not control state.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Starts source and `interval(period)`. First tick is due at `+period`, or `0` if `period < 0`. |
| `sourceNext(v)` | yes | source | Fills the slot. |
| `sourceError(e)` | yes | source | Immediate `error`; drop slot; interval unsubscribed. |
| `sourceComplete` | yes | source | Immediate `complete`; drop unsampled slot; interval unsubscribed. |
| `cancel` | yes | unsubscribe | Interval cleared; no `complete`. |
| `timerFired` / tick | yes | `interval` `next` | `sample` notifier `next` (`sample.ts` 60–66). |
| notifier complete | no | `interval` does not complete | Inapplicable. |
| notifier error | no | stock `interval` | Inapplicable. |
| user callback | no selector | downstream throw only | Fault. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required when a source notification and a tick share a virtual time.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | `period >= 0` | `none` | source subscribed; interval scheduled for `period` (`interval.ts` 56, `timer.ts` 169–178) | `Empty` | ε | first tick at +period | S01 |
| T02 | `Empty` or `Held` | `sourceNext(v)` | before or between ticks | `none` | slot becomes `v` | `Held(v)` | T01 | next tick | S01 |
| T03 | `Held(v)` | `timerFired` | `hasValue` | `next(v)` | slot cleared (`sample.ts` 61–65); interval stays subscribed | `Empty` | T02 | next period may sample again | S01 |
| T04 | `Empty` | `timerFired` | `!hasValue` | `none` | interval remains | `Empty` | T01 or T03 | — | S02 |
| T05 | `Held(v)` | `sourceComplete` | — | `complete`; not `next(v)` | interval unsubscribed with destination | `Stopped` | T02 | a due tick must not fire | S03 |
| T06 | `Empty` | `sourceComplete` | — | `complete` | interval cleared | `Stopped` | T04 | none | S02 |
| T07 | `Held` or `Empty` | `sourceError(e)` | — | `error(e)`; slot dropped | interval cleared | `Stopped` | T02 | none | S04 |
| T08 | any non-terminal | `cancel` | — | `none` | interval action unsubscribed; no `complete` | `Stopped` | T02 | virtual time must not emit | S05 |
| T09 | any | notifier `complete` | — | — | inapplicable: `interval` has no complete (`interval.ts` 14–16, `timer.ts` 175–178) | — | — | — | — |
| T10 | `Stopped` | tick or source | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T11 | `subscribe` | `period < 0` | coerced to 0 (`interval.ts` 51–53) | `none` until the scheduler runs the 0-delay repeating timer | first due time is 0, not “one negative period” | `Empty` | ε | tick cadence is scheduler-defined at delay 0 | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | No sample is emitted at subscribe time. The first opportunity is the first `interval` emission. |
| I02 | A tick emits at most the latest source value since the previous tick, then clears the slot. |
| I03 | Ticks with an empty slot emit nothing and do not complete the output. |
| I04 | The sampler does not complete on its own. Output completion comes only from the source (or the output errors from the source). |
| I05 | Source complete and source error do not flush an unsampled value. |
| I06 | `cancel` stops further ticks and does not complete. |
| I07 | `period < 0` is treated as `0` by `interval`, not rejected by `sampleTime`. |

## E. Scenario specification

### S01 Periodic sample of the latest value

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: `period = 10`, virtual scheduler
- prefix: `subscribe` at t=0, `sourceNext(a)` at t=3, `sourceNext(b)` at t=7
- target event: tick at t=10
- expected notifications: `next(b)`; nothing at t=0
- lifecycle: interval remains scheduled for t=20
- suffix: `Empty` until another source value
- final state: `Empty`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`sampleTime.ts` 49–50, `interval.ts` 50–56, `sample.ts` 60–66)

### S02 Empty ticks then idle complete

- Test ID: S02
- Covered row IDs: T04, T06
- Starting state: `Empty`
- Reset/fixture: no source values through the first tick
- prefix: `subscribe`, tick at `period`
- target event: that tick, then `sourceComplete`
- expected notifications: `none` on the tick; `complete` on source complete
- lifecycle: interval unsubscribed at complete
- suffix: `Stopped`; the next period must not emit
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S03 Complete drops a held sample

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Held(a)`
- Reset/fixture: value arrived after the previous tick (or before the first tick); next tick not yet due
- prefix: `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `complete`, not `next(a)`
- lifecycle: interval disposed
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`sample.ts` 51–56)

### S04 Error drops a held sample

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Held(a)`
- Reset/fixture: interval armed
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: interval disposed
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Cancel

- Test ID: S05
- Covered row IDs: T08
- Starting state: `Held(a)`
- Reset/fixture: next tick still in the future
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: interval action unsubscribed; no `complete`
- suffix: advancing past `period` must not `next`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 11 (T01–T11). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S02 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | none (inapplicable) | not executed |
| T10 | none | not executed |
| T11 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Tick/source tie order is assumed. `period = 0` is a legal repeating 0-delay timer and is not given its own scenario. `interval` completion is inapplicable, so `sample`’s surprising notifier-complete row does not apply here.
- Contract vs 7.8.2 characterization: JSDoc “periodically” and “starts as soon as subscribed” match `interval`’s first-tick-after-`period` behavior. The delegation does not add a flush-on-complete.
- Tests still required: S01–S05 on `TestScheduler`, plus a value that arrives exactly on a tick, and `period = 0` only if that edge is in product scope.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
