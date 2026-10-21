# `takeUntil`

`takeUntil` mirrors the source until the notifier emits a `next`, and that `next` completes the output (`takeUntil.ts` lines 45-50). Notifier `complete` is `noop` and does not complete the output. Notifier `error` is forwarded. The source is subscribed only when the destination is still open after the notifier subscription (`!subscriber.closed`). There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `takeUntil` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/takeUntil.ts` lines 45-50 |
| Helpers read | `innerFrom.ts` lines 16-41; `throwUnobservableError.ts` lines 5-11; `noop.ts` line 2; `OperatorSubscriber.ts` lines 67-100; `lift.ts` lines 22-27; `Subscriber.ts` lines 67-130 |
| Shape | Full operator via `operate` |
| Parameters | `notifier: ObservableInput<any>` |
| Output | Source values until the first notifier `next`, then `outComplete` |
| Model kind | Symbolic, extended with the synchronous notifier prefix during `subscribe` |
| Scheduler | None |
| Introduced errors | Invalid notifier → `TypeError` from `innerFrom`, delivered by `operate`. Notifier errors are forwarded as-is |
| Upstream | Subscribed only if `!subscriber.closed` after the notifier subscribe (line 48). The source is subscribed with the downstream subscriber itself, not a wrapping `createOperatorSubscriber` |
| Inners | One notifier subscription until it nexts, errors, completes, or the outer subscriber unsubscribes |
| Per-subscription state | No closed-over flag. Liveness is the destination subscriber plus whether the source child exists |
| Exclusions | No reentrant downstream callback. Synchronous notifier behavior during its subscribe is part of `subscribe`, because line 48 observes `subscriber.closed`. Teardown throws out of scope. Late signals after terminal are protocol-illegal and silent in this model. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_both, s_src, s_completed, s_errored, s_cancelled }
Σ  = { subscribe(sync),
       sourceNext(v), sourceError(e), sourceComplete, cancel,
       notifierNext, notifierError(e), notifierComplete }
     sync ∈ { quiet, innerNext, innerComplete, innerError(e), invalid }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic, extended by the synchronous notifier prefix
```

`s_both`: notifier and source both subscribed. `s_src`: notifier already completed without a next; only the source remains. Source notifications in `s_both` and `s_src` go straight to the destination (`source.subscribe(subscriber)`, line 48).

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_both` | Notifier and source live | No |
| `s_src` | Notifier finished by `complete` without nexting. Source live | No |
| `s_completed` | `outComplete` from notifier `next` or from source `complete` | Yes |
| `s_errored` | `outError` from notifier or source | Yes |
| `s_cancelled` | Cancelled with no terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `innerFrom(notifier).subscribe` then conditional `source.subscribe` (lines 47-48) |
| Source next | Yes | Direct `destination.next` when the source was subscribed |
| Source error | Yes | Direct `destination.error`, which also unsubscribes the notifier child |
| Source completion | Yes | Direct `destination.complete`. Not synthesized by notifier complete |
| Cancellation cancel | Yes | Unsubscribes destination children. Does not complete |
| Inner notifications | Yes | Notifier `next` completes the output. Notifier `complete` is `noop` (line 47). Notifier `error` uses the default error forward |
| Time | No | No clock |
| User callback outcomes | No | Handlers are `() => subscriber.complete()` and `noop` |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subNotifier | unsubNotifier | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

Notifier `next` produces `outComplete` and both unsubscribes, because `subscriber.complete()` unsubscribes the destination and therefore both children. Notifier `complete` unsubscribes only the notifier subscriber (`OperatorSubscriber` complete `finally`, lines 89-100) and does not unsubscribe the parent.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe(quiet)` | Notifier does not synchronously next, error, or complete | ε | `subNotifier`, `subSrc` | `s_both` | None | Source values pass until a notifier next | E01 |
| T02 | `s_idle` | `subscribe(innerNext)` | Notifier synchronously nexts | `outComplete` | `subNotifier`, `unsubNotifier`. No `subSrc` (`subscriber.closed`) | `s_completed` | None | Source factory does not run | E02 |
| T03 | `s_idle` | `subscribe(innerComplete)` | Notifier synchronously completes without a next | ε | `subNotifier`, `unsubNotifier`, `subSrc` | `s_src` | None | Later source values are mirrored. Output did not complete | E03 |
| T04 | `s_idle` | `subscribe(innerError(e))` | Notifier synchronously errors | `outError(e)` | `subNotifier`, `unsubNotifier`. No `subSrc` | `s_errored` | None | Contrast `skipUntil`, which still enters `source.subscribe` | E04 |
| T05 | `s_idle` | `subscribe(invalid)` | `innerFrom` throws `TypeError` | `outError(TypeError)` | ε | `s_errored` | None | No `subSrc` | E05 |
| T06 | `s_idle` | later signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T07 | `s_both` | `sourceNext(v)` | Source live | `outNext(v)` | ε | `s_both` | Notifier has not nexted | Payload unchanged | E01 |
| T08 | `s_both` | `notifierNext` | Any payload, ignored | `outComplete` | `unsubNotifier`, `unsubSrc` | `s_completed` | Both live | Not an error. Further source nexts are not subscribed | E01 |
| T09 | `s_both` | `notifierComplete` | No notifier next yet | ε | `unsubNotifier` | `s_src` | Both live | Source stays. No `outComplete` | E06 |
| T10 | `s_both` | `notifierError(e)` | None | `outError(e)` | `unsubNotifier`, `unsubSrc` | `s_errored` | Both live | No complete | — |
| T11 | `s_both` | `sourceError(e)` | None | `outError(e)` | `unsubSrc`, `unsubNotifier` | `s_errored` | Both live | Notifier next must not also complete | — |
| T12 | `s_both` | `sourceComplete` | None | `outComplete` | `unsubSrc`, `unsubNotifier` | `s_completed` | Both live | This complete came from the source, not the notifier | E07 |
| T13 | `s_both` | `cancel` | None | ε | `unsubSrc`, `unsubNotifier` | `s_cancelled` | Both live | No `outComplete` | E08 |
| T14 | `s_src` | `sourceNext(v)` | Notifier already gone | `outNext(v)` | ε | `s_src` | T09 or T03 | Values still pass. JSDoc lines 19-20 | E03 |
| T15 | `s_src` | `notifierNext` / `notifierComplete` / `notifierError` | Notifier already unsubscribed | ε | ε | `s_src` | Inapplicable if the inner honored unsubscribe | Protocol-illegal if forced | — |
| T16 | `s_src` | `sourceError(e)` | None | `outError(e)` | `unsubSrc` | `s_errored` | Source only | — | — |
| T17 | `s_src` | `sourceComplete` | None | `outComplete` | `unsubSrc` | `s_completed` | Source only | — | E03 |
| T18 | `s_src` | `cancel` | None | ε | `unsubSrc` | `s_cancelled` | Source only | No complete | — |
| T19 | terminal states | any further signal or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Source nexts are mirrored until the first notifier next. Notifier payloads are not values. E01 |
| At most one terminal | Yes | Notifier next and source complete both complete; notifier error and source error both error. They are different inputs and cannot both be delivered under quiescence |
| No downstream after terminal | Yes | T19. T02 never subscribes the source, so it cannot emit a later source next |
| Cancellation does not synthesize completion | Yes | T13, T18, E08 |
| Upstream / inner lifetime | Yes | Notifier is subscribed first. Source is skipped when the destination is already closed (line 48). Notifier complete drops only the notifier |
| Cleanup once | Yes | Destination unsubscribe collects both children when it is the parent. Notifier complete finalizes only itself |
| Per-subscription state | Yes | No shared mutable flag. Each subscribe closes over its own subscriber |
| Empty source | Yes | Source `complete` with no next is `outComplete`, including when the notifier is still live (T12) or already completed (T17) |
| Source error | Yes | Forwarded. Distinct from notifier error, which also forwards but may happen before `subSrc` |
| Silence | Yes | Quiet notifier and a live non-terminating source: mirror forever. Notifier that only completes: still mirror the source |
| Pending value or buffer on terminal | No | Nothing is buffered. A notifier next does not emit a final source value |
| Callback throws / reenters / cancels | No user callback | Reentry excluded |
| Equal-time ordering and timer cancellation | Ordering yes, timers no | Notifier subscribe is entirely before the `subscriber.closed` check (lines 47-48). No timer to cancel. E02 |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T07, T08 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier quiet during subscribe |
| State-reaching prefix | `subscribe(quiet)` → `s_both` |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `notifierNext` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `subNotifier`, `subSrc`, then both unsubscribed. Notifier payload is ignored |
| Distinguishing suffix | A source next after `notifierNext` is not subscribed |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T02 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier synchronously nexts inside subscribe |
| State-reaching prefix | None |
| Target event | `subscribe(innerNext)` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `subNotifier`, `unsubNotifier`, no `subSrc` |
| Distinguishing suffix | Contrast `skipUntil`, which would set a gate and still subscribe the source |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03, T14, T17 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier completes synchronously with no next |
| State-reaching prefix | `subscribe(innerComplete)` → `s_src` |
| Target event | `sourceNext('a')`, `sourceComplete` |
| Expected notifications | `outNext('a')`, `outComplete` |
| Expected lifecycle observations | Notifier already unsubscribed before `subSrc`. Source complete is the output complete |
| Distinguishing suffix | This would be a skip-forever outcome under `skipUntil`, not a mirror |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T04 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier synchronously errors with `e` |
| State-reaching prefix | None |
| Target event | `subscribe(innerError(e))` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | No `subSrc` because `subscriber.closed` is true at line 48 |
| Distinguishing suffix | No second notification from the source |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T05 |
| Starting state | `s_idle` |
| Reset/fixture | `notifier` is not an `ObservableInput` |
| State-reaching prefix | None |
| Target event | `subscribe(invalid)` |
| Expected notifications | `outError(TypeError)` |
| Expected lifecycle observations | Neither subscription is attempted (`innerFrom` throws before `.subscribe`) |
| Distinguishing suffix | Different from T04, which does `subNotifier` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T09, T14 |
| Starting state | `s_both` |
| Reset/fixture | Quiet subscribe already done |
| State-reaching prefix | `subscribe(quiet)` |
| Target event | `notifierComplete`, then `sourceNext(1)` |
| Expected notifications | `outNext(1)` |
| Expected lifecycle observations | `unsubNotifier` only |
| Distinguishing suffix | No `outComplete` on the notifier complete |
| Expected final state | `s_src` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T12 |
| Starting state | `s_both` |
| Reset/fixture | Source completes before the notifier nexts |
| State-reaching prefix | `subscribe(quiet)` |
| Target event | `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | Both children unsubscribed because the destination completed |
| Distinguishing suffix | A later notifier next must not emit a second complete (T19) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E08

| Field | Value |
| --- | --- |
| Test ID | E08 |
| Covered row IDs | T13 |
| Starting state | `s_both` |
| Reset/fixture | Both live |
| State-reaching prefix | `subscribe(quiet)` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc`, `unsubNotifier` |
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
| T11 | specified | not executed |
| T12 | specified | not executed |
| T13 | specified | not executed |
| T14 | specified | not executed |
| T15 | specified | not executed |
| T16 | specified | not executed |
| T17 | specified | not executed |
| T18 | specified | not executed |
| T19 | specified | not executed |

Denominator = 19. Specified 19/19. Executed 0/19.

Residual risk: T10, T11, T16, and T18 are specified without a dedicated scenario. Direct source subscription means source `error`/`complete` are not passed through an operator `onError` wrapper; behavior is `Subscriber._error` / `_complete`. Not executed.

## G. Review decision

Decision: accept with documented limits

Reason: Line 47 separates notifier `next` (complete the destination) from notifier `complete` (`noop`). Line 48 makes source subscription conditional on the destination still being open, which is the lifecycle difference from `skipUntil`.

Known implementation limitations: The source is the same subscriber as the consumer, so there is no operator-local `next` hook on source values. Invalid notifiers error inside `operate` before line 48. A synchronous notifier `next` completes before the source exists.

Differences between intended contract and version characterization: JSDoc lines 16-20 match the mirror-until-notifier-next rule and the "notifier complete passes all values" rule. They do not mention notifier `error`, which the default `OperatorSubscriber` path forwards, or the `subscriber.closed` guard.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
