# `elementAt`

`elementAt` has a factory-time throw and a subscription machine. If `index < 0`, `elementAt` throws `ArgumentOutOfRangeError` immediately, before an operator function exists (`elementAt.ts` lines 58-60). For `index >= 0` it is a thin composition: `filter` the source index, `take(1)`, then `defaultIfEmpty` or `throwIfEmpty(() => new ArgumentOutOfRangeError())` (lines 61-67). The out-of-range error for a non-negative index is created when the source completes without that index, not at subscribe time. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `elementAt` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/elementAt.ts` lines 57-68 |
| Helpers read | `filter.ts` lines 61-74; `take.ts` lines 48-69; `throwIfEmpty.ts` lines 42-60; `defaultIfEmpty.ts` lines 40-59; `ArgumentOutOfRangeError.ts` lines 21-28 |
| Shape | Factory throw, else thin wrapper |
| Parameters | `index`; optional `defaultValue` detected by `arguments.length >= 2` |
| Output | The source value whose 0-based index is strictly `=== index`, or the default, or `ArgumentOutOfRangeError` |
| Model kind | Symbolic, extended by a factory transition that may throw before `subscribe` |
| Scheduler | None |
| Introduced errors | `ArgumentOutOfRangeError`, `name` `'ArgumentOutOfRangeError'`, `message` `'argument out of range'`. Negative index: constructed and thrown at the call to `elementAt`. Otherwise constructed in the valueless complete factory |
| Upstream | Not subscribed if construction throws. Otherwise one source subscription, ended by `take(1)` when the index is hit |
| Inners | None |
| Per-subscription state | Filter index; `take` `seen`; empty-policy `hasValue`. Only if construction returned a function |
| Exclusions | No reentrant callback. The factory throw is a synchronous JavaScript exception, not `outError`. Comparison is `i === index` (`elementAt.ts` line 64), so a non-integer `index >= 0` (including `NaN` and `+Infinity`) never matches an integer source index. Explicit `undefined` default counts. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_pre
S  = { s_pre, s_failed, s_idle, s_seek(k), s_completed, s_errored, s_cancelled }
     k ∈ ℕ₀ is the next source index
Σ  = { construct, subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below, plus a factory exception that is not a notification
δ, λ tabulated in section C
kind = symbolic, extended by factory construction
parameter index is a JS number; default ∈ { absent, present(d) }
```

`s_pre` is before `elementAt(...)` returns. `s_failed` means the call threw and there is no observable. `s_idle` means the operator function exists and is not subscribed. `s_seek(k)` has seen `k` source nexts, none equal to `index`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_pre` | Factory not called. `s₀` | No |
| `s_failed` | Factory threw. No subscription machine | Yes for this operator call |
| `s_idle` | Operator function ready | No |
| `s_seek(k)` | Subscribed, `k` source nexts seen, index not hit | No |
| `s_completed` | Index value or default emitted, then complete | Yes |
| `s_errored` | Complete-time `ArgumentOutOfRangeError`, or source error | Yes |
| `s_cancelled` | Cancelled before a result | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | Only from `s_idle`. `take(1)` subscribes (`take.ts` lines 52-54) |
| Source next | Yes | `filter` keeps the value iff its index `=== index`, then `take(1)` emits and completes |
| Source error | Yes | Forwarded. The range factory is not called |
| Source completion | Yes | If the index was not seen: default next plus complete, or `outError` of a newly built `ArgumentOutOfRangeError` |
| Cancellation cancel | Yes | No default and no range error |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | No | `i === index` is library code. The error factory is library code and runs on valueless complete, which is modeled as the `sourceComplete` transition, not as a user callback |

`construct` is an extra initialization input because a negative index never reaches subscribe.

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v) then outComplete
                | outNext(d) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
factory       ::= throw ArgumentOutOfRangeError | return operator function
record        ::= (notifications in order, lifecycle in order)
```

The factory exception is not `outError` and has no lifecycle. It happens when `elementAt(index)` is evaluated, which is before `pipe` receives the operator if the call is an argument.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_pre` | `construct` | `index < 0` | none (synchronous throw of `new ArgumentOutOfRangeError()`) | ε | `s_failed` | None | `subscribe` is impossible; no observable | E01 |
| T02 | `s_pre` | `construct` | `!(index < 0)` | none | ε | `s_idle` | Includes `0`, positives, `NaN`, `+Infinity` | Default bit fixed by `arguments.length` | E02 |
| T03 | `s_pre` or `s_failed` | `subscribe` or source signals or `cancel` | No operator function | ε | ε | unchanged | Factory did not return | Inapplicable | — |
| T04 | `s_idle` | `subscribe` | Construction succeeded | ε | `subSrc` | `s_seek(0)` | `index >= 0` in the numeric sense of T02 | No emission yet | E02 |
| T05 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T06 | `s_seek(k)` | `sourceNext(v)` | `k === index` | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | `k` values with other indexes already skipped | `take(1)` unsubscribes. Later source values are not delivered | E02 |
| T07 | `s_seek(k)` | `sourceNext(v)` | `k !== index` | ε | ε | `s_seek(k+1)` | Still seeking | `v` is not stored | E03 |
| T08 | `s_seek(k)` | `sourceError(e)` | Any `k` | `outError(e)` | `unsubSrc` | `s_errored` | Index not hit | Not `ArgumentOutOfRangeError` | E04 |
| T09 | `s_seek(k)` | `sourceComplete` | Index not hit and `default` absent | `outError(new ArgumentOutOfRangeError())` | `unsubSrc` | `s_errored` | `arguments.length < 2` | Allocated now, including when `index` is `2.5`, `NaN`, or beyond the length | E03 |
| T10 | `s_seek(k)` | `sourceComplete` | Index not hit and `default` present as `d` | `outNext(d)`, `outComplete` | `unsubSrc` | `s_completed` | `arguments.length >= 2` | Includes `d === undefined` | E05 |
| T11 | `s_seek(k)` | `cancel` | Any `k` | ε | `unsubSrc` | `s_cancelled` | Index not hit | No default and no range error | E06 |
| T12 | `s_completed`, `s_errored`, or `s_cancelled` | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T06 and T07 partition nexts. T09 and T10 partition a miss complete. T01 and T02 partition construction for every JS number (`NaN < 0` is false, so `NaN` is T02).

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | At most one next: the matching source value or `d`. E02, E05 |
| At most one terminal | Yes | Hit completes. Miss errors or completes after the default. Source error is separate. The factory throw is not a second notification because there is no subscription |
| No downstream after terminal | Yes | T12. T06 unsubscribes via `take(1)` |
| Cancellation does not synthesize completion | Yes | T11, E06 |
| Upstream / inner lifetime | Yes | No source on T01. One source after T04, dropped when the index hits. No inner |
| Cleanup once | Yes | No extra finalizer in `elementAt.ts` |
| Per-subscription state | Yes | Filter index starts at 0 per subscription |
| Empty source | Yes | From `s_seek(0)`, T09 or T10. Same error class as a too-short source |
| Source error | Yes | Forwarded even if the index was not reached. E04 |
| Silence | Yes | `index` not yet reached and source never terminates: no next and no range error |
| Pending value or buffer on terminal | No | Non-matching values are not stored. The match is emitted immediately |
| Callback throws / reenters / cancels | No user callback | Factory throw is T01, not a callback inside `subscribe` |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01 |
| Starting state | `s_pre` |
| Reset/fixture | `index = -1` |
| State-reaching prefix | None |
| Target event | `construct` |
| Expected notifications | None. The call throws `ArgumentOutOfRangeError` with message `'argument out of range'` |
| Expected lifecycle observations | No `subSrc`. `subscribe` is not available |
| Distinguishing suffix | This is not an `outError` on a subscription. Contrast E03, where the same class is an `outError` created later |
| Expected final state | `s_failed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (exception versus notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T02, T04, T07, T06 |
| Starting state | `s_pre` |
| Reset/fixture | `elementAt(1)` with no default |
| State-reaching prefix | `construct` → `s_idle`, `subscribe` → `s_seek(0)` |
| Target event | `sourceNext('a')`, `sourceNext('b')` |
| Expected notifications | `outNext('b')`, `outComplete` |
| Expected lifecycle observations | `'a'` is index 0 and is dropped. `unsubSrc` when index 1 matches |
| Distinguishing suffix | A third source value is not emitted |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T07, T09 |
| Starting state | `s_seek(0)` |
| Reset/fixture | `elementAt(2)` and the source emits one value then completes |
| State-reaching prefix | `construct`, `subscribe` |
| Target event | `sourceNext('a')`, `sourceComplete` |
| Expected notifications | `outError(ArgumentOutOfRangeError)` allocated in the complete transition |
| Expected lifecycle observations | `unsubSrc`. No `outNext('a')` |
| Distinguishing suffix | Not the factory throw of E01. The error object did not exist at subscribe |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T08 |
| Starting state | `s_seek(0)` |
| Reset/fixture | `elementAt(5)` with no default |
| State-reaching prefix | `construct`, `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. Range factory not called |
| Distinguishing suffix | `e` is the source error, not `ArgumentOutOfRangeError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T10 |
| Starting state | `s_seek(0)` |
| Reset/fixture | `elementAt(3, undefined)` so a default was passed |
| State-reaching prefix | `construct`, `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(undefined)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc`. No `ArgumentOutOfRangeError` |
| Distinguishing suffix | `elementAt(3)` without a second argument is T09, not this row |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T11 |
| Starting state | `s_seek(0)` |
| Reset/fixture | `elementAt(0)` |
| State-reaching prefix | `construct`, `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | The index-0 value is not received. No range error |
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

Denominator = 12. Specified 12/12. Executed 0/12.

Residual risk: `NaN` and fractional indexes are specified as permanent misses via `===` and were not given their own scenario. The synchronous throw's interaction with `pipe` argument evaluation is specified and not executed.

## G. Review decision

Decision: accept with documented limits

Reason: The negative-index throw is textually before the returned function, and the non-negative miss uses `throwIfEmpty`'s complete-time factory. Those are different times and different channels.

Known implementation limitations: `index < 0` never becomes a notification. `arguments.length >= 2` supplies a default even if it is `undefined`. `i === index` does not coerce. `take(1)` unsubscribes when the index is reached. No subscribe-time range check for large positive indexes.

Differences between intended contract and version characterization: The `@throws` text (`elementAt.ts` lines 46-48) says `i < 0` or completion before the `i`th next both deliver `ArgumentOutOfRangeError` to the observer's `error` callback. For `i < 0` the 7.8.2 source throws at the factory instead, so there is no observer callback. Completion before a non-negative index does use `error` with an `ArgumentOutOfRangeError` created at that complete, unless a default argument was passed.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
