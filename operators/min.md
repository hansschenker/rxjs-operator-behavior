# `min`

`min` emits, when the source completes, the least value seen so far. It does not emit intermediate minima. There is no seed: the first source value is the minimum and the comparer is not called for it. Later values replace it when the comparer reports the new value as smaller, or when the default `<` comparison says the current minimum is not strictly smaller. An empty source completes with no emission and no `EmptyError`. A source error or a throw from the comparer (or from `<`) is a destination error and no minimum is emitted. Ties keep the later value. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Wrapper: `src/internal/operators/min.ts` lines 52–54 return `reduce` with no seed. Not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `min()` and `min(comparer)`. `MonoTypeOperatorFunction<T>`. Lines 52–54. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | `isFunction(comparer)` selects `(x, y) => (comparer(x, y) < 0 ? x : y)`; otherwise `(x, y) => (x < y ? x : y)`. That reducer is passed to `reduce` with no seed (`hasSeed` false). `x` is the current minimum and `y` is the new value. |
| Model kind | Symbolic. Values are uninterpreted except for the comparison result. |
| Parameter domain | `comparer`, if present and a function, is synchronous and should return a number. A non-function `comparer`, including `undefined`, selects the `<` reducer (`isFunction`, `src/internal/util/isFunction.ts` lines 5–7). |
| Payload/error domain | The output payload is one of the source values (the same reference the reducer returns). Errors are source errors or comparison throws. |
| Subscription boundary | One `reduce` / `scanInternals` state per subscription. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. “Tie” here means a comparison that is not strictly less, not an equal-time timer. The later source value wins. |
| Callback assumptions | Comparer is not called on the first value. On later values it is called as `comparer(currentMin, nextValue)`. Only a return `< 0` keeps the current minimum. `0`, positive, `NaN`, and any non-`< 0` result keep `y`. |
| Cleanup assumptions | Same as `reduce`: flush on complete iff `hasState`, otherwise bare `complete`. |
| Explicit exclusions | Ordinary model, no reentrancy. Terminal late events are silent by convention. No `EmptyError` path exists in `min.ts`. JavaScript `<` and relational `NaN` behavior are not repaired. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | `min(...)` returned. | which reducer was selected | the call | `subscribe` emits nothing |
| `active(false)` | Subscribed, no value yet. | no minimum | T01 | the next value is stored raw |
| `active(true, m)` | A minimum candidate `m` is held. | `m` and the scan index | one or more values | complete emits `m`; a smaller later value changes `m` |
| `completed` | Completed with or without a flush. | none | source `complete` | silence |
| `errored(e)` | Failed. | `e` | source error or comparison throw | `m` was not emitted |
| `cancelled` | Unsubscribed. | none | `cancel` | `m` is dropped |

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
| User callback outcomes | yes | The function comparer may return or throw, but only from the second value onward. The default `<` reducer may also throw (for example on values whose relational comparison throws) and that throw is the same accumulator failure. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Complete-with-a-value is the ordered pair `next(m)` then `complete`. Other inputs emit at most one notification.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)`; `hasState` false | `active(false)` | `min(...)` | empty complete does not error | S01 |
| T02 | `active(false)` | source `next(v)` | first value | none | comparer not called | `active(true, v)` | T01 | a second value does call the comparer | S02 |
| T03 | `active(true, m)` | source `next(v)` | function comparer returns `< 0`, or default `m < v` is true | none | stay subscribed | `active(true, m)` | T02 | complete still emits `m` | S03 |
| T04 | `active(true, m)` | source `next(v)` | comparer result is not `< 0`, or default `m < v` is false, including equality | none | stay subscribed | `active(true, v)` | T02 | complete emits `v`, not `m` | S04 |
| T05 | `active(true, m)` | source `next(v)` | comparer or `<` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | T02 | silence | S05 |
| T06 | `active` | source `error(e)` | any | `error(e)`; no flush | unsubscribe | `errored(e)` | T01 | silence | S06 |
| T07 | `active(true, m)` | source `complete` | at least one value | ordered `next(m)`, `complete` | unsubscribe | `completed` | T02 plus T03/T04 | silence | S02, S03, S04 |
| T08 | `active(false)` | source `complete` | no value | `complete` only. No `EmptyError`. | unsubscribe | `completed` | T01 | silence | S01 |
| T09 | `active` | `cancel` | open | none | unsubscribe | `cancelled` | T01 or T02 | no flush | S07 |
| T10 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S05 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | The emitted value is the survivor of a left-to-right fold (`min.ts` line 53). First value is not compared. |
| one terminal | yes | T05, T06, T07, T08. |
| silence after terminal | yes | T10. |
| cancel does not complete | yes | T09. |
| upstream/inner lifetime | yes | One source subscription. No inners. |
| cleanup once | yes | Inherited from `reduce`. |
| per-subscription state | yes | `scanInternals` cells are per subscription. The reducer function is chosen once per `min(...)` call. |
| empty/error/silence | yes | Empty: T08, `complete`, no `next`, no `EmptyError` (S01). Single value: that value, comparer not called (S02). Source error: T06. Never completes: silence in `active`. |
| pending buffer on terminal | yes | `m` is pending after T02. T07 emits it. T06 and T09 drop it. T08 has nothing pending. |
| callback throw/reenter/cancel | yes | T05, only after a candidate exists. Reentrancy excluded. |
| equal-time/timers | no | No timers. Comparison ties are T04, not a scheduler queue. |

## E. Scenario specification

### S01 Empty source

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T08 |
| Starting state | `idle` |
| Reset/fixture | `min()` or `min(comparer)`, empty source |
| State-reaching prefix | call `min` |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | comparer not called; no `EmptyError` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `complete` rather than `error` or `next` |
| Oracle source | `source characterization` |

### S02 Single value

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T07 |
| Starting state | `active(false)` |
| Reset/fixture | `min(comparer)` where `comparer` throws if called; source emits `v` then completes |
| State-reaching prefix | `subscribe` |
| Target event | source `next(v)` and source `complete` |
| Expected notifications | `next(v)`, `complete` |
| Expected lifecycle observations | comparer call count is 0 |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | comparer not invoked |
| Oracle source | `source characterization` |

### S03 Strictly smaller candidate is kept

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T07 |
| Starting state | `active(true, 1)` |
| Reset/fixture | `min()`, values `1` then `5`, then complete |
| State-reaching prefix | `subscribe` and `next(1)` |
| Target event | `next(5)` and complete |
| Expected notifications | `next(1)`, `complete` |
| Expected lifecycle observations | no emission before complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | survivor is the earlier smaller value |
| Oracle source | `source characterization` |

### S04 Tie or greater keeps the later value

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04, T07 |
| Starting state | `active(true, a)` |
| Reset/fixture | two equal numbers under `<`, or a comparer that returns `0`; then complete |
| State-reaching prefix | `subscribe` and the first next |
| Target event | second next and complete |
| Expected notifications | `next(later)`, `complete` |
| Expected lifecycle observations | no emission before complete |
| Distinguishing suffix | a comparer that returns `-1` on the same pair would have kept the earlier value (T03) |
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
| Reset/fixture | comparer throws `e` on the second value |
| State-reaching prefix | `subscribe` and one next |
| Target event | second source `next` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; `m` not emitted |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error, not a minimum |
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
| Reset/fixture | one value, source still open |
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

Evidence: `src/internal/operators/min.ts` lines 52–54, `isFunction` at `src/internal/util/isFunction.ts` lines 5–7, and the no-seed `reduce` path in `scanInternals.ts` lines 41–47 and 54–58. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `min` only chooses a seedless reducer. Empty, single-value, tie, and error behavior are consequences of `reduce` plus the `< 0` / `<` tests.

Known limitations: a non-function comparer is silently ignored. Equality keeps the later value, which is easy to miss if a comparer uses the convention “return 0 for equal” and the caller expects stability. `NaN` comparisons follow JavaScript and are not a special case in the source. Reentrancy is excluded.

Contract vs version characterization: the JSDoc says the smallest item is emitted when the source completes. It does not say what an empty source does. Empty completion without `EmptyError` is source characterization of 7.8.2, not the historical `EmptyError` behavior.

Tests still required: S01–S07, plus a non-function comparer argument to show the `<` fallback, and a comparer returning `-1` versus `0`.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
