# catchError

`catchError(selector)` forwards source `next` and `complete` unchanged. A source `error` is consumed: it is not forwarded. The operator calls `selector(err, caught)` where `caught` is `catchError(selector)(source)` — the same operator reapplied to the source, not a bare source reference (`catchError.ts:115`). The return value is passed through `innerFrom` and subscribed with the downstream subscriber directly (`catchError.ts:119`, `catchError.ts:136`). That inner's notifications are the output. Returning `caught` is only that subscription (a new instance of this machine), not an internal retry counter. A throw from `selector` or from `innerFrom` is a user-function fault: `OperatorSubscriber` sends that throw to `destination.error` and does not forward the original source error (`OperatorSubscriber.ts:76-86`).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `catchError` |
| Kind | Public pipeable operator |
| Module | `/tmp/rxjs/src/internal/operators/catchError.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `(selector: (err: any, caught: Observable<T>) => O) => OperatorFunction<T, T \| ObservedValueOf<O>>` (`catchError.ts:105-107`) |
| Deprecated | No |
| Wiring | `operate` (`lift.ts:17-31`). Init throw becomes `subscriber.error` (`lift.ts:23-26`) |
| Selector | `(err, caught)` with `caught = catchError(selector)(source)` (`catchError.ts:115`) |
| Replacement subscribe | `handledResult.subscribe(subscriber)` — downstream subscriber, no new `OperatorSubscriber` (`catchError.ts:119`, `catchError.ts:136`) |
| Source error | Consumed. Not an `outError` unless the selector path fails or the replacement errors |
| Source complete | Forwarded (`onComplete` omitted, `Subscriber._complete`, `Subscriber.ts:124-129`) |
| Source next | Forwarded (`onNext` omitted, `Subscriber._next`, `Subscriber.ts:112-114`) |
| Sync source error | `innerSub` still unset; flag `syncUnsub`, unsubscribe after `source.subscribe` returns, then subscribe the replacement (`catchError.ts:120-136`) |
| Async source error | `innerSub` already set; unsubscribe it, then subscribe the replacement (`catchError.ts:116-119`) |
| Callees | `innerFrom` (`innerFrom.ts:16-41`), `createOperatorSubscriber`, `operate` |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none)`.

Downstream `sub` is the entry event. Configuration `selector` is fixed.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `resubscribing`, `forwarding`, `terminal` | `waiting-for-notifier` is not a state. There is no notifier. `resubscribing` is the ordered handoff (unsubscribe source, then subscribe replacement), including the synchronous `syncUnsub` deferral |
| attempt | nat | Source-subscription id. The replacement subscribe is not a retry attempt; it is `eff:SubscribeReturned` |
| sourceOpen | bool | Current source `OperatorSubscriber` still the active upstream |
| replacement | `none` or observable input already converted | Set only after `selector` and `innerFrom` succeed |
| terminalReason | `none`, `complete`, `error`, `unsub` | Terminal cause for this machine |

### Σ (8 categories)

`srcError` may be consumed. `selectorThrow` and `innerFromThrow` are not source errors. After the replacement is subscribed, its `innerNext` / `innerError` / `innerComplete` are distinct from the source alphabet. There is no notifier, so those three are the replacement, not `notifierNext` / `notifierError` / `notifierComplete`.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub` → `eff:SubscribeSource(1)` |
| Source next | Yes | `srcNext(v)` forwarded while `active` |
| Source error | Yes | `srcError(e)` consumed |
| Source completion | Yes | `srcComplete` forwarded |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | Yes, the replacement observable | `innerNext(v)`, `innerError(e)`, `innerComplete` after `eff:SubscribeReturned`. No retry notifier |
| Time | No | No clock in this file |
| User callback outcomes | Yes | `selectorThrow(e)`, `innerFromThrow(e)` → `outError(thrown)`, original `e` dropped |

### Γ

| Symbol | Meaning |
| --- | --- |
| `outNext(v)` | Downstream next |
| `outError(e)` | Downstream error |
| `outComplete` | Downstream complete |
| `ε` | No observer notification |
| `eff:SubscribeSource(n)` | Subscribe source, new attempt id `n` |
| `eff:UnsubscribeSource` | Unsubscribe the source `OperatorSubscriber` |
| `eff:SubscribeReturned(obs)` | `innerFrom` result subscribed on the downstream subscriber |

`λ` may pair one notification with effects. Synchronous replacement traffic is an ordered continuation of `eff:SubscribeReturned`, not a hidden transition.

## C. Transition obligations

IDs are the `δ`/`λ` rows. Phases not used: `waiting-for-notifier`.

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | `sub` | — | active, attempt=1, sourceOpen | `ε` + `eff:SubscribeSource(1)` (`catchError.ts:113-126`) |
| T02 | active | `srcNext(v)` | source `OperatorSubscriber` not stopped | active | `outNext(v)` (`Subscriber.ts:112-114`) |
| T03 | active | `srcComplete` | — | terminal, terminalReason=complete, sourceOpen=false | `outComplete` (`Subscriber.ts:124-129`) |
| T04 | active | `srcError(e)` | `selector` returns; `innerFrom` ok; `innerSub` already assigned | resubscribing then forwarding | `ε` (source error consumed) + `eff:UnsubscribeSource` + `eff:SubscribeReturned` (`catchError.ts:115-119`). Inner notifications use T08–T10 |
| T05 | active | `srcError(e)` | same success, but `innerSub` still null (error during `source.subscribe`) | resubscribing then forwarding | same λ, deferred until `source.subscribe` returns (`catchError.ts:120-136`) |
| T06 | active | `srcError(e)` | `selector` throws or `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)`, not `outError(e)` (`OperatorSubscriber.ts:76-86`) |
| T07 | active or forwarding | `unsub` | downstream unsubscribes | terminal, terminalReason=unsub | `ε`. Child `OperatorSubscriber` and, once subscribed, the replacement are torn down via `destination.add` (`Subscriber.ts:53-54`, `Subscription.ts:47-90`) |
| T08 | forwarding | `innerNext(v)` | replacement subscribed on downstream | forwarding | `outNext(v)` — delivered by the replacement, not by this operator's handlers |
| T09 | forwarding | `innerError(e)` | — | terminal, terminalReason=error | `outError(e)`. This instance does not call `selector` again |
| T10 | forwarding | `innerComplete` | — | terminal, terminalReason=complete | `outComplete` |
| T11 | terminal | any | — | terminal | `ε` (`Subscriber.ts:81-88`, `Subscriber.ts:95-101`, stopped-notification path `Subscriber.ts:255-258`) |

T04/T05 ordering: unsubscribe the failed source subscription before `handledResult.subscribe` (`catchError.ts:117-119`, `catchError.ts:134-136`). The error handler's `finally` also unsubscribes that `OperatorSubscriber` (`OperatorSubscriber.ts:83-85`); the explicit `innerSub.unsubscribe()` is the earlier teardown so finalizers run before the replacement (`catchError.ts:128-133` comment).

`resubscribing` is not a stable wait. It is the ordered effect inside T04/T05. A synchronous error from the replacement is T09 before T04's handler returns. Nested `caught` subscriptions are new machines (new attempt ids), in-model as an ordered stack. Unbounded reentrancy is excluded.

## D. Contract invariants

1. While `phase=active`, every source next is forwarded and every source complete completes the output. `selector` is not called (`catchError.ts:114` passes `undefined, undefined` for next and complete).
2. A source error is never itself an `outError` from this operator. Either it is replaced by `outError(thrown)` (T06) or it is dropped and the replacement speaks (T04/T05).
3. `selectorThrow` and `innerFromThrow` are category 8, not category 3. The original `e` is discarded.
4. At most one source subscription is open. The replacement is subscribed only after that subscription is unsubscribed.
5. After T04/T05 this instance does not intercept the replacement. A later error is caught again only if the returned observable is itself under `catchError` (the `caught` value is that rewrap, `catchError.ts:115`).
6. `caught` is a fresh `operate` lift of `source`, so subscribing it re-enters `catchError` with the same `selector`. It is not a bare resubscribe of `source`.
7. Downstream `next` throws on the forwarded path are not caught here (`onNext` is absent). That is `Subscriber._next` (`Subscriber.ts:112-114`), outside T06.

## E. Scenario specification

Fields on every step: `phase`, `attempt`, `sourceOpen`, `replacement`, `terminalReason`.

### E1 — next then complete, no error

Oracle: source characterization. `onNext`/`onComplete` omitted (`catchError.ts:114`); default forward (`Subscriber.ts:112-129`).

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none | `sub` | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `ε` + `eff:SubscribeSource(1)` |
| 2 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcNext(1)` | same | `outNext(1)` |
| 3 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcComplete` | terminal, attempt=1, sourceOpen=false, replacement=none, terminalReason=complete | `outComplete` |

### E2 — async error, selector returns a different observable

Oracle: source characterization (`catchError.ts:115-119`). Spec file not executed.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none | `sub` | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `ε` + `eff:SubscribeSource(1)` |
| 2 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcNext(1)` | same | `outNext(1)` |
| 3 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcError(e)` and selector returns `obs` | forwarding, attempt=1, sourceOpen=false, replacement=obs, terminalReason=none | `ε` + `eff:UnsubscribeSource` + `eff:SubscribeReturned(obs)` |
| 4 | forwarding, attempt=1, sourceOpen=false, replacement=obs, terminalReason=none | `innerNext("I")` | same | `outNext("I")` |
| 5 | forwarding, attempt=1, sourceOpen=false, replacement=obs, terminalReason=none | `innerComplete` | terminal, attempt=1, sourceOpen=false, replacement=obs, terminalReason=complete | `outComplete` |

`e` is not emitted.

### E3 — selector throw

Oracle: source characterization. Throw lands in `OperatorSubscriber._error` (`OperatorSubscriber.ts:76-86`), which calls `destination.error(thrown)` and unsubscribes. `syncUnsub` stays false.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none | `sub` | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `ε` + `eff:SubscribeSource(1)` |
| 2 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcError(e)` + `selectorThrow(bad)` | terminal, attempt=1, sourceOpen=false, replacement=none, terminalReason=error | `outError(bad)` |

### E4 — selector returns `caught` (user-level resubscribe, not an internal counter)

Oracle: source characterization (`catchError.ts:115`). `innerFrom` returns the observable unchanged (`innerFrom.ts:17-18`). The new subscribe is another T01 of a fresh machine on the same downstream subscriber.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none | `sub` | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `ε` + `eff:SubscribeSource(1)` |
| 2 | active, attempt=1, sourceOpen=true, replacement=none, terminalReason=none | `srcError(e)`, selector returns `caught` | forwarding, attempt=1, sourceOpen=false, replacement=caught, terminalReason=none | `ε` + `eff:UnsubscribeSource` + `eff:SubscribeReturned(caught)` |
| 3 | new machine s₀ | that subscribe | new machine active, attempt=1 | `eff:SubscribeSource` of the rewrapped source |

A second error is handled only by the new machine. The first machine does not increment a retry count.

### E5 — synchronous source error

Oracle: source characterization (`catchError.ts:120-136`). Same λ as E2, but `eff:SubscribeReturned` runs after `source.subscribe` returns and after `innerSub.unsubscribe()`.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, sourceOpen=false, replacement=none, terminalReason=none | `sub` and sync `srcError(e)`, selector returns `obs` | forwarding, attempt=1, sourceOpen=false, replacement=obs, terminalReason=none | `ε` + `eff:UnsubscribeSource` + `eff:SubscribeReturned(obs)` |

## F. Coverage and evidence

Denominator: 11 transition rows T01–T11. Specified 11/11. Executed 0/11.

Secondary denominator, not executed: 23 `it(...)` cases in `/tmp/rxjs/spec/operators/catchError-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- `caught` is `catchError(selector)(source)`, not the bare source. Callers who expect a raw resubscribe must return `source` themselves; that path is still just T04/T05.
- This instance does not re-catch the replacement. Only the rewrapped `caught` observable does.
- Forwarded `srcNext` does not catch a throw from `destination.next` (`onNext` omitted).
- Unbounded synchronous re-entry through `caught` is excluded. One ordered resubscribe is in-model.
- `waiting-for-notifier` is unused. `innerNext` / `innerError` / `innerComplete` are the replacement's own protocol after `eff:SubscribeReturned`.
