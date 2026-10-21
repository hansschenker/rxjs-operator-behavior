# `pairwise`

`pairwise` emits nothing for the first source value. From the second value onward it emits `next([previous, current])` as a new two-element array, then stores `current` as the previous value. An empty source, or a source that emits one value and then completes, completes with no pair. The stored predecessor is dropped on complete, on source error, and on cancel; it is not emitted as a partial pair. Source errors and source completion are forwarded. There is no user callback. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/pairwise.ts` lines 48–61. Not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `pairwise()`. `OperatorFunction<T, [T, T]>`. Lines 48–61. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | `hasPrev` starts false and `prev` is unset. On `next(value)`: snapshot `prev`, assign `prev = value`, emit `[snapshot, value]` only if `hasPrev` was already true, then set `hasPrev = true` (lines 54–57). |
| Model kind | Symbolic. The stored value is an uninterpreted payload. Control flag `hasPrev` is finite. |
| Parameter domain | No parameters. |
| Payload/error domain | Output payload is a fresh array of two source references. Errors are source errors only. |
| Subscription boundary | `prev` and `hasPrev` are allocated inside `operate`, per subscription. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. Pairs follow source order. |
| Callback assumptions | No user callback. |
| Cleanup assumptions | Default `OperatorSubscriber` error and complete paths. The locals are discarded with the closure when the subscription ends. |
| Explicit exclusions | Ordinary model, no reentrancy. In particular, a downstream handler that unsubscribes inside `next` is excluded; the source sets `hasPrev = true` after `subscriber.next` (line 57), which is unobservable once the destination is stopped. Terminal late events are silent by convention. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Not subscribed. | none | empty | `subscribe` emits nothing |
| `wait` | Subscribed, no value yet. | `hasPrev = false` | T01 | the next value does not emit |
| `hold(p)` | One predecessor is stored. | `prev = p`, `hasPrev = true` | one or more values | the next value emits `[p, value]` |
| `completed` | Completed. | none | source `complete` from `wait` or `hold` | no extra pair; silence |
| `errored(e)` | Source errored. | `e` | source `error` | the held value is not emitted |
| `cancelled` | Unsubscribed. | none | `cancel` | the held value is not emitted |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 49–59. |
| Source next | yes | Lines 53–57. |
| Source error | yes | Default forward. |
| Source completion | yes | Default forward. No synthetic pair. |
| Cancellation `cancel` | yes | Drops `prev`. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | no | No user function. |

### Γ

```text
record {
  trace: ordered list of next([T, T]) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Every input emits at most one notification, so a one-notification record is enough. The pair array is a single `next` payload.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)`; `hasPrev = false` | `wait` | empty | the first next is silent | S01 |
| T02 | `wait` | source `next(v)` | `hasPrev` false | none | `prev = v`; then `hasPrev = true` | `hold(v)` | T01 | the next value emits a pair whose first element is `v` | S02 |
| T03 | `hold(p)` | source `next(v)` | `hasPrev` true | `next([p, v])` (new array) | `prev = v`; `hasPrev` stays true | `hold(v)` | T02 or a previous T03 | another next pairs with `v`, not with `p` | S02 |
| T04 | `wait` or `hold(p)` | source `complete` | any | `complete`; no pair | unsubscribe; `p` dropped if held | `completed` | T01, or T01 and T02 | silence | S01, S03 |
| T05 | `wait` or `hold(p)` | source `error(e)` | any | `error(e)`; no pair | unsubscribe; `p` dropped | `errored(e)` | T01 or T02 | silence | S04 |
| T06 | `wait` or `hold(p)` | `cancel` | open | none | unsubscribe; `p` dropped | `cancelled` | T01 or T02 | no `complete` and no pair | S05 |
| T07 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S04 |

The emission guard reads `hasPrev` before the assignment `hasPrev = true` (`pairwise.ts` lines 56–57), so T02 cannot emit.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | The Nth source value (`N ≥ 2`) produces `[value N-1, value N]` (JSDoc lines 14–18; code lines 54–56). |
| one terminal | yes | T04 or T05. |
| silence after terminal | yes | T07. |
| cancel does not complete | yes | T06. |
| upstream/inner lifetime | yes | One source subscription from T01 until T04, T05, or T06. No inners. |
| cleanup once | yes | Default unsubscribe is idempotent. |
| per-subscription state | yes | `prev` and `hasPrev` are inside `operate` (lines 49–51). |
| empty/error/silence | yes | Empty: T01 then T04, no pair (S01). Single value then complete: T02 then T04, no pair (S03). Source error: T05, no pair. Open source after one value: silence in `hold`. |
| pending buffer on terminal | yes | `hold(p)` is a one-value buffer. T04, T05, and T06 drop it. They do not emit a one-element result. |
| callback throw/reenter/cancel | no user callback | Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty source

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T04 |
| Starting state | `idle` |
| Reset/fixture | `pairwise()`, source completes immediately |
| State-reaching prefix | empty |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | source subscribed then unsubscribed |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S02 Pairs from the second value

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T03 |
| Starting state | `wait` |
| Reset/fixture | source values `a`, `b`, `c` |
| State-reaching prefix | `subscribe` |
| Target event | the three nexts |
| Expected notifications | no `next` for `a`; then `next([a, b])`, `next([b, c])` |
| Expected lifecycle observations | still subscribed; each pair is a new array |
| Distinguishing suffix | source `complete` adds only `complete` and not another pair |
| Expected final state | `hold(c)` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered pairs and silence on the first value |
| Oracle source | `contract` |

### S03 Single value then complete

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T02, T04 |
| Starting state | `wait` |
| Reset/fixture | one value `a`, then complete |
| State-reaching prefix | `subscribe` |
| Target event | `next(a)` and source `complete` |
| Expected notifications | `complete` only |
| Expected lifecycle observations | unsubscribed; `a` is not emitted |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of a pair |
| Oracle source | `contract` |

### S04 Error drops the held value

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05, T07 |
| Starting state | `hold(a)` |
| Reset/fixture | one value, then source `error(e)` |
| State-reaching prefix | `subscribe` and one next |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | no pair |
| Oracle source | `source characterization` |

### S05 Cancel drops the held value

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `hold(a)` |
| Reset/fixture | one value, source open |
| State-reaching prefix | `subscribe` and one next |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no pair and no `complete` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references every row. Specified coverage = 7/7.

Execution: not executed.

Evidence: `src/internal/operators/pairwise.ts` lines 48–61. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the operator is one boolean and one stored value, updated in a fixed order around a single `next`.

Known limitations: consecutive equal values still produce a pair; there is no distinctness check. The snapshot `p` is the previous reference, not a copy. Reentrancy across `subscriber.next` is excluded. `prev` is unset in `wait` and is not read while `hasPrev` is false.

Contract vs version characterization: the JSDoc (lines 14–18) matches “no emission on the first value”. Dropping a single held value on error and on cancel is source characterization of the default error path plus the absence of a flush.

Tests still required: S01–S05, plus three values to show the window slides by one.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
