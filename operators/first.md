# `first`

`first` is a thin composition, not its own subscriber. In RxJS 7.8.2 it pipes the source through an optional `filter`, then `take(1)`, then either `defaultIfEmpty` or `throwIfEmpty(() => new EmptyError())` (`first.ts` lines 82-93). A match emits that value and completes, unsubscribing the source. If the source completes with no selected value, the error or the default is produced then, not at subscribe time. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `first` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/first.ts` lines 82-93 |
| Helpers read | `filter.ts` lines 61-74; `take.ts` lines 48-69; `throwIfEmpty.ts` lines 42-60; `defaultIfEmpty.ts` lines 40-59; `identity.ts` lines 43-45; `EmptyError.ts` lines 23-30 |
| Shape | Thin wrapper: `filter` or `identity`, then `take(1)`, then `defaultIfEmpty` or `throwIfEmpty` |
| Parameters | Optional `predicate(value, index, source)`; optional `defaultValue` detected by `arguments.length >= 2` |
| Output | The first selected source value, or the default, or `EmptyError` |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | `EmptyError` with `name = 'EmptyError'` and `message = 'no elements in sequence'`, constructed when `throwIfEmpty` handles a valueless complete (`throwIfEmpty.ts` line 52, factory at `first.ts` line 91) |
| Upstream | One source subscription. `take(1)` unsubscribes it when the first selected value is forwarded |
| Inners | None |
| Per-subscription state | Filter index if a predicate is used; `take`'s `seen`; `throwIfEmpty` / `defaultIfEmpty` `hasValue` |
| Exclusions | No reentrant callback. Falsy `predicate` (`undefined`, `null`, and any other falsy) selects the `identity` path because the test is `predicate ? filter(...) : identity` (line 89). Non-callable truthy predicates are outside the ordinary domain. `defaultValue === undefined` still counts as a default when it was passed (`arguments.length >= 2`). |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_seek, s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e), sourceComplete, cancel }
     outcome ∈ { selected, rejected, throw(err) }
     If no predicate is installed, every sourceNext is selected
     and rejected/throw are inapplicable.
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
mode default ∈ { absent, present(d) }, fixed when first(...) is called
```

`selected` means the value is forwarded by `filter` into `take(1)`, or there is no filter. The predicate, when present, is `predicate(v, i, source)` where `i` is the 0-based count of source nexts, including rejects (`filter.ts` line 72, `first.ts` line 89). `this` is not bound to a `thisArg`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_seek` | Subscribed. No selected value has been forwarded yet | No |
| `s_completed` | A selected value, or a default, has been followed by complete | Yes |
| `s_errored` | `EmptyError`, predicate throw, or source error already delivered | Yes |
| `s_cancelled` | Cancelled before a result | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | The composed operators subscribe. `take(1)` uses the positive-count path, so it does subscribe (`take.ts` lines 52-54) |
| Source next | Yes | Rejected values are dropped. The first selected value is emitted and completes |
| Source error | Yes | Forwarded by `filter`/`identity`, `take`, and `throwIfEmpty`/`defaultIfEmpty`. `EmptyError` is not substituted |
| Source completion | Yes | With no selected value: `take(1)` completes empty, then `throwIfEmpty` or `defaultIfEmpty` runs |
| Cancellation cancel | Yes | Unsubscribes upstream. Does not emit a default and does not raise `EmptyError` |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Only when a truthy predicate is installed. Throw becomes `outError` from `filter`'s `OperatorSubscriber` catch. The `EmptyError` factory runs later, on valueless complete, and is library code |

### Γ: output inventory

```text
notifications ::= ε
                | outNext(v) then outComplete
                | outNext(d) then outComplete
                | outError(e)
                | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

`outComplete` alone is not a normal `first` result: a selected value and a default both next-then-complete, and the no-default empty path errors. It is listed so a protocol-illegal trace is not required to invent it. The ordinary empty no-default record is `outError(EmptyError)` only.

## C. Transition obligations

`EmptyError` is constructed inside the complete handler, not when `first(...)` is called and not at `subscribe`.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Source liftable | ε | `subSrc` | `s_seek` | `default` mode and predicate presence already fixed | No emission yet | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_seek` | `sourceNext(v, rejected)` | Predicate installed and returns falsy | ε | ε | `s_seek` | No selection yet | This `v` is not the eventual default | E02 |
| T04 | `s_seek` | `sourceNext(v, selected)` | No predicate, or predicate returns truthy | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | No selection yet | `take(1)` completes on that forwarded next (`take.ts` lines 59-66). Default/`EmptyError` not used | E01 |
| T05 | `s_seek` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | Predicate installed | Not `EmptyError` | E03 |
| T06 | `s_seek` | `sourceError(e)` | Any mode | `outError(e)` | `unsubSrc` | `s_errored` | No selection yet | Not `EmptyError`, even if nothing was selected | E04 |
| T07 | `s_seek` | `sourceComplete` | No selection yet and `default` absent | `outError(new EmptyError())` | `unsubSrc` | `s_errored` | `arguments.length < 2` | Factory runs now (`first.ts` line 91, `throwIfEmpty.ts` line 52) | E05 |
| T08 | `s_seek` | `sourceComplete` | No selection yet and `default` present as `d` (including `undefined`) | `outNext(d)`, `outComplete` | `unsubSrc` | `s_completed` | `arguments.length >= 2` | `d` is not an `EmptyError` | E06 |
| T09 | `s_seek` | `cancel` | Any mode | ε | `unsubSrc` | `s_cancelled` | No selection yet | No default and no `EmptyError` | E07 |
| T10 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03 is inapplicable when no predicate is installed; every next is T04. T03 and T04 and T05 partition nexts when a predicate is installed. T07 and T08 partition valueless completion by `arguments.length`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | At most one value: the first selected source value, or `d`. E01, E06 |
| At most one terminal | Yes | Match completes. Empty path either errors or completes after the default. Source error is the only other terminal |
| No downstream after terminal | Yes | T10. `take(1)` has unsubscribed the source on T04 |
| Cancellation does not synthesize completion | Yes | T09, E07 |
| Upstream / inner lifetime | Yes | Subscribed until first match, source error, source complete, or cancel. No inner |
| Cleanup once | Yes | Inherited from `take` / `filter` / `throwIfEmpty`. No extra finalizer in `first.ts` |
| Per-subscription state | Yes | Composition closures are created per subscription by each operator's `operate` |
| Empty source | Yes | T07 or T08 from `s_seek`. E05, E06 |
| Source error | Yes | Forwarded unchanged. E04 |
| Silence | Yes | Predicate never matches and the source never terminates: no next, no `EmptyError` |
| Pending value or buffer on terminal | No | `first` does not hold a previous match. `take(1)` emits the match immediately rather than waiting |
| Callback throws / reenters / cancels | Throws yes when a predicate is present (T05). Reentry excluded | `EmptyError` factory is not the user's predicate. It runs on complete, and a throw from a replaced factory is not this file's factory |
| Equal-time ordering and timer cancellation | No | No timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T04 |
| Starting state | `s_idle` |
| Reset/fixture | `first()` with no predicate and no default |
| State-reaching prefix | `subscribe` → `s_seek` |
| Target event | `sourceNext('a', selected)`, with a later source value available only if still subscribed |
| Expected notifications | `outNext('a')`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` on that next via `take(1)` |
| Distinguishing suffix | The second source value is not emitted. This is not `find`, which would also complete but is specified to emit `undefined` on a miss |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_seek` |
| Reset/fixture | `predicate = (v) => v === 'b'` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a', rejected)`, `sourceNext('b', selected)` |
| Expected notifications | `outNext('b')`, `outComplete` |
| Expected lifecycle observations | `'a'` increments the filter index and is not output. `unsubSrc` on `'b'` |
| Distinguishing suffix | Index passed to the predicate for `'b'` is 1, not 0 |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_seek` |
| Reset/fixture | Predicate throws `err` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | `err` is not an `EmptyError` created by this operator |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06 |
| Starting state | `s_seek` |
| Reset/fixture | No default |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. `EmptyError` factory not called |
| Distinguishing suffix | Contrast E05 |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T03, T07 |
| Starting state | `s_seek` |
| Reset/fixture | `first(v => false)` so `arguments.length` is 1 |
| State-reaching prefix | `subscribe`, any number of rejected nexts including zero |
| Target event | `sourceComplete` |
| Expected notifications | `outError(EmptyError)` whose `message` is `'no elements in sequence'` |
| Expected lifecycle observations | `unsubSrc`. The `EmptyError` object is allocated in this transition |
| Distinguishing suffix | Not `outComplete`. Not the `find` sentinel `undefined` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T08 |
| Starting state | `s_seek` |
| Reset/fixture | `first(predicate, undefined)` so a default is present and `d` is `undefined` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outNext(undefined)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc`. No `EmptyError` |
| Distinguishing suffix | Contrast `first(predicate)` (E05). `arguments.length` decides, not the value `undefined` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T09 |
| Starting state | `s_seek` |
| Reset/fixture | Default present or absent |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No default next and no `EmptyError` |
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

Denominator = 10. Specified 10/10. Executed 0/10.

Residual risk: a truthy predicate that returns a non-boolean is selected by `filter`'s `&&`. `first(null)` is the no-predicate path because `null` is falsy. Neither was executed. Composition with a synchronous source that emits the match inside `subscribe` is the same T04 row, applied before `subscribe` returns.

## G. Review decision

Decision: accept with documented limits

Reason: `first.ts` only chooses `identity` versus `filter`, then `take(1)`, then one of the two empty policies. `EmptyError` is created by the factory passed to `throwIfEmpty`, which runs on complete.

Known implementation limitations: Default presence is `arguments.length >= 2`, so an explicit `undefined` default is emitted. A falsy predicate argument disables filtering. The predicate receives the outer `source` object and the unfiltered index. Match completes through `take(1)` and unsubscribes; it does not wait for the source.

Differences between intended contract and version characterization: The `@throws` note (`first.ts` lines 71-73) matches the no-default empty path and the contrast with `take(1)`, which would complete. The implementation also treats a passed `undefined` default as success, which the prose "if `defaultValue` was not provided" (`first.ts` line 38) matches only if "provided" means an argument was passed.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
