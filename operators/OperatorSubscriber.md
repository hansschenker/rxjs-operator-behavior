# OperatorSubscriber

`OperatorSubscriber` is not a public operator and has no pipe contract. `createOperatorSubscriber` returns `new OperatorSubscriber(...)` (`OperatorSubscriber.ts:15-22`). Operators use it as the subscriber that sits between a source producer and a destination subscriber. It is a `Subscriber`: `next` / `error` / `complete` drop notifications when `isStopped` is already set (`Subscriber.ts:67-101`), `error` and `complete` set `isStopped` before the handler, and `unsubscribe` sets `isStopped` and `closed` (`Subscriber.ts:104-109`). The constructor installs optional handlers (`OperatorSubscriber.ts:67-101`). A custom `onNext` runs in `try`; a throw calls `destination.error(err)` and does not call this subscriber's `_error` (`OperatorSubscriber.ts:67-74`). A custom `onError` or `onComplete` runs in `try`; a throw calls `destination.error` with the new error; `finally` always `unsubscribe`s (`OperatorSubscriber.ts:76-100`). If a handler is omitted, the base method is used: `_next` forwards, `_error` forwards then unsubscribes, `_complete` forwards then unsubscribes (`Subscriber.ts:112-129`). `unsubscribe` honors optional `shouldUnsubscribe` (only for `groupBy`, not a public hook) and then runs `onFinalize` if this subscriber was not already closed (`OperatorSubscriber.ts:104-111`). Construction adds this subscriber as a child of a `Subscription` destination (`Subscriber.ts:47-55`), so a destination that unsubscribes on its own error or complete tears this subscriber down.

There is no notifier. Phases `waiting-for-notifier` and `resubscribing` are not states of this object. Operators build those phases by subscribing again with a new `OperatorSubscriber`.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `OperatorSubscriber` / `createOperatorSubscriber` |
| Kind | Internal subscriber. Not an `OperatorFunction` |
| Module | `/tmp/rxjs/src/internal/operators/OperatorSubscriber.ts` |
| Base | `/tmp/rxjs/src/internal/Subscriber.ts` lines 39-130, 255-258 |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Factory | `(destination, onNext?, onComplete?, onError?, onFinalize?)` (`OperatorSubscriber.ts:15-20`) |
| Class extras | `onFinalize`, `shouldUnsubscribe` (`OperatorSubscriber.ts:51-52`). `shouldUnsubscribe` is documented as `groupBy`-only (`OperatorSubscriber.ts:41-44`) |
| `next` when open, no `onNext` | `destination.next(value)` (`Subscriber.ts:112-114`). No try/catch |
| `next` when open, with `onNext` | `onNext(value)`; throw → `destination.error(err)` (`OperatorSubscriber.ts:67-74`). This subscriber is not stopped by that catch |
| `error` when open, no `onError` | `isStopped=true`, `destination.error`, `unsubscribe` (`Subscriber.ts:81-88`, `Subscriber.ts:116-121`) |
| `error` when open, with `onError` | `isStopped=true`, `onError(err)`, on throw `destination.error(thrown)`, `finally unsubscribe` (`OperatorSubscriber.ts:76-86`). The handler may consume the error and not call `destination.error` |
| `complete` | Same shape as error, with `onComplete` (`OperatorSubscriber.ts:89-100`, `Subscriber.ts:95-101`, `Subscriber.ts:124-129`) |
| Stopped | `handleStoppedNotification`: no delivery (`Subscriber.ts:255-258`) |
| `unsubscribe` | If `shouldUnsubscribe` is absent or returns true: base unsubscribe, then `onFinalize` if it was not already closed (`OperatorSubscriber.ts:104-111`) |
| Deprecated | The class is internal infrastructure. Not the deprecated `Subscriber.create` path |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)` models one subscriber instance, not a pipeable operator.

`s₀` after a successful constructor: `(phase=active, isStopped=false, closed=false, terminalReason=none)`.

Handlers, `onFinalize`, and `shouldUnsubscribe` are fixed configuration, not varying state.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `terminal` | `init` is only the pre-constructor moment. `waiting-for-notifier` and `resubscribing` are absent |
| isStopped | bool | Set by `error`, `complete`, and `unsubscribe` (`Subscriber.ts:85`, `Subscriber.ts:99`, `Subscriber.ts:106`) |
| closed | bool | Set by `Subscription.unsubscribe` (`Subscription.ts:51`) |
| terminalReason | `none`, `error`, `complete`, `unsub` | Why delivery stopped. `error` and `complete` both also unsubscribe, so `closed` becomes true |

### Σ (8 categories)

The "source" is whoever calls this subscriber. The destination is not an inner subscription of this class.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | Constructor links `destination.add(this)` when destination is a `Subscription` (`Subscriber.ts:49-54`). No source is subscribed by this class |
| Source next | Yes | `prodNext(v)` calls `this.next` |
| Source error | Yes | `prodError(e)` calls `this.error`. May be consumed by a custom `onError` |
| Source completion | Yes | `prodComplete` calls `this.complete`. May be consumed by a custom `onComplete` |
| Cancellation cancel | Yes | `unsub`, including parent teardown |
| Inner notifications | No | This class does not subscribe to a notifier. `notifierNext` / `notifierError` / `notifierComplete` are not symbols here |
| Time | No | No clock |
| User callback outcomes | Yes | `nextThrow(e)`, `errorThrow(e)`, `completeThrow(e)` from the installed handlers. A next-handler throw is delivered with `destination.error`, not by re-entering `this.error` |

### Γ

| Symbol | Meaning |
| --- | --- |
| `destNext(v)` | `destination.next` |
| `destError(e)` | `destination.error` |
| `destComplete` | `destination.complete` |
| `ε` | No destination notification |
| `eff:Unsubscribe` | This subscriber closes and drops from its parent |
| `eff:OnFinalize` | `onFinalize` if present and this call was the one that closed it (`OperatorSubscriber.ts:109`) |
| `eff:StoppedNotification` | `handleStoppedNotification` when already stopped (`Subscriber.ts:255-258`). Not a destination next/error/complete |

Custom handlers may perform further destination calls before they return. Those calls are part of λ for that transition when the handler is the operator's code; this machine's own λ is the destination call the class itself makes.

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | constructor | destination is a `Subscription` | active, isStopped=false, closed=false | `ε` + child linked (`Subscriber.ts:49-54`, handlers `OperatorSubscriber.ts:67-101`) |
| T02 | active | `prodNext(v)` | no custom `onNext` | active | `destNext(v)` (`Subscriber.ts:112-114`). A throw from `destination.next` propagates to the producer; this class does not catch it |
| T03 | active | `prodNext(v)` | custom `onNext` returns | active | `ε` from this class, plus whatever `onNext` did. `isStopped` stays false |
| T04 | active | `prodNext(v)` | custom `onNext` throws `e` | active unless destination teardown unsubscribes this child | `destError(e)` (`OperatorSubscriber.ts:71-73`). Not `this._error`. No `finally` unsubscribe in the next catch |
| T05 | active | `prodError(e)` | no custom `onError` | terminal, isStopped, closed, terminalReason=error | `destError(e)` + `eff:Unsubscribe` (`Subscriber.ts:116-121`) |
| T06 | active | `prodError(e)` | custom `onError` returns | terminal, isStopped, closed, terminalReason=error | `ε` from this class if the handler does not call `destination.error` (consumed) + `eff:Unsubscribe` (`OperatorSubscriber.ts:76-86`) |
| T07 | active | `prodError(e)` | custom `onError` throws `e2` | terminal, terminalReason=error | `destError(e2)` + `eff:Unsubscribe`. `e` is not forwarded (`OperatorSubscriber.ts:80-85`) |
| T08 | active | `prodComplete` | no custom `onComplete` | terminal, terminalReason=complete | `destComplete` + `eff:Unsubscribe` (`Subscriber.ts:124-129`) |
| T09 | active | `prodComplete` | custom `onComplete` returns | terminal, terminalReason=complete | `ε` from this class if the handler does not complete the destination (consumed) + `eff:Unsubscribe` |
| T10 | active | `prodComplete` | custom `onComplete` throws `e2` | terminal, terminalReason=error | `destError(e2)` + `eff:Unsubscribe` (`OperatorSubscriber.ts:89-99`). Not `destComplete` |
| T11 | active | `unsub` | `shouldUnsubscribe` absent or true, and not yet closed | terminal, isStopped, closed, terminalReason=unsub | `ε` + `eff:Unsubscribe` + `eff:OnFinalize` (`OperatorSubscriber.ts:104-110`, `Subscriber.ts:104-109`) |
| T12 | active | `unsub` | `shouldUnsubscribe` returns false | active | `ε`. Used only so `groupBy` can ignore unsubscribe (`OperatorSubscriber.ts:41-44`, `OperatorSubscriber.ts:105`) |
| T13 | terminal | `prodNext` or `prodError` or `prodComplete` | `isStopped` | terminal | `eff:StoppedNotification` only (`Subscriber.ts:68-70`, `Subscriber.ts:82-83`, `Subscriber.ts:96-97`) |
| T14 | terminal | `unsub` | already closed | terminal | `ε` (`Subscription.ts:50`) |

`error` and `complete` set `isStopped` before the handler (`Subscriber.ts:85`, `Subscriber.ts:99`). A reentrant `prodNext` on this same instance from inside `onError` or `onComplete` is T13, not T02/T03.

T04 does not set `isStopped`. If `destination.error` unsubscribes its children, this instance then takes T11 because it was added in T01. If `shouldUnsubscribe` returns false, the parent unsubscribe does not close it (T12) even though `destError` ran.

`waiting-for-notifier` and `resubscribing` are not reachable. A retry/repeat operator reaches those phases by constructing another `OperatorSubscriber` and subscribing the source again. That is a different machine.

## D. Contract invariants

1. After `isStopped`, this instance does not call `onNext`, `onError`, `onComplete`, or the base forwarders. Stopped signals are not destination notifications.
2. A custom error handler and a custom complete handler always unsubscribe in `finally`, even when they consume the terminal and do not touch the destination.
3. A throwing next handler notifies `destination.error` and does not run the custom `onError`. Those are different transitions (T04 vs T07).
4. Omitted handlers are the base subscriber, which does forward error and complete and does unsubscribe afterward.
5. `onFinalize` runs at most once, and only on a transition from not closed to closed (`OperatorSubscriber.ts:106-109`).
6. `shouldUnsubscribe() === false` makes `unsubscribe` a no-op. None of the operators in this batch pass that function.
7. Destination `error`/`complete` from the base path unsubscribe this object via `finally` on this object itself. Destination teardown can also unsubscribe it as a child. The second unsubscribe is T14.
8. This class does not resubscribe and does not own a notifier.

## E. Scenario specification

### E1

| Field | Value |
| --- | --- |
| Test ID | E1 |
| Covered row IDs | T01, T02, T08 |
| Starting state | `phase=init, isStopped=false, closed=false, terminalReason=none` |
| Reset/fixture | No custom handlers. Destination is a `Subscriber` |
| State-reaching prefix | Constructor → active |
| Target event | `prodNext(1)`, `prodComplete` |
| Expected notifications | `destNext(1)`, `destComplete` |
| Expected lifecycle observations | Child link on construct. `eff:Unsubscribe` after complete. No `onFinalize` |
| Distinguishing suffix | A following `prodNext(2)` is T13, not `destNext(2)` |
| Expected final state | `phase=terminal, isStopped=true, closed=true, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization (`Subscriber.ts:112-129`) |

### E2

| Field | Value |
| --- | --- |
| Test ID | E2 |
| Covered row IDs | T04 |
| Starting state | `phase=active, isStopped=false, closed=false, terminalReason=none` |
| Reset/fixture | Custom `onNext` throws `bad`. Custom `onError` records if it is called |
| State-reaching prefix | T01 |
| Target event | `prodNext(1)` |
| Expected notifications | `destError(bad)` |
| Expected lifecycle observations | Custom `onError` is not entered. This catch has no `finally` unsubscribe (`OperatorSubscriber.ts:67-74`). If the destination is a `Subscriber`, its error path unsubscribes children, so this instance then takes T11 |
| Distinguishing suffix | Not T07. The producer called `next`, not `error` |
| Expected final state | If the destination tears children down: `phase=terminal, isStopped=true, closed=true, terminalReason=unsub`. The class's own T04 does not set that |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`OperatorSubscriber.ts:67-74`, `Subscriber.ts:53-54`) |

### E3

| Field | Value |
| --- | --- |
| Test ID | E3 |
| Covered row IDs | T06, T13 |
| Starting state | `phase=active, isStopped=false, closed=false, terminalReason=none` |
| Reset/fixture | Custom `onError` consumes the error (does not call `destination.error`), as `retry` does while retries remain |
| State-reaching prefix | T01 |
| Target event | `prodError(e)` |
| Expected notifications | `ε` to the destination from this class |
| Expected lifecycle observations | `isStopped` set before `onError` (`Subscriber.ts:85`). `finally` `eff:Unsubscribe`. `e` is consumed |
| Distinguishing suffix | `prodError` again is T13, not a second handler call. The destination may still be open; that is how retry can resubscribe with a new subscriber |
| Expected final state | `phase=terminal, isStopped=true, closed=true, terminalReason=error` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`OperatorSubscriber.ts:76-86`) |

### E4

| Field | Value |
| --- | --- |
| Test ID | E4 |
| Covered row IDs | T07, T10 |
| Starting state | `phase=active, isStopped=false, closed=false, terminalReason=none` |
| Reset/fixture | Two separate instances. One `onError` throws `bad`. One `onComplete` throws `bad` |
| State-reaching prefix | T01 on each |
| Target event | `prodError(e)` or `prodComplete` |
| Expected notifications | `destError(bad)` in both cases. Not `destError(e)`. Not `destComplete` |
| Expected lifecycle observations | `eff:Unsubscribe` in `finally` even though the handler threw |
| Distinguishing suffix | Handler throw is a different error from the producer signal |
| Expected final state | `phase=terminal, isStopped=true, closed=true, terminalReason=error` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`OperatorSubscriber.ts:76-99`) |

### E5

| Field | Value |
| --- | --- |
| Test ID | E5 |
| Covered row IDs | T11, T12, T14 |
| Starting state | `phase=active, isStopped=false, closed=false, terminalReason=none` |
| Reset/fixture | Instance A: no `shouldUnsubscribe`, with `onFinalize`. Instance B: `shouldUnsubscribe` returns false |
| State-reaching prefix | T01 |
| Target event | `unsub` |
| Expected notifications | `ε` |
| Expected lifecycle observations | A: `eff:Unsubscribe` and `eff:OnFinalize`, then a second `unsub` is T14 and does not call `onFinalize` again. B: stays active, `onFinalize` not run |
| Distinguishing suffix | B can still take T02. A cannot |
| Expected final state | A: `terminal`, `terminalReason=unsub`, `closed=true`. B: `active`, `isStopped=false`, `closed=false` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`OperatorSubscriber.ts:104-111`) |

## F. Coverage and evidence

Denominator: 14 transition rows T01–T14. Specified 14/14. Executed 0/14.

Secondary denominator: no operator spec file. Behavior is `OperatorSubscriber.ts` plus `Subscriber.ts` and `Subscription.ts`. Not executed.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- Not a public operator. No pipe identity, no source resubscribe, no notifier phase.
- A throwing `onNext` calls `destination.error` and does not unsubscribe inside the catch. Teardown depends on the destination being a `Subscriber` parent. A throwing `onError` or `onComplete` does unsubscribe in `finally`.
- Omitted `onNext` does not catch a throw from `destination.next`.
- `shouldUnsubscribe` returning false is the `groupBy` escape. The operators beside this file do not use it.
- Stopped notifications are not modeled as destination traffic. `onStoppedNotification` scheduling (`Subscriber.ts:255-258`) is out of the output alphabet except as `eff:StoppedNotification`.
- Unbounded reentrant handler calls are excluded. A single reentrant `next` after `isStopped` is T13.
