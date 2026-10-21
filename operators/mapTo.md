# `mapTo`

`mapTo(value)` emits that same constant on every source `next` and otherwise behaves as `map`. It is a wrapper: `src/internal/operators/mapTo.ts` lines 46–48 return `map(() => value)` and contain no subscription logic of their own. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. The function is `@deprecated` and scheduled for removal in v9; the JSDoc replacement is `map(() => value)` (`mapTo.ts` lines 4–10 and 44). The inner arrow function does not throw, so this wrapper adds no callback-error alphabet of its own.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `mapTo(value)`. Overloads at lines 5 and 11; implementation at lines 46–48. `OperatorFunction<unknown, R>` (the explicit type-parameter overload is separately deprecated for removal in v8, lines 6–10). |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | Ignore the source payload. On each source `next`, emit `next(value)` with the identical reference captured when `mapTo` was called. Forward source `error` and source `complete`. |
| Model kind | Symbolic. The constant `value` is an uninterpreted payload. Control locations match `map`. |
| Parameter domain | `value` may be any reference, including `undefined`. It is read when `mapTo` is applied, not when the source emits. |
| Payload/error domain | Output payloads are that constant. Errors are the source error unchanged. |
| Subscription boundary | Delegated to `map`: one index cell per subscription, one source subscription, no inner observable. The constant is closed over by the operator function and shared by every subscriber of that operator result. |
| Scheduler and tie ordering | No scheduler. Source order only. |
| Callback assumptions | The generated project `() => value` is total and synchronous. It ignores `this`, the source value, and the index that `map` still passes. |
| Cleanup assumptions | Same as `map`: teardown follows the destination child-subscription chain. |
| Explicit exclusions | Ordinary model, no reentrancy. No user callback that can throw is introduced by `mapTo`. Downstream observer throws are excluded. Terminal late events are silent by convention, not legal traces. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

The transition relation is the `map` machine specialized to `project = () => value` (`map.ts` lines 47–61).

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | `mapTo(value)` has returned an operator function. | constant `value` | empty | `subscribe` installs `map`. |
| `active(n)` | Source subscribed; `n` constants have been emitted. | `map`’s `index = n` (not observable in the payload) | `subscribe` and `n` source nexts | Another source next emits `value` again, not a new object. |
| `completed` | Destination completed. | none | source `complete` | silence |
| `errored(e)` | Destination errored with the source error. | `e` | source `error(e)` | silence; `e` is not a projection failure |
| `cancelled` | Unsubscribed with no terminal notification. | none | `cancel` | no synthesized `complete` |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `map`’s `operate` subscribes. |
| Source next | yes | Causes `next(value)`. |
| Source error | yes | Forwarded by `map`’s default error path. |
| Source completion | yes | Forwarded by `map`’s default complete path. |
| Cancellation `cancel` | yes | Same child-unsubscribe chain as `map`. |
| Inner notifications | no | No inner subscribe. |
| Time | no | No clock. |
| User callback outcomes | no | `() => value` does not call user code and does not throw. A throwing project is inapplicable for this wrapper. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

One notification per input, so a single-notification record is enough. The constant’s identity (same reference on every `next`) is part of the payload, not a second event.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | operator already closed over `value` | none | `subscribe(source)` | `active(0)` | empty | a source next emits `value` | S01 |
| T02 | `active(n)` | source `next(v)` | project returns the closed-over `value`; `v` is ignored | `next(value)` (same reference) | stay subscribed; `map` index becomes `n+1` | `active(n+1)` | `subscribe` and `n` nexts | a second next emits the same reference | S01 |
| T03 | `active(n)` | project throw | inapplicable | none | none | unchanged | — | — | — |
| T04 | `active(n)` | source `error(e)` | any | `error(e)` | unsubscribe source | `errored(e)` | `subscribe` | silence | S02 |
| T05 | `active(n)` | source `complete` | any `n`, including 0 | `complete` | unsubscribe source | `completed` | `subscribe`, optional T02 | late next is silent | S03, S04 |
| T06 | `active(n)` | `cancel` | open subscription | none | unsubscribe source | `cancelled` | `subscribe` | no `complete` | S05 |
| T07 | terminal states | late source events or second cancel | stopped subscriber | none | no second teardown | same terminal | a prior terminal row | silence is not a legal trace | S02 |

T03 is listed so the callback-outcome obligation is explicit: the wrapper’s project cannot throw, unlike a user `map` project.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | T02. Every source next becomes `next(value)` regardless of the source payload (`mapTo.ts` line 47). |
| one terminal | yes | T04 or T05, then T07. |
| silence after terminal | yes | T07. |
| cancel does not complete | yes | T06. |
| upstream/inner lifetime | yes | Single upstream via `map`. No inners. |
| cleanup once | yes | Inherited from `map` / `Subscription`. |
| per-subscription state | yes | `map` allocates `index` per subscription. The constant itself is shared and immutable from the operator’s point of view. |
| empty/error/silence | yes | Empty source completes with no `next` (T05 from `active(0)`). Source error emits no constant (T04). A non-terminating source emits one constant per next and no terminal. |
| pending buffer on terminal | no | No buffer. |
| callback throw/reenter/cancel | no throw | T03 inapplicable. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Constant identity across nexts

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | `value` is a fresh object; source emits `1` then `2`. |
| State-reaching prefix | empty |
| Target event | `subscribe`, then both source nexts |
| Expected notifications | `next(value)`, `next(value)` with both payloads `=== value` |
| Expected lifecycle observations | one source subscription, still open |
| Distinguishing suffix | source `complete` → `complete` |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | reference equality of payloads; source values not emitted |
| Oracle source | `source characterization` |

### S02 Source error

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T04, T07 |
| Starting state | `active(0)` |
| Reset/fixture | source errors with `e` and no next |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` only |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | late `complete` is silent |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error payload identity |
| Oracle source | `contract` |

### S03 Values then complete

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T02, T05 |
| Starting state | `active(0)` |
| Reset/fixture | one source next then complete |
| State-reaching prefix | `subscribe` |
| Target event | source `next(_)` then source `complete` |
| Expected notifications | `next(value)`, `complete` |
| Expected lifecycle observations | unsubscribed on complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered trace |
| Oracle source | `contract` |

### S04 Empty complete

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active(0)` |
| Reset/fixture | source completes with no next |
| State-reaching prefix | `subscribe` |
| Target event | source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S05 Cancel

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `active(0)` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no later `next(value)` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references T01, T02, T04, T05, T06, T07. T03 is an explicit inapplicable row and is not a behavioral obligation. Specified coverage of applicable rows = 6/6. Execution: not executed.

Evidence: `src/internal/operators/mapTo.ts` lines 46–48 and the `map` implementation it returns. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `mapTo` is exactly `map` of a total constant function. The deprecation and the reference-sharing of `value` are visible in the wrapper.

Known limitations: the analysis does not re-prove `map`; it specializes it. The generated project ignores index and `this`. Two different `mapTo(value)` calls close over the same reference if the caller passed one object twice.

Contract vs version characterization: JSDoc matches the wrapper. “Does not throw” is a characterization of `() => value`, not a separate runtime check.

Tests still required: S01–S05, plus a check that `undefined` as `value` is still emitted as `next(undefined)` rather than treated as a missing argument.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
