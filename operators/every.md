# `every`

`every` emits `false` and completes as soon as the predicate returns a falsy result. If the source completes with every tested value truthy, including when it completes with no values, it emits `true` and completes (`every.ts` lines 44-66). A source error or a predicate throw emits no boolean. `thisArg` overloads are `@deprecated` (lines 7 and 12). The empty source is vacuously `true`.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `every` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/every.ts` lines 44-66 |
| Helpers read | `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | `predicate(value, index, source)`; optional `thisArg` (deprecated overloads) |
| Output | One boolean, then complete, on the success paths |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None. Predicate throw is `outError` |
| Upstream | One source subscription. Unsubscribed early on the first falsy result |
| Inners | None |
| Per-subscription state | `index`, starting at 0 (line 49) |
| Exclusions | No reentrant callback between `next(false)` and `complete` (lines 55-56) or between `next(true)` and `complete` (lines 60-61). Teardown throws out of scope. Downstream observer throws are not `outError`. Ordinary model assumes a callable predicate. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_pass(index), s_completed, s_errored, s_cancelled }
     index ∈ ℕ₀
Σ  = { subscribe, sourceNext(v, outcome), sourceError(e), sourceComplete, cancel }
     outcome ∈ { pass, fail, throw(err) }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

`s_pass(index)` means every source next so far was truthy, and the next call will use `index`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_pass(index)` | Subscribed. No falsy result yet. Next index is `index` | No |
| `s_completed` | `true` or `false` already followed by complete | Yes |
| `s_errored` | Predicate throw or source error. No boolean | Yes |
| `s_cancelled` | Cancelled. No boolean | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 50-65 |
| Source next | Yes | `if (!predicate.call(thisArg, value, index++, source))` then `next(false)` and `complete` (lines 54-57) |
| Source error | Yes | Default forward. The `true` handler does not run |
| Source completion | Yes | `next(true)` then `complete` (lines 59-62), including zero values |
| Cancellation cancel | Yes | No boolean |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Pass, fail, or throw. `this` is `thisArg`. Fail is falsy, not only `false` |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(false) then outComplete
                | outNext(true) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Callable predicate | ε | `subSrc` | `s_pass(0)` | `thisArg` fixed | — | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_pass(i)` | `sourceNext(v, pass)` | Predicate returns truthy | ε | ε | `s_pass(i+1)` | All previous passed | No boolean yet | E01 |
| T04 | `s_pass(i)` | `sourceNext(v, fail)` | Predicate returns falsy | `outNext(false)`, `outComplete` | `unsubSrc` | `s_completed` | All previous passed | Later source values are not tested. This does not wait for source complete | E02 |
| T05 | `s_pass(i)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | `index++` evaluated as an argument | No boolean | E03 |
| T06 | `s_pass(i)` | `sourceError(e)` | Any `i`, including after passes | `outError(e)` | `unsubSrc` | `s_errored` | No failure yet | No `outNext(true)` | E04 |
| T07 | `s_pass(i)` | `sourceComplete` | No failure, any `i` including 0 | `outNext(true)`, `outComplete` | `unsubSrc` | `s_completed` | Vacuous when `i = 0` | Not `false` | E01 |
| T08 | `s_pass(i)` | `cancel` | Any `i` | ε | `unsubSrc` | `s_cancelled` | No result yet | No boolean and no complete | E05 |
| T09 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03-T05 partition next outcomes. T07 is the only producer of `true`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Exactly one of `false` (early) or `true` (on complete) on success, then complete. E01, E02 |
| At most one terminal | Yes | The boolean and complete are one transition. Error is a different transition |
| No downstream after terminal | Yes | T09. T04 unsubscribes the source |
| Cancellation does not synthesize completion | Yes | T08, E05 |
| Upstream / inner lifetime | Yes | Early `unsubSrc` on failure. No inner |
| Cleanup once | Yes | No `onFinalize` |
| Per-subscription state | Yes | `index` is an init local (line 49) |
| Empty source | Yes | T07 from `s_pass(0)` is `outNext(true)`, `outComplete`. Vacuous truth. E01's empty variant is E06 |
| Source error | Yes | No boolean, even if every value so far passed. E04 |
| Silence | Yes | Non-terminating source of only passing values: no boolean |
| Pending value or buffer on terminal | No | Passing values are not stored. The result is a boolean, not a value |
| Callback throws / reenters / cancels | Throws yes (T05). Reentry excluded | Deprecated `thisArg` is still used via `call` |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T07 |
| Starting state | `s_idle` |
| Reset/fixture | `predicate = (v) => v < 5`, source `1, 2` then complete |
| State-reaching prefix | `subscribe` → `s_pass(0)` |
| Target event | `sourceNext(1, pass)`, `sourceNext(2, pass)`, `sourceComplete` |
| Expected notifications | `outNext(true)`, `outComplete` |
| Expected lifecycle observations | No output on the passing nexts. `unsubSrc` on complete |
| Distinguishing suffix | A later failing value was not present. If it had been, T04 would have emitted `false` without waiting |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_pass(0)` |
| Reset/fixture | `predicate = (v) => v < 5` |
| State-reaching prefix | `subscribe`, `sourceNext(1, pass)` → `s_pass(1)` |
| Target event | `sourceNext(6, fail)` |
| Expected notifications | `outNext(false)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` on `6`. Index passed to the predicate is 1 |
| Distinguishing suffix | Source complete is not required and must not add `outNext(true)` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_pass(0)` |
| Reset/fixture | Predicate throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(false)` and no `outNext(true)` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_pass(2)` |
| Reset/fixture | Two passes, then the source errors |
| State-reaching prefix | `subscribe`, two passing nexts |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outNext(true)`. Prior passes are not a result |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_pass(0)` |
| Reset/fixture | Subscribed |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No boolean. In particular not vacuous `true` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T07 |
| Starting state | `s_pass(0)` |
| Reset/fixture | Empty source |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(true)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc`. Predicate not called |
| Distinguishing suffix | Contrast `isEmpty`, which would emit `true` for a different reason, and contrast a failing predicate, which emits `false` |
| Expected final state | `s_completed` |
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
| T09 | specified | not executed |

Denominator = 9. Specified 9/9. Executed 0/9.

Residual risk: falsy non-booleans are failures by `!predicate`. Vacuous `true` is specified in E06 and was not executed. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: Failure is an early `false` plus complete. The complete handler is unconditional `true`, so the empty source is included.

Known implementation limitations: The source is unsubscribed on the first falsy result, so later failures are not observed. A throw or a source error suppresses the boolean. `thisArg` is deprecated and still applied. Index increments for passes, failures, and throws (the increment is an argument).

Differences between intended contract and version characterization: The informal JSDoc (lines 22-23) matches early `false` and complete-time `true`. It does not mention the empty source; the complete handler has no `index` check, so emptiness is `true`. That is the version characterization of lines 59-62.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
