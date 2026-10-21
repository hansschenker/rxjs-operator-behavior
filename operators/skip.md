# `skip`

`skip` is a thin wrapper, not its own subscription loop. In RxJS 7.8.2 it returns `filter((_, index) => count <= index)` (`skip.ts` lines 37-39). The result subscribes to the source even when `count <= 0` and then forwards the source value at 0-based index `i` if and only if `count <= i`. It does not complete early and it does not allocate a skip buffer. There is no `@deprecated` tag on `skip`.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `skip` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/skip.ts` lines 37-39, behavior induced through `src/internal/operators/filter.ts` lines 61-75 |
| Helpers read | `OperatorSubscriber.ts` lines 67-74; `lift.ts` lines 17-31; `Subscriber.ts` lines 67-130 |
| Shape | Thin wrapper around `filter` |
| Parameters | `count` (JS number in the ordinary domain) |
| Output | Unmodified source values that survive the index test |
| Model kind | Symbolic (payloads plus an integer index; `count` is a fixed JS number) |
| Scheduler | None |
| Introduced errors | None. The library predicate `count <= index` does not throw for a numeric `count` |
| Upstream | One source subscription on every subscribe, including `count <= 0` and `NaN` |
| Inners | None |
| Per-subscription state | Filter `index`, starting at 0 |
| Exclusions | Quiescence: no reentrant callback into this operator. Teardown throws out of scope. Downstream observer throws are not `outError`. Non-numeric `count` is excluded (`<=` could invoke `ToPrimitive` and throw inside the filter callback). Not the same control flow as `skipLast`. The model does not claim RxJS rejects excluded inputs. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_active(index) | index ∈ ℕ₀, s_completed, s_errored, s_cancelled }
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = (notifications, lifecycle) as below
δ, λ tabulated in section C
kind = symbolic
parameter count ∈ IEEE numbers, fixed for the machine
```

`sourceError` is only an upstream notification. There is no user callback in `skip` itself.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Wrapper not subscribed. `s₀` | No |
| `s_active(index)` | Source subscribed; next source value will be index `index` | No |
| `s_completed` | Complete delivered | Yes |
| `s_errored` | Error delivered | Yes |
| `s_cancelled` | Cancelled without a terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `filter` always calls `source.subscribe` (`filter.ts` lines 68-73). `count <= 0` does not skip subscribe |
| Source next | Yes | Emitted iff `count <= index` (`skip.ts` line 38) |
| Source error | Yes | Default `filter` forward, including when every value was skipped |
| Source completion | Yes | Default forward. Does not flush a buffer and does not error because the count was not reached |
| Cancellation cancel | Yes | Unsubscribes the source. Does not complete |
| Inner notifications | No | No notifier |
| Time | No | No timer |
| User callback outcomes | No | The predicate is the total library test `count <= index` for numeric `count`. It is not user code |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

## C. Transition obligations

Let `i` be the current index. For any JS number `count` and `i ∈ ℕ₀`, exactly one of `count <= i` and `!(count <= i)` holds. Notable cases, all instances of T03 or T04: `count <= 0` makes T03 hold for every `i` (mirror); `NaN` and `+Infinity` make T04 hold for every finite `i` (drop all nexts, still forward error and complete); a positive finite `count` first emits at `i = ceil(count)`.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Numeric `count` | ε | `subSrc` | `s_active(0)` | None | First next is governed by `count <= 0` | E01, E02 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_active(i)` | `sourceNext(v)` / source | `count <= i` | `outNext(v)` | ε | `s_active(i+1)` | `i` source nexts already seen | Later values with a greater index also pass if this one passed for a fixed `count` | E01, E03 |
| T04 | `s_active(i)` | `sourceNext(v)` / source | `!(count <= i)` | ε | ε | `s_active(i+1)` | Same | The skipped `v` is not emitted on complete | E02, E03 |
| T05 | `s_active(i)` | `sourceError(e)` / source | Any `i`, any `count` | `outError(e)` | `unsubSrc` | `s_errored` | Subscribed | No conversion into a count error | E04 |
| T06 | `s_active(i)` | `sourceComplete` / source | Any `i` | `outComplete` | `unsubSrc` | `s_completed` | Subscribed | No error if fewer than `count` values arrived | E02 |
| T07 | `s_active(i)` | `cancel` / consumer | Any `i` | ε | `unsubSrc` | `s_cancelled` | Subscribed | No `outComplete` | E05 |
| T08 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Surviving values keep order and identity. E01, E03 |
| At most one terminal | Yes | Inherited `Subscriber` stop flag. T05, T06 |
| No downstream after terminal | Yes | T08 |
| Cancellation does not synthesize completion | Yes | T07, E05 |
| Upstream / inner lifetime | Yes | Always `subSrc` once. No inner. Unlike `take`, non-positive `count` still subscribes |
| Cleanup once | Yes | Filter has no extra finalizer |
| Per-subscription state | Yes | Fresh `index` per `filter` subscription |
| Empty source | Yes | `outComplete` only. E02 when combined with a short source |
| Source error | Yes | Forwarded whether or not the skip window has ended. The JSDoc sentence about raising an error when the count exceeds the length is this forward, not a new error type (`skip.ts` lines 9-10). E04 |
| Silence | Yes | `count` of `NaN` or `+Infinity`, or a live source still inside the window, produces no nexts until a later pass or a terminal |
| Pending value or buffer on terminal | No | No buffer. Complete does not emit skipped values |
| Callback throws / reenters / cancels | No user callback | Reentry excluded |
| Equal-time ordering and timer cancellation | No | No clock and no second producer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 0` (also represents every `count <= 0`) |
| State-reaching prefix | `subscribe` → `s_active(0)` with `subSrc` |
| Target event | `sourceNext('a')`, `sourceNext('b')` |
| Expected notifications | `outNext('a')`, `outNext('b')` |
| Expected lifecycle observations | Source was subscribed. This is not the `take`/`EMPTY` shortcut |
| Distinguishing suffix | `sourceComplete` → `outComplete` |
| Expected final state | `s_active(2)` before suffix |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T04, T06 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 2` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `subSrc` then `unsubSrc`. Both values skipped because indexes 0 and 1 fail `2 <= i` |
| Distinguishing suffix | No `outError` and no replay of 1 or 2 |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03, T04 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 2.5` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a')`, `sourceNext('b')`, `sourceNext('c')`, `sourceNext('d')` |
| Expected notifications | `outNext('d')` only (`2.5 <= i` first holds at `i = 3`) |
| Expected lifecycle observations | Source remains subscribed |
| Distinguishing suffix | A fifth value also emits. Complete does not emit `a`/`b`/`c` |
| Expected final state | `s_active(4)` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T04, T05 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 10`, one value already skipped |
| State-reaching prefix | `subscribe`, `sourceNext(1)` → `s_active(1)` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outComplete`, and `e` is the source error unchanged |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T07 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 1` |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

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

Denominator = 8. Specified 8/8. Executed 0/8.

Residual risk: `NaN` / `Infinity` are specified as comparison consequences but easy to miss in integer-only tests. Non-numeric `count` is excluded. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: `skip.ts` is only the `filter` projection `count <= index`. The machine is that projection plus filter's default terminal forwarding, including the fact that `count <= 0` still subscribes.

Known implementation limitations: Non-positive counts are not an `identity` short circuit and not `EMPTY`. `NaN` and `+Infinity` skip every next and still mirror error and complete. Fractional `count` skips `ceil(count)` leading values. There is no early complete after the window.

Differences between intended contract and version characterization: The informal JSDoc line about raising an error when the skip count exceeds the source length (`skip.ts` lines 9-10) does not construct a new error; a source error is forwarded and a short successful source just completes. Guide text that treats `skip(0)` as a special empty or identity operator is finer than this file: it is `filter` with a predicate that is always true for indexes `>= 0`.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
