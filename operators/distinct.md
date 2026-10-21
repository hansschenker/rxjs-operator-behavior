# `distinct`

`distinct` emits a source value when its key has not been seen, then records the key in a host `Set` (`distinct.ts` lines 64-79). A later value with a key already in the set is dropped. An optional `flushes` input clears the set on each of its `next`s and does not itself emit. Flush `complete` does not clear, does not error, and does not complete the output. Flush `error` is forwarded. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `distinct` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/distinct.ts` lines 64-79 |
| Helpers read | `innerFrom.ts` lines 16-41; `OperatorSubscriber.ts` lines 67-100; `noop.ts` line 2; `lift.ts` lines 22-27; `Subscription.ts` lines 116-135 |
| Shape | Full operator via `operate` |
| Parameters | Optional `keySelector(value)`; optional `flushes: ObservableInput` |
| Output | First source value for each key, in source order |
| Model kind | Symbolic (set of keys; SameValueZero). Extended by flush-subscribe ordering |
| Scheduler | None |
| Introduced errors | `keySelector` throw is `outError`. Invalid `flushes` can throw `TypeError` from `innerFrom` after `source.subscribe` has already run |
| Upstream | Source is subscribed first (line 67). `flushes` is subscribed second only when `flushes` is truthy (line 77) |
| Inners | Zero or one flush subscription |
| Per-subscription state | `distinctKeys` `Set`, created in init (line 66) |
| Exclusions | No reentrant callback. The key is `add`ed before `subscriber.next` (lines 71-72); reentry that could observe that order is excluded, but the order is still an obligation. Teardown throws out of scope. The set is not cleared on unsubscribe (no `onFinalize`). A synchronous source that completes or errors before line 77 runs to quiescence first; a later invalid `flushes` throw hits `operate`'s `this.error` on an already stopped subscriber and is not a second terminal. Ordinary model: `flushes` is either absent or a valid `ObservableInput` that does not have to be synchronous, and the source does not synchronously terminate before the flush subscription is installed. Synchronous flush versus synchronous source is still specified as subscribe order. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_src(K), s_both(K), s_completed, s_errored, s_cancelled }
     K is a finite set of symbolic keys
Σ  = { subscribe(syncFlush),
       sourceNext(v, keyOutcome),
       sourceError(e), sourceComplete, cancel,
       flushNext, flushComplete, flushError(e) }
     keyOutcome ∈ { key(k), throw(err) }
     Without a keySelector, keyOutcome is always key(v).
     syncFlush ∈ { absent, quiet, invalid }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

Key equality is the host `Set`: SameValueZero. `NaN` matches `NaN`. `+0` matches `-0`. Objects match by reference. There is no `===` comparator in this file.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_src(K)` | Source subscribed, no flush subscription, key set `K` | No |
| `s_both(K)` | Source and flushes both subscribed, key set `K` | No |
| `s_completed` | Source complete delivered | Yes |
| `s_errored` | Source error, flush error, or `keySelector` throw | Yes |
| `s_cancelled` | Cancelled. Set not explicitly cleared | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | Source first, then maybe `innerFrom(flushes)` (lines 67-77) |
| Source next | Yes | Key selection, `Set.has`, maybe `add` and `next` (lines 68-74) |
| Source error | Yes | Default forward. Also unsubscribes a live flush child |
| Source completion | Yes | Default forward. Does not emit stored keys again |
| Cancellation cancel | Yes | Unsubscribes source and flush. Does not complete. Does not `clear()` |
| Inner notifications | Yes | Flush `next` calls `distinctKeys.clear()` (line 77). Flush `complete` is `noop`. Flush `error` uses the default error path |
| Time | No | No clock |
| User callback outcomes | Yes | Only `keySelector`, when provided. Throw happens before `has` / `add`. Absent selector uses the value itself |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc | subFlush | unsubFlush
record        ::= (notifications in order, lifecycle in order)
```

Flush `next` has empty notifications. The set update is state, not output.

## C. Transition obligations

`K` does not contain `k` and `K` does contain `k` are mutually exclusive under SameValueZero.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe(absent)` | `flushes` is falsy (`undefined`, `null`, `0`, `false`, `''`) | ε | `subSrc` | `s_src(∅)` | None | No flush line | E01 |
| T02 | `s_idle` | `subscribe(quiet)` | `flushes` truthy, valid, no synchronous terminal | ε | `subSrc`, `subFlush` | `s_both(∅)` | Source subscribe returns while the destination is open | A later flush next can clear keys | E02 |
| T03 | `s_idle` | `subscribe(invalid)` | `flushes` truthy and `innerFrom` throws `TypeError` before the destination is stopped | `outError(TypeError)` | `subSrc`, `unsubSrc` | `s_errored` | Source subscription was attempted first (line 67 before 77) | If the source synchronously nexted during that subscribe, those nexts were already processed against `K` before the throw | E03 |
| T04 | `s_idle` | source or flush signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T05 | `s_src(K)` or `s_both(K)` | `sourceNext(v, key(k))` | `k` not in `K` | `outNext(v)` | ε | same control state with `K ∪ {k}` | Subscribed | `add` happens before `outNext`. Payload is `v`, not `k` | E01 |
| T06 | `s_src(K)` or `s_both(K)` | `sourceNext(v, key(k))` | `k` in `K` | ε | ε | unchanged | Key already recorded | `v` is not emitted later unless a flush removes `k` first | E01 |
| T07 | `s_src(K)` or `s_both(K)` | `sourceNext(v, throw(err))` | `keySelector` throws | `outError(err)` | `unsubSrc`, and `unsubFlush` if present | `s_errored` | Selector present | `K` unchanged by this value. Not a source error | E04 |
| T08 | `s_both(K)` | `flushNext` | Any flush payload, ignored | ε | ε | `s_both(∅)` | Flush subscribed | Previously seen keys can pass again. Nothing is emitted by the flush | E02 |
| T09 | `s_both(K)` | `flushComplete` | None | ε | `unsubFlush` | `s_src(K)` | Flush subscribed | Set is not cleared. Output does not complete | E05 |
| T10 | `s_both(K)` | `flushError(e)` | None | `outError(e)` | `unsubFlush`, `unsubSrc` | `s_errored` | Flush subscribed | Not a clear | E06 |
| T11 | `s_src(K)` or `s_both(K)` | `sourceError(e)` | Any `K` | `outError(e)` | `unsubSrc`, and `unsubFlush` if present | `s_errored` | Any keys | Seen values are not replayed | — |
| T12 | `s_src(K)` or `s_both(K)` | `sourceComplete` | Any `K` | `outComplete` | `unsubSrc`, and `unsubFlush` if present | `s_completed` | Any keys | Set is not emitted | E01 |
| T13 | `s_src(K)` or `s_both(K)` | `cancel` | Any `K` | ε | `unsubSrc`, and `unsubFlush` if present | `s_cancelled` | Any keys | No `clear()` call and no complete | E07 |
| T14 | `s_src(K)` | `flushNext` / `flushComplete` / `flushError` | No flush subscription | ε | ε | `s_src(K)` | Inapplicable | — | — |
| T15 | terminal states | any further signal or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention. A flush error after a synchronous source terminal is this row, not a second `outError` | — |

T05 and T06 partition successful key outcomes. T01-T03 partition subscribe for the ordinary flush cases. A synchronous flush `next` during `subFlush` is T08 applied before `subscribe` returns, after any synchronous source prefix from T02's `subSrc`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | First value for each key, source order, original value not the key. E01 |
| At most one terminal | Yes | Source complete, source error, flush error, or selector throw |
| No downstream after terminal | Yes | T15 |
| Cancellation does not synthesize completion | Yes | T13, E07 |
| Upstream / inner lifetime | Yes | Source always subscribed on the operate path. Flush only if truthy, and only after the source line. Flush complete drops only the flush |
| Cleanup once | Yes | No `onFinalize`. The `Set` is not cleared on teardown; it becomes garbage with the closure. JSDoc lines 17-19 discuss long-lived memory, which this missing clear does not solve by itself |
| Per-subscription state | Yes | `new Set()` inside `operate` (line 66) |
| Empty source | Yes | `outComplete` from an empty set. No next |
| Source error | Yes | Forwarded. Distinct from flush error and from selector throw |
| Silence | Yes | A live source that only repeats recorded keys emits nothing further until a flush or a new key |
| Pending value or buffer on terminal | No | Keys are not a queue of values. Complete does not flush unseen duplicates |
| Callback throws / reenters / cancels | Selector throw yes (T07). Reentry excluded | No selector: no callback |
| Equal-time ordering and timer cancellation | Ordering yes, timers no | Source subscription is before flush subscription (lines 67 and 77). No clock. A synchronous source prefix is distinct before any synchronous flush clear |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T05, T06, T12 |
| Starting state | `s_idle` |
| Reset/fixture | No `keySelector`, no `flushes`. Values `1, 1, 2` |
| State-reaching prefix | `subscribe(absent)` → `s_src(∅)` |
| Target event | `sourceNext(1, key(1))`, `sourceNext(1, key(1))`, `sourceNext(2, key(2))`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `subSrc` only. Second `1` dropped by `Set.has` |
| Distinguishing suffix | Contrast `distinctUntilChanged`, which would also drop the adjacent `1` but would emit a later `1` after `2` without a flush |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T02, T05, T06, T08, T05 |
| Starting state | `s_idle` |
| Reset/fixture | No selector. `flushes` quiet during subscribe |
| State-reaching prefix | `subscribe(quiet)` → `s_both(∅)` |
| Target event | `sourceNext('a', key('a'))`, `sourceNext('a', key('a'))`, `flushNext`, `sourceNext('a', key('a'))` |
| Expected notifications | `outNext('a')`, `outNext('a')` |
| Expected lifecycle observations | `subSrc`, `subFlush`. Flush emits nothing. Set is empty after `flushNext` |
| Distinguishing suffix | Without the flush, the third `'a'` would be T06 |
| Expected final state | `s_both({'a'})` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03 |
| Starting state | `s_idle` |
| Reset/fixture | `flushes` is not an `ObservableInput`. Source does not synchronously terminate |
| State-reaching prefix | None |
| Target event | `subscribe(invalid)` |
| Expected notifications | `outError(TypeError)` |
| Expected lifecycle observations | `subSrc` happens before `innerFrom` throws. Then `unsubSrc`. No `subFlush` |
| Distinguishing suffix | If the source had synchronously completed first, this `TypeError` would be a stopped notification (T15), not a second terminal |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T07 |
| Starting state | `s_both(∅)` or `s_src(∅)` |
| Reset/fixture | `keySelector` throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | Source unsubscribed. Key not added |
| Distinguishing suffix | Not `sourceError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T05, T09, T06 |
| Starting state | `s_both({'a'})` |
| Reset/fixture | `'a'` already emitted. Flush then completes |
| State-reaching prefix | `subscribe(quiet)`, one new key |
| Target event | `flushComplete`, then `sourceNext('a', key('a'))` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubFlush`. Set still contains `'a'`, so the later next is a duplicate |
| Distinguishing suffix | Contrast T08, which would have cleared the set. Output is still open (`s_src`) |
| Expected final state | `s_src({'a'})` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T10 |
| Starting state | `s_both(K)` |
| Reset/fixture | Flush subscribed |
| State-reaching prefix | `subscribe(quiet)` |
| Target event | `flushError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubFlush`, `unsubSrc`. Set not emitted |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T13 |
| Starting state | `s_src({1})` |
| Reset/fixture | One key recorded |
| State-reaching prefix | `subscribe(absent)`, one new value |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc`. No `clear()` in the source |
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

Denominator = 15. Specified 15/15. Executed 0/15.

Residual risk: SameValueZero for `NaN` is specified and not scenario-listed. The synchronous-source-then-invalid-flush race is only a note on T03/T15. T11 has no dedicated scenario. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The set update, the optional flush subscriber, and the `noop` flush complete are all in lines 66-77. Flush next, flush complete, and flush error are different inputs.

Known implementation limitations: Equality is `Set`, not a user comparator and not `===`. The implementation does not contain the array-backed set described in the JSDoc. The set is not cleared on cancel, error, or complete. `flushes` is subscribed after the source, so a synchronous source runs first. A falsy `flushes` skips the inner subscription. `keySelector` throw does not record a key.

Differences between intended contract and version characterization: JSDoc lines 14-16 say other runtimes use a minimal array `Set`. The 7.8.2 body is only `new Set()` (line 66). JSDoc lines 17-19 correctly warn about retained keys and describe `flushes` as clearing the set; they do not say that flush `complete` leaves the set intact or that flush `error` fails the output. Those are source facts at line 77.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
