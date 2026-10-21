# `throwIfEmpty`

`throwIfEmpty` mirrors every source `next`, including falsy values. If the source completes after at least one `next`, it completes. If the source completes after none, it errors with the value returned by `errorFactory` (`throwIfEmpty.ts` lines 42-56). The default factory returns `new EmptyError()` at that complete, not at subscribe (`throwIfEmpty.ts` lines 58-60). A throw inside `errorFactory` is a callback failure while handling `sourceComplete`, not a `sourceError`. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `throwIfEmpty` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/throwIfEmpty.ts` lines 42-60 |
| Helpers read | `EmptyError.ts` lines 23-30; `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | `errorFactory` defaulting to `defaultErrorFactory` |
| Output | The source sequence, or `outError(errorFactory())` when that sequence completes empty |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | Default: `EmptyError` message `'no elements in sequence'`, allocated when the empty complete is handled. Custom factory: whatever it returns, including non-`Error` values, passed to `subscriber.error` |
| Upstream | One source subscription |
| Inners | None |
| Per-subscription state | `hasValue`, initially false (line 44) |
| Exclusions | No reentrant callback. Teardown throws out of scope. Downstream observer throws are not `outError`. If `errorFactory` throws, `OperatorSubscriber`'s custom complete path sends that exception to `destination.error` and unsubscribes in `finally` (`OperatorSubscriber.ts` lines 89-100). That is modeled as a callback outcome of `sourceComplete`, not as `sourceError`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_empty, s_seen, s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v),
       sourceError(e),
       sourceComplete(factory),
       cancel }
     factory ∈ { return(x), throw(err) }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

`sourceComplete(factory)` is one input. `factory` is the synchronous result of calling `errorFactory` only on the empty complete path. On the `hasValue` path the factory is not called.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_empty` | Subscribed, `hasValue === false` | No |
| `s_seen` | At least one source next forwarded | No |
| `s_completed` | Complete delivered after a seen value | Yes |
| `s_errored` | Source error, factory result, or factory throw delivered | Yes |
| `s_cancelled` | Cancelled. Factory not called | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 45-54. `EmptyError` is not constructed here |
| Source next | Yes | Sets `hasValue` and forwards `value` (lines 48-51). Falsy values count |
| Source error | Yes | Default forward. Factory not called |
| Source completion | Yes | `hasValue ? subscriber.complete() : subscriber.error(errorFactory())` (line 52) |
| Cancellation cancel | Yes | Does not complete and does not call the factory |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | `errorFactory` return or throw, only if completing while `hasValue` is false. The default factory returns normally |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v)
                | outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

A full empty-default trace is a single `outError(EmptyError)`. A non-empty trace is the forwarded nexts and then `outComplete`.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_empty` | Factory fixed, possibly the default | No error yet | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_empty` | `sourceNext(v)` | Any `v`, including `undefined`, `0`, `false`, `null` | `outNext(v)` | ε | `s_seen` | No value yet | A later complete will not call the factory | E02 |
| T04 | `s_seen` | `sourceNext(v)` | Already seen | `outNext(v)` | ε | `s_seen` | At least one next forwarded | Order preserved | E02 |
| T05 | `s_empty` | `sourceComplete(return(x))` | `hasValue === false` and factory returns `x` | `outError(x)` | `unsubSrc` | `s_errored` | No next | `x` is a new `EmptyError` if the default factory is used. No `outComplete` | E01 |
| T06 | `s_empty` | `sourceComplete(throw(err))` | `hasValue === false` and factory throws `err` | `outError(err)` | `unsubSrc` | `s_errored` | No next | Callback throw during complete handling, not `sourceError` | E03 |
| T07 | `s_seen` | `sourceComplete(factory)` | `hasValue === true`. Factory is not invoked | `outComplete` | `unsubSrc` | `s_completed` | At least one next | No extra default next | E02 |
| T08 | `s_empty` or `s_seen` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | Factory not called | Even from `s_empty`, this is `e`, not `EmptyError` | E04 |
| T09 | `s_empty` or `s_seen` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | Factory not called | No `outComplete` and no `outError` | E05 |
| T10 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T05 and T06 partition the empty complete by the factory outcome. T07 does not consult the factory, so `factory` is irrelevant there.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Seen values are forwarded in order, then complete. Empty complete is one error and no next. E01, E02 |
| At most one terminal | Yes | T05, T06, T07, T08 |
| No downstream after terminal | Yes | T10 |
| Cancellation does not synthesize completion | Yes | T09, E05. Also does not synthesize the empty error |
| Upstream / inner lifetime | Yes | One source. No inner |
| Cleanup once | Yes | Complete and error paths unsubscribe in `finally` (`OperatorSubscriber.ts` lines 96-99) or via `Subscriber._error` |
| Per-subscription state | Yes | `hasValue` is an init local (line 44) |
| Empty source | Yes | T05 or T06. Default object created in that transition. E01 |
| Source error | Yes | Forwarded from both active states. E04 |
| Silence | Yes | No next and no complete from the source: stay in `s_empty` with no error |
| Pending value or buffer on terminal | No | Values are forwarded immediately. The flag is not a stored payload |
| Callback throws / reenters / cancels | Factory throw yes (T06, E03). Reentry excluded | A returning factory's return value is the error payload even if it is not an `Error` |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T05 |
| Starting state | `s_idle` |
| Reset/fixture | Default `errorFactory` |
| State-reaching prefix | `subscribe` → `s_empty` |
| Target event | `sourceComplete(return(EmptyError))` |
| Expected notifications | `outError(EmptyError)` message `'no elements in sequence'` |
| Expected lifecycle observations | `subSrc` then `unsubSrc`. The error object is created in the complete handler (`throwIfEmpty.ts` lines 52 and 58-60) |
| Distinguishing suffix | No `outComplete`. Not allocated at subscribe |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04, T07 |
| Starting state | `s_empty` |
| Reset/fixture | Default or custom factory. Source emits `0` then `false` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(0)`, `sourceNext(false)`, `sourceComplete` |
| Expected notifications | `outNext(0)`, `outNext(false)`, `outComplete` |
| Expected lifecycle observations | `hasValue` is true after `0`. Factory not called |
| Distinguishing suffix | Falsy nexts suppress the empty error. This is not `defaultIfEmpty` adding a value |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T06 |
| Starting state | `s_empty` |
| Reset/fixture | `errorFactory` throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete(throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc` from the complete handler `finally` |
| Distinguishing suffix | The input was `sourceComplete`, not `sourceError`. No `EmptyError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T08 |
| Starting state | `s_empty` |
| Reset/fixture | Default factory, source errors |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. Factory not called |
| Distinguishing suffix | Contrast E01 |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T09 |
| Starting state | `s_empty` |
| Reset/fixture | Subscribed, no next |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `EmptyError` and no `outComplete` |
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

Residual risk: a factory that returns a non-error is specified as `outError(x)` and not scenario-isolated. `s_seen` plus `sourceError` is the same row T08 as the empty error case and was not given a second scenario. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: `hasValue` is set on every next before the mirror, and the complete handler is the only place `errorFactory` runs. That places `EmptyError` construction at complete time.

Known implementation limitations: Any next, even a falsy one, disables the error. The factory's return value is used as the error payload as-is. A throwing factory becomes `outError` through the complete-handler catch. Cancel does not invoke the factory. There is no default value emission in this file.

Differences between intended contract and version characterization: JSDoc lines 6-9 say the error is created at completion time by the optional factory, otherwise `EmptyError`. That matches lines 42-60. Callers such as `first` and `elementAt` rely on that timing. No contradicting path was found in this file.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
