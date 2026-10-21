# repeat

`repeat` resubscribes after source **complete**, not after error. A source error is forwarded by the default error path and the repeat stops (`repeat.ts:151-162` installs only `onComplete`). `count` is the total number of source subscriptions, including the first. The test is `++soFar < count` with `soFar` starting at `0` (`repeat.ts:131`, `repeat.ts:153`). `repeat(3)` subscribes three times (two resubscriptions). `repeat(1)` subscribes once and then completes. `repeat()` leaves `count` at `Infinity` and repeats forever (`repeat.ts:117-126`). `count <= 0` does not subscribe to the source: the operator function returns `() => EMPTY` (`repeat.ts:128-129`, `empty.ts:66`), which completes with no values. That is not `identity`. `delay`, when present, runs only if another subscription will happen. The delay function receives `soFar` after the increment (1 for the first gap). It is not called on the completing iteration that fails `++soFar < count`. A numeric delay uses `timer(delay)` (`repeat.ts:138`). The notifier subscriber overrides only next (`repeat.ts:139-142`): first next unsubscribes the notifier and subscribes the source; notifier complete with no next completes the output (default `_complete`); notifier error errors the output (default `_error`). A throw from the delay function is a category-8 fault inside the source complete handler and becomes `outError(thrown)` (`OperatorSubscriber.ts:89-99`).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `repeat` |
| Kind | Public pipeable operator |
| Module | `/tmp/rxjs/src/internal/operators/repeat.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `(countOrConfig?: number \| RepeatConfig) => MonoTypeOperatorFunction<T>` (`repeat.ts:116`) |
| `count` default | `Infinity` (`repeat.ts:117`, `repeat.ts:122`) |
| `count` meaning | Total subscriptions. Resubscribe while `++soFar < count` (`repeat.ts:153-160`) |
| `count <= 0` | `() => EMPTY`. Source is never subscribed (`repeat.ts:128-129`) |
| `delay` | Optional number or `(count: number) => ObservableInput` (`repeat.ts:15-21`, `repeat.ts:137-146`) |
| Error policy | Forwarded. Does not repeat (`repeat.ts:39`) |
| Complete policy | Repeat if under `count`, else `subscriber.complete()` (`repeat.ts:159-160`) |
| Delay notifier next | Unsubscribe notifier, `subscribeToSource` (`repeat.ts:139-141`) |
| Delay notifier complete | `outComplete`. No further subscribe |
| Delay notifier error | `outError` of the notifier error |
| Sync complete | `sourceSub` unset → `syncUnsub`; `resubscribe` after `source.subscribe` returns (`repeat.ts:154-167`) |
| Deprecated | No |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, soFar=0, attempt=0, count, delay=absent, notifierOpen=false, terminalReason=none)`.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `waitingNotifier`, `resubscribing`, `terminal`, `empty` | `empty` is the `count <= 0` shortcut, not a source subscription |
| soFar | nat | Completions observed. Also the argument to a delay function |
| attempt | nat | Source subscription id. Equals `soFar + 1` while a subscription is open and no delay is in flight |
| count | nat or `Infinity` | Max attempts, not extra repeats |
| delay | absent, number, or function | Absent: resubscribe inside the complete path |
| notifierOpen | bool | Delay notifier subscribed |
| terminalReason | `none`, `complete`, `error`, `unsub` | — |

### Σ (8 categories)

`srcError` is not consumed. `srcComplete` may be consumed in favor of another subscription. `notifierNext`, `notifierError`, and `notifierComplete` are distinct. `delayThrow` is not a source error.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub`, or T00 `EMPTY` when `count <= 0` (no source subscribe) |
| Source next | Yes | `srcNext(v)` forwarded on every attempt |
| Source error | Yes | `srcError(e)` forwarded. Does not repeat |
| Source completion | Yes | `srcComplete` resubscribes while `++soFar < count`, else `outComplete` |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | Yes, the delay notifier | `notifierNext` unsubscribes the notifier and subscribes the source; `notifierComplete` completes the output and does not subscribe; `notifierError(e)` errors the output |
| Time | Yes when `delay` is a number | `timer(delay)` on `asyncScheduler`. The operator waits in `waitingNotifier` until the notifier signals |
| User callback outcomes | Yes | `delayThrow(e)`, `innerFromThrow(e)` from the complete handler → `outError(thrown)` |

### Γ

| Symbol | Meaning |
| --- | --- |
| `outNext(v)`, `outError(e)`, `outComplete`, `ε` | Observer notifications |
| `eff:SubscribeSource(n)` | New attempt id |
| `eff:UnsubscribeSource` | `sourceSub?.unsubscribe()` before delay or resubscribe (`repeat.ts:135-136`) |
| `eff:SubscribeNotifier` | `timer(delay)` or `innerFrom(delay(soFar))` (`repeat.ts:138`) |
| `eff:UnsubscribeNotifier` | First notifier next (`repeat.ts:140`) |
| `eff:EmptyComplete` | `EMPTY` subscribe completes immediately |

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T00 | (operator apply) | config | `count <= 0` | empty | on later `sub`: `outComplete` + no source subscribe (`repeat.ts:128-129`, `empty.ts:66`) |
| T01 | init | `sub` | `count > 0` | active, attempt=1, soFar=0 | `ε` + `eff:SubscribeSource(1)` (`repeat.ts:170`) |
| T02 | active | `srcNext(v)` | — | active | `outNext(v)` |
| T03 | active | `srcError(e)` | — | terminal, terminalReason=error | `outError(e)`. `soFar` unchanged. No notifier (`Subscriber.ts:116-121`) |
| T04 | active | `srcComplete` | `++soFar < count` and `delay == null` and `sourceSub` set | resubscribing then active, attempt=attempt+1 | `ε` (this complete is not `outComplete`) + `eff:UnsubscribeSource` + `eff:SubscribeSource` (`repeat.ts:134-146`, `repeat.ts:153-155`) |
| T05 | active | `srcComplete` | under count, `delay == null`, `sourceSub` null | resubscribing then active | same λ after `source.subscribe` returns (`repeat.ts:156-158`, `repeat.ts:165-167`) |
| T06 | active | `srcComplete` | under count and `delay != null` | waitingNotifier, notifierOpen, soFar incremented | `ε` + `eff:UnsubscribeSource` + `eff:SubscribeNotifier` (`repeat.ts:135-143`) |
| T07 | waitingNotifier | `notifierNext` | first next | resubscribing then active, attempt=attempt+1, notifierOpen=false | `ε` + `eff:UnsubscribeNotifier` + `eff:SubscribeSource` (`repeat.ts:139-141`) |
| T08 | waitingNotifier | `notifierComplete` | no next on this notifier subscriber | terminal, terminalReason=complete | `outComplete` (default `_complete`). No `eff:SubscribeSource` |
| T09 | waitingNotifier | `notifierError(e2)` | — | terminal, terminalReason=error | `outError(e2)` |
| T10 | active | `srcComplete` | `++soFar >= count` | terminal, terminalReason=complete, soFar=count | `outComplete` (`repeat.ts:159-160`). `delay` is not consulted |
| T11 | active | `srcComplete` | under count but delay function or `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)` (`OperatorSubscriber.ts:89-99`) |
| T12 | active or waitingNotifier | `unsub` | — | terminal, terminalReason=unsub | `ε` |
| T13 | terminal or empty | any | — | same | `ε` |

`repeat(n)` performs `n` source subscriptions if each one completes and nothing unsubscribes. Extra repeats = `n - 1` for `n >= 1`. `repeat(1)` is T01 then T10, not "repeat one extra time".

T07 unsubscribes the notifier before the source subscribe, so a synchronous `notifierComplete` after that next is ignored (`isStopped`). T08 is only the no-next complete, including a delay observable that is empty. JSDoc states that empty-notifier case (`repeat.ts:19`).

`resubscribe` unsubscribes `sourceSub` before the next `subscribeToSource` (`repeat.ts:135-136`). For an asynchronous complete, that unsubscribe is the completing `OperatorSubscriber`, so source finalizers run before the next attempt. The handler `finally` unsubscribes again, idempotently (`OperatorSubscriber.ts:96-98`).

## D. Contract invariants

1. Errors do not repeat. Completions do, until `count` subscriptions have completed.
2. `count` is total subscriptions, not the retry-style "extra attempts" count. `repeat(n)` and `retry(n)` do not mean the same integer.
3. `repeat(0)` and negative counts are `EMPTY`, never `identity`. The source subscription count is 0.
4. No-arg `repeat()` is infinite completions, not a single pass.
5. `delay` is skipped on the final allowed completion (T10). The delay function sees `1 .. count-1` when `count` is finite, which is the number of completed subscriptions so far (`repeat.ts:16-18`, `repeat.ts:138`).
6. Notifier complete does not subscribe. Notifier next does. Notifier error fails the output after a successful source completion was already consumed.
7. Values from every attempt are forwarded. Nothing is replayed from a buffer; a new attempt is a new subscription.
8. One synchronous complete-resubscribe is in-model. An infinite synchronous complete loop (`count=Infinity` and a sync source) is excluded as unbounded reentrancy.

## E. Scenario specification

Fields: `phase`, `soFar`, `attempt`, `count`, `delay`, `notifierOpen`, `terminalReason`.

### E1 — `repeat(3)` completes three times

Oracle: source characterization (`repeat.ts:153-160`). Three subscriptions, then `outComplete`. Not executed.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, soFar=0, attempt=0, count=3, delay=absent, notifierOpen=false, terminalReason=none | `sub` | active, soFar=0, attempt=1, count=3, delay=absent, notifierOpen=false, terminalReason=none | `eff:SubscribeSource(1)` |
| 2 | active, soFar=0, attempt=1, count=3, … | `srcNext("a")`, `srcComplete` | active, soFar=1, attempt=2, … | `outNext("a")`, then `ε` + `eff:SubscribeSource(2)` |
| 3 | active, soFar=1, attempt=2, count=3, … | `srcComplete` | active, soFar=2, attempt=3, … | `ε` + `eff:SubscribeSource(3)` |
| 4 | active, soFar=2, attempt=3, count=3, … | `srcComplete` | terminal, soFar=3, attempt=3, terminalReason=complete | `outComplete` |

`++soFar` values are 1, 2, 3. Only 1 and 2 satisfy `< 3`.

### E2 — `repeat(1)` and `repeat(0)`

`repeat(1)`: T01 (attempt=1, soFar=0, count=1) then `srcComplete` → T10 because `1 < 1` is false. λ = `outComplete`. One subscription.

`repeat(0)`: phase=empty from T00. `sub` → `outComplete`, attempt stays 0, no `eff:SubscribeSource`.

### E3 — error does not repeat

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | active, soFar=1, attempt=2, count=Infinity, delay=absent, notifierOpen=false, terminalReason=none | `srcNext(1)`, `srcError(e)` | terminal, soFar=1, attempt=2, terminalReason=error | `outNext(1)`, `outError(e)` |

`soFar` stays 1. No T04.

### E4 — delay notifier: next resubscribes, bare complete does not

Config: `count=Infinity`, `delay=fn`. After one completion: waitingNotifier, soFar=1, attempt=1, notifierOpen=true, terminalReason=none. λ of that completion was `eff:UnsubscribeSource` + `eff:SubscribeNotifier` with `fn(1)`.

| Step | Input | After | λ |
| --- | --- | --- | --- |
| alt A | `notifierNext` | active, soFar=1, attempt=2, notifierOpen=false | `eff:UnsubscribeNotifier` + `eff:SubscribeSource(2)` |
| alt B | `notifierComplete` | terminal, soFar=1, attempt=1, terminalReason=complete | `outComplete`. No subscribe |
| alt C | `notifierError(e2)` | terminal, terminalReason=error | `outError(e2)` |

### E5 — finite count does not delay the last completion; delay throw

`count=3`, `delay=fn`. Completions call `fn(1)` and `fn(2)` only (T06). The third completion is T10: `outComplete`, `fn` not called.

If `fn(2)` throws: from waitingNotifier's next active subscription, `srcComplete` → T11, `outError(thrown)`, soFar=2, no `eff:SubscribeSource(3)`.

## F. Coverage and evidence

Denominator: 14 transition rows T00–T13. Specified 14/14. Executed 0/14.

Secondary denominator, not executed: 28 `it(...)` cases in `/tmp/rxjs/spec/operators/repeat-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- `count` is total subscriptions. `repeat(n)` is not "`n` extra repeats". `repeat(1)` emits the source once. This is the opposite integer convention from `retry(n)`.
- `repeat(0)` is `EMPTY`. `retry(0)` is `identity`.
- Notifier completion completes the output and does not subscribe. Notifier next does. The implementation gets that complete by omitting `onComplete`, not by an explicit `subscriber.complete()` callback (that explicit callback is what `retry` uses).
- `delay` is not applied after the last counted completion.
- `timer` makes numeric `delay: 0` asynchronous.
- Unbounded synchronous re-completion (`repeat()` on a synchronous source) is excluded. A single sync handoff (`syncUnsub`) is in-model.
- Spec arrays that list a delay-function argument equal to `count` are not what `repeat.ts:153` does; the function runs only while `++soFar < count`.
