# `skipWhile`

`skipWhile` is a full operator. It drops source values while the predicate returns truthy and, on the first falsy result, emits that value and every later value without calling the predicate again (`skipWhile.ts` lines 52-60). Source error and complete are forwarded in both phases. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `skipWhile` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/skipWhile.ts` lines 52-60 |
| Helpers read | `OperatorSubscriber.ts` lines 67-74; `lift.ts` lines 17-31; `Subscriber.ts` lines 67-130 |
| Shape | Full operator via `operate` |
| Parameters | `predicate(value, index)` |
| Output | The first value that fails the predicate, then the rest of the source |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | None. A predicate throw is `outError` |
| Upstream | One source subscription |
| Inners | None |
| Per-subscription state | `taking` (false), `index` (0) at lines 54-55 |
| Exclusions | No reentrant callback. Teardown throws out of scope. Downstream observer throws are not `outError`. Predicate is assumed callable. The short-circuit expression is one transition, not a separate callback input after the next. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle,
       s_skip(index),
       s_take,
       s_completed, s_errored, s_cancelled }
Σ  = { subscribe,
       sourceNext(v, outcome),
       sourceError(e), sourceComplete, cancel }
     outcome ∈ { truthy, falsy, throw(err) } while skipping;
     outcome is absent once taking, because the predicate is not called
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

The handler is `(taking || (taking = !predicate(value, index++))) && subscriber.next(value)` (`skipWhile.ts` line 57).

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_skip(index)` | `taking === false`. Next predicate index is `index` | No |
| `s_take` | `taking === true`. Predicate retired | No |
| `s_completed` | Complete delivered | Yes |
| `s_errored` | Error delivered | Yes |
| `s_cancelled` | Cancelled without a terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `source.subscribe` at lines 56-58 |
| Source next | Yes | Either skipped, or emitted as the hinge value, or mirrored |
| Source error | Yes | Default forward in both phases |
| Source completion | Yes | Default forward. No error if the predicate never became falsy |
| Cancellation cancel | Yes | Unsubscribes the source. Does not emit the skipped prefix |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | Only in `s_skip`. Truthy continues skipping, falsy starts taking and emits, throw is `outError`. In `s_take` the predicate is not called (`taking ||` short-circuit) |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | Callable predicate | ε | `subSrc` | `s_skip(0)` | None | Leading truthy values emit nothing | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_skip(i)` | `sourceNext(v, truthy)` | Predicate returns truthy for `(v, i)` | ε | ε | `s_skip(i+1)` | Still skipping | This `v` is not emitted when a later value fails | E01 |
| T04 | `s_skip(i)` | `sourceNext(v, falsy)` | Predicate returns falsy | `outNext(v)` | ε | `s_take` | Still skipping | Later nexts do not consult the predicate. The failing value itself is emitted | E01 |
| T05 | `s_skip(i)` | `sourceNext(v, throw(err))` | Predicate throws | `outError(err)` | `unsubSrc` | `s_errored` | `index++` has already been evaluated | No `outNext(v)`. `taking` stays false because the assignment does not finish | E02 |
| T06 | `s_skip(i)` | `sourceError(e)` | None | `outError(e)` | `unsubSrc` | `s_errored` | Skipping | Not a predicate failure | E03 |
| T07 | `s_skip(i)` | `sourceComplete` | None | `outComplete` | `unsubSrc` | `s_completed` | Skipping | No nexts if every value was skipped or none arrived | E04 |
| T08 | `s_skip(i)` | `cancel` | None | ε | `unsubSrc` | `s_cancelled` | Skipping | No complete | — |
| T09 | `s_take` | `sourceNext(v)` | Predicate not called | `outNext(v)` | ε | `s_take` | Hinge already passed | Index is irrelevant | E01 |
| T10 | `s_take` | `sourceError(e)` | None | `outError(e)` | `unsubSrc` | `s_errored` | Taking | — | — |
| T11 | `s_take` | `sourceComplete` | None | `outComplete` | `unsubSrc` | `s_completed` | Taking | — | E01 |
| T12 | `s_take` | `cancel` | None | ε | `unsubSrc` | `s_cancelled` | Taking | No complete | E05 |
| T13 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T03-T05 partition predicate outcomes. There is no "falsy but do not emit" row: the value that fails the predicate is the first output.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | After the hinge, values are unmodified and in order, including the hinge value. E01 |
| At most one terminal | Yes | T05-T07, T10-T11 |
| No downstream after terminal | Yes | T13 |
| Cancellation does not synthesize completion | Yes | T08, T12, E05 |
| Upstream / inner lifetime | Yes | Single source subscription for the whole skipping and taking life. No inner |
| Cleanup once | Yes | No extra finalizer |
| Per-subscription state | Yes | `taking` and `index` are init locals (lines 54-55) |
| Empty source | Yes | `outComplete` from `s_skip(0)`. E04 |
| Source error | Yes | Forwarded during skip and during take. E03 |
| Silence | Yes | An infinite source whose predicate stays truthy never emits and never completes |
| Pending value or buffer on terminal | No | Skipped values are not stored |
| Callback throws / reenters / cancels | Throws yes (T05, E02). Reentry and cancel-from-callback excluded | Once `s_take`, a throwing predicate cannot occur because it is not called |
| Equal-time ordering and timer cancellation | No | No second stream and no timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T04, T09, T11 |
| Starting state | `s_idle` |
| Reset/fixture | `predicate = (v) => v < 3` |
| State-reaching prefix | `subscribe` → `s_skip(0)` |
| Target event | `sourceNext(1, truthy)`, `sourceNext(2, truthy)`, `sourceNext(3, falsy)`, `sourceNext(4)`, `sourceComplete` |
| Expected notifications | `outNext(3)`, `outNext(4)`, `outComplete` |
| Expected lifecycle observations | `subSrc` until complete. Predicate not called for `4` |
| Distinguishing suffix | `1` and `2` are absent, which separates this from `filter` (filter would also drop a later `v < 3`) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T05 |
| Starting state | `s_skip(0)` |
| Reset/fixture | Predicate throws `err` on the first value |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(v, throw(err))` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. No `outNext` |
| Distinguishing suffix | Not `sourceError`. A following source complete is silent (T13) |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03, T06 |
| Starting state | `s_skip(0)` |
| Reset/fixture | First predicate result truthy |
| State-reaching prefix | `subscribe`, `sourceNext(1, truthy)` → `s_skip(1)` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | The skipped `1` is not emitted before the error |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T07 |
| Starting state | `s_skip(0)` |
| Reset/fixture | Empty source, or only truthy values then complete |
| State-reaching prefix | `subscribe` |
| Target event | `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `EmptyError` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T04, T12 |
| Starting state | `s_skip(0)` |
| Reset/fixture | First value fails the predicate |
| State-reaching prefix | `subscribe`, `sourceNext(0, falsy)` → `s_take` with `outNext(0)` |
| Target event | `cancel` |
| Expected notifications | ε for the cancel |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` after the hinge value |
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
| T10 | specified | not executed |
| T11 | specified | not executed |
| T12 | specified | not executed |
| T13 | specified | not executed |

Denominator = 13. Specified 13/13. Executed 0/13.

Residual risk: T08 and T10 have no dedicated scenario. Falsy non-booleans (`0`, `''`, `null`) take T04; that is specified by the `!predicate` expression and not executed. The excluded reentrant case (predicate subscribes or nexts synchronously) is untested.

## G. Review decision

Decision: accept with documented limits

Reason: One boolean `taking` plus the short-circuit on line 57 determines every next. Terminals are the default subscriber paths.

Known implementation limitations: The hinge value is emitted. The predicate is not called after that, and `index` stops increasing. Truthiness, not `=== true`, decides skipping. A throw increments `index` only as a discarded local.

Differences between intended contract and version characterization: The formal comment (`skipWhile.ts` lines 9-11) matches the code. The later informal sentence "Once the predicate is true, it will not be called again" (line 17) does not. The predicate stops being called when it returns a falsy result, not when it returns true. While it returns true it keeps being called.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
