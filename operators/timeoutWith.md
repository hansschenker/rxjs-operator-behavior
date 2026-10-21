# timeoutWith

`timeoutWith(due, withObservable, scheduler?)` is a deprecated wrapper around `timeout` and will be removed in v8 (`timeoutWith.ts` 6–11, 79–81). A `Date` `due` becomes `{ first: due, with: () => withObservable, scheduler }`. A numeric `due` becomes `{ each: due, with: () => withObservable, scheduler }` (`timeoutWith.ts` 93–115). The `with` factory ignores timeout info and always returns the same `ObservableInput`. There is no default `TimeoutError` on this path: if `withObservable` is missing the operator throws `TypeError` at build time (99–103). Scheduler default is `async` from `../scheduler/async` (line 91), the same `asyncScheduler`. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/timeoutWith.ts` delegating to `timeout.ts`.

## A. Identity, contract, and scope

- Operator/overload: `timeoutWith(due: Date, withObservable, scheduler?)` and `timeoutWith(due: number, withObservable, scheduler?)` (`timeoutWith.ts` 8–11, 83–87). Both overloads are `@deprecated`.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 14–27. Numeric `due` is the allowed gap between values, including the wait for the first value, because it maps to `each`. A `Date` is only a first-value deadline (maps to `first`). On timeout, unsubscribe the source and subscribe to `withObservable` (the `timeout` failover, `timeout.ts` 345–352).
- Model kind: timed, not finite. The state machine is `timeout`’s, with `with` fixed.
- Parameter domain: `due` must be a valid `Date` (`isValidDate`, used at line 93) or a `number` (line 95). Anything else leaves `first` and `each` unset and throws `TypeError('No timeout provided.')` (105–108). Falsy `withObservable` throws `TypeError('No observable provided to switch to')` (99–103) before the timeout check. `scheduler` defaults to `async` (line 91).
- Payload/error domain: output is `T | R` where `R` comes from `withObservable`. This wrapper does not construct `TimeoutError` unless `withObservable` itself does. `with` is `() => withObservable` (line 100), so `TimeoutInfo` is ignored. If `withObservable` is cold, each failover subscribes fresh; if it is hot, the subscription joins that execution. Only one failover occurs, because the source is unsubscribed.
- Subscription boundary: identical to `timeout` after the config object is built (110–115). Source subscribed immediately. Timer is a child of the destination.
- Scheduler and tie ordering: same assumption as `timeout`, not a proof: same-virtual-time actions run in schedule order. Micro-trace required at the deadline.
- Callback assumptions: the factory does not throw; it returns a stored input. Errors come from `withObservable` or from `timeout`’s subscribe path. Ordinary model: no reentrancy.
- Cleanup assumptions: inherited. `cancel` clears the timer and does not complete. Source error and complete are immediate and do not switch. Timeout unsubscribes the source before subscribing to `withObservable`.
- Explicit exclusions: reentrancy; using this API after v8; `meta`; a `with` factory that sees `TimeoutInfo` (this wrapper drops it); negative delays beyond what `timeout`/`executeSchedule` do.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Armed(seen = 0, lastValue = null)
```

`δ`/`λ` are the `timeout` rows for either `{ each: due, with }` or `{ first: due, with }`. This file adds only the normalization.

### S

`Armed`, `Idle` (Date form, after the first value), `FailedOver`, `Stopped`. Same meanings as `timeout.md`. No separate `TimeoutError` location unless the switched observable errors with one.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | After a successful build. |
| `sourceNext(v)` | yes | source | `timeout.ts` 364–371. |
| `sourceError(e)` | yes | source | Immediate; no switch. |
| `sourceComplete` | yes | source | Immediate; no switch. |
| `cancel` | yes | unsubscribe | Timer cleared; no `complete`. |
| `timerFired` | yes | timeout schedule | Switch, not `TimeoutError`, when `withObservable` is set. |
| `withNext` / `withError` / `withComplete` | yes | `withObservable` after failover | Direct to destination (`timeout.ts` 352). |
| `selectorThrow` | no | factory is `() => withObservable` | Inapplicable unless `innerFrom` throws, which then follows `timeout`’s catch (353–355). |
| build `TypeError` | yes, outside the stream | this function (99–108) | Not a notification. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Failover itself is `none` until `withObservable` notifies. Micro-trace required at `timerFired`.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | build | `timeoutWith(n, inner, sch?)` | `n` is a number and `inner` is truthy | `none` | `each=n`, `with=()=>inner`, `scheduler=sch??async` (95–114) | returns `timeout({...})` | — | subscribe uses the each-machine | S01 |
| T02 | build | `timeoutWith(date, inner, sch?)` | `isValidDate(date)` and `inner` truthy | `none` | `first=date`, `each` unset (93–94, 110–114) | returns `timeout({...})` | — | first-only machine | S02 |
| T03 | build | call | `!withObservable` | throw `TypeError` ('No observable provided to switch to') | no operator (99–103) | none | — | — | S03 |
| T04 | build | call | `due` neither valid `Date` nor number | throw `TypeError` ('No timeout provided.') | no operator (105–108). This runs only if `withObservable` was truthy | none | — | — | S03 |
| T05 | `Armed` | `subscribe` | numeric form, `each > 0` | `none` | initial `startTimer(each)` (`timeout.ts` 392) | `Armed(0, null)` | T01 | value or timer | S01 |
| T06 | `Armed` | `sourceNext(v)` | numeric, `each > 0` | `next(v)` | re-arm `each` (`timeout.ts` 366–371) | `Armed(seen, v)` | T05 | gap reset | S01 |
| T07 | `Armed` | `timerFired` | — | `none` until `inner` notifies | source unsubscribed; `innerFrom(inner).subscribe(subscriber)` (`timeout.ts` 345–352). Info object is built and ignored by this factory | `FailedOver` | T05 or T06 | inner signals | S01 |
| T08 | `FailedOver` | `withNext` / `withComplete` / `withError` | — | that signal | original source already unsubscribed | stay or `Stopped` | T07 | no further source | S01 |
| T09 | `Armed` | `sourceError(e)` | — | `error(e)`; no switch | timer cleared | `Stopped` | T05 | none | S04 |
| T10 | `Armed` | `sourceComplete` | — | `complete`; no switch | timer cleared | `Stopped` | T06 | none | S04 |
| T11 | `Armed` | `cancel` | — | `none` | timer cleared; no `complete` | `Stopped` | T05 | deadline must not switch | S05 |
| T12 | `Armed` then `Idle` | Date form `sourceNext` before deadline | `each` unset | `next(v)` | timer not re-armed (`timeout.ts` 371) | `Idle` | T02 | later gaps do not switch | S02 |
| T13 | `Armed` | Date form `timerFired` before any value | date reached | switch as T07 | absolute delay `+date - scheduler.now()` (`timeout.ts` 392) | `FailedOver` | T02 | inner signals | S02 |
| T14 | `Stopped` or `Idle` | `timerFired` | no timer | — | inapplicable | — | — | — | — |
| T15 | `FailedOver` | `sourceNext` | source unsubscribed | — | inapplicable | `FailedOver` | T07 | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Numeric `timeoutWith(ms, inner)` is `timeout({ each: ms, with: () => inner })` (lines 95–114). Every gap, including the first, can switch. |
| I02 | `timeoutWith(date, inner)` is `timeout({ first: date, with: () => inner })`. Only the first value is guarded (93–94, and `timeout.ts` 371). |
| I03 | The switched observable does not receive `TimeoutInfo`. The factory closes over `withObservable` (line 100). |
| I04 | This wrapper does not emit `TimeoutError` by itself. |
| I05 | Source `error` and source `complete` do not switch. |
| I06 | `cancel` does not switch and does not complete. |
| I07 | Missing observable or missing deadline throws at build time, not as a stream error (99–108). |
| I08 | The API is deprecated and scheduled for removal in v8 (lines 6–11, 79–81). |

## E. Scenario specification

### S01 Numeric due switches and the inner completes

- Test ID: S01
- Covered row IDs: T01, T05, T06, T07, T08
- Starting state: operator built with `timeoutWith(10, inner)`
- Reset/fixture: virtual scheduler; `inner` emits `x` and completes; source emitted `a` at t=4 and then goes silent
- prefix: `subscribe`, `sourceNext(a)` at t=4 (`next(a)`, re-arm to t=14)
- target event: `timerFired` at t=14
- expected notifications: `next(a)` then, at failover, `next(x)`, `complete`; no `TimeoutError`
- lifecycle: source unsubscribed at t=14; `inner` subscribed
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler (`async` default if omitted)
- assertion type: source characterization
- oracle source: source characterization (`timeoutWith.ts` 95–114, `timeout.ts` 345–371)

### S02 Date due only gates the first value

- Test ID: S02
- Covered row IDs: T02, T12, T13
- Starting state: built with a future `Date`
- Reset/fixture: two runs: value before the date, and no value by the date
- prefix: `subscribe`
- target event: `sourceNext(a)` before the date, or `timerFired` if no value
- expected notifications: first run `next(a)` and no later switch even if the next gap is long; second run switch to `inner` at the date
- lifecycle: Date form does not set `each` (93–94)
- suffix: `Idle` or `FailedOver`
- final state: as suffix
- version and scheduler: 7.8.2, virtual scheduler whose `now()` matches `Date` epoch math (`timer` warning does not apply; `timeout.ts` 392 uses `scheduler.now()` directly)
- assertion type: source characterization
- oracle source: source characterization and contract (JSDoc 26–32, deprecation comment lines 6–7)

### S03 Build throws

- Test ID: S03
- Covered row IDs: T03, T04
- Starting state: not built
- Reset/fixture: `timeoutWith(10, null)` and `timeoutWith(undefined, inner)`
- prefix: none
- target event: the call
- expected notifications: none; `TypeError` thrown synchronously
- lifecycle: no subscription
- suffix: none
- final state: no operator
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (99–108)

### S04 Source termination does not switch

- Test ID: S04
- Covered row IDs: T09, T10
- Starting state: `Armed` for numeric `timeoutWith(10, inner)`
- Reset/fixture: separate error and complete runs before the deadline
- prefix: `subscribe`, optional `sourceNext`
- target event: `sourceError(e)` or `sourceComplete`
- expected notifications: `error(e)` or `complete`; `inner` not subscribed
- lifecycle: timer cleared with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (delegated default handlers in `timeout.ts` 373–374)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T11
- Starting state: `Armed`
- Reset/fixture: deadline in the future
- prefix: `subscribe`
- target event: `cancel`
- expected notifications: none
- lifecycle: timer unsubscribed; `inner` not subscribed; no `complete`
- suffix: deadline must not switch
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (timer parented by `executeSchedule` inside `timeout`)

## F. Coverage and evidence

Denominator = 15 (T01–T15). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S02 | not executed |
| T03 | S03 | not executed |
| T04 | S03 | not executed |
| T05 | S01 | not executed |
| T06 | S01 | not executed |
| T07 | S01 | not executed |
| T08 | S01 | not executed |
| T09 | S04 | not executed |
| T10 | S04 | not executed |
| T11 | S05 | not executed |
| T12 | S02 | not executed |
| T13 | S02 | not executed |
| T14 | none (inapplicable) | not executed |
| T15 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Behavior after the config object is built is `timeout`’s machine; this document does not re-prove `executeSchedule`. Hot versus cold `withObservable` is only distinguished as “the same input is subscribed,” not as a full inner model. Tie order is assumed. Deprecated API.
- Contract vs 7.8.2 characterization: deprecation comments (6–11, 79–81) match the object passed at 110–115. JSDoc’s “switch when the timespan elapses before the source emits any given value” matches the numeric `each` mapping, not a `first`-only reading.
- Tests still required: S01–S05, plus a past `Date`, and a hot `withObservable` if that sharing matters to callers.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
