# `takeLast`

`takeLast` emits nothing until the source completes, then emits the retained suffix in arrival order and completes (`takeLast.ts` lines 45-80). `count <= 0` is `() => EMPTY`: immediate complete, source not subscribed. A source error or a cancel does not flush the buffer. There is no `@deprecated` tag. A source that never completes stays silent, as the JSDoc warns (lines 20-21).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `takeLast` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/takeLast.ts` lines 45-80 |
| Helpers read | `empty.ts` line 66; `OperatorSubscriber.ts` lines 76-110; `lift.ts` lines 17-31; `Subscriber.ts` lines 81-130 |
| Shape | Branch: `EMPTY` if `count <= 0`; otherwise `operate` |
| Parameters | `count` (JS number) |
| Output | At most the retained suffix, only on source complete |
| Model kind | Symbolic (buffer holds symbolic values; length is data) |
| Scheduler | None. `EMPTY` is synchronous |
| Introduced errors | None. Does not throw `ArgumentOutOfRangeError` |
| Upstream | No subscribe when `count <= 0`. Otherwise one source subscription until source terminal, error, or cancel. No early unsubscribe on a full buffer |
| Inners | None |
| Per-subscription state | `buffer` array (line 53), replaced with `null` in `onFinalize` (lines 74-77) |
| Exclusions | No reentrant callback during the complete-time flush. Teardown throws out of scope. Downstream observer throws are not `outError`. `onFinalize` runs only when unsubscribe observes `!closed` (`OperatorSubscriber.ts` lines 104-110). |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_buf(buffer), s_completed, s_errored, s_cancelled }
     buffer is a finite sequence of symbolic values
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
parameter count ∈ IEEE numbers, fixed
```

`NaN <= 0` is false, so `takeLast(NaN)` uses the buffer branch.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_buf(buffer)` | Source subscribed. `buffer` is the retained suffix so far | No |
| `s_completed` | Flush (possibly empty) and complete already delivered, or `EMPTY` completed | Yes |
| `s_errored` | Source error delivered, buffer not flushed | Yes |
| `s_cancelled` | Cancelled, buffer not flushed | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `count <= 0` → `EMPTY` without `source.subscribe` (lines 46-47). Else subscribe at lines 54-79 |
| Source next | Yes | `push`, then at most one `shift` if `count < buffer.length` (lines 57-62) |
| Source error | Yes | Custom handlers pass `undefined` for `onError` (line 73), so the default forward is used. Buffer is not emitted |
| Source completion | Yes | Custom `onComplete` nexts every retained value, then `subscriber.complete()` (lines 64-70) |
| Cancellation cancel | Yes | Does not run `onComplete`. `onFinalize` drops the array (lines 74-77) |
| Inner notifications | No | No notifier |
| Time | No | Waits for completion, not for a duration |
| User callback outcomes | No | No user callback |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v1), ..., outNext(vn), outComplete
                | outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc | releaseBuffer
record        ::= (notifications in order, lifecycle in order)
```

`n` may be 0, which is bare `outComplete`. `releaseBuffer` is `buffer = null` in `onFinalize`. On the complete path it runs as part of unsubscription after the flush notifications, because `subscriber.complete()` unsubscribes the destination, which unsubscribes this operator subscriber.

## C. Transition obligations

Buffer update on next: append `v`, then if `count < buffer.length` remove the oldest element once. That single `&&` is enough for one `push`. For a positive integer `N`, the retained sequence is the last `min(received, N)` values in order. For other JS numbers the same comparison is the rule: `+Infinity` and `NaN` never satisfy `count < length`, so the buffer keeps every value; `takeLast(0.5)` shifts back to empty on every next and still subscribes (`0.5 <= 0` is false).

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T02 | `s_idle` | `subscribe` | `count <= 0` | `outComplete` | ε | `s_completed` | None | No `subSrc` | E01 |
| T03 | `s_idle` | `subscribe` | `!(count <= 0)` | ε | `subSrc` | `s_buf([])` | None | No next until `sourceComplete` | E02 |
| T04 | `s_buf(b)` | `sourceNext(v)` | Let `b' = b` appended with `v`. Not `count < length(b')` | ε | ε | `s_buf(b')` | Source still open | Nothing is emitted yet | E02 |
| T05 | `s_buf(b)` | `sourceNext(v)` | `b'` as above and `count < length(b')` | ε | ε | `s_buf(tail(b'))` where `tail` drops the oldest | Source still open | The dropped oldest is not emitted later | E03 |
| T06 | `s_buf(b)` | `sourceComplete` | Any `b`, including empty | `outNext` for each element of `b` in order, then `outComplete` | `unsubSrc`, `releaseBuffer` | `s_completed` | Source completed | No extra value. Empty `b` is complete only | E02, E03 |
| T07 | `s_buf(b)` | `sourceError(e)` | Any `b` | `outError(e)` | `unsubSrc`, `releaseBuffer` | `s_errored` | Buffer may be non-empty | Buffer is not flushed before the error | E04 |
| T08 | `s_buf(b)` | `cancel` | Any `b` | ε | `unsubSrc`, `releaseBuffer` | `s_cancelled` | Buffer may be non-empty | No complete and no flush | E05 |
| T09 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T04 and T05 partition nexts. Flush order is the `for...of` order on lines 67-69, which is oldest retained value first.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Retained values emit on complete in arrival order, unmodified. E03 |
| At most one terminal | Yes | Complete flush, source error, or the `EMPTY` complete. Cancel is not a terminal notification |
| No downstream after terminal | Yes | T09. After `subscriber.complete()` the subscriber is stopped |
| Cancellation does not synthesize completion | Yes | T08, E05 |
| Upstream / inner lifetime | Yes | No early unsub when the buffer is full. No inner. T02 does not subscribe |
| Cleanup once | Yes | `onFinalize` runs when going from not-`closed` to unsubscribed (`OperatorSubscriber.ts` lines 104-110) |
| Per-subscription state | Yes | `buffer` is an init local |
| Empty source | Yes | T06 with `[]` → `outComplete` only. T02 is also complete-only but without `subSrc` |
| Source error | Yes | `outError` and the suffix is discarded. E04 |
| Silence | Yes | Non-terminating source: no next and no complete, buffer held. JSDoc lines 20-21 |
| Pending value or buffer on terminal | Yes | Pending suffix is emitted only on `sourceComplete`. It is dropped on error and cancel |
| Callback throws / reenters / cancels | No user callback. Reentry during flush excluded | A downstream `next` that unsubscribes mid-flush is not in the ordinary model |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T02 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 0` |
| State-reaching prefix | None |
| Target event | `subscribe` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | No `subSrc` |
| Distinguishing suffix | `takeLast(0.5)` does not use this row (`0.5 <= 0` is false) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04, T06 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 3`, source emits `1, 2` then completes |
| State-reaching prefix | `subscribe` → `s_buf([])` |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | No output before complete. `releaseBuffer` on the way out |
| Distinguishing suffix | Those nexts are absent if the target event is `sourceError` instead (E04) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T04, T05, T06 |
| Starting state | `s_buf([])` |
| Reset/fixture | `count = 2` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a')`, `sourceNext('b')`, `sourceNext('c')`, `sourceComplete` |
| Expected notifications | `outNext('b')`, `outNext('c')`, `outComplete` |
| Expected lifecycle observations | `'a'` shifted out when `'c'` arrives (`2 < 3`). Source stayed subscribed the whole time |
| Distinguishing suffix | `'a'` is not in the flush. This is not `skipLast`, which would have emitted `'a'` before complete |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T07 |
| Starting state | `s_buf(['a','b'])` |
| Reset/fixture | `count = 2`, buffer full |
| State-reaching prefix | `subscribe` and two nexts |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`, `releaseBuffer`. No `outNext` |
| Distinguishing suffix | Not a flush-then-error |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_buf(['a'])` |
| Reset/fixture | `count = 2` |
| State-reaching prefix | `subscribe`, `sourceNext('a')` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc`, `releaseBuffer` |
| Distinguishing suffix | `'a'` is not emitted. No `outComplete` |
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

Residual risk: unbounded buffers for `NaN` and `+Infinity` are specified by the comparison and not scenario-tested. Mid-flush reentry is excluded. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The file withholds every next until the custom complete handler, and `count <= 0` bypasses the source. Error and cancel share the non-flush policy via the absence of a flush outside `onComplete`.

Known implementation limitations: One `shift` per next, driven by `count < length`, not by `Math.floor` written in source. Non-positive `count` does not subscribe; fractional `count` in `(0, 1)` subscribes and retains nothing. `onFinalize` nulls the array on every unsubscribe that is not already closed. No `ArgumentOutOfRangeError`.

Differences between intended contract and version characterization: JSDoc lines 12-21 match the integer buffer and the never-completes warning. They do not mention the `EMPTY` shortcut or non-integer comparisons. `ArgumentOutOfRangeError.ts` `@see`s `takeLast`, but this file never builds that error.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
