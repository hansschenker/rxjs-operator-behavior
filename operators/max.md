# `max`

`max` emits, when the source completes, the greatest value seen so far. It does not emit intermediate maxima. There is no seed: the first source value is the maximum and the comparer is not called for it. Later values replace it when the comparer reports the current maximum as greater than `0` against the new value is false — that is, when `comparer(current, next) > 0` is false — or, with the default reducer, when `current > next` is false. An empty source completes with no emission and no `EmptyError`. A source error or a throw from the comparer (or from `>`) is a destination error and no maximum is emitted. Ties keep the later value. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Wrapper: `src/internal/operators/max.ts` lines 52–54 return `reduce(isFunction(comparer) ? (x, y) => (comparer(x, y) > 0 ? x : y) : (x, y) => (x > y ? x : y))` with no seed. Not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `max()` and `max(comparer)`. `MonoTypeOperatorFunction<T>`. Lines 52–54. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. `x` is the current maximum and `y` is the new source value. `isFunction` (`src/internal/util/isFunction.ts` lines 5–7) selects the comparer reducer; any non-function, including `undefined`, selects `>`. |
| Model kind | Symbolic. Same shape as `min`, with the comparison polarity reversed. |
| Parameter domain | Optional synchronous `comparer`. Non-functions fall back to `>`. |
| Payload/error domain | The successful payload is one of the source values. Errors are source errors or comparison throws. |
| Subscription boundary | One seedless `reduce` state per subscription. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. A comparison that is not strictly greater keeps the later value. |
| Callback assumptions | Comparer is not called on the first value. Later it is `comparer(currentMax, nextValue)`. Only a result `> 0` keeps the current maximum. |
| Cleanup assumptions | `reduce` flushes on complete iff `hasState`. |
| Explicit exclusions | Ordinary model, no reentrancy. Terminal late events are silent by convention. No `EmptyError` in `max.ts`. Relational `NaN` behavior is not repaired. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | `max(...)` returned. | selected reducer | the call | `subscribe` emits nothing |
| `active(false)` | No value yet. | none | T01 | the next value is stored raw |
| `active(true, m)` | Candidate maximum `m`. | `m` | one or more values | complete emits `m` |
| `completed` | Finished. | none | source `complete` | silence |
| `errored(e)` | Failed without a flush. | `e` | source error or comparison throw | silence |
| `cancelled` | Unsubscribed. | none | `cancel` | candidate dropped |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `reduce` subscribes. |
| Source next | yes | Installs or replaces the candidate. No emission. |
| Source error | yes | Forwarded. No flush. |
| Source completion | yes | Flushes iff a value was seen. |
| Cancellation `cancel` | yes | Drops the candidate. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | yes | Function comparer, or the default `>`, may throw from the second value onward. The first value does not call it. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Complete after at least one value is ordered `next(m)` then `complete`. A one-notification record is not enough for that input.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)`; `hasState` false | `active(false)` | `max(...)` | empty complete does not error | S01 |
| T02 | `active(false)` | source `next(v)` | first value | none | comparer not called | `active(true, v)` | T01 | the second value is compared | S02 |
| T03 | `active(true, m)` | source `next(v)` | `comparer(m, v) > 0`, or default `m > v` | none | stay subscribed | `active(true, m)` | T02 | complete emits `m` | S03 |
| T04 | `active(true, m)` | source `next(v)` | comparer result is not `> 0`, or default `m > v` is false, including equality | none | stay subscribed | `active(true, v)` | T02 | complete emits `v` | S04 |
| T05 | `active(true, m)` | source `next(v)` | comparer or `>` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | T02 | silence | S05 |
| T06 | `active` | source `error(e)` | any | `error(e)`; no flush | unsubscribe | `errored(e)` | T01 | silence | S06 |
| T07 | `active(true, m)` | source `complete` | at least one value | ordered `next(m)`, `complete` | unsubscribe | `completed` | T02 plus T03/T04 | silence | S02, S03, S04 |
| T08 | `active(false)` | source `complete` | no value | `complete` only. No `EmptyError`. | unsubscribe | `completed` | T01 | silence | S01 |
| T09 | `active` | `cancel` | open | none | unsubscribe | `cancelled` | T01 or T02 | no flush | S07 |
| T10 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S05 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Left-to-right fold (`max.ts` line 53). The survivor is a source value, not a comparison number. |
| one terminal | yes | T05, T06, T07, T08. |
| silence after terminal | yes | T10. |
| cancel does not complete | yes | T09. |
| upstream/inner lifetime | yes | One source subscription. No inners. |
| cleanup once | yes | Inherited from `reduce`. |
| per-subscription state | yes | `scanInternals` cells per subscription. |
| empty/error/silence | yes | Empty: T08, no `next`, no `EmptyError`. Single value: T07 emits it and the comparer was not called. Source error: T06. Open source: silence. |
| pending buffer on terminal | yes | Candidate `m` is flushed only by T07. Error and cancel drop it. |
| callback throw/reenter/cancel | yes | T05 after a candidate exists. Reentrancy excluded. |
| equal-time/timers | no | No timers. Ties are T04. |

## E. Scenario specification

### S01 Empty source

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T08 |
| Starting state | `idle` |
| Reset/fixture | `max()`, empty source |
| State-reaching prefix | call `max` |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | comparer not called; no `EmptyError` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `complete` rather than `error` |
| Oracle source | `source characterization` |

### S02 Single value

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T07 |
| Starting state | `active(false)` |
| Reset/fixture | comparer throws if called; one value `v` then complete |
| State-reaching prefix | `subscribe` |
| Target event | `next(v)` and complete |
| Expected notifications | `next(v)`, `complete` |
| Expected lifecycle observations | comparer call count is 0 |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | comparer not invoked |
| Oracle source | `source characterization` |

### S03 Current maximum is strictly greater

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T07 |
| Starting state | `active(true, 5)` |
| Reset/fixture | `max()`, values `5` then `1`, then complete |
| State-reaching prefix | `subscribe` and `next(5)` |
| Target event | `next(1)` and complete |
| Expected notifications | `next(5)`, `complete` |
| Expected lifecycle observations | no emission before complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | survivor is `5` |
| Oracle source | `source characterization` |

### S04 Tie keeps the later value

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04, T07 |
| Starting state | `active(true, a)` |
| Reset/fixture | two equal values, or a comparer that returns `0`; then complete |
| State-reaching prefix | `subscribe` and the first next |
| Target event | second next and complete |
| Expected notifications | `next(later)`, `complete` |
| Expected lifecycle observations | no emission before complete |
| Distinguishing suffix | comparer returning a positive number would have kept `a` (T03) |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | reference of the later value |
| Oracle source | `source characterization` |

### S05 Comparer throw

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T05, T10 |
| Starting state | `active(true, m)` |
| Reset/fixture | comparer throws `e` |
| State-reaching prefix | `subscribe` and one next |
| Target event | second `next` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; no `next(m)` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error, not a maximum |
| Oracle source | `source characterization` |

### S06 Source error

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T06 |
| Starting state | `active(true, m)` |
| Reset/fixture | one value, then source `error(e)` |
| State-reaching prefix | `subscribe` and one next |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | no flush |
| Oracle source | `contract` |

### S07 Cancel

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T09 |
| Starting state | `active(true, m)` |
| Reset/fixture | one value, source open |
| State-reaching prefix | `subscribe` and one next |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no `next(m)` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 10 section C rows (T01–T10).

Section E references every row. Specified coverage = 10/10.

Execution: not executed.

Evidence: `src/internal/operators/max.ts` lines 52–54 and the seedless `reduce` / `scanInternals` complete handler (`scanInternals.ts` lines 54–58). No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `max` is `min` with the comparison polarity changed from `<` to `>` and from `< 0` to `> 0`. The subscription protocol is the same seedless `reduce`.

Known limitations: non-function comparers are ignored. Equality prefers the later value. There is no `EmptyError` on an empty source in this version. Reentrancy is excluded.

Contract vs version characterization: JSDoc promises the largest item when the source completes. Empty-source completion without an error is source characterization, contrary to an `EmptyError` reading of older RxJS.

Tests still required: S01–S07, plus the `>` fallback when `comparer` is not a function.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
