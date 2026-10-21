# `takeWhile`

`takeWhile` mirrors source values while `predicate(value, index)` is truthy, then completes. If `inclusive` is true it also emits the first failing value before that complete (`takeWhile.ts` lines 55-66). `inclusive` defaults to `false`. Source error and complete are forwarded. There is no `@deprecated` tag on this function.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `takeWhile` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/takeWhile.ts` lines 55-66 (default parameter line 55) |
| Helpers read | `OperatorSubscriber.ts` lines 67-74; `Subscriber.ts` lines 95-130; `lift.ts` lines 17-31 |
| Shape | Full operator via `operate` |
| Parameters | `predicate(value, index)`; `inclusive = false` |
| Output | A prefix of the source, plus the failing value only when `inclusive` |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None. A predicate throw is `outError` and is not a source error |
| Upstream | One source subscription, unsubscribed when the predicate fails (`subscriber.complete`) or on source terminal or cancel |
| Inners | None |
| Per-subscription state | `index`, starting at 0 (line 57) |
| Exclusions | No reentrant callback. In the inclusive failure path, `next` is ordered before `complete` (lines 61-62); a downstream `next` that reenters is excluded. Teardown throws out of scope. Downstream observer throws are not `outError`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_active(index), s_completed, s_errored, s_cancelled }
     index ∈ ℕ₀
Σ  = { subscribe, sourceNext(v, outcome), sourceError(e), sourceComplete, cancel }
     outcome ∈ { truthy, falsy, throw(err) }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
parameter inclusive ∈ {true, false}, fixed at construction
```

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_active(index)` | Source subscribed. Next predicate call uses `index` | No |
| `s_completed` | Completed because the predicate failed, or because the source completed | Yes |
| `s_errored` | Predicate throw or source error | Yes |
| `s_cancelled` | Cancelled without a terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 58-64 |
| Source next | Yes | Predicate, optional `next`, optional `complete` (lines 60-62) |
| Source error | Yes | Default forward |
| Source completion | Yes | Default forward if the predicate has not already completed |
| Cancellation cancel | Yes | Unsubscribes the source. Does not complete |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | `result = predicate(value, index++)`. Throw skips both `next` and `complete`. Truthy emits and stays. Falsy completes, and emits first only when `inclusive` |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v)
                | outNext(v) then outComplete
                | outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

## C. Transition obligations

`inclusive` is fixed. Truthiness matches `(result || inclusive)` and `!result` (lines 61-62), not a strict boolean compare. `index++` runs before the predicate body, as an argument.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Callable predicate | ε | `subSrc` | `s_active(0)` | None | — | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_active(i)` | `sourceNext(v, truthy)` | Predicate returns truthy | `outNext(v)` | ε | `s_active(i+1)` | `i` tests already passed | Source stays subscribed | E01 |
| T04 | `s_active(i)` | `sourceNext(v, falsy)` | Predicate returns falsy and `inclusive === false` | `outComplete` | `unsubSrc` | `s_completed` | Still active | `v` is not emitted | E02 |
| T05 | `s_active(i)` | `sourceNext(v, falsy)` | Predicate returns falsy and `inclusive === true` | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | Still active | `v` is emitted and is the last next | E03 |
| T06 | `s_active(i)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | Still active | No `outNext` and no `outComplete` | E04 |
| T07 | `s_active(i)` | `sourceError(e)` | None | `outError(e)` | `unsubSrc` | `s_errored` | Still active | Not a predicate failure | E05 |
| T08 | `s_active(i)` | `sourceComplete` | None | `outComplete` | `unsubSrc` | `s_completed` | Every value so far was truthy, or there were none | No synthetic failure | E06 |
| T09 | `s_active(i)` | `cancel` | None | ε | `unsubSrc` | `s_cancelled` | Still active | No `outComplete` | E07 |
| T10 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03-T06 partition `sourceNext` outcomes together with the fixed `inclusive` flag. T04 and T05 are mutually exclusive because `inclusive` is either true or false.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Passing values, and the failing value if inclusive, keep source order and identity. E01, E03 |
| At most one terminal | Yes | Failure complete, source complete, predicate throw, or source error |
| No downstream after terminal | Yes | T10. `subscriber.complete` stops the destination and unsubscribes the source |
| Cancellation does not synthesize completion | Yes | T09, E07 |
| Upstream / inner lifetime | Yes | One source. Unsubscribed on predicate failure as well as on ordinary terminals. No inner |
| Cleanup once | Yes | No `onFinalize` |
| Per-subscription state | Yes | `index` is an init local (line 57) |
| Empty source | Yes | T08 from `s_active(0)` is `outComplete` only |
| Source error | Yes | Forwarded without running the predicate. E05 |
| Silence | Yes | Only a non-terminating source whose predicate stays truthy |
| Pending value or buffer on terminal | No | The failing value is either emitted in the same transition or dropped. It is not stored |
| Callback throws / reenters / cancels | Throws yes (T06, E04). Reentry and cancel-from-callback excluded | Inclusive order is next then complete when both happen |
| Equal-time ordering and timer cancellation | No | No second producer and no timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T08 |
| Starting state | `s_idle` |
| Reset/fixture | `predicate = (v) => v < 10`, `inclusive` false, source `1, 2` then complete |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(1, truthy)`, `sourceNext(2, truthy)`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` only at source complete |
| Distinguishing suffix | No early complete, because the predicate never failed |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_active(0)` |
| Reset/fixture | `predicate = (v) => v > 0`, `inclusive = false` |
| State-reaching prefix | `subscribe`, `sourceNext(1, truthy)` |
| Target event | `sourceNext(0, falsy)` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `unsubSrc`. `0` is not an `outNext`. Prior `outNext(1)` already happened |
| Distinguishing suffix | A following source value is not delivered |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_active(0)` |
| Reset/fixture | `inclusive = true`, predicate falsy for `'stop'` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('stop', falsy)` |
| Expected notifications | `outNext('stop')`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` after both notifications |
| Distinguishing suffix | Contrast E02, where the same falsy outcome would omit `outNext('stop')` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_active(0)` |
| Reset/fixture | Predicate throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outComplete`. `inclusive` is irrelevant because line 61 is not reached |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T07 |
| Starting state | `s_active(1)` |
| Reset/fixture | One value already accepted |
| State-reaching prefix | `subscribe`, one truthy next |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | The accepted value is not repeated. No complete |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T08 |
| Starting state | `s_active(0)` |
| Reset/fixture | Empty source |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `EmptyError` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T09 |
| Starting state | `s_active(0)` |
| Reset/fixture | `inclusive` either value |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

## F. Coverage and evidence

| Row | Status | Execution |
| --- | --- | --- |
| T01 | specified | not executed |
| T02 | specified | not executed |
| T03 | specified | not executed |
| T04 | specified | not executed |
| T05 | specified | not executed |
| T06 | specified | not executed |
| T07 | specified | not executed |
| T08 | specified | not executed |
| T09 | specified | not executed |
| T10 | specified | not executed |

Denominator = 10. Specified 10/10. Executed 0/10.

Residual risk: falsy non-booleans are specified as T04/T05 and not separately scenario-listed. Reentry between inclusive `next` and `complete` is excluded. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: Lines 60-62 are a total split on throw, truthy, and falsy, with `inclusive` affecting only the falsy emission. Default `inclusive` is false.

Known implementation limitations: Completion on failure is `subscriber.complete()`, which unsubscribes the source. The index increments for every attempt, including the failing one. Truthiness, not `=== true`, keeps the subscription alive. There is no `thisArg`.

Differences between intended contract and version characterization: The JSDoc (`takeWhile.ts` lines 12-27 and 49-50) matches exclusive and inclusive behavior. It describes a boolean predicate; the code uses truthiness. No other fork showed up in this file.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
