# `findIndex`

`findIndex` is a thin wrapper around `createFind(..., 'index')` (`findIndex.ts` lines 58-63, helper in `find.ts` lines 71-96). A match emits the 0-based source index and completes. If the source completes with no match, it emits `-1` and completes. It does not raise `EmptyError`. `thisArg` overloads are `@deprecated` (`findIndex.ts` lines 7 and 9).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `findIndex` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/findIndex.ts` lines 58-63, behavior from `src/internal/operators/find.ts` lines 71-96 |
| Helpers read | `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Thin wrapper: `operate(createFind(predicate, thisArg, 'index'))` |
| Parameters | `predicate(value, index, source)`; optional `thisArg` (deprecated overloads) |
| Output | A number: the matching index, or `-1` |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None. A predicate throw is `outError` |
| Upstream | One source subscription, dropped on the first match |
| Inners | None |
| Per-subscription state | `index` local inside `createFind` (`find.ts` line 78) |
| Exclusions | Same quiescence and teardown exclusions as `find`. `findIndex` is the `emit === 'index'` branch: match payload is `i`, miss payload is `-1` (`find.ts` lines 76, 85, 90). Ordinary model assumes a callable predicate. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_seek(index), s_completed, s_errored, s_cancelled }
Σ  = { subscribe, sourceNext(v, outcome), sourceError(e), sourceComplete, cancel }
     outcome ∈ { match, miss, throw(err) }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_seek(index)` | Subscribed. Next index to test is `index` | No |
| `s_completed` | An index or `-1` already followed by complete | Yes |
| `s_errored` | Predicate throw or source error | Yes |
| `s_cancelled` | Cancelled. No `-1` | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `createFind` subscribes (`find.ts` lines 79-94) |
| Source next | Yes | On match, `subscriber.next(i)` because `findIndex` is true (line 85) |
| Source error | Yes | Default forward. No `-1` |
| Source completion | Yes | `subscriber.next(-1)` then complete (lines 90-91) |
| Cancellation cancel | Yes | Does not emit `-1` |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Match, miss, or throw via `predicate.call(thisArg, value, i, source)` |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(i) then outComplete
                | outNext(-1) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
i ∈ ℕ₀
```

The emitted index is the source next count, not the count of matches.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Callable predicate | ε | `subSrc` | `s_seek(0)` | `thisArg` fixed | — | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_seek(i)` | `sourceNext(v, match)` | Predicate truthy for `(v, i, source)` | `outNext(i)`, `outComplete` | `unsubSrc` | `s_completed` | `i` misses | The value `v` is not the payload | E01 |
| T04 | `s_seek(i)` | `sourceNext(v, miss)` | Predicate falsy | ε | ε | `s_seek(i+1)` | Still seeking | Misses still consume an index | E02 |
| T05 | `s_seek(i)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | Index was captured | No `outNext(-1)` | E03 |
| T06 | `s_seek(i)` | `sourceError(e)` | Any `i` | `outError(e)` | `unsubSrc` | `s_errored` | Any misses | No `-1` | E04 |
| T07 | `s_seek(i)` | `sourceComplete` | No match, any `i` | `outNext(-1)`, `outComplete` | `unsubSrc` | `s_completed` | Includes the empty source | Not `undefined` (that is `find`) and not `EmptyError` | E02 |
| T08 | `s_seek(i)` | `cancel` | Any `i` | ε | `unsubSrc` | `s_cancelled` | No match | No `-1` and no complete | E05 |
| T09 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | One number: the first matching index, or `-1` after complete. E01, E02 |
| At most one terminal | Yes | Success paths complete. Error paths do not also next `-1` |
| No downstream after terminal | Yes | T09 |
| Cancellation does not synthesize completion | Yes | T08, E05 |
| Upstream / inner lifetime | Yes | Source unsubscribed on match. No inner |
| Cleanup once | Yes | No extra finalizer |
| Per-subscription state | Yes | Index lives in the `createFind` closure |
| Empty source | Yes | `outNext(-1)`, `outComplete`. E02 |
| Source error | Yes | Forwarded. E04 |
| Silence | Yes | No match and no terminal: no `-1` yet |
| Pending value or buffer on terminal | No | No stored value. The index is computed from the count |
| Callback throws / reenters / cancels | Throws yes (T05). Reentry excluded | Deprecated `thisArg` is still passed to `call` |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T04, T03 |
| Starting state | `s_idle` |
| Reset/fixture | Predicate true only for `'c'` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a', miss)`, `sourceNext('b', miss)`, `sourceNext('c', match)` |
| Expected notifications | `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` on the match. `'c'` is not the payload |
| Distinguishing suffix | Contrast `find`, which would `outNext('c')` for the same predicate |
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
| Reset/fixture | No value matches, including an empty source |
| State-reaching prefix | `subscribe` |
| Target event | optional misses, then `sourceComplete` |
| Expected notifications | `outNext(-1)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outNext(undefined)` and not `EmptyError` |
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
| Distinguishing suffix | No `outNext(-1)` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_seek(0)` |
| Reset/fixture | Source errors immediately |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `-1` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_seek(1)` |
| Reset/fixture | One miss already seen |
| State-reaching prefix | `subscribe`, one miss |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(-1)` and no `outComplete` |
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

Residual risk: shared with `createFind`. A truthy non-boolean is a match. No test was executed. `find.ts` and `findIndex.ts` must be changed together; this file does not reimplement the loop.

## G. Review decision

Decision: accept with documented limits

Reason: `findIndex.ts` only selects the `'index'` mode of `createFind`. The miss value `-1` and the match value `i` are both in that helper.

Known implementation limitations: Same subscriber loop as `find`. Deprecated `thisArg` is still forwarded. `-1` is emitted only on source complete, not on cancel or error. Index 0 is a successful find, distinct from `-1`.

Differences between intended contract and version characterization: JSDoc lines 25-29 say a missing match does not error, unlike `first`. They do not print the `-1` sentinel; that sentinel is the `emit === 'index'` arm in `find.ts` lines 90-91. The informal "emits the index" text matches T03.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
