# `skipUntil`

`skipUntil` is a full operator. It subscribes to `notifier` first and to the source second, and it starts forwarding source `next`s only after the notifier has emitted one `next` (`skipUntil.ts` lines 52-69). A notifier `complete` does not open the gate and does not complete the output. A notifier `error` is forwarded. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `skipUntil` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/skipUntil.ts` lines 52-69 |
| Helpers read | `innerFrom.ts` lines 16-41; `throwUnobservableError.ts` lines 5-11; `noop.ts` line 2; `OperatorSubscriber.ts` lines 67-101; `lift.ts` lines 22-27; `Subscription.ts` lines 116-135; `Subscriber.ts` lines 67-101 and 255-258 |
| Shape | Full operator via `operate` |
| Parameters | `notifier: ObservableInput<any>` |
| Output | Source values after the first notifier `next`, unmodified |
| Model kind | Symbolic, extended with a synchronous notifier prefix during `subscribe` (not a timed machine) |
| Scheduler | None |
| Introduced errors | Invalid `notifier` → `TypeError` from `innerFrom` at subscribe, delivered by `operate`'s catch. Notifier `error` is forwarded, not wrapped |
| Upstream | Source subscription is started even if the notifier already stopped the destination (line 67 has no `subscriber.closed` guard). See T04 |
| Inners | One notifier subscription until its first `next`, its `complete`/`error`, or outer teardown |
| Per-subscription state | `taking` boolean, initially `false` (line 54) |
| Exclusions | Downstream handlers and user code must not reenter the operator. Synchronous notifier signals during `innerFrom(notifier).subscribe` are included as part of processing `subscribe`, because the following source line observes `taking` and `subscriber.closed`. Teardown throws out of scope. A notifier that emits again from inside its own unsubscription is out of scope. After a terminal, late source events are protocol-illegal and silent here; that is not a claim that a stopped subscriber validates them. `config.onStoppedNotification` is not modeled. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_skipping, s_taking, s_completed, s_errored, s_cancelled }
Σ  = { subscribe(sync),
       sourceNext(v), sourceError(e), sourceComplete, cancel,
       notifierNext, notifierError(e), notifierComplete }
     sync ∈ { quiet, innerNext, innerComplete, innerError(e), invalid }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic, extended by the synchronous notifier prefix
```

`notifierNext` ignores payload (`skipUntil.ts` lines 58-61). `notifierComplete` is `noop` (line 62), then the custom complete path unsubscribes only that inner subscriber (`OperatorSubscriber.ts` lines 89-100).

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_skipping` | Both subscribed (or source attempted) and `taking === false` | No |
| `s_taking` | `taking === true`, notifier already unsubscribed, source subscribed | No |
| `s_completed` | Source complete delivered | Yes |
| `s_errored` | Error delivered | Yes |
| `s_cancelled` | Cancelled, no terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | Notifier then source (`skipUntil.ts` lines 65-67). `sync` records what the notifier does before that call returns |
| Source next | Yes | Forwarded only when `taking` (line 67) |
| Source error | Yes | Default forward from the source `OperatorSubscriber` |
| Source completion | Yes | Default forward, whether or not `taking` is true |
| Cancellation cancel | Yes | Destination unsubscribe tears down both children. Not completion |
| Inner notifications | Yes | Notifier `next` opens the gate; `complete` does not; `error` fails the output |
| Time | No | No clock |
| User callback outcomes | No | Both handlers are library functions. `innerFrom` may throw before a subscription exists |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subNotifier | unsubNotifier | subSrc | unsubSrc
                | subSrcWhileStopped
record        ::= (notifications in order, lifecycle in order)
```

`subSrcWhileStopped` means line 67 still invokes `source.subscribe` after the destination is already closed. The new operator subscriber is finalized immediately by `Subscription.add` on a closed parent (`Subscription.ts` lines 120-123), synchronous source notifications hit a stopped subscriber (`Subscriber.ts` lines 67-72 and 255-258) and are not forwarded, and the source teardown runs before `subscribe` returns.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe(quiet)` | Notifier subscribes and does not synchronously terminate | ε | `subNotifier`, `subSrc` | `s_skipping` | None | Source nexts are dropped until a later notifier next | E01 |
| T02 | `s_idle` | `subscribe(innerNext)` | Notifier synchronously emits at least one `next` | ε | `subNotifier`, `unsubNotifier`, `subSrc`. `taking = true` after the inner unsubscribe (lines 59-60) | `s_taking` | None | A synchronous source prefix after this is forwarded | E02 |
| T03 | `s_idle` | `subscribe(innerComplete)` | Notifier synchronously completes without a `next` | ε | `subNotifier`, `unsubNotifier` (noop complete), `subSrc`. `taking` stays false | `s_skipping` | None | Later source nexts stay dropped; source complete still completes | E03 |
| T04 | `s_idle` | `subscribe(innerError(e))` | Notifier synchronously errors | `outError(e)` | `subNotifier`, `unsubNotifier`, `subSrcWhileStopped` | `s_errored` | None | No source values. Differs from `takeUntil`, which does not call `source.subscribe` when `subscriber.closed` | E04 |
| T05 | `s_idle` | `subscribe(invalid)` | `innerFrom` throws `TypeError` | `outError(TypeError)` | ε | `s_errored` | None | No `subSrc` (throw is before line 67) | E05 |
| T06 | `s_idle` | later source or notifier signals, or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T07 | `s_skipping` | `sourceNext(v)` / source | `taking === false` | ε | ε | `s_skipping` | Gate closed | Value is not replayed when the gate opens | E01 |
| T08 | `s_skipping` | `notifierNext` / notifier | First notifier next | ε | `unsubNotifier`. `taking = true` | `s_taking` | Gate was closed | The next source value is forwarded; this input itself is not emitted | E01 |
| T09 | `s_skipping` | `notifierComplete` / notifier | No prior notifier next | ε | `unsubNotifier` | `s_skipping` | Gate closed | Gate stays closed forever | E06 |
| T10 | `s_skipping` | `notifierError(e)` / notifier | None | `outError(e)` | `unsubNotifier`, `unsubSrc` | `s_errored` | Both live | No `outComplete` | — |
| T11 | `s_skipping` | `sourceError(e)` / source | None | `outError(e)` | `unsubSrc`, `unsubNotifier` | `s_errored` | Gate may still be closed | Skipped values are not emitted first | — |
| T12 | `s_skipping` | `sourceComplete` / source | None | `outComplete` | `unsubSrc`, `unsubNotifier` | `s_completed` | Gate may still be closed | Complete is not withheld by `taking` | E03 |
| T13 | `s_skipping` | `cancel` | None | ε | `unsubSrc`, `unsubNotifier` | `s_cancelled` | Subscribed | No complete and no open of the gate | — |
| T14 | `s_taking` | `sourceNext(v)` / source | `taking === true` | `outNext(v)` | ε | `s_taking` | Gate open | Order preserved | E02 |
| T15 | `s_taking` | `notifierNext` / `notifierComplete` / `notifierError` | Notifier already unsubscribed | ε | ε | `s_taking` | Inapplicable for a notifying inner that honored unsubscribe | Protocol-illegal if a late inner signal is forced | — |
| T16 | `s_taking` | `sourceError(e)` | None | `outError(e)` | `unsubSrc` | `s_errored` | Gate open | — | — |
| T17 | `s_taking` | `sourceComplete` | None | `outComplete` | `unsubSrc` | `s_completed` | Gate open | — | E02 |
| T18 | `s_taking` | `cancel` | None | ε | `unsubSrc` | `s_cancelled` | Gate open | No complete | E07 |
| T19 | terminal states | any source or notifier signal or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T01-T05 partition `subscribe` by the notifier's synchronous behavior, assuming a valid quiet source during that call except for the stopped-subscriber characterization in T04. A synchronous source prefix is the same rows T07/T12/T14/T16/T17 applied before `subscribe` returns, in source order, after the notifier prefix.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | After the gate opens, source nexts are unchanged and in order. Notifier payloads are never output. E02 |
| At most one terminal | Yes | Source complete, source error, or notifier error. Notifier complete is not a terminal. E06 |
| No downstream after terminal | Yes | T19 |
| Cancellation does not synthesize completion | Yes | T13, T18, E07 |
| Upstream / inner lifetime | Yes | Notifier first. Notifier unsubscribed on its first next without unsubscribing the source (lines 59-60). Source line always runs (line 67), including T04's stopped attempt. Invalid notifier: no source (T05) |
| Cleanup once | Yes | Each child unsubscribes once via destination teardown or its own complete/error `finally` |
| Per-subscription state | Yes | `taking` is an init local |
| Empty source | Yes | If the source completes while skipping, the output completes with no next. E03 |
| Source error | Yes | Forwarded in both active states. Notifier error is a different input and also `outError` |
| Silence | Yes | A live source with a notifier that never nexts, or that only completes, yields no nexts. That is not an error |
| Pending value or buffer on terminal | No | Skipped values are discarded, not stored for later |
| Callback throws / reenters / cancels | No user callback | Reentry excluded. Opening the gate does not call a user function |
| Equal-time ordering and timer cancellation | Ordering yes, timers no | There is no clock. If both producers are synchronous, the notifier subscription runs to quiescence before `source.subscribe` (lines 65-67). That is sequenced subscribe order, not a tie. E02 versus a quiet notifier |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T07, T08, T14 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier emits nothing during subscribe |
| State-reaching prefix | `subscribe(quiet)` → `s_skipping` |
| Target event | `sourceNext('a')`, then `notifierNext`, then `sourceNext('b')` |
| Expected notifications | `outNext('b')` |
| Expected lifecycle observations | `subNotifier`, `subSrc` at start; `unsubNotifier` on `notifierNext`; source stays up |
| Distinguishing suffix | `'a'` is not emitted after the gate opens |
| Expected final state | `s_taking` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T02, T14, T17 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier's subscribe synchronously delivers one `next` (for example a notifier that behaves like `of(0)`) |
| State-reaching prefix | None beyond the subscribe input |
| Target event | `subscribe(innerNext)`, then synchronous or later `sourceNext(1)`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outComplete` |
| Expected lifecycle observations | Notifier subscribed and unsubscribed before the source subscription. `taking` is already true |
| Distinguishing suffix | The notifier payload `0` is not an `outNext` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03, T07, T12 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier completes synchronously without a next (empty notifier) |
| State-reaching prefix | `subscribe(innerComplete)` → `s_skipping` with notifier already gone |
| Target event | `sourceNext(1)`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | Source was subscribed. No `outError` |
| Distinguishing suffix | Contrast `takeUntil`, whose notifier `complete` also leaves the source mirrored, but a notifier `next` completes `takeUntil` instead of opening a gate |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T04 |
| Starting state | `s_idle` |
| Reset/fixture | Notifier synchronously errors with `e` |
| State-reaching prefix | None |
| Target event | `subscribe(innerError(e))` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `subSrcWhileStopped` after the error. Sync source notifications are not appended. No second error |
| Distinguishing suffix | Downstream is already terminal before the source line; a late source complete must not become `outComplete` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T05 |
| Starting state | `s_idle` |
| Reset/fixture | `notifier` is not an `ObservableInput` (`innerFrom.ts` line 41) |
| State-reaching prefix | None |
| Target event | `subscribe(invalid)` |
| Expected notifications | `outError(TypeError)` |
| Expected lifecycle observations | No `subSrc` and no `subNotifier` |
| Distinguishing suffix | Different lifecycle from T04 |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T09, T07 |
| Starting state | `s_skipping` |
| Reset/fixture | Quiet subscribe already done |
| State-reaching prefix | `subscribe(quiet)` |
| Target event | `notifierComplete`, then `sourceNext(1)` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubNotifier` only. Source remains. `taking` stays false |
| Distinguishing suffix | `sourceComplete` would still `outComplete` (T12). This is not an error |
| Expected final state | `s_skipping` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E07

| Field | Value |
| --- | --- |
| Test ID | E07 |
| Covered row IDs | T18 |
| Starting state | `s_taking` |
| Reset/fixture | Gate already open |
| State-reaching prefix | `subscribe(innerNext)` or T08 |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
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
| T16 | specified | not executed |
| T17 | specified | not executed |
| T18 | specified | not executed |
| T19 | specified | not executed |

Denominator = 19. Specified 19/19. Executed 0/19.

Residual risk: T04's stopped source subscription depends on `Subscription.add` and `handleStoppedNotification` defaults. A source that throws after the subscriber is stopped, or a notifier that reenters from teardown, is outside the model. T10, T11, T13, and T16 are specified but have no dedicated scenario row.

## G. Review decision

Decision: accept with documented limits

Reason: Next, complete, and error on the notifier are different transitions in the 7.8.2 source, and the missing `subscriber.closed` check before `source.subscribe` is visible at line 67.

Known implementation limitations: After a synchronous notifier error the source is still subscribed against a stopped destination and then torn down. Notifier completion leaves the output skipping until the source itself terminates. The first notifier `next` unsubscribes the notifier before `taking` is set.

Differences between intended contract and version characterization: The JSDoc (`skipUntil.ts` lines 16-20) matches the gate, the unsubscribe-on-notifier-next rule, and the "no source values if the notifier completes or errors first" rule. It does not spell out T04's extra source subscription attempt. That attempt does not emit source values, so it does not contradict the JSDoc's emission claim; it is an extra lifecycle fact.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
