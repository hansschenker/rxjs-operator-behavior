# `isEmpty`

`isEmpty` is a full operator. The first source `next` emits `false` and completes, unsubscribing the source. If the source completes with no `next`, it emits `true` and completes (`isEmpty.ts` lines 66-81). A source error is forwarded and no boolean is emitted. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `isEmpty` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/isEmpty.ts` lines 66-81 |
| Helpers read | `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | None |
| Output | Exactly one boolean on the success paths, then complete |
| Model kind | Symbolic (the source payload is ignored) |
| Scheduler | None |
| Introduced errors | None |
| Upstream | One source subscription. Unsubscribed on the first next, not only on source complete |
| Inners | None |
| Per-subscription state | None. "Empty so far" is just still being active |
| Exclusions | No reentrant callback between `subscriber.next(false)` and `subscriber.complete()` (lines 72-73). Teardown throws out of scope. Downstream observer throws are not `outError`. |

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
| `s_active` | Subscribed and no source next has arrived | No |
| `s_completed` | `false` or `true` already emitted and complete delivered | Yes |
| `s_errored` | Source error delivered with no boolean | Yes |
| `s_cancelled` | Cancelled before any boolean | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 68-80 |
| Source next | Yes | Payload ignored. `outNext(false)` then `outComplete` (lines 71-74) |
| Source error | Yes | Default forward. The complete handler is not used, so `true` is not emitted |
| Source completion | Yes | Custom handler emits `true` then completes (lines 75-78) |
| Cancellation cancel | Yes | Neither boolean is emitted |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | No | Both handlers are library closures |

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
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_active` | None | No boolean yet | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_active` | `sourceNext(v)` | Any `v`, including falsy values | `outNext(false)`, `outComplete` | `unsubSrc` | `s_completed` | No next seen yet | Further source nexts are not subscribed. `v` itself is not output | E01 |
| T04 | `s_active` | `sourceError(e)` | No next seen | `outError(e)` | `unsubSrc` | `s_errored` | Still active | No `outNext(true)` and no `outNext(false)` | E02 |
| T05 | `s_active` | `sourceComplete` | No next seen | `outNext(true)`, `outComplete` | `unsubSrc` | `s_completed` | Empty of nexts | Not an error | E03 |
| T06 | `s_active` | `cancel` | No next seen | ε | `unsubSrc` | `s_cancelled` | Still active | No boolean and no complete | E04 |
| T07 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03-T06 partition the active state. Falsy `v` still takes T03: emptiness is "no next", not "no truthy next".

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | One boolean then complete on success. `false` means a next arrived. `true` means complete without a next. E01, E03 |
| At most one terminal | Yes | Complete follows the boolean in the same transition, or the transition is a single error |
| No downstream after terminal | Yes | T07. T03 unsubscribes the source |
| Cancellation does not synthesize completion | Yes | T06, E04 |
| Upstream / inner lifetime | Yes | Unsubscribed on the first next, before later source values. No inner |
| Cleanup once | Yes | No extra finalizer |
| Per-subscription state | Yes | No shared flag. Fresh subscriber per subscribe |
| Empty source | Yes | `outNext(true)`, `outComplete`. E03 |
| Source error | Yes | `outError` with no boolean, even if the source had not nexted. E02 |
| Silence | Yes | Non-terminating source with no next: no boolean |
| Pending value or buffer on terminal | No | The first payload is discarded, not stored. The boolean is computed from presence |
| Callback throws / reenters / cancels | No user callback. Reentry between `next(false)` and `complete` excluded | Order in source is next then complete (lines 72-73 and 76-77) |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03 |
| Starting state | `s_idle` |
| Reset/fixture | Source will emit `'a'` then `'b'` if still subscribed |
| State-reaching prefix | `subscribe` → `s_active` |
| Target event | `sourceNext('a')` |
| Expected notifications | `outNext(false)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` before `'b'` can be delivered |
| Distinguishing suffix | `'b'` is not a second notification. `'a'` is not the output payload |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T04 |
| Starting state | `s_active` |
| Reset/fixture | Source errors without a next |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outNext(true)`. An error is not "empty" |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_active` |
| Reset/fixture | Empty source |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(true)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Contrast `ignoreElements`, which would complete with no next, and `every`, whose empty result is also `true` but means vacuous predicate success |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_active` |
| Reset/fixture | Subscribed, no next yet |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(true)` and no `outComplete` |
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

Denominator = 7. Specified 7/7. Executed 0/7.

Residual risk: a falsy first value (`0`, `null`) is specified as `false` and not separately scenario-named. Reentry between the boolean and complete is excluded. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The two custom handlers are exhaustive for next and complete, and error stays on the default path. `true` is only the no-next complete path.

Known implementation limitations: The first next completes immediately, so later values are not observed. Falsy payloads still count as non-empty. Error does not yield a boolean. There is no predicate.

Differences between intended contract and version characterization: JSDoc lines 5-18 match `false` on the first value and `true` on empty complete. They do not discuss source error; the code forwards it with no boolean. That is a gap in the narrative, not a second implementation.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
