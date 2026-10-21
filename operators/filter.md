# `filter`

`filter` is a full operator (not a wrapper) pinned to RxJS 7.8.2. It subscribes to the source and forwards a `next` only when the user predicate returns a truthy value for that emission; source `error` and `complete` are forwarded unchanged. Overloads that take `thisArg` are marked `@deprecated` (removed in v8); the implementation still applies `thisArg` via `Function.prototype.call`.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `filter` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/filter.ts` lines 61-75 (deprecated `thisArg` overload notes at lines 5 and 9) |
| Helpers read | `src/internal/operators/OperatorSubscriber.ts` lines 15-23 and 67-74; `src/internal/util/lift.ts` lines 17-31; `src/internal/Subscriber.ts` lines 67-130 |
| Shape | Full operator via `operate` |
| Parameters | `predicate(value, index)`; optional `thisArg` (deprecated overloads) |
| Output | Same value references the predicate accepts; no projection |
| Model kind | Symbolic (JS values and a per-subscription integer index; not a finite alphabet) |
| Scheduler | None |
| Introduced errors | None of its own. A throw inside `predicate` is a callback failure delivered as `outError` |
| Upstream | Exactly one source subscription per outer subscription |
| Inners | None |
| Per-subscription state | `index`, starting at 0 (`filter.ts` lines 64-72) |
| Exclusions | Each input is processed to quiescence before the next. A downstream `next`/`error`/`complete` or the predicate must not synchronously reenter this operator (no reentrant source notification, inner signal, or cancel). Teardown throws are out of scope. Downstream observer `next` throws are `ConsumerObserver` unhandled errors, not `outError`. Non-function `predicate` is outside the ordinary predicate domain (it throws when first called). Source is assumed to be a liftable RxJS `Observable`; otherwise `operate` throws `TypeError` at application time (`lift.ts` line 30) and no machine starts. The model does not claim RxJS rejects excluded inputs. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle,
       s_active(index) | index ∈ ℕ₀,
       s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e),
       sourceComplete,
       cancel }
     outcome ∈ { truthy, falsy, throw(err) }
     v, e, err range over symbolic JS values
Γ  = records (notifications, lifecycle) described below
δ, λ tabulated in section C
kind = symbolic
```

Quiescence assumption: one Σ element at a time. `outcome` is the synchronous predicate result while handling that `sourceNext`, not a later queued input. `sourceError` is only an upstream error notification. A predicate throw is `outcome = throw(err)`, never `sourceError`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Operator built, not subscribed. `s₀` | No |
| `s_active(index)` | Source subscribed. Next predicate index is `index` (0-based count of source `next`s already attempted) | No |
| `s_completed` | `outComplete` already delivered, or equivalent stop after complete | Yes |
| `s_errored` | `outError` already delivered | Yes |
| `s_cancelled` | Unsubscribed with no terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `operate` init subscribes to `source` (`filter.ts` lines 68-73) |
| Source next | Yes | Predicate and possible `subscriber.next` (`filter.ts` line 72) |
| Source error | Yes | No custom `onError`; `OperatorSubscriber` uses `Subscriber._error` and forwards |
| Source completion | Yes | No custom `onComplete`; default forward |
| Cancellation cancel | Yes | Unsubscribing the destination unsubscribes the source child. Not completion |
| Inner notifications | No | No `ObservableInput` notifier |
| Time | No | No scheduler and no timer |
| User callback outcomes | Yes | `predicate.call(thisArg, value, index++)` may return truthy, return falsy, or throw (`filter.ts` line 72; catch at `OperatorSubscriber.ts` lines 69-73) |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v)
                | outError(e)
                | outComplete
lifecycle     ::= ε
                | subSrc
                | unsubSrc
record        ::= (notifications in emission order, lifecycle in order)
```

`outNext(v)` is the same `v` just tested. At most one terminal notification appears in any record. `unsubSrc` is the source teardown caused by destination unsubscribe (error, complete, or cancel), not a second independent cleanup.

## C. Transition obligations

Index is incremented in the argument list (`index++`) before the predicate body runs. On a throw the new index is unobservable because the subscription is torn down. `this` inside the predicate is `thisArg` (`undefined` when omitted).

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` / consumer | Source is liftable | ε | `subSrc` | `s_active(0)` | None | A later passing `sourceNext` can emit | E01 |
| T02 | `s_idle` | `sourceNext` / `sourceError` / `sourceComplete` / `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable; not a legal trace | — |
| T03 | `s_active(index)` | `sourceNext(v, truthy)` / source | Predicate returns a truthy value for `(v, index)` | `outNext(v)` | ε | `s_active(index+1)` | `index` source nexts already presented to the predicate | A following falsy next emits nothing | E01, E02 |
| T04 | `s_active(index)` | `sourceNext(v, falsy)` / source | Predicate returns a falsy value | ε | ε | `s_active(index+1)` | Same | A later truthy next still emits; index counts the dropped value | E02 |
| T05 | `s_active(index)` | `sourceNext(v, throw(err))` / predicate | Predicate throws `err` | `outError(err)` | `unsubSrc` | `s_errored` | Same | No `outNext(v)`; not a source error | E03 |
| T06 | `s_active(index)` | `sourceError(e)` / source | None (any `index`) | `outError(e)` | `unsubSrc` | `s_errored` | Subscribed, not stopped | No predicate call on this input | E04 |
| T07 | `s_active(index)` | `sourceComplete` / source | None | `outComplete` | `unsubSrc` | `s_completed` | Subscribed, not stopped | No synthetic next | E05 |
| T08 | `s_active(index)` | `cancel` / consumer | None | ε | `unsubSrc` | `s_cancelled` | Subscribed, not stopped | No `outComplete` | E06 |
| T09 | `s_completed`, `s_errored`, or `s_cancelled` | `sourceNext` / `sourceError` / `sourceComplete` / `cancel` | Protocol-illegal after stop | ε | ε | unchanged | Already terminal | Silent by model convention, not a claim that late events are valid RxJS traces | — |

T03-T05 are mutually exclusive and cover every predicate outcome. T06-T08 cover the other active-state inputs. Truthiness is the implementation test (`&&`), not a strict `=== true` check (`filter.ts` line 72).

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Accepted values are forwarded in source order, unmodified (`filter.ts` line 72). Dropped values produce no `outNext`. E01, E02 |
| At most one terminal | Yes | `Subscriber.error` / `complete` set `isStopped` before the handler (`Subscriber.ts` lines 81-101). T05-T07 |
| No downstream after terminal | Yes | T09 silent. Stopped `next` does not call `_next` (`Subscriber.ts` lines 67-72) |
| Cancellation does not synthesize completion | Yes | T08 emits nothing. E06 |
| Upstream / inner lifetime | Yes | One `source.subscribe` in init; no inner. Unsubscribed when the destination unsubscribes |
| Cleanup once | Yes | No `onFinalize`. `Subscription.unsubscribe` is idempotent if already `closed` |
| Per-subscription state | Yes | `index` is a closure local created inside `operate` (`filter.ts` lines 64-64), not shared across subscribers |
| Empty source | Yes | `sourceComplete` from `s_active(0)` is `outComplete` only. E05 |
| Source error | Yes | Forwarded even if every prior value was dropped. E04 |
| Silence | Yes | A non-terminating source that only fails the predicate yields no output. Not an error |
| Pending value or buffer on terminal | No | Nothing is retained across notifications |
| Callback throws / reenters / cancels | Throws: yes, T05, E03. Reentry and cancel-from-callback: excluded | Throw path is `destination.error` from `OperatorSubscriber._next`, not `sourceError` |
| Equal-time ordering and timer cancellation | No | No second stream and no clock |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03 |
| Starting state | `s_idle` |
| Reset/fixture | `predicate = (v) => v > 0`, `thisArg` omitted, source not yet subscribed |
| State-reaching prefix | `subscribe` → `s_active(0)` |
| Target event | `sourceNext(1, truthy)` then `sourceNext(2, truthy)` |
| Expected notifications | `outNext(1)`, `outNext(2)` |
| Expected lifecycle observations | `subSrc` on subscribe; source still subscribed |
| Distinguishing suffix | `sourceComplete` → `outComplete` and `s_completed` (T07) |
| Expected final state | `s_active(2)` before the suffix; `s_completed` after it |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_active(0)` |
| Reset/fixture | `predicate = (_, i) => i % 2 === 0` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a', truthy)`, `sourceNext('b', falsy)`, `sourceNext('c', truthy)` |
| Expected notifications | `outNext('a')`, `outNext('c')` |
| Expected lifecycle observations | `subSrc` only; `'b'` still consumes an index |
| Distinguishing suffix | Another even-index value would emit; the dropped `'b'` is not replayed |
| Expected final state | `s_active(3)` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_active(0)` |
| Reset/fixture | Predicate throws `err` on the first call |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. No `outNext` |
| Distinguishing suffix | A later `sourceNext` or `sourceComplete` is protocol-illegal and silent (T09), so this is not `sourceError` followed by complete |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T04, T06 |
| Starting state | `s_active(0)` |
| Reset/fixture | Predicate returns false for `0` |
| State-reaching prefix | `subscribe`, `sourceNext(0, falsy)` → `s_active(1)` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. The earlier drop is not turned into a value or a different error |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T07 |
| Starting state | `s_active(0)` |
| Reset/fixture | Empty source |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `unsubSrc`. No `outNext` |
| Distinguishing suffix | No `EmptyError` (that is `first` / `throwIfEmpty`, not `filter`) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T08 |
| Starting state | `s_active(1)` |
| Reset/fixture | One value already dropped or passed |
| State-reaching prefix | `subscribe`, one `sourceNext` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` once |
| Distinguishing suffix | Source `sourceComplete` after cancel is not delivered (T09) |
| Expected final state | `s_cancelled` |
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

Denominator = 9 transition rows. Specified 9/9. Executed 0/9.

Residual risk: truthy non-booleans pass; strict-boolean callers can disagree. Reentrant `next` can observe a further index increment before the outer `&& subscriber.next` returns; excluded, so interleavings are untested. `thisArg` deprecation does not change 7.8.2 behavior. No integration run was performed.

## G. Review decision

Decision: accept with documented limits

Reason: The 7.8.2 body is a single `operate` subscription whose only value policy is `predicate.call(thisArg, value, index++) && subscriber.next(value)`, with default error and complete forwarding. The symbolic machine matches that control flow under the stated quiescence exclusion.

Known implementation limitations: Selection is truthiness, not `=== true`. The index increments for failures and for throws. Deprecated `thisArg` overloads remain active. There is no `onFinalize`. A non-liftable source fails at `operate` application time, before `s₀` moves.

Differences between intended contract and version characterization: The narrative JSDoc describes a boolean predicate. The implementation forwards on any truthy return. Deprecated `thisArg` signatures are still implemented. No behavioral fork beyond that was found in this file.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
