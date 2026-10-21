# multicast

Deprecated (every overload’s JSDoc, `operators/multicast.ts` 15–20, 31–34, 50–54, 66–69, 77–80). Will be removed in v8. Two runtime shapes (`multicast.ts` 82–98):

- If `selector` is a function, the operator is `connect(selector, { connector: subjectFactory })` (`operators/connect.ts` 99–109). `subjectOrSubjectFactory` is wrapped so a `Subject` instance becomes `() => thatSameSubject`, while a factory is kept (`multicast.ts` 86).
- If `selector` is absent, the operator returns `new ConnectableObservable(source, subjectFactory)` (`observable/ConnectableObservable.ts` 16–95). Nothing is subscribed until `connect()` or a later `refCount`.

`ConnectableObservable._subscribe` only subscribes the caller to `getSubject()` (lines 43–45). `getSubject` calls the factory when `_subject` is null or `isStopped` (lines 47–53). `connect` (lines 66–95) subscribes the source once, through an `OperatorSubscriber` whose complete and error handlers call `_teardown` and then `subject.complete` / `subject.error`. `_teardown` (lines 55–60) zeros `_refCount`, nulls `_subject` and `_connection`, and unsubscribes the connection. The factory still decides what the next `getSubject` returns. `publish`, `publishBehavior`, `publishLast`, and `publishReplay` pass `() => theSameSubject`, so a stopped subject is handed out again. A caller-supplied factory can return a fresh subject after `_subject` was nulled.

Equivalences in the JSDoc, not extra behavior: `multicast(subject), refCount()` is described as `share({ connector: () => subject, resetOnError: false, resetOnComplete: false, resetOnRefCountZero: false })` (lines 17–18). `multicast(factory), refCount()` is described as `share({ connector: factory })` (lines 52–53), which uses `share`’s default resets. Those are documentation pointers. This file’s own non-selector machine is `ConnectableObservable`, not `share`.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `shape` | `connectable \| selector` | chosen when the operator is applied | — |
| `phase` | `idle \| subscribedSilent \| connected \| completed \| errored \| cancelled` | `idle` | `subscribedSilent`: observers sit on the subject, `connect()` has not been called. |
| `subjectFactory` | `() => Subject` | wrapped argument | — |
| `subject` | `Subject \| none` | none until `getSubject` | `_subject`. |
| `connection` | `Subscription \| none` | none | `_connection`. Idempotent `connect` while this is set and not closed (lines 67–68). |
| `selector` | function or absent | — | Selector shape only. Per outer subscription, see `connect.md`. |

`ConnectableObservable` also has `_refCount`, but only `refCount` and `_teardown` touch it. It stays `0` if nobody calls `refCount`.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Non-selector rows are the connectable. Selector rows delegate.

### S

| Location | Meaning |
| --- | --- |
| `idle` | No subject yet, or `_teardown` cleared it. |
| `subscribedSilent` | At least one subscriber on the subject. Source not connected. |
| `connected` | `_connection` set. Source notifications go to the subject. |
| `completed` | Source completed; `_teardown` ran; then `subject.complete()`. |
| `errored` | Source errored; `_teardown` ran; then `subject.error(e)`. |
| `cancelled` | `connect()`’s subscription was unsubscribed by the user, which runs the subscriber finalizer `_teardown` (line 84). |

Selector shape does not use these locations across outer subscribers. Each subscribe to the operator result is a fresh `connect` execution. If the factory closes over one `Subject`, those executions still share that subject. See D6.

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Connectable: subject only. Selector: `connect`’s per-subscription setup. |
| 2 | Downstream cancel | `unsubscribe` | Leaves the subject. Does not by itself clear `_connection`. |
| 3 | Source next | `sourceNext(v)` | Only after `connect`. `subject.next(v)`. |
| 4 | Source error | `sourceError(e)` | `_teardown` then `subject.error`. |
| 5 | Source complete | `sourceComplete` | `_teardown` then `subject.complete`. |
| 6 | Connect | `connect` | User calls `ConnectableObservable.connect`. |
| 7 | Disconnect | `connection.unsubscribe` | User-driven. Also the finalizer path. |
| 8 | Selector | `selector(shared)` | Only the selector overload. No scheduler. |

### Γ

`ε`, `getSubject` (maybe `subjectFactory()`), `subSource`, `unsubSource`, `outNext(v)`, `outError(e)`, `outComplete`, `syncTerminal` for a subscriber who joins a stopped subject.

No output on `subscribe` before `connect`, except what the subject itself pushes. A plain `Subject` pushes nothing. `BehaviorSubject` / `ReplaySubject` / `AsyncSubject` push according to their classes; those are the `publish*` files.

## C. Transition obligations

Non-selector (`ConnectableObservable.ts` 43–95):

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `subscribedSilent` | `getSubject`; if none or stopped, `subject := subjectFactory()`. Subscriber joins the subject. No `subSource`. |
| T02 | waiting | `subscribedSilent` or `connected` | `subscribe` | subject not stopped | same | another join. No extra `subSource`. |
| T03 | init | `subscribedSilent` | `connect` | `_connection` unset | `connected` | `subSource` once (lines 66–87) |
| T04 | waiting | `connected` | `connect` | `_connection` already set and not closed | `connected` | `ε`. Returns the same subscription (lines 67–68). |
| T05 | emitting | `connected` | `sourceNext(v)` | — | `connected` | `outNext(v)` to subject observers |
| T06 | per-source error | `connected` | `sourceError(e)` | — | `errored` | `_teardown`: `unsubSource`, `_subject = null`, `_refCount = 0`; then `subject.error(e)` (lines 81–83, 55–60) |
| T07 | terminal | `connected` | `sourceComplete` | — | `completed` | `_teardown`, then `subject.complete()` (lines 76–79) |
| T08 | cancel | `subscribedSilent` | `unsubscribe` | last or not; connection was never created | `subscribedSilent` or `idle` if no observers left | `ε`. Source stays unsubscribed. Location returns to `idle` only in the sense that no observers remain; `_subject` is kept. |
| T09 | cancel | `connected` | `unsubscribe` of one observer | `_connection` untouched | `connected` | `ε`. Other observers remain. Source stays connected. This operator does not refCount. |
| T10 | cancel | `connected` | `connection.unsubscribe` | user disconnect | `idle` | finalizer `_teardown` (line 84): `unsubSource`, drop `_subject`. Observers are not completed by `_teardown` itself. |
| T11 | waiting | `completed` or `errored` | `subscribe` | factory returns the same stopped subject | same | `syncTerminal`: `Subject` errors with `thrownError` or completes (`Subject.ts` 136–144). No `subSource`. |
| T12 | waiting | `completed` or `errored` | `subscribe` | factory returns a new subject because the old one `isStopped` and the factory is not a constant | `subscribedSilent` | join the fresh subject. Still no `subSource` until T03. |
| T13 | terminal | `connected` | `connect`’s subscribe closes the connection synchronously | source completes or errors inside `subSource` | `completed` or `errored` | T06 or T07, and `connect` returns `Subscription.EMPTY` because `connection.closed` (lines 89–92). |
| T14 | terminal | terminal or `idle` | ignored source notification | no connection | same | `ε` |

Selector shape:

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T15 | init | `idle` | `subscribe` | `selector` present | per `connect.md` | `connect(selector, { connector: subjectFactory })` (`multicast.ts` 88–94) |
| T16 | cancel | that execution | selector result terminates or downstream `unsubscribe` | — | done for that subscriber | source unsubscribe is the one `connect` added (`connect.ts` 107) |

## D. Contract invariants

1. Without `selector`, `subscribe` never subscribes the source. Only `connect` does, and a live `_connection` makes `connect` a no-op (T03, T04).
2. Source `error` and `complete` always `_teardown` before they notify the subject, so `_connection` is cleared and `_subject` is nulled first. The local `subject` variable still receives the terminal (T06, T07).
3. Disconnect by unsubscribing the connection tears the source down and drops the subject reference (T10). It does not by itself complete observers.
4. A constant `() => sharedSubject` factory cannot recover after the subject stops: `getSubject` calls the factory because `isStopped` is true, and gets the stopped instance back (T11). A real factory that allocates can return a cold subject (T12) but still waits for a new `connect`.
5. Observer `unsubscribe` is not `unsubSource` (T09). Use `refCount` or unsubscribe the connection. `refCount` is a different operator (`refCount.md`).
6. With `selector`, multicast does not return a `ConnectableObservable`. Each subscription to the result runs `connect`. A constant subject is then shared across those `connect` executions, and each of them calls `source.subscribe(subject)` (`connect.ts` 107). That can subscribe the source more than once. A factory subject is fresh per `connect` execution.
7. The class and the operator are deprecated. `hasLift` is copied onto the connectable so subclass `lift` still composes (`ConnectableObservable.ts` 34–39). That lift copy is not a notification transition.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Subscribe does nothing until connect

`src.pipe(multicast(new Subject()))`. Two `subscribe`s are T01 and T02. Source side effects have not run. `connect()` is T03 `subSource`. `sourceNext(1)` is T05 `outNext(1)` to both. A second `connect()` is T04.

### E2. Complete then late subscriber, constant subject

Source completes. T07 nulls `_subject`, then the same subject completes. Observers get `outComplete`. A later `subscribe` calls `getSubject`, sees a null `_subject` or would see `isStopped`, calls `() => thatSameSubject`, and T11 `syncComplete`. `connect()` after that subscribes the source again (T03) but `getSubject` still returns the stopped subject, so new source values go to a stopped `Subject.next`, which drops them (`Subject.ts` 59–62). This constant-subject trap is why `publish` documents `resetOnDisconnect: false`.

### E3. User disconnect

After T03, the caller unsubscribes the subscription `connect` returned. T10 `_teardown`. Observers do not get `outComplete`. A later `connect` can `subSource` again. What they hear depends on whether `subjectFactory` returns a new subject or the old one (D4).

### E4. Error

`sourceError(e)` while connected. T06: connection cleared, then observers get `outError(e)`. A late subscriber on a constant subject gets T11 `syncError(e)`. No `outComplete`.

### E5. Selector form

`multicast(new Subject(), shared => shared.pipe(take(1)))`. T15 runs `connect`. The selector’s observable is subscribed before the source (`connect.ts` 106–107). The first source value is forwarded and `take(1)` completes the selector result, which unsubscribes the downstream and therefore the source subscription `connect` added. A second subscriber to the operator result runs T15 again against the **same** subject (the instance was wrapped as `() => subject`). That is D6, not a fresh `ConnectableObservable`.

## F. Coverage and evidence

Not executed.

Denominator = 16 (T01–T16). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: single source; subject fan-out is in-model
- limits: Selector executions are not re-specified beyond `connect.md`. `refCount`’s mutations of `_refCount` are in `refCount.md`. Subject variants are in the `publish*` files. Deprecated status is part of the contract, not an extra transition.
