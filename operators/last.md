# `last`

`last` is a thin composition. It pipes through an optional `filter`, then `takeLast(1)`, then `defaultIfEmpty` or `throwIfEmpty(() => new EmptyError())` (`last.ts` lines 80-91). Unlike `first`, it does not unsubscribe when a match appears. The selected value is the last one that passed, and it is emitted only when the source completes. `EmptyError` is created at that empty complete, not at subscribe time. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `last` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/last.ts` lines 80-91 |
| Helpers read | `filter.ts` lines 61-74; `takeLast.ts` lines 45-80; `throwIfEmpty.ts` lines 42-60; `defaultIfEmpty.ts` lines 40-59; `identity.ts` lines 43-45; `EmptyError.ts` lines 23-30 |
| Shape | Thin wrapper: `filter` or `identity`, then `takeLast(1)`, then `defaultIfEmpty` or `throwIfEmpty` |
| Parameters | Optional `predicate(value, index, source)`; default detected by `arguments.length >= 2` |
| Output | The last selected value, or one default, or `EmptyError` |
| Model kind | Symbolic (one pending slot) |
| Scheduler | None |
| Introduced errors | `EmptyError` (`message` `'no elements in sequence'`) constructed in the valueless complete path |
| Upstream | One source subscription held until the source terminates, errors, or the consumer cancels. A match does not unsubscribe |
| Inners | None |
| Per-subscription state | Optional filter index; `takeLast(1)` buffer of length at most 1; downstream `hasValue` |
| Exclusions | No reentrant callback. Falsy `predicate` selects `identity` (`last.ts` line 87). Explicit `undefined` default counts (`arguments.length >= 2`). `takeLast` does not emit on source error, so a pending last value is discarded. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_none, s_held(v), s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e), sourceComplete, cancel }
     outcome ∈ { selected, rejected, throw(err) }
     With no predicate, every next is selected.
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
mode default ∈ { absent, present(d) }
```

`s_none`: subscribed, no selected value yet. `s_held(v)`: `takeLast(1)` currently stores `v` as the latest selection. Rejected nexts do not enter the `takeLast` buffer.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_none` | Subscribed, nothing selected | No |
| `s_held(v)` | Subscribed, `v` is the latest selection, not yet emitted | No |
| `s_completed` | Held value or default emitted, then complete | Yes |
| `s_errored` | Source error, predicate throw, or `EmptyError` | Yes |
| `s_cancelled` | Cancelled. Held value not emitted | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `takeLast(1)` uses the operate branch (`1 <= 0` is false) and subscribes (`takeLast.ts` lines 46-54) |
| Source next | Yes | Predicate may reject, throw, or replace the single held value. No downstream next yet |
| Source error | Yes | `takeLast` forwards `error` without flushing (`takeLast.ts` lines 72-73). Pending `v` is dropped |
| Source completion | Yes | `takeLast` flushes the one held value if any, then `throwIfEmpty` or `defaultIfEmpty` sees whether a next happened |
| Cancellation cancel | Yes | `takeLast` `onFinalize` drops the buffer and does not emit (`takeLast.ts` lines 74-77) |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Predicate throw is `outError` from `filter`. No user factory; `() => new EmptyError()` is library code and runs only on valueless complete |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v) then outComplete
                | outNext(d) then outComplete
                | outError(e)
lifecycle     ::= ε | subSrc | unsubSrc | releaseBuffer
record        ::= (notifications in order, lifecycle in order)
```

No `outNext` appears before `sourceComplete` on the success paths.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_none` | Mode fixed | No emission | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_none` | `sourceNext(v, rejected)` | Predicate returns falsy | ε | ε | `s_none` | Nothing held | `v` will not be emitted on complete | E02 |
| T04 | `s_none` | `sourceNext(v, selected)` | No predicate, or predicate truthy | ε | ε | `s_held(v)` | Nothing held | Still no `outNext` | E01 |
| T05 | `s_held(w)` | `sourceNext(v, rejected)` | Predicate returns falsy | ε | ε | `s_held(w)` | `w` still the last selection | `w` is kept | E02 |
| T06 | `s_held(w)` | `sourceNext(v, selected)` | Selected | ε | ε | `s_held(v)` | A previous selection existed | `w` is discarded and never emitted | E02 |
| T07 | `s_none` or `s_held(w)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | Predicate installed | Held `w`, if any, is not emitted | E03 |
| T08 | `s_none` or `s_held(w)` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc`, `releaseBuffer` | `s_errored` | May be holding `w` | `w` is not emitted. Not `EmptyError` | E04 |
| T09 | `s_held(v)` | `sourceComplete` | A selection exists. Default mode ignored | `outNext(v)`, `outComplete` | `unsubSrc`, `releaseBuffer` | `s_completed` | `takeLast(1)` flushes one value (`takeLast.ts` lines 64-70), so `hasValue` is true | Default is not appended | E01 |
| T10 | `s_none` | `sourceComplete` | `default` absent | `outError(new EmptyError())` | `unsubSrc` | `s_errored` | No selection. `arguments.length < 2` | Factory runs in this transition | E05 |
| T11 | `s_none` | `sourceComplete` | `default` present as `d` | `outNext(d)`, `outComplete` | `unsubSrc` | `s_completed` | `arguments.length >= 2` | Includes `d === undefined` | E06 |
| T12 | `s_none` or `s_held(w)` | `cancel` | Any | ε | `unsubSrc`, `releaseBuffer` if a buffer exists | `s_cancelled` | May be holding `w` | `w` is not emitted. No complete | E07 |
| T13 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03 is inapplicable without a predicate. T05 is inapplicable without a predicate. T04 then T06 is how "no predicate" updates the held last value: every next is selected.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Zero or one next, and it is the last selection or the default, only after source complete. E01, E02 |
| At most one terminal | Yes | Flush complete, default complete, `EmptyError`, predicate throw, or source error |
| No downstream after terminal | Yes | T13 |
| Cancellation does not synthesize completion | Yes | T12, E07. The held value is not flushed |
| Upstream / inner lifetime | Yes | Source stays subscribed across selections. No inner. Differs from `first`/`take(1)` |
| Cleanup once | Yes | `takeLast` `onFinalize` clears the one-slot buffer on unsubscribe |
| Per-subscription state | Yes | Buffer is per `takeLast` subscription |
| Empty source | Yes | T10 or T11 from `s_none`. E05, E06 |
| Source error | Yes | Pending last value discarded. E04 |
| Silence | Yes | Source that never completes: stay in `s_none` or `s_held`, no output. Same warning as `takeLast` |
| Pending value or buffer on terminal | Yes | The pending slot is emitted only on `sourceComplete`. Dropped on error and cancel |
| Callback throws / reenters / cancels | Throws yes (T07). Reentry excluded | Index still counts rejected source values |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T04, T09 |
| Starting state | `s_idle` |
| Reset/fixture | `last()` with no predicate and no default |
| State-reaching prefix | `subscribe` → `s_none` |
| Target event | `sourceNext(1, selected)`, `sourceNext(2, selected)`, `sourceComplete` |
| Expected notifications | `outNext(2)`, `outComplete` |
| Expected lifecycle observations | No `outNext` before complete. `unsubSrc` on complete. `1` was held and then replaced |
| Distinguishing suffix | Contrast `first()`, which would have emitted `1` and unsubscribed before `2` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04, T05, T06, T09 |
| Starting state | `s_none` |
| Reset/fixture | `predicate = (v) => v % 2 === 0` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(1, rejected)`, `sourceNext(2, selected)`, `sourceNext(3, rejected)`, `sourceNext(4, selected)`, `sourceComplete` |
| Expected notifications | `outNext(4)`, `outComplete` |
| Expected lifecycle observations | Source remained subscribed through every next. Predicate indexes are 0,1,2,3 |
| Distinguishing suffix | `2` is not emitted |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T07 |
| Starting state | `s_held('a')` |
| Reset/fixture | Predicate throws `err` on the next value |
| State-reaching prefix | `subscribe`, one selected next |
| Target event | `sourceNext('b', throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. `'a'` is not emitted |
| Distinguishing suffix | Not `EmptyError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T08 |
| Starting state | `s_held(1)` |
| Reset/fixture | No default |
| State-reaching prefix | `subscribe`, one selected value |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | Buffer released. `1` is not an `outNext` |
| Distinguishing suffix | Contrast T09, which would have emitted `1` on complete |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T10 |
| Starting state | `s_none` |
| Reset/fixture | `last()` or `last(predicate)` with no second argument. Empty source, or only rejects |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outError(EmptyError)` allocated now, message `'no elements in sequence'` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | Not `outComplete`. `find` would next `undefined` instead |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T11 |
| Starting state | `s_none` |
| Reset/fixture | `last(null, 'missing')` (`null` predicate is falsy, so no filter; default is present) |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext('missing')`, `outComplete` |
| Expected lifecycle observations | `unsubSrc`. No `EmptyError` |
| Distinguishing suffix | A real source value would have been held and would replace this default (T09, not T11) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T12 |
| Starting state | `s_held(1)` |
| Reset/fixture | Any default mode |
| State-reaching prefix | `subscribe`, one selected next |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc`, buffer released |
| Distinguishing suffix | `1` is not emitted. No `outComplete` |
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

Denominator = 13. Specified 13/13. Executed 0/13.

Residual risk: `last(undefined, d)` versus `last(predicate, d)` both set the default bit; only the predicate's truthiness enables `filter`. That split is specified and not executed. Silence on a non-completing source is specified and easy to confuse with a hung test. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The file is the `takeLast(1)` analogue of `first`. Emission waits for source complete, and the empty policy runs only after `takeLast` flushes or completes empty.

Known implementation limitations: Source error drops the held value. Cancel drops it. Falsy predicates do not filter. `arguments.length >= 2` enables the default even when the default is `undefined`. The operator never unsubscribes early on a match.

Differences between intended contract and version characterization: JSDoc lines 30-32 and 70-78 match last-match, default, and `EmptyError`. They do not say that a source error suppresses a value already seen. That suppression is `takeLast`'s error path, which this composition does not override.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
