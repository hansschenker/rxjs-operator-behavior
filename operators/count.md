# `count`

`count` emits one number when the source completes: how many source values were seen, or how many satisfied `predicate`, starting from `0`. An empty source emits `0` and completes. A source error is forwarded and no number is emitted. A throw from `predicate` is an accumulator error of the underlying `reduce`: destination `error`, no count. The operator does not emit intermediate counts and does not complete if the source never completes. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. It is a wrapper: `src/internal/operators/count.ts` lines 59–61 return `reduce((total, value, i) => (!predicate || predicate(value, i) ? total + 1 : total), 0)`. The seed `0` is always passed, so `reduce`’s `hasSeed` is true. Not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `count()` and `count(predicate)`. Implementation lines 59–61. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. `predicate` omitted means every value counts, and `predicate` is not called (`!predicate` short-circuits). A provided `predicate` is called as `predicate(value, i)` with the zero-based source index from `scanInternals` (seed present, so the first value has index 0). |
| Model kind | Symbolic in the source values; the stored total is a natural number. Control locations are finite aside from that counter, so the model is symbolic rather than a finite automaton. |
| Parameter domain | `predicate` is either omitted/`undefined` or a synchronous function. `count` does not use `isFunction`. A truthy non-function `predicate` throws when the first value is applied (`predicate(value, i)`), which is a callback error. Falsy non-function values are treated as “no predicate” because of `!predicate`. |
| Payload/error domain | The only successful payload is a number. Errors are source errors or exceptions thrown by `predicate`. |
| Subscription boundary | Delegated to `reduce` / `scanInternals`: one total per subscription, one source subscription, no inners. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | `predicate` is synchronous. The increment uses JavaScript truthiness of the return value, not `=== true` (line 60). |
| Cleanup assumptions | Same as `reduce`’s flush-on-complete path. |
| Explicit exclusions | Ordinary model, no reentrancy. Terminal late events are silent by convention. Non-function predicates other than `undefined` are outside the documented parameter domain; the throw path is still the `reduce` accumulator throw if one is passed. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | `count(...)` returned. | `predicate` or its absence | the call | `subscribe` emits nothing |
| `active(n)` | Count so far is `n`, not yet emitted. | integer `n ≥ 0` | `subscribe` and the counted prefix | complete emits `n`; a further matching value would emit `n+1` instead |
| `completed` | The count was emitted, or the machine completed after it. | none | source `complete` | silence |
| `errored(e)` | Source error or predicate throw. | `e` | T04 or T05 | the count was not emitted |
| `cancelled` | Unsubscribed. | none | `cancel` | the count is dropped |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `reduce` subscribes with seed `0`. |
| Source next | yes | May increment `n`. No emission. |
| Source error | yes | `reduce` forwards it. No count. |
| Source completion | yes | Flushes `n`, then completes. |
| Cancellation `cancel` | yes | Drops `n`. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | yes | If a `predicate` function is present it may return truthy, return falsy, or throw. If it is absent, there is no callback. |

### Γ

```text
record {
  trace: ordered list of next(number) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Only source `complete` emits two ordered notifications (`next(n)` then `complete`). Other inputs emit at most one. An ordered trace is required for T06.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)`; total `0`; `hasSeed` true | `active(0)` | `count(...)` | empty complete emits `0` | S01 |
| T02 | `active(n)` | source `next(v)` | `predicate` absent, or `predicate(v, i)` is truthy | none | stay subscribed; total `n+1`; index `i` was `n`’s source index | `active(n+1)` | T01 and a prefix whose counted size is `n` | complete emits `n+1` | S02 |
| T03 | `active(n)` | source `next(v)` | `predicate(v, i)` is falsy | none | stay subscribed; total unchanged | `active(n)` | T01 | complete still emits `n` | S03 |
| T04 | `active(n)` | source `next(v)` | `predicate` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | T01 | silence | S04 |
| T05 | `active(n)` | source `error(e)` | any | `error(e)`; no count | unsubscribe | `errored(e)` | T01 | silence | S05 |
| T06 | `active(n)` | source `complete` | any `n`, including 0 | ordered `next(n)`, `complete` | unsubscribe | `completed` | T01 plus T02/T03 | silence | S01, S02, S03 |
| T07 | `active(n)` | `cancel` | open | none | unsubscribe | `cancelled` | T01 | no count | S06 |
| T08 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S04 |

T03 and T04 are unreachable when `predicate` is omitted, because the reducer does not call it (`count.ts` line 60).

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Count follows source order. Index passed to `predicate` is 0, 1, 2, … because the `reduce` seed forces every value through the accumulator (`scanInternals.ts` lines 38–43). |
| one terminal | yes | T04, T05, or T06. |
| silence after terminal | yes | T08. |
| cancel does not complete | yes | T07. |
| upstream/inner lifetime | yes | One source subscription. No inners. |
| cleanup once | yes | Inherited from `reduce`. |
| per-subscription state | yes | The seed `0` is passed at each subscription of the operator returned by `reduce`; `scanInternals` stores the total per subscription. |
| empty/error/silence | yes | Empty: T06 from `active(0)` emits `0` (S01). Source error: T05, no number. Never completes: stays `active`, no emission. All-falsy predicate: still emits `0` on complete (S03). |
| pending buffer on terminal | yes | The integer is pending until T06. T05 and T07 drop it. |
| callback throw/reenter/cancel | yes | T04. Omitted predicate cannot throw. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty source emits 0

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T06 |
| Starting state | `idle` |
| Reset/fixture | `count()` or `count(() => true)`, empty source |
| State-reaching prefix | call `count` |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `next(0)`, `complete` |
| Expected lifecycle observations | predicate not called when omitted; unsubscribed after complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | numeric payload 0 |
| Oracle source | `contract` |

### S02 Every value, or matching values

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T06 |
| Starting state | `active(0)` |
| Reset/fixture | source `a, b, c` then complete; once with no predicate, once with `(_, i) => i !== 1` |
| State-reaching prefix | `subscribe` |
| Target event | three nexts and complete |
| Expected notifications | no predicate: `next(3)`, `complete`. With that predicate: `next(2)`, `complete`. No intermediate nexts. |
| Expected lifecycle observations | predicate indexes 0, 1, 2 when it is provided |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | final number and index sequence |
| Oracle source | `source characterization` |

### S03 All rejected

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T06 |
| Starting state | `active(0)` |
| Reset/fixture | `count(() => false)`, two values, then complete |
| State-reaching prefix | `subscribe` |
| Target event | both nexts and complete |
| Expected notifications | `next(0)`, `complete` |
| Expected lifecycle observations | predicate called twice |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload stays 0 |
| Oracle source | `source characterization` |

### S04 Predicate throw

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04, T08 |
| Starting state | `active(0)` |
| Reset/fixture | `predicate` throws `e` on the first value |
| State-reaching prefix | `subscribe` |
| Target event | source `next(v)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; no `next(0)` and no `next(1)` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error, not a count |
| Oracle source | `source characterization` |

### S05 Source error

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T05 |
| Starting state | `active(1)` |
| Reset/fixture | one value already counted, then source `error(e)` |
| State-reaching prefix | `subscribe` and one matching next |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S06 Cancel

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T07 |
| Starting state | `active(2)` |
| Reset/fixture | two values seen, source still open |
| State-reaching prefix | `subscribe` and two matching nexts |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no `next(2)` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 8 section C rows (T01–T08).

Section E references every row. Specified coverage = 8/8.

Execution: not executed.

Evidence: `src/internal/operators/count.ts` lines 59–61 together with `reduce.ts` line 60 and `scanInternals.ts` lines 37–58. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `count` is a seeded `reduce` whose reducer is a total increment except when a user predicate throws or returns falsy.

Known limitations: truthiness, not a boolean test, decides the increment. A falsy predicate argument is ignored rather than called. Reentrancy is excluded. The total is a JavaScript number; overflow is outside the model.

Contract vs version characterization: the JSDoc (lines 5–20 and 52–55) matches empty→`0`, error forwarding, and the optional predicate. Truthiness and the index origin are source characterization of the reducer expression.

Tests still required: S01–S06, plus a truthy non-boolean predicate return such as `1`.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
