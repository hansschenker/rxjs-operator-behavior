# `defaultIfEmpty`

`defaultIfEmpty` mirrors the source. If the source completes without any `next`, it emits `defaultValue` and then completes (`defaultIfEmpty.ts` lines 40-59). If any `next` was seen, including a falsy one, it only completes. A source error is forwarded and the default is not emitted. There is no `@deprecated` tag. This is the non-error counterpart of `throwIfEmpty`.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `defaultIfEmpty` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/defaultIfEmpty.ts` lines 40-59 |
| Helpers read | `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | `defaultValue`, required by the signature but may be `undefined` if the caller passes it or omits it |
| Output | Source values, or exactly one `defaultValue` when the source completes empty |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None |
| Upstream | One source subscription |
| Inners | None |
| Per-subscription state | `hasValue`, initially false (line 42) |
| Exclusions | No reentrant callback between `subscriber.next(defaultValue)` and `subscriber.complete()` (lines 51-54). Teardown throws out of scope. Downstream observer throws are not `outError`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_empty, s_seen, s_completed, s_errored, s_cancelled }
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
parameter d = defaultValue, a symbolic JS value fixed at construction
```

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_empty` | Subscribed, no next forwarded | No |
| `s_seen` | At least one source next forwarded | No |
| `s_completed` | Complete delivered, with or without a default next | Yes |
| `s_errored` | Source error delivered | Yes |
| `s_cancelled` | Cancelled. Default not emitted | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 43-58 |
| Source next | Yes | Sets `hasValue` and forwards `value` (lines 46-49) |
| Source error | Yes | Default forward. Default is not emitted |
| Source completion | Yes | If `!hasValue`, `outNext(d)` then `outComplete`; else `outComplete` only (lines 50-55) |
| Cancellation cancel | Yes | Does not emit `d` and does not complete |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | No | `d` is a value, not a factory. No user function is called |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v)
                | outNext(d) then outComplete
                | outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_empty` | `d` fixed | No emission | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_empty` | `sourceNext(v)` | Any `v`, including falsy `v` and `v === d` | `outNext(v)` | ε | `s_seen` | No next yet | Complete will not emit a second default | E02 |
| T04 | `s_seen` | `sourceNext(v)` | Already seen | `outNext(v)` | ε | `s_seen` | At least one next | Order preserved | E02 |
| T05 | `s_empty` | `sourceComplete` | `hasValue === false` | `outNext(d)`, `outComplete` | `unsubSrc` | `s_completed` | No source next | `d` may be `undefined`. This is not an error | E01 |
| T06 | `s_seen` | `sourceComplete` | `hasValue === true` | `outComplete` | `unsubSrc` | `s_completed` | At least one source next | `d` is not appended | E02 |
| T07 | `s_empty` or `s_seen` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | Default not substituted for an error | No `outNext(d)` | E03 |
| T08 | `s_empty` or `s_seen` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | May have forwarded values already | No synthetic `d` and no `outComplete` | E04 |
| T09 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T05 and T06 partition complete. T03 treats every JS value as "seen", which is what makes a source that emits `undefined` different from a source that emits nothing when `d` is also `undefined`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Source nexts in order. At most one default, and only as the sole next on empty complete. E01, E02 |
| At most one terminal | Yes | Complete or source error |
| No downstream after terminal | Yes | T09 |
| Cancellation does not synthesize completion | Yes | T08, E04. Also does not synthesize the default |
| Upstream / inner lifetime | Yes | One source. No inner |
| Cleanup once | Yes | Complete unsubscribes via `subscriber.complete` |
| Per-subscription state | Yes | `hasValue` is an init local (line 42). `d` is closed over from the operator call |
| Empty source | Yes | `outNext(d)`, `outComplete`. E01 |
| Source error | Yes | Forwarded from `s_empty` without `d`. E03 |
| Silence | Yes | No next and no complete: stay in `s_empty`, default not emitted |
| Pending value or buffer on terminal | No | Source values are not held. `d` is a parameter, emitted only on empty complete |
| Callback throws / reenters / cancels | No user callback. Reentry between default next and complete excluded | Contrast `throwIfEmpty`, whose factory can throw |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T05 |
| Starting state | `s_idle` |
| Reset/fixture | `defaultValue = 'no clicks'`, empty source |
| State-reaching prefix | `subscribe` → `s_empty` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext('no clicks')`, `outComplete` |
| Expected lifecycle observations | `subSrc`, `unsubSrc`. No error |
| Distinguishing suffix | `throwIfEmpty` on the same source would `outError` instead of `outNext` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04, T06 |
| Starting state | `s_empty` |
| Reset/fixture | `d = 'fallback'`. Source emits `0` then `1` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(0)`, `sourceNext(1)`, `sourceComplete` |
| Expected notifications | `outNext(0)`, `outNext(1)`, `outComplete` |
| Expected lifecycle observations | `hasValue` true after `0`, even though `0` is falsy |
| Distinguishing suffix | `'fallback'` is absent |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T07 |
| Starting state | `s_empty` |
| Reset/fixture | `d = 0`, source errors |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | `0` is not emitted. An error is not emptiness |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T08 |
| Starting state | `s_empty` |
| Reset/fixture | `d = 'x'` |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext('x')` and no `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T05 |
| Starting state | `s_empty` |
| Reset/fixture | `defaultIfEmpty(undefined)` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(undefined)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | A source that actually nexts `undefined` is T03 then T06: one `outNext(undefined)` as a source value, and the flag ends in `s_seen`. The notifications match this empty case, but a second source next would show the difference. The empty case never had a source next |
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

Residual risk: E05 notes that `outNext(undefined)` is ambiguous unless the source next count is observed. `s_seen` plus `sourceError` shares T07 and has no separate scenario. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The complete handler is the only place `defaultValue` is pushed, and only when `hasValue` is still false. Every source next both sets the flag and forwards.

Known implementation limitations: Falsy source values suppress the default. The default is not a factory and is not called. Source error does not fall back. Cancel does not emit it. `undefined` is a legal default payload.

Differences between intended contract and version characterization: JSDoc lines 5-16 match the empty-complete default and the mirror behavior. They do not say that a source error skips the default; the code does that by not customizing `onError`. No contradicting emission path was found.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
