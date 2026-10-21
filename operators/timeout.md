# timeout

`timeout` fails the source over to a `TimeoutError` or to a `with` observable when a first-value deadline or an inter-value deadline is missed (`timeout.ts` 299–393). Number and `Date` call shapes are sugar for `{ each }` and `{ first }` (`timeout.ts` 310–316). The fully specified machine below is `timeout({ each, scheduler, meta })` with the default `with` that throws `TimeoutError`. Other overloads are the same loop with a different initial delay, a disabled re-arm, or a user `with` factory; their deltas are in the overload table and in T20–T28. `cancel` clears the timer and does not complete. Source `error` and source `complete` are immediate and are not turned into timeouts. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/timeout.ts`. `TimeoutError`’s public constructor is deprecated as an internal detail (lines 70–72) but the error class is the supported type for `instanceof` checks (lines 76–84).

## A. Identity, contract, and scope

- Operator/overload: see the overload table. Runtime dispatch is lines 310–316: valid `Date` → `{ first: config }`; `number` → `{ each: config }`; otherwise the object. `scheduler` argument is used only for the number/`Date` forms (`schedulerArg`, line 314). If neither `first` nor `each` is set, `timeout` throws `TypeError('No timeout provided.')` at operator-build time (318–321), before subscribe.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 102–115 and 182–186. `first` applies only before the first source value. `each` is the gap after each forwarded value, and also the initial gap when `first` is omitted. Missing `with` means `timeoutErrorFactory`, which throws `TimeoutError` (`timeout.ts` 401–403) inside the timer callback’s try/catch (344–355), so the output errors. A `with` factory’s observable is subscribed on the same destination after the source is unsubscribed (345–352).
- Model kind: timed, not finite. `seen` is unbounded.
- Parameter domain: `each` and numeric `first` are scheduler delays. `each > 0` is required to re-arm after a value (line 371); `each <= 0` or `NaN` does not re-arm. The initial timer still receives `each` when `first` is null, even if `each` is 0 (line 392). `Date` `first` is `+first - scheduler.now()` (line 392), which may be negative; unlike `timer()`, `executeSchedule` does not clamp. Negative delays are scheduler-defined and excluded from the ordinary rows. `meta` defaults to `null` (line 315) and is copied into `TimeoutInfo`. `scheduler` defaults to `schedulerArg ?? asyncScheduler`.
- Payload/error domain: forwarded source values `T`. Timeout without `with` yields `TimeoutError` whose `info` is `{ meta, lastValue, seen }` (347–351, 86–93). `lastValue` is the last forwarded value or `null`. `seen` is the count of forwarded values. User `with` may emit `ObservedValueOf<O>` or error with any error. A throw from `with` itself is `subscriber.error(err)` (353–355), not necessarily a `TimeoutError`.
- Subscription boundary: source is subscribed synchronously (361–384). The timer is `executeSchedule(subscriber, ...)` (340–358), so it is a child of the destination. On timeout the original source subscription is unsubscribed (345) and `with` is subscribed directly to `subscriber` (352), not through another operator subscriber.
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. A `sourceNext` and a due timer at the same virtual time are ordered by queue order. Micro-trace required.
- Callback assumptions: `with` runs on the timer turn, not on the source turn. Selector/`with` throw ≠ source error. Ordinary model: no reentrancy. `each! > 0` uses JS numeric comparison (`null`/`undefined` are not `> 0`).
- Cleanup assumptions: source complete and source error use default handlers (373–374), so they stop the destination and therefore the timer. Finalize (375–382) unsubscribes a still-open timer and nulls `lastValue`. `cancel` does the same via destination unsubscribe and does not emit `complete` or `TimeoutError`.
- Explicit exclusions: reentrancy; negative/`NaN` delays; host `setTimeout` horizon; constructing `TimeoutError` outside this operator (deprecated, lines 70–72); proving `with` observable behavior beyond “subscribed after source unsubscribe.”

### Overload table

| Call | Normalized config | Initial arm | Re-arm after each `next` | On timeout |
| --- | --- | --- | --- | --- |
| `timeout(each: number, scheduler?)` | `{ each, scheduler }` (lines 284, 315) | `startTimer(each)` | iff `each > 0` | `TimeoutError` |
| `timeout(first: Date, scheduler?)` | `{ first, scheduler }` (lines 270, 312) | `startTimer(+date - now())` | no (`each` unset, line 371) | `TimeoutError` |
| `timeout({ each })` | object | `startTimer(each)` | iff `each > 0` | `TimeoutError` |
| `timeout({ first })` | object, `first` number or `Date` | number as relative delay, `Date` as absolute delta (392) | no | `TimeoutError` |
| `timeout({ first, each })` | object | `first` only (392, `!seen`) | `each` iff `each > 0` | `TimeoutError` |
| `timeout({ ..., with })` | object | same as the matching row | same | unsubscribe source, subscribe `with(info)` (345–352) |
| `timeout({})` or neither deadline | — | throws `TypeError` at build (318–321) | — | — |

Fully specified transitions T01–T19 are `timeout({ each })` with default `with` and `each > 0`. Deltas are T20–T28.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Armed(seen = 0, lastValue = null, phase = initial)
```

For `timeout({ each })`, `phase = each` and the initial delay equals `each`.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Armed(seen, last, which)` | a timer is scheduled; source subscribed | `which` is `initial` or `inter`. |
| `Idle` | source subscribed, no timer | Reachable when `each <= 0` after the first value, or when only `first` was set and the first value arrived. Not the steady state of `{ each > 0 }`. |
| `FailedOver` | source unsubscribed; `with` observable subscribed | Only if `with` returns an observable instead of throwing. |
| `Stopped` | terminal | Error, complete, or cancel. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Arms the initial timer (392) unless build already threw. |
| `sourceNext(v)` | yes | source | Unsubscribe timer, `seen++`, `next(v)`, maybe re-arm (364–371). |
| `sourceError(e)` | yes | source | Immediate `error(e)`, not a timeout (373–374). |
| `sourceComplete` | yes | source | Immediate `complete`. Timer cleared by teardown, not by a delayed complete. |
| `cancel` | yes | unsubscribe | Timer cleared (375–378 and parent `add`). No `complete`, no `TimeoutError`. |
| `timerFired` | yes | `executeSchedule` callback (342–356) | Timeout transition. |
| `withNext` / `withError` / `withComplete` | yes only after failover | the `with` observable | Passed straight to `subscriber`. |
| `withThrow(e)` | yes | `with` factory or `timeoutErrorFactory` | Caught at 353–355. Default factory throws `TimeoutError`. |
| user duration selector | no | — | The only callback is `with`. |
| inner source after failover | no | original source unsubscribed (345) | Further source signals are inapplicable. |

### Γ

`none` | `next(v)` | `error(e)` including `error(TimeoutError)` | `complete`. Micro-trace required when `sourceNext` and `timerFired` can share a due time.

## C. Transition obligations

### `timeout({ each })` with `each > 0` and default `with`

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | `each > 0` | `none` | subscribe source; `seen=0`; `lastValue=null`; `startTimer(each)` (392) | `Armed(0, null, initial)` | ε | value or timer | S01 |
| T02 | `Armed` | `sourceNext(v)` | timer live | `next(v)` | `timerSubscription.unsubscribe()` first (366); `seen++`; `lastValue=v`; `startTimer(each)` (371) | `Armed(seen, v, inter)` | T01 | quiet gap resets | S01 |
| T03 | `Armed(seen, last, *)` | `timerFired` | no `with` (default factory throws) | `error(TimeoutError)` with `info = { meta, lastValue: last, seen }` | unsubscribe original source (345); factory throws (401–403); catch `subscriber.error` (353–355) | `Stopped` | T01 or T02 | source must not emit | S02 |
| T04 | `Armed` | `sourceComplete` | — | `complete` | default complete; finalize clears timer if needed (375–381); no timeout | `Stopped` | T02 | timer must not fire | S03 |
| T05 | `Armed(0, null)` | `sourceComplete` | no value yet | `complete` | initial timer cleared by teardown | `Stopped` | T01 | none | S03 |
| T06 | `Armed` | `sourceError(e)` | — | `error(e)`, not `TimeoutError` | default error; timer cleared; pending timeout abandoned | `Stopped` | T01 or T02 | none | S04 |
| T07 | `Armed` or `Idle` | `cancel` | — | `none` | timer unsubscribed; `lastValue=null` in finalize (375–381); no `complete` | `Stopped` | T02 | timer must not fire | S05 |
| T08 | `Stopped` | `timerFired` or source | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T09 | build | `timeout` called with no deadline | `first == null && each == null` | not a stream notification | synchronous `TypeError` (318–321); no subscribe | not an operator state | — | — | S06 |
| T10 | `Idle` | `timerFired` | no timer | — | inapplicable in the `each > 0` machine | — | — | — | — |

### Deltas for other overloads

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T20 | ∅ | `subscribe` | `timeout(first: Date)` or `{ first }` only | `none` | initial delay `typeof first === 'number' ? first : +first - now()` (392); `each` unset | `Armed(0, null, initial)` | ε | only the first value is guarded | S07 |
| T21 | `Armed` initial | `sourceNext(v)` | `each` unset or `!(each > 0)` | `next(v)` | timer cleared; line 371 does not re-arm | `Idle` | T20 | later gaps do not timeout | S07 |
| T22 | `Idle` after T21 | `sourceNext` / long gap | no timer | `next` only | no `startTimer` | `Idle` | T21 | source complete is T04-like | S07 |
| T23 | ∅ | `subscribe` | `{ first, each }` with `each > 0` | `none` | initial arm uses `first`, not `each` (392) | `Armed` initial | ε | after first value, T02 uses `each` | S08 |
| T24 | `Armed` | `timerFired` | user `with` returns an input | `none` at the instant of failover | unsubscribe source; `innerFrom(with(info)).subscribe(subscriber)` (345–352) | `FailedOver` | T01 | `with` signals are the output | S09 |
| T25 | `FailedOver` | `withNext(x)` / `withComplete` / `withError(e)` | — | that notification, unchanged | direct subscribe (352); original source already gone | `FailedOver` or `Stopped` on terminal | T24 | source signals inapplicable | S09 |
| T26 | `Armed` | `timerFired` | `with` throws `e` (custom or default) | `error(e)` | caught at 353–355; default `e` is `TimeoutError` | `Stopped` | T01 | none | S02 |
| T27 | `Armed` | `timerFired` | `{ meta }` | `TimeoutError.info.meta === meta` and `seen`/`lastValue` match the snapshot taken at fire time (347–351) | same as T03 | `Stopped` | T02 | none | S02 |
| T28 | number or `Date` call | operator build | — | — | normalized by 312–316; then the matching row above. `scheduler` argument fills the default (314) | — | — | same machine | S06 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | For `{ each > 0 }` every forwarded `next` clears the current timer and arms a new one for `each` (366–371). |
| I02 | `first` is consulted only for the initial arm (`!seen && startTimer`, line 392). After the first `next`, only `each` can arm a timer. |
| I03 | Default timeout notification is `error(TimeoutError)`, not a `next`, and `info.seen` / `info.lastValue` / `info.meta` match the snapshot (45–51, 347–351). |
| I04 | Source `error` and source `complete` are not delayed and are not rewritten into `TimeoutError`. |
| I05 | On timeout the original source is unsubscribed before `with` is called (345–347). |
| I06 | `cancel` clears the timer and emits neither `complete` nor `TimeoutError`. |
| I07 | `each <= 0` does not satisfy `each > 0`, so inter-value timers are not armed (371) even though a falsy `each` can still be passed to the initial `startTimer`. |
| I08 | Operator construction without a deadline throws `TypeError` and does not return an operator (318–321). |

## E. Scenario specification

### S01 Each-gap resets on every value

- Test ID: S01
- Covered row IDs: T01, T02
- Starting state: unsubscribed
- Reset/fixture: `timeout({ each: 10 })`, virtual scheduler
- prefix: `subscribe` at t=0
- target event: `sourceNext(a)` at t=6, `sourceNext(b)` at t=12
- expected notifications: `next(a)`, `next(b)`; no error
- lifecycle: timer unsubscribed and re-armed at each value; second deadline is t=22
- suffix: `Armed(2, b, inter)`
- final state: `Armed(2, b, inter)`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`timeout.ts` 364–371, 392)

### S02 Silence produces TimeoutError with info

- Test ID: S02
- Covered row IDs: T03, T26, T27
- Starting state: `Armed(1, a, inter)` after one value, or `Armed(0, null, initial)` if no value
- Reset/fixture: `timeout({ each: 10, meta: 'm' })`
- prefix: optional `sourceNext(a)`
- target event: `timerFired` with no further source value
- expected notifications: `error(TimeoutError)`; `info.meta === 'm'`; `info.seen` is 0 or 1; `info.lastValue` is `null` or `a`; `message === 'Timeout has occurred'` (line 90)
- lifecycle: source unsubscribed inside the timer (345); factory throws; catch forwards
- suffix: `Stopped`; source must not deliver a late value
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (342–355, 401–403)

### S03 Complete cancels the timer

- Test ID: S03
- Covered row IDs: T04, T05
- Starting state: `Armed`
- Reset/fixture: `each: 10`; complete before the deadline, with and without a prior value
- prefix: `subscribe` and optional `sourceNext`
- target event: `sourceComplete`
- expected notifications: `complete`, not `TimeoutError`
- lifecycle: timer disposed with the destination; finalize nulls `lastValue` (375–381)
- suffix: deadline must not error
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (lines 373–381)

### S04 Source error is not a timeout

- Test ID: S04
- Covered row IDs: T06
- Starting state: `Armed`
- Reset/fixture: timer still armed
- prefix: `subscribe`
- target event: `sourceError(e)`
- expected notifications: `error(e)` and `e` is not produced by `timeoutErrorFactory`
- lifecycle: timer cleared; no `with` call
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (error handler omitted, 373–374)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T07
- Starting state: `Armed`
- Reset/fixture: timer armed
- prefix: `subscribe`, optional value
- target event: `cancel`
- expected notifications: none
- lifecycle: `executeSchedule` child unsubscribed; finalize guards `timerSubscription.closed` (376–378); no `complete`
- suffix: deadline must not error
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization

### S06 Build-time validation and numeric sugar

- Test ID: S06
- Covered row IDs: T09, T28
- Starting state: operator not built
- Reset/fixture: `timeout({})` and `timeout(10, scheduler)`
- prefix: none
- target event: the call to `timeout`
- expected notifications: `timeout({})` throws `TypeError` and does not subscribe; `timeout(10, scheduler)` behaves as `{ each: 10, scheduler }`
- lifecycle: throw is outside the stream (318–321)
- suffix: the numeric form continues as S01
- final state: no subscription, or `Armed` for the numeric form
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (310–321)

### S07 First-only Date or number does not guard later gaps

- Test ID: S07
- Covered row IDs: T20, T21, T22
- Starting state: unsubscribed
- Reset/fixture: `timeout(futureDate)` or `timeout({ first: 10 })`
- prefix: `subscribe`, `sourceNext(a)` before the deadline
- target event: a long gap and `sourceNext(b)`
- expected notifications: `next(a)`, `next(b)`, no `TimeoutError`
- lifecycle: timer not re-armed (371)
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2, virtual scheduler; `Date` math uses `scheduler.now()` (392)
- assertion type: source characterization
- oracle source: source characterization and contract (JSDoc 107–115)

### S08 first plus each

- Test ID: S08
- Covered row IDs: T23, T02
- Starting state: unsubscribed
- Reset/fixture: `{ first: 30, each: 10 }`
- prefix: `subscribe` at t=0
- target event: `sourceNext(a)` at t=20, then silence until t=30
- expected notifications: `next(a)` at t=20; `TimeoutError` at t=30 (`20+each`), not at t=30 from the original `first` if `a` arrived, and not at t=10
- lifecycle: initial timer unsubscribed at `a`; inter timer armed for 10
- suffix: `Stopped` if the second deadline is included
- final state: `Stopped` after the inter timeout, or `Armed` if the scenario stops at `a`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (line 392 versus line 371)

### S09 with-factory failover

- Test ID: S09
- Covered row IDs: T24, T25
- Starting state: `Armed(0, null, initial)`
- Reset/fixture: `{ each: 10, with: (info) => inner }`; `inner` emits `x` and completes
- prefix: `subscribe`, no source value
- target event: `timerFired` then inner signals
- expected notifications: `next(x)`, `complete`; not `TimeoutError`
- lifecycle: source unsubscribed before `with(info)`; `info.seen === 0`, `info.lastValue === null`; inner subscribed to the same subscriber (352)
- suffix: `Stopped` after inner complete
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (344–352) and contract (JSDoc 102–105)

## F. Coverage and evidence

Denominator = 19 transition rows (T01–T10 and T20–T28). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01, S08 | not executed |
| T03 | S02 | not executed |
| T04 | S03 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S05 | not executed |
| T08 | none | not executed |
| T09 | S06 | not executed |
| T10 | none (inapplicable for each>0) | not executed |
| T20 | S07 | not executed |
| T21 | S07 | not executed |
| T22 | S07 | not executed |
| T23 | S08 | not executed |
| T24 | S09 | not executed |
| T25 | S09 | not executed |
| T26 | S02 | not executed |
| T27 | S02 | not executed |
| T28 | S06 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Same-time ordering of `sourceNext` and `timerFired` is assumed. Negative due times are not clamped in this file. `each <= 0` is specified only by the `> 0` guard, not by a dedicated scenario. `with` observables are not given an inner Mealy model beyond subscribe-after-unsubscribe. Reentrancy excluded.
- Contract vs 7.8.2 characterization: the configuration JSDoc matches the dispatch at 310–316 and the arming rule at 386–392. `TimeoutError` message and `info` fields match 86–93 and 347–351. Number and `Date` overloads are documented as sugar (259–274) and implemented that way.
- Tests still required: S01–S09 on `TestScheduler`, plus a same-timestamp value-versus-timer case, `{ each: 0 }`, a past `Date`, `with` that throws, and `with` that errors.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
