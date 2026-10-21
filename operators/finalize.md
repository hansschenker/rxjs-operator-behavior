# `finalize`

`finalize(callback)` mirrors the source. It does not add, remove, or rewrite a notification. `callback` runs on teardown: after a source `complete`, after a source `error`, and on explicit unsubscribe. It runs after the destination’s own `complete` or `error` handler, because `Subscriber._complete` / `_error` notify the destination and only then unsubscribe, and the callback is a finalizer on that subscriber. A synchronous terminal during `source.subscribe` still runs the callback: it is added in a `finally`, and `Subscription.add` executes a finalizer immediately when the subscriber is already closed. A throw from `callback` is not modeled as an observable notification. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/finalize.ts` lines 65–75. Not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `finalize(callback)`. `MonoTypeOperatorFunction<T>`. Lines 65–75. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | `source.subscribe(subscriber)` with the destination subscriber itself, then `subscriber.add(callback)`. No `OperatorSubscriber` wrapper. Nexts, errors, and completion are the source’s, unchanged. |
| Model kind | Symbolic. The callback is an uninterpreted effect. Control locations are finite. |
| Parameter domain | `callback` is a synchronous zero-argument function. |
| Payload/error domain | Same as the source. `finalize` does not manufacture an error or a completion. |
| Subscription boundary | The callback is registered per `operate` invocation, so per subscription. One source subscription, and it is the destination’s own subscription to `source`. No inners. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | `callback` is synchronous. It is not given the terminal kind or the error. It does not see next values. |
| Cleanup assumptions | The callback is a finalizer, so `Subscription.unsubscribe` runs it at most once (the list is cleared, lines 75–77 of `Subscription.ts`). If `add` happens when `closed` is already true, `execFinalizer` runs it immediately (lines 120–123) and it is not stored for a second run. |
| Explicit exclusions | Ordinary model, no reentrancy. Throwing `callback` is excluded as a notification. Partial source characterization, not a transition that emits `error`: if the subscriber is already closed, `add` calls the callback with no try/catch (`Subscription.ts` lines 120–123), the throw leaves `init`, and `operate` catches it and calls `this.error` (`lift.ts` lines 22–27); a subscriber that already completed or errored is stopped, so that `error` becomes `handleStoppedNotification` and, with default `onStoppedNotification === null`, does not notify the consumer. If the callback throws later from `unsubscribe`’s finalizer loop, `Subscription.unsubscribe` aggregates an `UnsubscriptionError` (lines 78–93) after the destination terminal handler has already run. `useDeprecatedSynchronousErrorHandling` is the reason for the `try/finally` comment (lines 67–68) and is left off. Terminal late events are silent by convention. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator created. | `callback` | the call | `subscribe` does not run `callback` before the source |
| `active` | Source subscribed and `callback` registered, or about to be if subscribe is still on the stack. | finalizer installed | T01 | a later terminal or cancel runs `callback` once |
| `completed` | Destination completed and `callback` has run. | none | source `complete` | silence; `callback` is not pending |
| `errored(e)` | Destination errored and `callback` has run. | `e` | source `error` | silence |
| `cancelled` | Unsubscribed and `callback` has run. | none | `cancel` | no `complete` was emitted |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 69–73. |
| Source next | yes | Forwarded because the destination is subscribed directly. `callback` does not run. |
| Source error | yes | Destination `error`, then `callback`. |
| Source completion | yes | Destination `complete`, then `callback`. |
| Cancellation `cancel` | yes | `callback` without a terminal notification. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | no, as notifications | The callback is lifecycle. A returning callback is the modeled case. A throwing callback is an exclusion, not a `Σ` outcome that changes `Γ`’s notification trace. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source) | callback() | unsubscribe(source)
}
```

Notifications are exactly the source notifications. The effect order on a terminal is: destination handler, then `callback`, because unsubscribe is in the `finally` of `_error` / `_complete` (`Subscriber.ts` lines 116–129). A one-notification record is enough for the notification component. The effect order is required and is not a second notification.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | `callback` is a function; source does not terminate inside subscribe | none | `source.subscribe(subscriber)`, then `subscriber.add(callback)` (lines 69–73) | `active` | `finalize(callback)` | a next does not run `callback` | S01 |
| T02 | `active` | source `next(v)` | any | `next(v)` | `callback` not run | `active` | T01 | a later complete does run `callback` | S01 |
| T03 | `active`, or synchronous terminal from `idle` | source `error(e)` | `callback` returns | `error(e)` | consumer `error` handler, then `callback` once, then the subscription is closed | `errored(e)` | T01, or the throw-free subscribe path that completes the error inside `source.subscribe` | silence; `callback` is not called again | S02 |
| T04 | `active`, or synchronous terminal from `idle` | source `complete` | `callback` returns | `complete` | consumer `complete` handler, then `callback` once | `completed` | T01, including the empty synchronous source | silence | S03 |
| T05 | `active` | `cancel` | open | none | `callback` once; source unsubscribed | `cancelled` | T01 | no `complete` | S04 |
| T06 | terminal | late source events or a second unsubscribe | stopped / `closed` | none | `callback` is not stored twice and `unsubscribe` returns immediately when `closed` | same | a terminal row | convention, not a legal trace | S02 |
| T07 | any non-terminal | `callback` throws | excluded | not an observable notification from `finalize` | see Explicit exclusions | not a modeled successor | — | — | — |

T03 and T04 include the synchronous case: the source notifies and unsubscribes before `add`, then `add` sees `closed` and runs `callback` before `operate` returns. The consumer still observed the terminal first, during `source.subscribe`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Next payloads and order are the source’s. No value is inserted. |
| one terminal | yes | T03 or T04, whichever the source does. `finalize` does not add another. |
| silence after terminal | yes | T06. |
| cancel does not complete | yes | T05. `callback` still runs. |
| upstream/inner lifetime | yes | The destination is subscribed to the source once. No inners. |
| cleanup once | yes | Finalizer list is nulled during unsubscribe, or the callback is run immediately on `add` to a closed subscriber and not stored. |
| per-subscription state | yes | `operate` registers `callback` on the subscriber for that subscription only. |
| empty/error/silence | yes | Empty source: T04, `complete`, and `callback` (S03). Source error: T03, `error`, and `callback`, no next. Never terminates: `callback` has not run. |
| pending buffer on terminal | no | No buffer. |
| callback throw/reenter/cancel | throw excluded | T07. Reentrancy excluded. Cancel is T05, not a complete. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Next does not run the callback

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | `finalize(cb)`; source emits `v` and stays open |
| State-reaching prefix | call `finalize` |
| Target event | `subscribe` and source `next(v)` |
| Expected notifications | `next(v)` |
| Expected lifecycle observations | `cb` call count is 0; source still subscribed |
| Distinguishing suffix | unsubscribe runs `cb` once (T05) |
| Expected final state | `active` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload identity and callback count |
| Oracle source | `contract` |

### S02 Error then callback

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T03, T06 |
| Starting state | `active` |
| Reset/fixture | source `error(e)`; `cb` records whether the consumer has already seen `e` |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` only |
| Expected lifecycle observations | consumer `error` runs before `cb`; `cb` once; a second unsubscribe does not call `cb` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | order of consumer handler versus callback |
| Oracle source | `source characterization` |

### S03 Complete then callback, including empty

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T04 |
| Starting state | `idle` |
| Reset/fixture | empty source that completes synchronously, and a separate source that emits `v` then completes |
| State-reaching prefix | call `finalize` |
| Target event | `subscribe` (empty case) or next-then-complete |
| Expected notifications | empty: `complete`. Non-empty: `next(v)`, `complete`. |
| Expected lifecycle observations | in both cases `cb` runs once, after the consumer `complete`, including when complete happens inside `source.subscribe` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | notification trace plus one callback |
| Oracle source | `source characterization` |

### S04 Cancel runs the callback and does not complete

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | `cb` once; source unsubscribed |
| Distinguishing suffix | no `complete` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal and one callback |
| Oracle source | `contract` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references T01, T02, T03, T04, T05, T06. T07 is an explicit exclusion, not an executable obligation. Specified coverage of applicable rows = 6/6.

Execution: not executed.

Evidence: `src/internal/operators/finalize.ts` lines 65–75, `Subscriber.ts` lines 116–129, and `Subscription.ts` lines 47–94 and 116–123. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the operator adds one finalizer and otherwise does not wrap notifications. The `try/finally` only moves registration to after `source.subscribe`, which also covers the already-closed subscriber.

Known limitations: throwing callbacks are excluded, with the partial host behavior recorded above. The callback cannot observe why it ran. Reentrancy is excluded. The comment at lines 67–68 ties the `try/finally` to a deprecated config flag that this analysis leaves off; the `finally` still has a behavioral effect with that flag off, because synchronous termination closes the subscriber before `add`.

Contract vs version characterization: JSDoc lines 5–7 say the function runs on complete, error, and explicit unsubscribe. “It does not add a notification” and “it runs after the consumer terminal handler” are source characterization.

Tests still required: S01–S04, including synchronous empty completion, and a negative test that a throwing callback is not specified here.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
