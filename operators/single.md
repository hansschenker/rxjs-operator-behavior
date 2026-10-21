# `single`

`single` is a full operator (`single.ts` lines 93-121). It emits the unique matching value on source complete. A second match errors immediately with `SequenceError('Too many matching values')`. Complete with no next at all errors with `EmptyError`. Complete after nexts that all failed the predicate errors with `NotFoundError('No matching values')`. Those errors are created at the transition that reports them, not at subscribe time. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `single` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/single.ts` lines 93-121 |
| Helpers read | `EmptyError.ts` lines 23-30; `SequenceError.ts` lines 19-26; `NotFoundError.ts` lines 19-26; `OperatorSubscriber.ts` lines 67-100; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | Optional `predicate(value, index, source)` |
| Output | The single match on complete, or one of the three errors above |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | `SequenceError` message `'Too many matching values'` at the second match (line 105). `NotFoundError` message `'No matching values'` at complete if any next was seen and none matched (line 115). `EmptyError` message `'no elements in sequence'` at complete if no next was seen (line 115) |
| Upstream | One source subscription until a second match, a predicate throw, source terminal, or cancel |
| Inners | None |
| Per-subscription state | `hasValue`, `singleValue`, `seenValue`, `index` (lines 95-98) |
| Exclusions | No reentrant callback. After `subscriber.error(SequenceError)` the same turn still assigns `hasValue = true` and `singleValue = value` (lines 105-107). The destination is already stopped, so those writes are not a later emission. A falsy `predicate` means "every value matches" because of `!predicate || predicate(...)` (line 104); `index++` is then not evaluated. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_empty, s_miss, s_held(v), s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e), sourceComplete, cancel }
     outcome ∈ { match, reject, throw(err) }
     Without a predicate, reject and throw are inapplicable and every next matches.
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

`seenValue` is false only in `s_empty`. It becomes true on every source next before the predicate runs (line 103). `s_miss` is "seen, but no match". `s_held(v)` is exactly one match stored.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_empty` | Subscribed, `seenValue === false` | No |
| `s_miss` | At least one next, `hasValue === false`. Requires a predicate | No |
| `s_held(v)` | Exactly one match stored as `v`. Not emitted yet | No |
| `s_completed` | `outNext(v)` and `outComplete` delivered | Yes |
| `s_errored` | `SequenceError`, `NotFoundError`, `EmptyError`, predicate throw, or source error | Yes |
| `s_cancelled` | Cancelled. Stored `v` not emitted | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 99-119. No error is constructed here |
| Source next | Yes | Sets `seenValue`, maybe calls the predicate, maybe stores or `SequenceError`s |
| Source error | Yes | Default forward. Does not emit `singleValue` and does not convert to `EmptyError` |
| Source completion | Yes | Custom handler (lines 110-117): emit and complete, or `NotFoundError`, or `EmptyError` |
| Cancellation cancel | Yes | Does not run the complete handler, so no success next and no empty/not-found error |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Predicate match, reject, or throw. Throw happens after `seenValue = true`. No predicate: the `||` short-circuit skips the call |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

`e` on the second match is a new `SequenceError`. On empty complete it is a new `EmptyError`. On miss complete it is a new `NotFoundError`.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_empty` | Predicate presence fixed | No error yet | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_empty` | `sourceNext(v, match)` | No predicate, or predicate returns truthy | ε | ε | `s_held(v)` | Nothing seen | No `outNext` yet. `index` increments only if the predicate was called | E01 |
| T04 | `s_empty` | `sourceNext(v, reject)` | Predicate returns falsy | ε | ε | `s_miss` | Predicate present | Not a stored value | E02 |
| T05 | `s_miss` | `sourceNext(v, reject)` | Predicate returns falsy | ε | ε | `s_miss` | Already missed at least once | Still no store | E02 |
| T06 | `s_miss` | `sourceNext(v, match)` | Predicate returns truthy | ε | ε | `s_held(v)` | Prior rejects only | First match is stored, not emitted | E02 |
| T07 | `s_held(w)` | `sourceNext(v, reject)` | Predicate returns falsy | ε | ε | `s_held(w)` | One match stored | `w` is kept. `v` does not count as a second match | E03 |
| T08 | `s_held(w)` | `sourceNext(v, match)` | Second match | `outError(new SequenceError('Too many matching values'))` | `unsubSrc` | `s_errored` | `hasValue` already true (line 105) | Neither `w` nor `v` is nexted. Later local writes are not observable | E04 |
| T09 | `s_empty`, `s_miss`, or `s_held(w)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | `seenValue` was set true before the call | No `SequenceError` unless `err` is that object. No stored emission | E05 |
| T10 | `s_empty`, `s_miss`, or `s_held(w)` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | May be holding `w` | `w` is not emitted. Factory errors are not used | E06 |
| T11 | `s_held(v)` | `sourceComplete` | Exactly one match | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | `hasValue` true (lines 111-113) | The next is delayed until this complete | E01 |
| T12 | `s_empty` | `sourceComplete` | `seenValue === false` | `outError(new EmptyError())` | `unsubSrc` | `s_errored` | No source next | Not `NotFoundError` | E07 |
| T13 | `s_miss` | `sourceComplete` | Seen and no match | `outError(new NotFoundError('No matching values'))` | `unsubSrc` | `s_errored` | Predicate rejected every next | Not `EmptyError` | E02 |
| T14 | `s_empty`, `s_miss`, or `s_held(w)` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | May be holding `w` | No next and none of the three operator errors | E08 |
| T15 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

Without a predicate, T04, T05, T07, T09, and T13 are unreachable. T03 and T08 cover every next.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | At most one `outNext`, and only from the complete handler, carrying the stored match. E01 |
| At most one terminal | Yes | `SequenceError` terminals before complete. Complete chooses exactly one of success, `EmptyError`, or `NotFoundError` |
| No downstream after terminal | Yes | T15. Second match unsubscribes via `subscriber.error` |
| Cancellation does not synthesize completion | Yes | T14, E08 |
| Upstream / inner lifetime | Yes | Unsubscribed on second match, not on the first. No inner |
| Cleanup once | Yes | No `onFinalize`. One unsubscribe |
| Per-subscription state | Yes | The four locals are created inside `operate` (lines 95-98) |
| Empty source | Yes | `EmptyError` at complete (T12, E07), not `NotFoundError` |
| Source error | Yes | Forwarded with no success next (T10) |
| Silence | Yes | A non-terminating source with fewer than two matches emits nothing, including when one match is already stored |
| Pending value or buffer on terminal | Yes | `singleValue` is emitted only on complete. It is dropped on `SequenceError`, source error, predicate throw, and cancel |
| Callback throws / reenters / cancels | Throws yes (T09). Reentry excluded | `seenValue = true` happens even if the predicate throws |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T11 |
| Starting state | `s_idle` |
| Reset/fixture | `single()` with no predicate |
| State-reaching prefix | `subscribe` → `s_empty` |
| Target event | `sourceNext('only', match)`, `sourceComplete` |
| Expected notifications | `outNext('only')`, `outComplete` |
| Expected lifecycle observations | No output on the next. `unsubSrc` on complete. Predicate not called |
| Distinguishing suffix | A second next would have been T08 instead of waiting for complete |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T04, T05, T13 |
| Starting state | `s_empty` |
| Reset/fixture | `predicate` returns false for every value |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(1, reject)`, `sourceNext(2, reject)`, `sourceComplete` |
| Expected notifications | `outError(NotFoundError)` message `'No matching values'` |
| Expected lifecycle observations | `seenValue` is true. `unsubSrc`. Object allocated on complete |
| Distinguishing suffix | Not `EmptyError`, because a next was seen. Not `outNext(undefined)` (`find` would do that) |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T06, T07, T11 |
| Starting state | `s_empty` |
| Reset/fixture | Predicate matches only `'b'` |
| State-reaching prefix | `subscribe`, `sourceNext('a', reject)` → `s_miss` |
| Target event | `sourceNext('b', match)`, `sourceNext('c', reject)`, `sourceComplete` |
| Expected notifications | `outNext('b')`, `outComplete` |
| Expected lifecycle observations | `'c'` does not replace `'b'` and does not `SequenceError` |
| Distinguishing suffix | Two matches would be E04 |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T03, T08 |
| Starting state | `s_empty` |
| Reset/fixture | No predicate, so every next matches |
| State-reaching prefix | `subscribe`, `sourceNext(1, match)` → `s_held(1)` |
| Target event | `sourceNext(2, match)` |
| Expected notifications | `outError(SequenceError)` message `'Too many matching values'` |
| Expected lifecycle observations | `unsubSrc` on the second next, before source complete. `1` is not emitted |
| Distinguishing suffix | A source complete after this error is silent (T15), not a second terminal |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T09 |
| Starting state | `s_empty` |
| Reset/fixture | Predicate throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. This is a callback throw, not `sourceError` |
| Distinguishing suffix | Complete handler does not run, so no `NotFoundError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T10 |
| Starting state | `s_held('a')` |
| Reset/fixture | One match stored |
| State-reaching prefix | `subscribe`, one match |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. `'a'` is not nexted |
| Distinguishing suffix | Contrast T11 |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T12 |
| Starting state | `s_empty` |
| Reset/fixture | Empty source. Predicate present or absent |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outError(EmptyError)` message `'no elements in sequence'` |
| Expected lifecycle observations | `unsubSrc`. Allocated now |
| Distinguishing suffix | The `@throws` JSDoc for `NotFoundError` (`single.ts` lines 80-81) describes this situation incorrectly; the code uses `EmptyError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E08

| Field | Value |
| --- | --- |
| Test ID | E08 |
| Covered row IDs | T14 |
| Starting state | `s_held(1)` |
| Reset/fixture | One match stored |
| State-reaching prefix | `subscribe`, one match |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outNext(1)` and no `outComplete` |
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

Denominator = 15. Specified 15/15. Executed 0/15.

Residual risk: the post-`error` assignments on lines 106-107 are specified as unobservable and were not executed. Predicate index values are specified and not asserted by a scenario. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The four locals and the complete handler's three-way branch are the whole contract, plus an eager `SequenceError` on the second match.

Known implementation limitations: `SequenceError` does not return before the following assignments; stopping comes from `subscriber.error`. `seenValue` is set even when the predicate throws. Without a predicate, `index` does not increment. No default-value parameter exists in this file.

Differences between intended contract and version characterization: The prose at lines 19-27 matches the three errors. The `@throws` tag for `NotFoundError` (lines 80-81) says it is delivered when the source completes before any `next`. The code delivers `EmptyError` in that case and `NotFoundError` only when at least one next was seen and none matched (line 115). The example comments at lines 59 and 72 match the implementation strings.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
