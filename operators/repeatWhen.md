# repeatWhen

`repeatWhen(notifier)` mirrors source next. Source error is forwarded and does not ask the notifier to repeat (`onError` omitted, `repeatWhen.ts:94`). Source complete is consumed: `isMainComplete` is set, and if the notifier is not already complete the completion is pushed as `completions$.next()` with no value (`repeatWhen.ts:94-101`). The notifier factory runs once, lazily, on the first source complete (`repeatWhen.ts:60-87`). A notifier next resubscribes the source under a new attempt (`repeatWhen.ts:69-78`). A notifier complete sets sticky `isNotifierComplete` and completes the output only when `isMainComplete` is also true (`repeatWhen.ts:55`, `repeatWhen.ts:80-83`). It does not by itself subscribe. A notifier error uses the default error path and is `outError` (`Subscriber.ts:116-121`). Deprecated for removal in v9 or v10 in favor of `repeat`'s `delay`, which is not a pure alias (`repeatWhen.ts:41-42`).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `repeatWhen` |
| Kind | Public pipeable operator |
| Module | `/tmp/rxjs/src/internal/operators/repeatWhen.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `(notifier: (notifications: Observable<void>) => ObservableInput<any>) => MonoTypeOperatorFunction<T>` (`repeatWhen.ts:44`) |
| Deprecated | Yes. v9 or v10. Migration text: `repeat({ delay: () => notify$ })` (`repeatWhen.ts:41-42`) |
| Trigger | Source `complete` only. Source `error` is `outError` and the notifier is not fed (`repeatWhen.ts:94`) |
| Notifier lifetime | One `Subject<void>`, one `innerFrom(notifier(...))` subscription, created on first complete (`repeatWhen.ts:61-66`) |
| Notifier next | `subscribeForRepeatWhen` if `innerSub` is set; else `syncResub` (`repeatWhen.ts:69-78`, `repeatWhen.ts:105-118`) |
| Notifier complete | `isNotifierComplete = true`, then `checkComplete` (`repeatWhen.ts:80-83`) |
| `checkComplete` | `isMainComplete && isNotifierComplete && (subscriber.complete(), true)` (`repeatWhen.ts:55`) |
| Notifier error | Default forward: `outError(notifierError)` |
| Factory throw | Inside the source complete handler, so `OperatorSubscriber` sends `destination.error(thrown)` (`repeatWhen.ts:64-65`, `OperatorSubscriber.ts:89-99`) |
| Resubscribe overlap | `innerSub` is overwritten without an explicit unsubscribe (`repeatWhen.ts:93`). The completing subscriber unsubscribes in `finally` after a synchronous notifier next returns (`OperatorSubscriber.ts:96-98`) |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, attempt=0, isMainComplete=false, isNotifierComplete=false, notifierState=unwired, terminalReason=none)`.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `waitingNotifier`, `resubscribing`, `terminal` | `waitingNotifier` is source completed, completion pushed (or about to be), output still open |
| attempt | nat | Source subscription id |
| isMainComplete | bool | Cleared at the start of every `subscribeForRepeatWhen` (`repeatWhen.ts:91`) |
| isNotifierComplete | bool | Sticky. Set from notifier complete and never cleared (`repeatWhen.ts:81`) |
| notifierState | `unwired`, `open`, `closed` | Unwired until the first source complete |
| terminalReason | `none`, `complete`, `error`, `unsub` | — |

### Σ (8 categories)

Distinct inner symbols, not one collapsed "inner" event: `notifierNext`, `notifierError`, `notifierComplete`.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub` → `eff:SubscribeSource(1)`. Notifier not yet subscribed |
| Source next | Yes | `srcNext(v)` forwarded |
| Source error | Yes | `srcError(e)` forwarded. Not consumed. Notifier not signalled |
| Source completion | Yes | `srcComplete` consumed when a repeat may still happen |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | Yes | `notifierNext` resubscribes; `notifierComplete` is sticky and conjunctive; `notifierError(e)` replaces the open output with an error |
| Time | No | No scheduler in this file. User notifier may introduce time; that is inside the notifier, not this operator |
| User callback outcomes | Yes | `notifierFactoryThrow(e)`, `innerFromThrow(e)`. Distinct from `srcError` |

### Γ

`outNext(v)` | `outError(e)` | `outComplete` | `ε`

Lifecycle: `eff:SubscribeSource(n)`, `eff:UnsubscribeSource` (syncResub path and complete-handler `finally`), `eff:SubscribeNotifier` (once), `eff:CompletionsNext` (`completions$.next()`, no payload, `repeatWhen.ts:101`).

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | `sub` | — | active, attempt=1, isMainComplete=false | `ε` + `eff:SubscribeSource(1)` (`repeatWhen.ts:122-123`) |
| T02 | active | `srcNext(v)` | — | active | `outNext(v)` |
| T03 | active | `srcError(e)` | any notifier state | terminal, terminalReason=error | `outError(e)`. No `eff:CompletionsNext` |
| T04 | active | `srcComplete` | `!isNotifierComplete` | waitingNotifier, isMainComplete=true, notifierState=open | `ε` + `eff:SubscribeNotifier` on first time + `eff:CompletionsNext` (`repeatWhen.ts:94-101`) |
| T05 | active | `srcComplete` | `isNotifierComplete` already | terminal, terminalReason=complete, isMainComplete=true | `outComplete` via `checkComplete`. Subject is not notified (`repeatWhen.ts:55`, `repeatWhen.ts:101`) |
| T06 | waitingNotifier | `notifierNext` | `innerSub` set | resubscribing then active, attempt=attempt+1, isMainComplete=false | `ε` + `eff:SubscribeSource(new)`. Notifier stays open (`repeatWhen.ts:69-71`) |
| T07 | waitingNotifier | `notifierNext` | `innerSub` null (complete during `source.subscribe`) | resubscribing then active | `syncResub`: after subscribe returns, `eff:UnsubscribeSource` then `eff:SubscribeSource` (`repeatWhen.ts:105-118`) |
| T08 | waitingNotifier | `notifierComplete` | `isMainComplete` | terminal, isNotifierComplete=true, terminalReason=complete | `outComplete`. No subscribe (`repeatWhen.ts:80-83`, `repeatWhen.ts:55`) |
| T09 | active | `notifierComplete` | a prior next already cleared `isMainComplete` | active, isNotifierComplete=true | `ε`. Output stays open until the new source completes, which then takes T05 |
| T10 | waitingNotifier or active | `notifierError(e2)` | — | terminal, terminalReason=error | `outError(e2)` |
| T11 | active | `srcComplete` | factory or `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)`. Not the source's complete, and not a source error (`OperatorSubscriber.ts:89-99`) |
| T12 | any non-terminal | `unsub` | — | terminal, terminalReason=unsub | `ε` |
| T13 | terminal | any | — | terminal | `ε` |

T04 then a synchronous empty notifier: `getCompletionSubject` subscribes before `.next()` (`repeatWhen.ts:66`, `repeatWhen.ts:101`). An empty notifier completes inside that subscribe, T08 sees `isMainComplete` already true, and `outComplete` happens. `completions$.next()` still runs afterward because `checkComplete` was false before `getCompletionSubject()` was entered (`repeatWhen.ts:101`). If the output is already complete, that `next` does not deliver another terminal.

T06 does not unsubscribe the notifier. A following `notifierComplete` is T09 if resubscribe already set `isMainComplete` false, not an immediate `outComplete`. The sticky flag makes the next source completion T05. This is weaker than "notifier complete always completes now", and stronger than `repeat`'s delay notifier, which unsubscribes on next so a trailing complete is ignored and the new attempt is not pre-doomed.

`subscribeForRepeatWhen` does not unsubscribe the previous `innerSub` before assigning (`repeatWhen.ts:93`). Synchronous T06 from inside the complete handler overlaps the old subscription until `_complete`'s `finally`. One such handoff is in-model. A second synchronous `notifierNext` that orphans the middle subscription is excluded.

## D. Contract invariants

1. Source error never resubscribes and never calls the notifier factory.
2. Source complete is not forwarded when a repeat is still possible (T04). It is forwarded only by `subscriber.complete()` in `checkComplete` (T05/T08).
3. `isNotifierComplete` is monotonic. After it becomes true, the next source completion ends the output without another `eff:CompletionsNext`.
4. Notifier next is the only resubscribe signal. Notifier complete does not subscribe. Notifier error does not subscribe.
5. The factory runs at most once per downstream subscription.
6. Factory throw is category "user callback", not a source error and not `outComplete`.
7. Each resubscribe uses a new attempt id and a new `OperatorSubscriber`, and clears `isMainComplete` before that subscribe (`repeatWhen.ts:91`).

## E. Scenario specification

### E1

| Field | Value |
| --- | --- |
| Test ID | E1 |
| Covered row IDs | T01, T02, T04, T06, T05 |
| Starting state | `phase=init, attempt=0, isMainComplete=false, isNotifierComplete=false, notifierState=unwired, terminalReason=none` |
| Reset/fixture | Notifier emits one next per completion and does not complete |
| State-reaching prefix | `sub` → active attempt=1 |
| Target event | `srcNext(1)`, `srcComplete`, `notifierNext`, `srcNext(1)`, `srcComplete`, then unsubscribe the notifier externally is not required; second complete waits |
| Expected notifications | `outNext(1)`, `outNext(1)` and no `outComplete` while the notifier stays open after the second `eff:CompletionsNext` if the scenario stops at the second complete's wait. Full trace if the second complete is the target and the notifier has not nexted yet: `outNext(1)` from attempt 1, `ε` on complete, `outNext(1)` from attempt 2 |
| Expected lifecycle observations | `eff:SubscribeSource(1)`, `eff:SubscribeNotifier`, `eff:CompletionsNext`, `eff:SubscribeSource(2)` |
| Distinguishing suffix | A source error on attempt 2 would be `outError`, not another repeat (E4) |
| Expected final state | `phase=waitingNotifier, attempt=2, isMainComplete=true, isNotifierComplete=false, notifierState=open, terminalReason=none` after the second complete with no following notifier next |
| Version and scheduler | RxJS 7.8.2, no scheduler in the operator |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization (`repeatWhen.ts:90-101`) |

### E2

| Field | Value |
| --- | --- |
| Test ID | E2 |
| Covered row IDs | T04, T08 |
| Starting state | `phase=active, attempt=1, isMainComplete=false, isNotifierComplete=false, notifierState=unwired, terminalReason=none` |
| Reset/fixture | Notifier is empty: completes on subscribe, no next |
| State-reaching prefix | `sub` |
| Target event | `srcComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `eff:SubscribeNotifier`. No `eff:SubscribeSource(2)`. Source error is not involved |
| Distinguishing suffix | Contrast E1: there is no second attempt |
| Expected final state | `phase=terminal, attempt=1, isMainComplete=true, isNotifierComplete=true, notifierState=closed, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, synchronous EMPTY notifier |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`repeatWhen.ts:55`, `repeatWhen.ts:80-83`) |

### E3

| Field | Value |
| --- | --- |
| Test ID | E3 |
| Covered row IDs | T04, T10 |
| Starting state | `phase=active, attempt=1, isMainComplete=false, isNotifierComplete=false, notifierState=unwired, terminalReason=none` |
| Reset/fixture | Notifier errors |
| State-reaching prefix | `sub`, source has already nexted `1` |
| Target event | `srcComplete` then `notifierError(e2)` |
| Expected notifications | `outNext(1)`, `outError(e2)`. No `outComplete` |
| Expected lifecycle observations | `eff:SubscribeNotifier`, `eff:CompletionsNext` if the error is in response to the subject next; factory itself did not throw |
| Distinguishing suffix | The successful source completion is not delivered |
| Expected final state | `phase=terminal, terminalReason=error, isMainComplete=true, notifierState=closed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (default `_error`, `Subscriber.ts:116-121`) |

### E4

| Field | Value |
| --- | --- |
| Test ID | E4 |
| Covered row IDs | T03 |
| Starting state | `phase=active, attempt=1, notifierState=unwired, isMainComplete=false, isNotifierComplete=false, terminalReason=none` |
| Reset/fixture | Source errors. Notifier factory would throw if called; it must not be called |
| State-reaching prefix | `sub` |
| Target event | `srcError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | No `eff:SubscribeNotifier`, no `eff:CompletionsNext` |
| Distinguishing suffix | Contrast T11, where the source completed and the factory threw a different error |
| Expected final state | `phase=terminal, attempt=1, notifierState=unwired, terminalReason=error` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`repeatWhen.ts:94` has no `onError`) |

### E5

| Field | Value |
| --- | --- |
| Test ID | E5 |
| Covered row IDs | T06, T09, T05 |
| Starting state | `phase=waitingNotifier, attempt=1, isMainComplete=true, isNotifierComplete=false, notifierState=open, terminalReason=none` |
| Reset/fixture | Notifier emits next and then completes |
| State-reaching prefix | One source completion already consumed |
| Target event | `notifierNext`, `notifierComplete`, then the new source's `srcComplete` |
| Expected notifications | No terminal on the next. No terminal on the notifier complete. `outComplete` only when the new source completes |
| Expected lifecycle observations | `eff:SubscribeSource(2)` on the next. Notifier stays subscribed until destination complete |
| Distinguishing suffix | Differs from `repeat({ delay })`, whose notifier is unsubscribed on next so a trailing complete is ignored and does not stick `isNotifierComplete` |
| Expected final state | After the pair: `phase=active, attempt=2, isMainComplete=false, isNotifierComplete=true, notifierState=open, terminalReason=none`. After the new source completes: `terminal`, `terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`repeatWhen.ts:55`, `repeatWhen.ts:69-83`, `repeatWhen.ts:91`) |

## F. Coverage and evidence

Denominator: 13 transition rows T01–T13. Specified 13/13. Executed 0/13.

Secondary denominator, not executed: 24 `it(...)` cases in `/tmp/rxjs/spec/operators/repeatWhen-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- Notifier complete does not subscribe. It completes the output only while `isMainComplete` is true. If a notifier next has already resubscribed, completion is sticky and the output completes on the next source completion (T09 then T05), not immediately.
- Source error is forwarded and does not enter the notifier. That matches the intended repeat-on-complete contract.
- `repeat({ delay: () => notify$ })` is not an alias: `delay` is a new notifier per repetition, unsubscribed on first next, and receives the subscription count.
- Synchronous multi-next reentrancy that orphans `innerSub` is excluded. One synchronous resubscribe is in-model, including the `finally`-after-resubscribe teardown order.
- `waitingNotifier` can still call `completions$.next()` after a synchronous T08 has completed the destination. No second observer terminal is produced.
