# retryWhen

`retryWhen(notifier)` mirrors source next and complete. Complete does not retry (`onComplete` omitted, `retryWhen.ts:75`). The first source error creates a `Subject`, subscribes once to `innerFrom(notifier(errors$))`, then pushes the error into that subject (`retryWhen.ts:76-92`). Later errors only call `errors$.next(err)`. The source error is consumed. A notifier next resubscribes the source (new attempt id) and does not unsubscribe the notifier, so every later next resubscribes again (`retryWhen.ts:79-85`). A notifier complete uses the default complete path and completes the output without emitting the source error (`Subscriber.ts:124-129`). A notifier error uses the default error path and replaces the source error (`Subscriber.ts:116-121`). The factory is not called per error. Deprecated, removal planned in v9 or v10, with `retry`'s `delay` named as the replacement (`retryWhen.ts:63-65`). That replacement is not behaviorally identical (see G).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `retryWhen` |
| Kind | Public pipeable operator |
| Module | `/tmp/rxjs/src/internal/operators/retryWhen.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `(notifier: (errors: Observable<any>) => ObservableInput<any>) => MonoTypeOperatorFunction<T>` (`retryWhen.ts:67`) |
| Deprecated | Yes. "Will be removed in v9 or v10". Suggested form: `retry({ delay: () => notify$ })` (`retryWhen.ts:63-65`) |
| Notifier lifetime | One subscription, created on the first `srcError` (`retryWhen.ts:76-87`) |
| Error feed | `errors$.next(err)` after the notifier is subscribed (`retryWhen.ts:89-92`) |
| Notifier handlers | Only `onNext` is custom (`retryWhen.ts:79-85`). Complete and error are `Subscriber` defaults |
| Notifier next | If `innerSub` set, `subscribeForRetryWhen()` immediately. Else `syncResub = true` (`retryWhen.ts:79-85`, `retryWhen.ts:96-107`) |
| Notifier complete | `outComplete`. Source error is not emitted |
| Notifier error | `outError(notifierError)`. Source error is not emitted |
| Source complete | `outComplete`. Notifier is not signalled |
| Factory throw | Category 8, `destination.error(thrown)` from the source error handler (`OperatorSubscriber.ts:76-86`). `errors$.next` is not reached if the throw happens first |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, attempt=0, notifierState=unwired, heldError=none, terminalReason=none)`.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `waitingNotifier`, `resubscribing`, `terminal` | `waitingNotifier` means the source has errored, the error was or is being fed to `errors$`, and the output is still open |
| attempt | nat | Source subscription id. Each notifier-driven resubscribe increments it |
| notifierState | `unwired`, `open`, `closed` | `unwired` until the first error. Stays `open` across retries |
| heldError | `none` or error | Last consumed source error. Not an output unless some other path rethrows it (this operator does not) |
| terminalReason | `none`, `complete`, `error`, `unsub` | — |

### Σ (8 categories)

`notifierNext`, `notifierError`, and `notifierComplete` are distinct. The factory runs once; errors are pushed on a `Subject`. `srcError` is consumed.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub` → `eff:SubscribeSource(1)`. Notifier still unwired |
| Source next | Yes | `srcNext(v)` forwarded |
| Source error | Yes | `srcError(e)` consumed: `eff:ErrorsNext(e)`, not `outError(e)` |
| Source completion | Yes | `srcComplete` forwarded. Notifier is not asked to retry |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | Yes | `notifierNext` resubscribes and leaves the notifier open; `notifierComplete` completes the output and does not emit the source error; `notifierError(e)` replaces the source error |
| Time | No | No clock in this file |
| User callback outcomes | Yes | `notifierFactoryThrow(e)`, `innerFromThrow(e)` → `outError(thrown)`, and `errors$.next` is skipped if the throw aborts the handler |

### Γ

| Symbol | Meaning |
| --- | --- |
| `outNext(v)`, `outError(e)`, `outComplete`, `ε` | Observer notifications |
| `eff:SubscribeSource(n)` | New attempt |
| `eff:UnsubscribeSource` | Explicit only on the `syncResub` path after `source.subscribe` returns (`retryWhen.ts:100-102`). On the async path the failing `OperatorSubscriber` unsubscribes in `finally` after the handler (`OperatorSubscriber.ts:83-85`) |
| `eff:SubscribeNotifier` | Once |
| `eff:ErrorsNext(e)` | `errors$.next(err)` (`retryWhen.ts:91`) |

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | `sub` | — | active, attempt=1, notifierState=unwired | `ε` + `eff:SubscribeSource(1)` (`retryWhen.ts:110-111`) |
| T02 | active | `srcNext(v)` | — | active | `outNext(v)` |
| T03 | active | `srcComplete` | — | terminal, terminalReason=complete | `outComplete`. Notifier not subscribed if still unwired; if open, destination complete tears it down |
| T04 | active | `srcError(e)` | notifier unwired; factory and `innerFrom` ok | waitingNotifier, notifierState=open, heldError=e | `ε` + `eff:SubscribeNotifier` + `eff:ErrorsNext(e)` (`retryWhen.ts:76-92`) |
| T05 | waitingNotifier or active | `srcError(e)` | notifier already open | waitingNotifier, heldError=e | `ε` + `eff:ErrorsNext(e)` only |
| T06 | waitingNotifier | `notifierNext` | `innerSub` assigned (async error) | resubscribing then active, attempt=attempt+1 | `ε` + `eff:SubscribeSource(new)` . Notifier stays open (`retryWhen.ts:79-85`) |
| T07 | waitingNotifier | `notifierNext` | `innerSub` still null | resubscribing then active | flag `syncResub`; after `source.subscribe` returns: `eff:UnsubscribeSource` + `eff:SubscribeSource` (`retryWhen.ts:96-107`) |
| T08 | waitingNotifier | `notifierComplete` | notifier subscriber not stopped | terminal, terminalReason=complete | `outComplete`. No `outError(heldError)` (`Subscriber.ts:124-129`) |
| T09 | waitingNotifier | `notifierError(e2)` | — | terminal, terminalReason=error | `outError(e2)` (`Subscriber.ts:116-121`) |
| T10 | active | `srcError(e)` | factory or `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)`. `eff:ErrorsNext` does not run if the throw aborts the handler (`OperatorSubscriber.ts:76-86`) |
| T11 | any non-terminal | `unsub` | — | terminal, terminalReason=unsub | `ε` |
| T12 | terminal | any | — | terminal | `ε` |

Order on first error (`retryWhen.ts:76-92`): subscribe the notifier, then `errors$.next`. A notifier that emits `notifierNext` synchronously from its own subscribe (before it sees the error) takes T06/T07 before `eff:ErrorsNext`. The error is still pushed afterward.

`subscribeForRetryWhen` assigns `innerSub` without unsubscribing the previous source first (`retryWhen.ts:74`). The previous source's `OperatorSubscriber` unsubscribes in the error handler `finally`, which runs after a synchronous T06 returns. Overlap until that `finally` is the ordered sync effect. A second synchronous `notifierNext` before that `finally` can start another source subscription and orphan the middle one. That multi-next reentrancy is excluded.

Notifier `next` then `complete` on the same notifier subscriber: T06 runs, then T08, because next does not unsubscribe the notifier. T08 completes the destination and tears down the subscription T06 just started, after any synchronous values from that new attempt. This differs from `retry`'s delay notifier, which unsubscribes on the first next so a trailing complete is ignored.

## D. Contract invariants

1. Source complete is not a retry trigger and is not written to `errors$`.
2. Source errors are not `outError` while the output stays open. They are `eff:ErrorsNext` inputs to the user notifier.
3. Notifier complete completes the output and does not subscribe. Notifier error errors the output. Neither emits `heldError`.
4. The notifier factory runs at most once per downstream subscription.
5. Notifier next does not complete or error the output by itself, and does not close the notifier.
6. Factory throw is not `outError(source error)`.
7. Each surviving resubscribe has a new attempt id and a new `OperatorSubscriber`.

## E. Scenario specification

Fields: `phase`, `attempt`, `notifierState`, `heldError`, `terminalReason`.

### E1 — error, notifier next, then source complete

Oracle: source characterization (`retryWhen.ts:73-92`). Not executed.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, attempt=0, notifierState=unwired, heldError=none, terminalReason=none | `sub` | active, attempt=1, notifierState=unwired, heldError=none, terminalReason=none | `eff:SubscribeSource(1)` |
| 2 | active, attempt=1, notifierState=unwired, heldError=none, terminalReason=none | `srcNext(1)`, `srcError(e)` | waitingNotifier, attempt=1, notifierState=open, heldError=e, terminalReason=none | `outNext(1)`, `ε` + `eff:SubscribeNotifier` + `eff:ErrorsNext(e)` |
| 3 | waitingNotifier, attempt=1, notifierState=open, heldError=e, terminalReason=none | `notifierNext` | active, attempt=2, notifierState=open, heldError=e, terminalReason=none | `eff:SubscribeSource(2)` |
| 4 | active, attempt=2, notifierState=open, heldError=e, terminalReason=none | `srcComplete` | terminal, attempt=2, notifierState=closed, heldError=e, terminalReason=complete | `outComplete` |

`e` never appears as `outError`.

### E2 — notifier complete swallows the error

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | active, attempt=1, notifierState=unwired, heldError=none, terminalReason=none | `srcError(e)`, notifier is empty (completes on subscribe, no next) | terminal, attempt=1, notifierState=closed, heldError=e, terminalReason=complete | `outComplete` |

T04's subscribe runs T08 synchronously before `eff:ErrorsNext`. Output is complete. No resubscribe. Matches the control flow of an empty notifier on a throwing source: complete, not error.

### E3 — notifier error replaces the source error

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | waitingNotifier, attempt=1, notifierState=open, heldError=e, terminalReason=none | `notifierError(e2)` | terminal, attempt=1, notifierState=closed, heldError=e, terminalReason=error | `outError(e2)` |

### E4 — source error is not sent to the notifier when the source completes first

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | active, attempt=1, notifierState=unwired, heldError=none, terminalReason=none | `srcComplete` | terminal, attempt=1, notifierState=unwired, heldError=none, terminalReason=complete | `outComplete` |

### E5 — factory throw

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | active, attempt=1, notifierState=unwired, heldError=none, terminalReason=none | `srcError(e)` + `notifierFactoryThrow(bad)` | terminal, attempt=1, notifierState=unwired, heldError=none, terminalReason=error | `outError(bad)` |

## F. Coverage and evidence

Denominator: 12 transition rows T01–T12. Specified 12/12. Executed 0/12.

Secondary denominator, not executed: 23 `it(...)` cases in `/tmp/rxjs/spec/operators/retryWhen-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- Notifier completion completes the output and does not resubscribe. The source error is not emitted. Notifier error replaces it.
- Unlike `retry`'s `delay`, the notifier is not unsubscribed on next, the factory runs once, and a trailing `notifierComplete` after `notifierNext` still takes T08 and completes the destination.
- `retry({ delay: () => notify$ })` is the documented migration, not a semantic alias: `delay` is invoked per error, receives `(error, retryCount)`, and drops the notifier after the first next.
- Synchronous double `notifierNext` can orphan a source subscription because `innerSub` is overwritten before the previous error handler's `finally`. Excluded as unbounded reentrancy. One synchronous resubscribe is in-model.
- `errors$.next` after a synchronous T08/T09 hits a subject whose observers are already torn down with the destination. No second terminal is delivered.
