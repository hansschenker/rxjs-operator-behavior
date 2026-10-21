# `timestamp`

`timestamp` maps each source value to a plain object `{ value, timestamp }` whose `timestamp` is `timestampProvider.now()` at the moment that value is projected. Source errors and source completion are forwarded. A throw from `now` is a `map` callback error: destination `error` and unsubscribe. The operator does not schedule work and does not delay values. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Wrapper: `src/internal/operators/timestamp.ts` lines 37–39 return `map((value) => ({ value, timestamp: timestampProvider.now() }))`. The default provider is `dateTimestampProvider`, not `asyncScheduler` (line 37). Not deprecated. The JSDoc sentence that says the default is `asyncScheduler` (lines 10–12) does not match the default argument.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `timestamp()` and `timestamp(timestampProvider)`. `OperatorFunction<T, Timestamp<T>>`. Lines 37–39. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | On each source `next(v)`, emit `next({ value: v, timestamp: timestampProvider.now() })`. `Timestamp<T>` is `{ value: T, timestamp: number }` (`src/internal/types.ts` lines 49–56). |
| Model kind | Symbolic, with an external `now()` oracle. Not a timed automaton: there is no scheduled action, no delay, and no clock that wakes the operator. |
| Parameter domain | `timestampProvider` implements `now(): number` (`types.ts` lines 240–248). Default is `dateTimestampProvider`. |
| Payload/error domain | Payload is a fresh object per value. `timestamp` is whatever `now()` returns (a number when the provider is honest). Errors are source errors or a throw from `now`. |
| Subscription boundary | No cell of its own. `map` keeps a per-subscription index that this operator ignores. One source subscription. No inners. |
| Scheduler and tie ordering | No queue. If two source nexts see the same `now()` result, both output objects carry that same number, in source order. Nothing is reordered. |
| Callback assumptions | `now` is synchronous and is called inside the `map` project, once per source value, not at subscribe. The default `dateTimestampProvider.now` is `(dateTimestampProvider.delegate \|\| Date).now()` (`src/internal/scheduler/dateTimestampProvider.ts` lines 7–13). |
| Cleanup assumptions | Inherited from `map`. |
| Explicit exclusions | Ordinary model, no reentrancy. A provider whose `now` returns a non-number is outside the type but is not rejected. Terminal late events are silent by convention. The default is not “call `asyncScheduler`”; `asyncScheduler.now` happens to use `Scheduler.now`, which is also `dateTimestampProvider.now` (`Scheduler.ts` line 25), so the numeric clock matches unless `delegate` is set. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator created. | `timestampProvider` | the call | `subscribe` does not read `now` |
| `active` | Subscribed. | none beyond `map`’s index | T01 | each next reads `now` once |
| `completed` | Source completed. | none | source `complete` | silence |
| `errored(e)` | Source error or `now` throw. | `e` | T03 or T04 | silence |
| `cancelled` | Unsubscribed. | none | `cancel` | no timestamp object |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `map` subscribes. `now` is not called here. |
| Source next | yes | Builds the object. |
| Source error | yes | `map` default forward. `now` is not called. |
| Source completion | yes | `map` default forward. |
| Cancellation `cancel` | yes | Same as `map`. |
| Inner notifications | no | None. |
| Time | yes, as an oracle read | `now()` is sampled on source next only. There is no timeout input. |
| User callback outcomes | yes | `now` may return or throw. There is no other user function. The object literal itself does not throw. |

### Γ

```text
record {
  trace: ordered list of next({value, timestamp}) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source) | read(now)
}
```

Each input emits at most one notification. A one-notification record is enough. The `now` read is an effect paired with T02 or T03, not a second notification.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any provider | none | `subscribe(source)`; `now` not called | `active` | `timestamp(provider)` | a source next calls `now` once | S01 |
| T02 | `active` | source `next(v)` | `now()` returns `t` | `next({ value: v, timestamp: t })` | stay subscribed | `active` | T01 | a second next reads `now` again and allocates a new object | S01 |
| T03 | `active` | source `next(v)` | `now()` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | T01 | silence | S02 |
| T04 | `active` | source `error(e)` | any | `error(e)` | unsubscribe; `now` not called | `errored(e)` | T01 | silence | S03 |
| T05 | `active` | source `complete` | any | `complete` | unsubscribe | `completed` | T01, optional T02 | silence | S04 |
| T06 | `active` | `cancel` | open | none | unsubscribe | `cancelled` | T01 | no object | S05 |
| T07 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S02 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | One object per source value, source order (`timestamp.ts` line 38). `value` is the same reference. |
| one terminal | yes | T03, T04, or T05. |
| silence after terminal | yes | T07. |
| cancel does not complete | yes | T06. |
| upstream/inner lifetime | yes | One source subscription. No inners. |
| cleanup once | yes | Inherited from `map`. |
| per-subscription state | yes | No timestamp is stored. `map`’s index is per subscription and unused. The provider is shared. |
| empty/error/silence | yes | Empty source: T05, no object, and `now` was not called (S04). Source error: T04, `now` not called. Open source: one object per next. |
| pending buffer on terminal | no | Nothing is buffered. |
| callback throw/reenter/cancel | yes | T03 is a `now` throw, distinct from T04. Reentrancy excluded. |
| equal-time/timers | yes, as oracle ties only | Two nexts with the same `now()` result keep source order and both carry that timestamp. No timer queue exists to reorder them. |

## E. Scenario specification

### S01 Two values sample now twice

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | provider `now` returns `10` then `40`; source emits `a` then `b` |
| State-reaching prefix | `timestamp(provider)` |
| Target event | `subscribe` and both nexts |
| Expected notifications | `next({value: a, timestamp: 10})`, `next({value: b, timestamp: 40})` |
| Expected lifecycle observations | `now` called once per next and not at subscribe; two distinct objects |
| Distinguishing suffix | source `complete` → `complete` |
| Expected final state | `completed` after the suffix |
| Version and scheduler | 7.8.2; provider is the test double, not a scheduler queue |
| Assertion type | field equality and call count of `now` |
| Oracle source | `source characterization` |

### S02 now throws

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T03, T07 |
| Starting state | `active` |
| Reset/fixture | `now` throws `e` |
| State-reaching prefix | `subscribe` |
| Target event | source `next(v)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; no object |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler queue |
| Assertion type | error, not a partial object |
| Oracle source | `source characterization` |

### S03 Source error does not read now

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T04 |
| Starting state | `active` |
| Reset/fixture | `now` would throw if called; source `error(e)` |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | `now` call count is 0 |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler queue |
| Assertion type | error payload and `now` not called |
| Oracle source | `source characterization` |

### S04 Empty complete

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active` |
| Reset/fixture | source completes with no next; default provider |
| State-reaching prefix | `subscribe` |
| Target event | source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, default `dateTimestampProvider` |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S05 Cancel

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `active` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed; `now` not called |
| Distinguishing suffix | no timestamp object |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler queue |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references every row. Specified coverage = 7/7.

Execution: not executed.

Evidence: `src/internal/operators/timestamp.ts` lines 37–39, `src/internal/scheduler/dateTimestampProvider.ts` lines 7–14, and `map.ts` lines 54–58. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the operator is `map` of a one-field object that samples `now` synchronously.

Known limitations: the JSDoc default (`asyncScheduler`) is not the parameter default (`dateTimestampProvider`). They share a clock only while `dateTimestampProvider.delegate` is unset and `Scheduler.now` still points at `dateTimestampProvider.now`. Reentrancy is excluded. Equal timestamps are not a race.

Contract vs version characterization: the object shape is the JSDoc and `Timestamp<T>`. The default argument and “`now` is not called on subscribe, error, complete, or cancel” are source characterization.

Tests still required: S01–S05, plus a default-provider test that does not require a scheduler flush.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
