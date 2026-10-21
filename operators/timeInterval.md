# `timeInterval`

`timeInterval` emits a `TimeInterval` instance `{ value, interval }` for each source value. `interval` is the difference between `scheduler.now()` at that value and the previous stamp. The previous stamp is initialized with `scheduler.now()` when the operator subscribes, before `source.subscribe`, so the first interval is measured from subscription, not from a previous value. Later intervals are measured from the previous value’s stamp. The operator does not delay or schedule emissions. A throw from the initial `now` is a destination error and the source is not subscribed. A throw from a later `now` is a destination error and does not emit that value. Source errors and completion are forwarded. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/timeInterval.ts` lines 45–57. Default argument is `asyncScheduler` (line 45). Not deprecated. The `TimeInterval` constructor is marked an internal detail to become an interface in v8 (lines 62–66); the operator still uses `new TimeInterval`.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `timeInterval()` and `timeInterval(scheduler)`. Lines 45–57. Return type uses the class `TimeInterval<T>` (lines 62–67), which matches `value` and `interval` on the interface in `types.ts` lines 65–69. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | `last = scheduler.now()` at subscription. On each value: `now = scheduler.now()`, `interval = now - last`, `last = now`, `next(new TimeInterval(value, interval))`. |
| Model kind | Symbolic, with an external `now()` oracle and one stored stamp. Not a timed automaton: no action is scheduled, and time does not by itself cause a transition. |
| Parameter domain | `scheduler` is `SchedulerLike` and must provide synchronous `now(): number`. Default `asyncScheduler` uses `Scheduler.now`, which is `dateTimestampProvider.now` (`Scheduler.ts` line 25) unless that binding was replaced. |
| Payload/error domain | Payload is a `TimeInterval` instance. `interval` is a JavaScript number subtraction, so a backwards clock yields a negative interval and is not rejected. Errors are source errors or throws from `now`. |
| Subscription boundary | `last` is a local of `operate`, per subscription (line 47). One source subscription. No inners. |
| Scheduler and tie ordering | No queue. Several synchronous nexts that observe the same `now()` result produce `interval` `0` after the first of those that shared a stamp with `last`, in source order. Nothing is sorted by time. |
| Callback assumptions | `now` is synchronous. It runs once before subscribe and once per source value. It does not run on source error, source complete, or cancel. |
| Cleanup assumptions | If the initial `now` throws, `operate`’s `try/catch` calls `this.error` (`src/internal/util/lift.ts` lines 22–27) and `source.subscribe` is not reached. A later throw uses `OperatorSubscriber._next`. Default error and complete paths otherwise. |
| Explicit exclusions | Ordinary model, no reentrancy. A non-numeric `now` result is outside the model (subtraction would still run). Terminal late events are silent by convention. The constructor’s deprecation does not stop the operator from constructing the class. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Not subscribed. | the scheduler | the call | the next step reads `now` before subscribing |
| `active(last)` | Subscribed. | stamp `last` | a successful T01 | the next value’s interval is `now - last` |
| `completed` | Source completed. | none | source `complete` | silence |
| `errored(e)` | `now` threw or the source errored. | `e` | T02, T04 | a T02 error never subscribed the source |
| `cancelled` | Unsubscribed. | none | `cancel` | no `TimeInterval` |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 46–55. Includes the first `now` read. |
| Source next | yes | Lines 49–54. |
| Source error | yes | Default forward. `now` not called. |
| Source completion | yes | Default forward. |
| Cancellation `cancel` | yes | Drops `last`. |
| Inner notifications | no | None. |
| Time | yes, as an oracle | `now()` is read at subscribe and on each next. There is no timer interrupt. |
| User callback outcomes | yes | `now` may throw. There is no other user function. `new TimeInterval` only assigns fields (lines 62–67). |

### Γ

```text
record {
  trace: ordered list of next(TimeInterval) | error(err) | complete,
  effects: read(now) | subscribe(source) | unsubscribe(source)
}
```

Each input emits at most one notification. T01 can fail with `error` and must not be recorded as also having subscribed. An ordered trace of effects matters for T01: `read(now)` happens before `subscribe(source)`.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | initial `scheduler.now()` returns `t0` | none | `last = t0`, then `subscribe(source)` (lines 47–48) | `active(t0)` | `timeInterval(scheduler)` | the first value’s interval is `now - t0` | S01 |
| T02 | `idle` | `subscribe` | initial `now()` throws `e` | `error(e)` | source is not subscribed (`lift.ts` lines 22–27 catch the throw from `init`) | `errored(e)` | the call | no source effect runs | S02 |
| T03 | `active(last)` | source `next(v)` | `now()` returns `t` | `next(new TimeInterval(v, t - last))` | `last` becomes `t`; stay subscribed | `active(t)` | T01 | the next interval uses `t`, not the original subscription stamp | S01 |
| T04 | `active(last)` | source `next(v)` | `now()` throws `e` | `error(e)`; no `next` | `last` is not updated (throw is on line 50, before line 52); unsubscribe | `errored(e)` | T01 | silence | S03 |
| T05 | `active(last)` | source `error(e)` | any | `error(e)` | unsubscribe; `now` not called | `errored(e)` | T01 | silence | S04 |
| T06 | `active(last)` | source `complete` | any | `complete` | unsubscribe | `completed` | T01, optional T03 | silence | S05 |
| T07 | `active(last)` | `cancel` | open | none | unsubscribe | `cancelled` | T01 | no `TimeInterval` | S06 |
| T08 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S03 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | One `TimeInterval` per source value, source order. `value` is the source reference. `interval` is `now - last` (lines 50–53). |
| one terminal | yes | T02, T04, T05, or T06. |
| silence after terminal | yes | T08. |
| cancel does not complete | yes | T07. |
| upstream/inner lifetime | yes | Source is subscribed only after a successful initial `now` (T01) and is released by T04–T07. T02 never subscribes. No inners. |
| cleanup once | yes | Default unsubscribe. T02 has no source subscription to clean. |
| per-subscription state | yes | `last` is inside `operate` (line 47). |
| empty/error/silence | yes | Empty source: T01 then T06, no `TimeInterval`, but `now` was called once (S05). Source error: T05, no instance. Open source: one instance per next. |
| pending buffer on terminal | no | The stamp is not a value buffer. It is dropped without emission. |
| callback throw/reenter/cancel | yes | T02 and T04. Reentrancy excluded. |
| equal-time/timers | yes, as equal oracle reads | If `now()` is unchanged, the corresponding `interval` is `0`. Emissions are not reordered. A backwards clock yields a negative interval and is still a `next`. |

## E. Scenario specification

### S01 Subscription stamp, then sliding stamp

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T03 |
| Starting state | `idle` |
| Reset/fixture | `now` returns `100` at subscribe, `130` on the first value, `130` on the second value; source emits `a` then `b` |
| State-reaching prefix | `timeInterval(scheduler)` |
| Target event | `subscribe` and both nexts |
| Expected notifications | `next(TimeInterval(a, 30))`, `next(TimeInterval(b, 0))` |
| Expected lifecycle observations | `now` called once before `source.subscribe` and once per value; both results are `TimeInterval` instances |
| Distinguishing suffix | a third value with `now() === 155` has interval `25`, not `155 - 100` |
| Expected final state | `active(130)` after the two nexts |
| Version and scheduler | 7.8.2; scheduler is only a `now` oracle |
| Assertion type | intervals and instance type |
| Oracle source | `source characterization` |

### S02 Initial now throws

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02 |
| Starting state | `idle` |
| Reset/fixture | `now` throws `e` on the first call |
| State-reaching prefix | `timeInterval(scheduler)` |
| Target event | `subscribe` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source subscribe function was not called |
| Distinguishing suffix | none |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no queue |
| Assertion type | error and absence of source subscription |
| Oracle source | `source characterization` |

### S03 Later now throws

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T04, T08 |
| Starting state | `active(100)` |
| Reset/fixture | the next `now` throws `e` |
| State-reaching prefix | successful `subscribe` |
| Target event | source `next(v)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; no `TimeInterval` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no queue |
| Assertion type | error, not a partial instance |
| Oracle source | `source characterization` |

### S04 Source error does not sample now

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active(t0)` |
| Reset/fixture | source `error(e)` |
| State-reaching prefix | successful `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | `now` is not called again |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no queue |
| Assertion type | error payload |
| Oracle source | `source characterization` |

### S05 Empty complete still sampled once

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `active(t0)` |
| Reset/fixture | source completes with no next |
| State-reaching prefix | successful `subscribe` |
| Target event | source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | unsubscribed; `now` call count remains 1 |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, default `asyncScheduler` only as the `now` source |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S06 Cancel

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T07 |
| Starting state | `active(t0)` |
| Reset/fixture | live source |
| State-reaching prefix | successful `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no `TimeInterval` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no queue |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 8 section C rows (T01–T08).

Section E references every row. Specified coverage = 8/8.

Execution: not executed.

Evidence: `src/internal/operators/timeInterval.ts` lines 45–67 and `src/internal/util/lift.ts` lines 22–27. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the operator stores one stamp, samples `now` at two well-defined sites, and otherwise forwards terminals.

Known limitations: negative and zero intervals are legal outputs. The public type is documented as an object, while the runtime value is a class instance whose constructor is deprecated. Reentrancy is excluded. This is not a model of `asyncScheduler` flushing.

Contract vs version characterization: JSDoc lines 6–12 describe the delta and the default scheduler. “First delta is from subscription” follows from line 47 running before line 48, which the JSDoc’s “between emitting the current value and the previous value” under-specifies for the first value. The initial-throw path is source characterization of `operate`.

Tests still required: S01–S06, including a zero interval and a negative interval.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
