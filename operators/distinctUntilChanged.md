# `distinctUntilChanged`

`distinctUntilChanged` emits the first source value and then emits a later value only when `comparator(previousKey, currentKey)` returns falsy (`distinctUntilChanged.ts` lines 139-178). The default comparator is `===` (`lines 180-182`), and `null` or `undefined` selects that default because the code uses `??` (lines 143-146). `keySelector` defaults to `identity` and runs on every value, including the first. State is updated before `next`. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `distinctUntilChanged` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/distinctUntilChanged.ts` lines 139-182 |
| Helpers read | `identity.ts` lines 43-45; `OperatorSubscriber.ts` lines 67-74; `Subscriber.ts` lines 81-130 |
| Shape | Full operator via `operate` |
| Parameters | Optional `comparator(previous, current)`; optional `keySelector(value)` defaulting to `identity` |
| Output | Source values that differ from the last emitted key |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None of its own. `keySelector` or `comparator` throws are `outError` |
| Upstream | One source subscription |
| Inners | None |
| Per-subscription state | `previousKey` and `first` (lines 151-153) |
| Exclusions | No reentrant callback. Lines 164-173 update `first` and `previousKey` before `subscriber.next` because emission can reenter; that reentry is excluded, and the update-before-emit order remains mandatory. Teardown throws out of scope. Downstream observer throws are not `outError`. A non-function comparator other than `null`/`undefined` is outside the ordinary domain (`??` will not replace it). |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_fresh, s_held(previousKey), s_completed, s_errored, s_cancelled }
Σ  = { subscribe, sourceNext(v, sel, cmp), sourceError(e), sourceComplete, cancel }
     sel ∈ { key(k), throw(err) }
     cmp ∈ { same, different, throw(err), notCalled }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

`cmp = notCalled` is mandatory on the first successful selection, because `first || !comparator(...)` does not call the comparator when `first` is true (line 163). `same` means the comparator returned truthy. `different` means it returned falsy. Default `===` makes `NaN` different from `NaN`, and `+0` the same as `-0`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_fresh` | Subscribed, no value emitted, `first === true` | No |
| `s_held(previousKey)` | At least one value emitted. `previousKey` is the key stored before that `next` | No |
| `s_completed` | Source complete forwarded | Yes |
| `s_errored` | Selector throw, comparator throw, or source error | Yes |
| `s_cancelled` | Cancelled with no terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 155-176. Comparator normalization happens when the operator function is called, before subscribe (lines 146) |
| Source next | Yes | Always runs `keySelector` (line 158), then maybe the comparator |
| Source error | Yes | Default forward. No replay of `previousKey` |
| Source completion | Yes | Default forward |
| Cancellation cancel | Yes | Does not emit a held value and does not complete |
| Inner notifications | No | No flush notifier in this operator |
| Time | No | No clock |
| User callback outcomes | Yes | `keySelector` throw or key. On later values, comparator same, different, or throw. Comparator is not called for the first value |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

The emitted item is the source value, not the key (`distinctUntilChanged.ts` line 173).

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Selector and comparator callable as specified | ε | `subSrc` | `s_fresh` | `comparator ?? defaultCompare` already applied | First next does not call the comparator | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_fresh` | `sourceNext(v, key(k), notCalled)` | `keySelector` returns `k` | `outNext(v)` | ε | `s_held(k)` | `first === true` | `first` is set false and `previousKey = k` before `outNext` (lines 169-173) | E01 |
| T04 | `s_fresh` or `s_held(p)` | `sourceNext(v, throw(err), _)` | `keySelector` throws | `outError(err)` | `unsubSrc` | `s_errored` | Any open state | `previousKey` unchanged. No `outNext` | E02 |
| T05 | `s_held(p)` | `sourceNext(v, key(k), different)` | Comparator returns falsy for `(p, k)` | `outNext(v)` | ε | `s_held(k)` | A key is held | Store `k` before emit. `p` is not the payload | E01 |
| T06 | `s_held(p)` | `sourceNext(v, key(k), same)` | Comparator returns truthy for `(p, k)` | ε | ε | `s_held(p)` | A key is held | `p` stays. `v` is dropped | E03 |
| T07 | `s_held(p)` | `sourceNext(v, key(k), throw(err))` | Comparator throws | `outError(err)` | `unsubSrc` | `s_errored` | A key is held | `previousKey` not replaced. Not a source error | E04 |
| T08 | `s_fresh` or `s_held(p)` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | Open | Held key is not emitted again | E05 |
| T09 | `s_fresh` or `s_held(p)` | `sourceComplete` | Any | `outComplete` | `unsubSrc` | `s_completed` | Open | No extra value | E03 |
| T10 | `s_fresh` or `s_held(p)` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | Open | No complete | E06 |
| T11 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03 is the only first-value success. T05-T07 partition later successful selections by comparator outcome. T04 covers selector failure in both open states.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Emitted values are a subsequence of the source, original values, decided by keys. E01, E03 |
| At most one terminal | Yes | Source complete, source error, or one callback throw |
| No downstream after terminal | Yes | T11 |
| Cancellation does not synthesize completion | Yes | T10, E06 |
| Upstream / inner lifetime | Yes | One source until terminal or cancel. No inner |
| Cleanup once | Yes | No `onFinalize` |
| Per-subscription state | Yes | `first` and `previousKey` are init locals (lines 151-153) |
| Empty source | Yes | `sourceComplete` from `s_fresh` is `outComplete` only |
| Source error | Yes | Forwarded. E05 |
| Silence | Yes | After the first value, a source that stays `same` emits nothing further until it terminates or a different key arrives |
| Pending value or buffer on terminal | No | Suppressed values are not stored for complete. Only the last emitted key is stored, and it is not re-emitted |
| Callback throws / reenters / cancels | Selector and comparator throws yes. Reentry excluded | First value does not call the comparator. Update-before-emit is lines 164-173 |
| Equal-time ordering and timer cancellation | No | No second stream and no timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T05 |
| Starting state | `s_idle` |
| Reset/fixture | Default comparator and default `identity` selector. Values `1, 2` |
| State-reaching prefix | `subscribe` → `s_fresh` |
| Target event | `sourceNext(1, key(1), notCalled)`, `sourceNext(2, key(2), different)` |
| Expected notifications | `outNext(1)`, `outNext(2)` |
| Expected lifecycle observations | Comparator not used for `1`. For `2`, `===` is false. `previousKey` is `1` before `outNext(1)` returns |
| Distinguishing suffix | A following `2` would be T06 and would not emit |
| Expected final state | `s_held(2)` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T04 |
| Starting state | `s_fresh` |
| Reset/fixture | `keySelector` throws `err` on the first value |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err), _)` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. `first` remains true only as a dead local |
| Distinguishing suffix | No `outNext`. Not `sourceError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T06, T09 |
| Starting state | `s_held(1)` |
| Reset/fixture | Default `===`. Next value is also `1`, then complete |
| State-reaching prefix | `subscribe`, `sourceNext(1)` |
| Target event | `sourceNext(1, key(1), same)`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | The second `1` is suppressed. `previousKey` stays `1` |
| Distinguishing suffix | `distinct` would also suppress this adjacent duplicate, but a later non-adjacent `1` after another number would still be suppressed by `distinct` and not by this operator |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T07 |
| Starting state | `s_held(p)` |
| Reset/fixture | Comparator throws `err` when called with `(p, k)` |
| State-reaching prefix | `subscribe`, one successful first value |
| Target event | `sourceNext(v, key(k), throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. `previousKey` remains `p` |
| Distinguishing suffix | The first value was already emitted. This throw is not a source error |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_held(1)` |
| Reset/fixture | One value already emitted |
| State-reaching prefix | `subscribe`, one next |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | `1` is not repeated |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T10 |
| Starting state | `s_fresh` |
| Reset/fixture | Subscribed, nothing emitted |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete`. The first value is not synthesized |
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

Denominator = 11. Specified 11/11. Executed 0/11.

Residual risk: `NaN !== NaN` under the default comparator means consecutive `NaN`s take T05, not T06. That is specified and not scenario-listed. `comparator = null` is specified as the default via `??` and not executed. Reentry after the state write is excluded.

## G. Review decision

Decision: accept with documented limits

Reason: The first-value short-circuit, the `!comparator` test, and the update-before-emit assignments are a complete policy for source nexts. Terminals are the default subscriber paths.

Known implementation limitations: Comparator truthy means "suppress". Default equality is `===`, so `NaN` is never the same as `NaN`. `keySelector` runs on the first value even though the comparator does not. `null` and `undefined` comparators become `===`; other falsy comparators do not. No flush stream.

Differences between intended contract and version characterization: The long JSDoc (lines 17-34) matches first-value emission, key selection, and inequality emission. The comment at lines 143-146 documents `null` as an accepted comparator, which `??` implements. No contradicting branch was found. `distinctUntilKeyChanged` does not use this function's `keySelector` parameter; that is specified in that file, not as a bug here.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
