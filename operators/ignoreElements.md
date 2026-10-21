# `ignoreElements`

`ignoreElements` is a full operator. It subscribes to the source and discards every `next` by installing `noop` as the only custom handler (`ignoreElements.ts` lines 41-45). Source `error` and `complete` are forwarded by the default `OperatorSubscriber` paths. It never emits a `next`. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `ignoreElements` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/ignoreElements.ts` lines 41-45 |
| Helpers read | `noop.ts` line 2; `OperatorSubscriber.ts` lines 67-74 and the default `_error` / `_complete` inherited from `Subscriber.ts` lines 112-130 |
| Shape | Full operator via `operate` |
| Parameters | None |
| Output | No values. Terminal notification of the source only |
| Model kind | Symbolic (source payloads are ignored; errors stay symbolic) |
| Scheduler | None |
| Introduced errors | None |
| Upstream | One source subscription |
| Inners | None |
| Per-subscription state | None beyond the subscriber |
| Exclusions | No reentrant callback. Teardown throws out of scope. `noop` does not throw. Downstream observer throws are not `outError`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_active, s_completed, s_errored, s_cancelled }
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_active` | Source subscribed. Nexts are discarded | No |
| `s_completed` | Source complete forwarded | Yes |
| `s_errored` | Source error forwarded | Yes |
| `s_cancelled` | Cancelled without a terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 43-44 |
| Source next | Yes | Handler is `noop` (line 43). Payload is ignored |
| Source error | Yes | No custom `onError`, so `Subscriber._error` forwards |
| Source completion | Yes | No custom `onComplete`, so `Subscriber._complete` forwards |
| Cancellation cancel | Yes | Unsubscribes the source. Does not complete |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | No | `noop` is not user code |

### Γ: output inventory

```text
notifications ::= ε | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

`outNext` is not in the output alphabet of this operator.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_active` | None | A following next still emits nothing | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_active` | `sourceNext(v)` | Any `v` | ε | ε | `s_active` | Subscribed | `v` is not replayed on complete | E01 |
| T04 | `s_active` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | Subscribed | Not converted to complete | E02 |
| T05 | `s_active` | `sourceComplete` | Any, including after nexts or with none | `outComplete` | `unsubSrc` | `s_completed` | Subscribed | No trailing value | E01 |
| T06 | `s_active` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | Subscribed | No `outComplete` | E03 |
| T07 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | The only possible notifications are the source terminal, unchanged. No payload from nexts. E01, E02 |
| At most one terminal | Yes | T04 versus T05 |
| No downstream after terminal | Yes | T07 |
| Cancellation does not synthesize completion | Yes | T06, E03 |
| Upstream / inner lifetime | Yes | One source until terminal or cancel. No inner |
| Cleanup once | Yes | No `onFinalize` |
| Per-subscription state | Yes | No data locals. Each subscribe creates its own subscriber |
| Empty source | Yes | `sourceComplete` from `s_active` is `outComplete` only |
| Source error | Yes | Forwarded even if nexts were ignored. E02 |
| Silence | Yes | A non-terminating source, with or without nexts, produces no output |
| Pending value or buffer on terminal | No | Nexts are dropped immediately, not buffered |
| Callback throws / reenters / cancels | No user callback | `noop` returns normally |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T05 |
| Starting state | `s_idle` |
| Reset/fixture | Source emits `'you'`, `'talking'` then completes |
| State-reaching prefix | `subscribe` → `s_active` |
| Target event | `sourceNext('you')`, `sourceNext('talking')`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `subSrc` then `unsubSrc`. Both payloads discarded |
| Distinguishing suffix | No `outNext` of either string, unlike the source without this operator |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_active` |
| Reset/fixture | One next already ignored |
| State-reaching prefix | `subscribe`, `sourceNext(1)` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | The ignored `1` does not appear, and the error is not swallowed |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T06 |
| Starting state | `s_active` |
| Reset/fixture | Subscribed |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T05 |
| Starting state | `s_active` |
| Reset/fixture | Empty source |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `unsubSrc`. No boolean or sentinel next |
| Distinguishing suffix | Contrast `isEmpty`, which would `outNext(true)` before complete |
| Expected final state | `s_completed` |
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

Denominator = 7. Specified 7/7. Executed 0/7.

Residual risk: low control risk. The interesting mistake is emitting a next or completing on cancel; both are specified as absent. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The implementation is `createOperatorSubscriber(subscriber, noop)` and nothing else. Terminals are the default subscriber methods.

Known implementation limitations: The source stays subscribed until it terminates or the consumer cancels, even though values are useless. There is no early complete.

Differences between intended contract and version characterization: JSDoc lines 7-16 and the return text at lines 37-39 match the code. The phrase "returns an empty Observable" (line 37) means no nexts; it still subscribes to the source rather than returning `EMPTY`.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
