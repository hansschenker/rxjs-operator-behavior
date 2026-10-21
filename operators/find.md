# `find`

`find` is a full operator. It uses `createFind` in `'value'` mode (`find.ts` lines 64-96). The first predicate success emits that value and completes, unsubscribing the source. If the source completes with no success, the operator emits `undefined` and then completes. It does not raise `EmptyError`. `thisArg` overloads are `@deprecated` (lines 8 and 16); `predicate.call(thisArg, ...)` is still what the code does. `findIndex` is the same helper in `'index'` mode and is specified separately.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `find` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/find.ts` lines 64-96 |
| Helpers read | `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130; `lift.ts` lines 17-31 |
| Shape | Full operator. `operate(createFind(predicate, thisArg, 'value'))` |
| Parameters | `predicate(value, index, source)`; optional `thisArg` (deprecated overloads) |
| Output | The first matching value, or `undefined` if the source completes without one |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None. A predicate throw is `outError` |
| Upstream | One source subscription, dropped on the first match |
| Inners | None |
| Per-subscription state | `index`, starting at 0 (`find.ts` line 78) |
| Exclusions | No reentrant callback between `subscriber.next(value)` and `subscriber.complete()` (lines 85-86), or between `next(undefined)` and `complete` (lines 90-91). Teardown throws out of scope. Downstream observer throws are not `outError`. A missing or non-function predicate throws when a next invokes it; a complete with no next still emits `undefined` because the complete handler does not call the predicate. Ordinary model assumes a callable predicate. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_seek(index), s_completed, s_errored, s_cancelled }
     index ∈ ℕ₀
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e), sourceComplete, cancel }
     outcome ∈ { match, miss, throw(err) }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

`findIndex` is false in this file's call (`emit === 'value'`), so the match payload is `value` and the miss payload is `undefined` (lines 76, 85, 90).

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_seek(index)` | Subscribed. Next predicate index is `index` | No |
| `s_completed` | Match or `undefined` already followed by complete | Yes |
| `s_errored` | Predicate throw or source error | Yes |
| `s_cancelled` | Cancelled. No `undefined` sentinel | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 79-94 |
| Source next | Yes | `predicate.call(thisArg, value, i, source)` (lines 83-87) |
| Source error | Yes | Default forward. No `undefined` |
| Source completion | Yes | `outNext(undefined)` then `outComplete` (lines 89-92) |
| Cancellation cancel | Yes | Does not emit `undefined` and does not complete |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Match, miss, or throw. `this` is `thisArg`. The miss sentinel is not a callback |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v) then outComplete
                | outNext(undefined) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

`outNext(undefined)` is a real next whose payload is the value `undefined`, not a missing notification.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Callable predicate | ε | `subSrc` | `s_seek(0)` | `thisArg` fixed, possibly `undefined` | No emission | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_seek(i)` | `sourceNext(v, match)` | `predicate.call(thisArg, v, i, source)` is truthy | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | `i` misses so far | Later source values are not tested | E01 |
| T04 | `s_seek(i)` | `sourceNext(v, miss)` | Predicate returns falsy | ε | ε | `s_seek(i+1)` | Still seeking | `v` is not stored | E02 |
| T05 | `s_seek(i)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | `const i = index++` already ran (line 83) | No `outNext(undefined)` | E03 |
| T06 | `s_seek(i)` | `sourceError(e)` | Any `i` | `outError(e)` | `unsubSrc` | `s_errored` | Misses may have occurred | No sentinel | E04 |
| T07 | `s_seek(i)` | `sourceComplete` | Any `i`, including 0 | `outNext(undefined)`, `outComplete` | `unsubSrc` | `s_completed` | No match | Not `EmptyError`. Not `outNext(-1)` (that is `findIndex`) | E02 |
| T08 | `s_seek(i)` | `cancel` | Any `i` | ε | `unsubSrc` | `s_cancelled` | No match yet | No `undefined` and no complete | E05 |
| T09 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03-T05 partition next outcomes. Truthiness, not `=== true`, is the match test (`if (predicate.call(...))`, line 84).

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Either the first matching source value, or a single `undefined` after complete. E01, E02 |
| At most one terminal | Yes | Match and miss both complete. Throw and source error do not also complete |
| No downstream after terminal | Yes | T09. Match unsubscribes the source |
| Cancellation does not synthesize completion | Yes | T08, E05. Also does not synthesize `undefined` |
| Upstream / inner lifetime | Yes | Unsubscribed on first match, not on misses. No inner |
| Cleanup once | Yes | No `onFinalize` |
| Per-subscription state | Yes | `index` is local to `createFind`'s subscriber function (line 78) |
| Empty source | Yes | T07 from `s_seek(0)` emits `undefined` then complete. Not an error |
| Source error | Yes | Forwarded with no sentinel. E04 |
| Silence | Yes | No match and no source terminal: stay in `s_seek`, no `undefined` |
| Pending value or buffer on terminal | No | Misses are not stored. The match is emitted in the same transition |
| Callback throws / reenters / cancels | Throws yes (T05). Reentry excluded | `thisArg` is applied with `call` even though those overloads are deprecated |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T04, T03 |
| Starting state | `s_idle` |
| Reset/fixture | Predicate matches only `'b'` |
| State-reaching prefix | `subscribe` → `s_seek(0)` |
| Target event | `sourceNext('a', miss)`, `sourceNext('b', match)` |
| Expected notifications | `outNext('b')`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` on `'b'`. Index passed with `'b'` is 1. `this` is `thisArg` |
| Distinguishing suffix | A later `'c'` is not delivered. Contrast `first`, which would `EmptyError` if `'b'` never came, instead of `undefined` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T04, T07 |
| Starting state | `s_seek(0)` |
| Reset/fixture | Predicate always falsy, or empty source |
| State-reaching prefix | `subscribe`, and optionally misses |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(undefined)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outError(EmptyError)` and not `outNext(-1)` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_seek(0)` |
| Reset/fixture | Predicate throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(undefined)`. This is not `sourceError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_seek(1)` |
| Reset/fixture | One miss already taken |
| State-reaching prefix | `subscribe`, one miss |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No sentinel `undefined` before the error |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_seek(0)` |
| Reset/fixture | Subscribed, no match |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(undefined)` and no `outComplete` |
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

Denominator = 9. Specified 9/9. Executed 0/9.

Residual risk: truthy non-booleans take T03. A non-function predicate on a next versus on an empty complete is excluded from the ordinary callable-predicate machine. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: `createFind` with `'value'` nexts the source value on success and `undefined` on complete. Both paths then complete. Source error stays on the default path.

Known implementation limitations: The predicate is required by the types but not checked up front. `thisArg` still works and is deprecated. Match uses truthiness. The index is the source next count, and the third argument is the source observable passed into `createFind`. Cancel does not emit the miss sentinel.

Differences between intended contract and version characterization: JSDoc lines 31-35 say `find` does not error when nothing matches and emits `undefined` instead, unlike `first`. That matches lines 89-91. The deprecated `thisArg` notes match the overload comments; the runtime still honors `thisArg`.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
