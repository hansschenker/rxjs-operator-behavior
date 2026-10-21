# retry

`retry` mirrors the source until an error. `complete` is forwarded and does not retry (`retry.ts:112-113`). An error is consumed while `soFar++ < count` (`retry.ts:115`): the failed subscription is unsubscribed and the source is subscribed again under a new attempt id. `count` is the number of retries (resubscriptions after error), not the number of total attempts. `retry(2)` allows two resubscriptions, so three source subscriptions, then forwards the next error (`retry.ts:40-47`, `retry.ts:115-156`). Omitted `count` is `Infinity` (`retry.ts:84`, `retry.ts:93`). `count <= 0` does not run this machine: the operator function is `identity` (`retry.ts:95-96`, `identity.ts:43-45`), so the source is unchanged, including its errors. `resetOnSuccess` defaults to `false` (`retry.ts:93`). When `true`, every source next sets `soFar = 0` before the value is forwarded (`retry.ts:105-110`). `delay` may be absent, a number, or `(error, retryCount) => ObservableInput`. A number uses `timer(delay)` (`retry.ts:131`). The function is called with the already incremented `soFar`, so the first retry passes `1`. The delay notifier's first next unsubscribes the notifier and resubscribes (`retry.ts:134-139`). Notifier complete without a next completes the output and does not emit the source error (`retry.ts:141-145`). Notifier error replaces the source error (`onError` omitted on the notifier subscriber, `Subscriber.ts:116-121`). A throw from the delay function is category 8 and becomes `outError(thrown)` (`OperatorSubscriber.ts:76-86`).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `retry` |
| Kind | Public pipeable operator (`MonoTypeOperatorFunction`) |
| Module | `/tmp/rxjs/src/internal/operators/retry.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `retry(count?: number)` or `retry(config: RetryConfig)` (`retry.ts:34-35`, `retry.ts:84`) |
| `RetryConfig.count` | Max retries. Omitted means infinite resubscribe (`retry.ts:15-17`, `retry.ts:93`) |
| `RetryConfig.delay` | `number` or `(error, retryCount) => ObservableInput` (`retry.ts:20-26`, `retry.ts:127-147`) |
| `RetryConfig.resetOnSuccess` | Default `false` (`retry.ts:27-31`, `retry.ts:93`) |
| `count <= 0` | `identity` — not an empty observable (`retry.ts:95-96`) |
| Error policy | Consume and resubscribe while retries remain; otherwise `subscriber.error(err)` with the same error (`retry.ts:152-156`) |
| Complete policy | Always forwarded. No resubscribe |
| Delay notifier next | Unsubscribe notifier, then resubscribe source (`retry.ts:134-139`) |
| Delay notifier complete | `subscriber.complete()`. No resubscribe. Source error not emitted (`retry.ts:141-145`) |
| Delay notifier error | Forwarded as `outError`. Source error not also emitted |
| Sync resubscribe | If `innerSub` is still null, set `syncUnsub` and resubscribe after `source.subscribe` returns (`retry.ts:122-124`, `retry.ts:160-164`) |
| Deprecated | No. `retryWhen` points here (`retryWhen.ts:63-65`) |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, soFar=0, attempt=0, count, delay, resetOnSuccess=false, notifierOpen=false, terminalReason=none)`.

If `count <= 0`, there is no run of `M`: λ of applying the operator is the identity function.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `waitingNotifier`, `resubscribing`, `terminal`, `identity` | `resubscribing` is the ordered teardown-then-subscribe, sync or after notifier next |
| soFar | nat | Retries already started. Incremented on the error check even when the comparison fails (`retry.ts:115`) |
| attempt | nat | 0-based source subscription index. Attempt 0 is the original subscription. Retries use attempt `1..count` |
| count | nat or `Infinity` | Max value of retries, not of attempts |
| delay | absent, number, or function | Absent means immediate resubscribe |
| resetOnSuccess | bool | Default false. `true` clears `soFar` on every next |
| notifierOpen | bool | Delay notifier subscribed |
| terminalReason | `none`, `complete`, `error`, `unsub` | — |

### Σ (8 categories)

`notifierNext`, `notifierError`, and `notifierComplete` are distinct inner symbols. `srcError` is consumable while retries remain. `delayThrow` is not a source error.

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub`, or T00 `identity` when `count <= 0` (no subscribe wrapper) |
| Source next | Yes | `srcNext(v)`; may zero `soFar` when `resetOnSuccess` |
| Source error | Yes | `srcError(e)` consumed and resubscribed, or forwarded when the retry budget is spent |
| Source completion | Yes | `srcComplete` forwarded. Does not retry |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | Yes, the delay notifier | `notifierNext` resubscribes and unsubscribes the notifier; `notifierComplete` completes the output and does not resubscribe; `notifierError(e)` replaces the source error |
| Time | Yes when `delay` is a number | `timer(delay)` on `asyncScheduler`, including `delay: 0` (`timer.ts:159-184`). Not a separate alphabet symbol; it shows up as a later `notifierNext` |
| User callback outcomes | Yes | `delayThrow(e)`, `innerFromThrow(e)` → `outError(thrown)` |

### Γ

| Symbol | Meaning |
| --- | --- |
| `outNext(v)`, `outError(e)`, `outComplete`, `ε` | Observer notifications |
| `eff:SubscribeSource(n)` | New attempt id `n` |
| `eff:UnsubscribeSource` | Tear down current source subscription before the next attempt |
| `eff:SubscribeNotifier` | `timer(delay)` or `innerFrom(delay(err, soFar))` (`retry.ts:131`) |
| `eff:UnsubscribeNotifier` | On first notifier next (`retry.ts:138`) |

`timer` clamps a negative due to `0` and schedules on `asyncScheduler` (`timer.ts:159-184`). `delay: 0` and `delay < 0` are still asynchronous waits, not T07.

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T00 | (operator apply) | config | `count <= 0` | identity | no subscribe wrapper (`retry.ts:95-96`) |
| T01 | init | `sub` | `count > 0` | active, attempt=1, soFar=0 | `ε` + `eff:SubscribeSource(1)` (`retry.ts:166`) |
| T02 | active | `srcNext(v)` | `resetOnSuccess` | active, soFar=0 | `outNext(v)` (`retry.ts:107-110`) |
| T03 | active | `srcNext(v)` | not `resetOnSuccess` | active, soFar unchanged | `outNext(v)` |
| T04 | active | `srcComplete` | — | terminal, terminalReason=complete | `outComplete` (`retry.ts:112-113`, `Subscriber.ts:124-129`) |
| T05 | active | `srcError(e)` | `soFar < count` after reading pre-increment; `delay == null`; `innerSub` set | resubscribing, then active, soFar=soFar+1, attempt=attempt+1 | `ε` (error consumed) + `eff:UnsubscribeSource` + `eff:SubscribeSource(attempt+1)` (`retry.ts:115-125`, `retry.ts:148-150`) |
| T06 | active | `srcError(e)` | retries remain, `delay == null`, `innerSub` null | resubscribing, then active | same λ, after `source.subscribe` returns (`retry.ts:160-164`) |
| T07 | active | `srcError(e)` | retries remain and `delay != null` | waitingNotifier, soFar incremented, notifierOpen | `ε` + `eff:SubscribeNotifier`. `retryCount` argument is the new `soFar` (`retry.ts:127-147`) |
| T08 | waitingNotifier | `notifierNext` | first next | resubscribing, then active, attempt=attempt+1, notifierOpen=false | `ε` + `eff:UnsubscribeNotifier` + `eff:UnsubscribeSource` + `eff:SubscribeSource` (`retry.ts:134-139`, `retry.ts:117-121`) |
| T09 | waitingNotifier | `notifierComplete` | no next yet | terminal, terminalReason=complete | `outComplete`. Source error not emitted (`retry.ts:141-145`) |
| T10 | waitingNotifier | `notifierError(e2)` | no next yet | terminal, terminalReason=error | `outError(e2)`, not `e` (`Subscriber.ts:116-121`) |
| T11 | active | `srcError(e)` | `soFar >= count` before increment succeeds | terminal, terminalReason=error, soFar=soFar+1 | `outError(e)` (`retry.ts:152-156`) |
| T12 | active | `srcError(e)` | delay function or `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)` (`OperatorSubscriber.ts:76-86`). Original `e` consumed |
| T13 | active or waitingNotifier | `unsub` | — | terminal, terminalReason=unsub | `ε` + drop source and notifier |
| T14 | terminal or identity | any further source traffic | stopped | same | `ε` |

Post-increment: the comparison is `soFar++ < count` (`retry.ts:115`). The first error sees `0 < count`. After `count` successful retry decisions, the next error takes T11. Total source subscriptions on a pure error loop is `count + 1`.

T08 vs T09: `timer` emits then completes. The next handler unsubscribes the notifier subscriber first, so the following complete sees `isStopped` and is not T09 (`retry.ts:138`, `Subscriber.ts:95-97`). A notifier that completes with no next is T09, not a resubscribe.

T05 orders `eff:UnsubscribeSource` before `eff:SubscribeSource` (`retry.ts:118-121`). The error handler `finally` unsubscribes the same `OperatorSubscriber` again (`OperatorSubscriber.ts:83-85`); that second unsubscribe is idempotent (`Subscription.ts:50`).

`resetOnSuccess` does not reset on error, only on next. The JSDoc phrase "first value" (`retry.ts:28-30`) matches the code because later nexts only write `0` again.

## D. Contract invariants

1. `complete` never starts a retry and never consults `delay`.
2. `count` counts consumed errors that led to `eff:SubscribeSource`, not total attempts. Attempts = retries + 1 when the source keeps failing.
3. Default `count` is `Infinity`. Default `resetOnSuccess` is `false`. Default `delay` is immediate resubscribe (`delay == null`). `delay: 0` is not immediate; it is `timer(0)`.
4. While retries remain, the source error object is not an output. T11 is the only path that outputs that same object.
5. Notifier complete (T09) and notifier error (T10) both drop the source error. T09 completes; T10 errors with the notifier's error.
6. A new attempt always uses a new `OperatorSubscriber`. The previous one is stopped by its own error path.
7. `identity` (`count <= 0`) does not swallow errors and does not subscribe through `operate`.
8. Synchronous resubscribe is one ordered T05/T06/T08. Unbounded reentrant failure loops are excluded.

## E. Scenario specification

Fields: `phase`, `soFar`, `attempt`, `count`, `delay`, `resetOnSuccess`, `notifierOpen`, `terminalReason`.

### E1 — `retry(2)`, three failures

`count=2` means two retries. Oracle: source characterization of `retry.ts:115-156`. The spec name "count=3" in the suite is not this number; `retry(2)` subscribes three times. Not executed.

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, soFar=0, attempt=0, count=2, delay=absent, resetOnSuccess=false, notifierOpen=false, terminalReason=none | `sub` | active, soFar=0, attempt=1, count=2, delay=absent, resetOnSuccess=false, notifierOpen=false, terminalReason=none | `eff:SubscribeSource(1)` |
| 2 | active, soFar=0, attempt=1, … | `srcNext(1)` then `srcError(e)` | active, soFar=1, attempt=2, notifierOpen=false, terminalReason=none | `outNext(1)`, then `ε` + `eff:UnsubscribeSource` + `eff:SubscribeSource(2)` |
| 3 | active, soFar=1, attempt=2, … | `srcError(e)` | active, soFar=2, attempt=3, … | `ε` + resubscribe |
| 4 | active, soFar=2, attempt=3, … | `srcError(e)` | terminal, soFar=3, attempt=3, terminalReason=error | `outError(e)` |

### E2 — `retry()` infinite, then complete

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | init, soFar=0, attempt=0, count=Infinity, delay=absent, resetOnSuccess=false, notifierOpen=false, terminalReason=none | `sub` | active, attempt=1, soFar=0, count=Infinity, … | `eff:SubscribeSource(1)` |
| 2 | active, soFar=0, attempt=1, count=Infinity, … | `srcError(e)` | active, soFar=1, attempt=2, count=Infinity, … | `ε` + resubscribe |
| 3 | active, soFar=1, attempt=2, … | `srcNext(1)`, `srcComplete` | terminal, soFar=1, attempt=2, terminalReason=complete | `outNext(1)`, `outComplete` |

No T11 while `count` is `Infinity` for finite `soFar`.

### E3 — delay notifier complete vs next vs error

Config: `count=Infinity`, `delay=fn`, `resetOnSuccess=false`. Start: active, soFar=0, attempt=1, notifierOpen=false, terminalReason=none.

| Step | Input | After | λ |
| --- | --- | --- | --- |
| 1 | `srcError(e1)`, `fn` returns a notifier | waitingNotifier, soFar=1, attempt=1, notifierOpen=true | `ε` + `eff:SubscribeNotifier` with `fn(e1, 1)` |
| 2a | `notifierComplete` | terminal, terminalReason=complete, notifierOpen=false | `outComplete` (T09). Not `eff:SubscribeSource` |
| 2b | `notifierError(e2)` | terminal, terminalReason=error | `outError(e2)` (T10) |
| 2c | `notifierNext` | active, soFar=1, attempt=2, notifierOpen=false | `eff:UnsubscribeNotifier` + `eff:SubscribeSource(2)` (T08). A following `notifierComplete` is ignored because the notifier subscriber is already stopped |

2a, 2b, and 2c are alternatives from the same waiting state.

### E4 — `resetOnSuccess: true`

| Step | Before | Input | After | λ |
| --- | --- | --- | --- | --- |
| 1 | active, soFar=0, attempt=1, count=1, resetOnSuccess=true, delay=absent, notifierOpen=false, terminalReason=none | `srcError(e)` | active, soFar=1, attempt=2, … | resubscribe (the one allowed retry) |
| 2 | active, soFar=1, attempt=2, count=1, resetOnSuccess=true, … | `srcNext(v)` | active, soFar=0, attempt=2, … | `outNext(v)` (T02) |
| 3 | active, soFar=0, attempt=2, count=1, … | `srcError(e2)` | active, soFar=1, attempt=3, … | resubscribe again, because `0 < 1` |

Without the next, a second error would be T11.

### E5 — `retry(0)` and delay-function throw

`retry(0)`: T00, phase=identity. Source error is the source's own `outError`. No `soFar`.

Delay throw, from waiting-bound error with retries left: active, soFar=0, attempt=1, delay=fn. Input `srcError(e)` plus `delayThrow(bad)`. After: terminal, terminalReason=error. λ = `outError(bad)`. `e` is not forwarded (T12).

## F. Coverage and evidence

Denominator: 15 transition rows T00–T14. Specified 15/15. Executed 0/15.

Secondary denominator, not executed: 29 `it(...)` cases in `/tmp/rxjs/spec/operators/retry-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- `count` is retries, not total subscriptions. `retry(n)` failing forever subscribes `n + 1` times.
- `retry(0)` and any `count <= 0` are `identity`, unlike `repeat(0)` which is `EMPTY`.
- Notifier completion completes the output. It does not resubscribe. Notifier error replaces the source error.
- `delay: 0` goes through `timer` and `asyncScheduler`, so it is `waitingNotifier`, not a synchronous T05.
- `resetOnSuccess` clears `soFar` on every next, which matches "reset on first value" for the counter.
- Numeric overflow of `soFar` under `Infinity`, `NaN` counts (`NaN <= 0` is false, and `soFar < NaN` is false, so the first error is T11), and unbounded synchronous re-error are excluded.
- Migration text from `retryWhen` is not a pure alias: `retry` builds a new delay notifier per error and unsubscribes it on the first next; `retryWhen` keeps one notifier.
