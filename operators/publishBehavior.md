# publishBehavior

Deprecated (`operators/publishBehavior.ts` 11–18). Removed in v8. There has never been a selector overload (comment at line 21).

`publishBehavior(initialValue)` (`publishBehavior.ts` 20–25) allocates **one** `BehaviorSubject(initialValue)` when the operator function runs, and returns `new ConnectableObservable(source, () => subject)`. The factory always returns that same subject. `ConnectableObservable` (`observable/ConnectableObservable.ts` 43–95) subscribes callers to the subject and does not subscribe the source until `connect()`.

`BehaviorSubject._subscribe` (`BehaviorSubject.ts` 19–23) joins via `Subject._subscribe`, and if that subscription is still open it synchronously `next`s `_value`. So every subscriber, before `connect` and while the subject is not stopped, immediately receives the seed or the latest value. `next` stores `_value` then forwards (`BehaviorSubject.ts` 34–36).

On source complete or error, `connect`’s subscriber `_teardown`s (nulls `_subject`, unsubscribes the connection, zeros `_refCount`) and then `subject.complete()` or `subject.error(e)` (`ConnectableObservable.ts` 76–84). A later `getSubject` sees `_subject == null` or `isStopped` and calls the factory, which returns the **same** stopped subject (`ConnectableObservable.ts` 47–52). `Subject._checkFinalizedStatuses` then sync-completes or sync-errors the new subscriber (`Subject.ts` 136–144) **before** `BehaviorSubject` would emit `_value`. The seed/latest is not emitted on that path because the subscription returned to `BehaviorSubject._subscribe` is `EMPTY_SUBSCRIPTION` (`closed`) when the subject is already stopped (`Subject.ts` 124–127, `BehaviorSubject.ts` 20–21).

JSDoc equivalence (`publishBehavior.ts` 13–17): `connectable(source, { connector: () => new BehaviorSubject(init), resetOnDisconnect: false })`. `publishBehavior(init), refCount()` is described as `share` with that connector and all three resets `false`. Those resets are not what this file implements; this file implements the connectable. `refCount` is separate.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `silent \| connected \| completed \| errored` | `silent` | The subject exists as soon as `publishBehavior(seed)` is called, even with no subscribers. |
| `current` | `T` | `initialValue` | `BehaviorSubject._value`. |
| `subjectStopped` | `none \| complete \| error(e)` | `none` | — |
| `connection` | subscription or none | none | — |
| `observers` | list | empty | — |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`. `s₀` is `silent` with `current = initialValue`, no connection. The machine starts when the operator is applied to a source, not at the first subscribe: the seed already exists.

### S

| Location | Meaning |
| --- | --- |
| `silent` | Source not connected. Joining observers get `current`. |
| `connected` | Source subscribed. Source nexts replace `current` and fan out. |
| `completed` | Subject completed after `_teardown`. |
| `errored` | Subject holds `e` after `_teardown`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Always hits the subject. Sync value iff not stopped. |
| 2 | Downstream cancel | `unsubscribe` | Leaves the subject. Does not disconnect. |
| 3 | Source next | `sourceNext(v)` | Only while `connected`. |
| 4 | Source error | `sourceError(e)` | — |
| 5 | Source complete | `sourceComplete` | — |
| 6 | Connect | `connect` | — |
| 7 | Disconnect | `connection.unsubscribe` | `_teardown` without completing observers. `current` is kept on the subject object. |
| 8 | Seed | `initialValue` | Not an event. It is `current` at `s₀`. No selector and no scheduler. |

### Γ

`ε`, `syncNext(current)`, `subSource`, `unsubSource`, `outNext(v)`, `outError(e)`, `outComplete`, `syncComplete`, `syncError(e)`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `silent` | `subscribe` | subject not stopped | `silent` | `syncNext(current)` after the observer is joined (`BehaviorSubject.ts` 19–22). No `subSource`. |
| T02 | init | `silent` or `connected` | `connect` | no live connection | `connected` | `subSource`. Observers do not get an extra seed. |
| T03 | waiting | `connected` | `connect` | connection live | `connected` | `ε` |
| T04 | emitting | `connected` | `sourceNext(v)` | — | `connected` | `current := v`; `outNext(v)` to current observers (`BehaviorSubject.ts` 34–36) |
| T05 | emitting | `connected` | `subscribe` | subject not stopped | `connected` | `syncNext(current)` then later live values. Misses values that were overwritten. |
| T06 | per-source error | `connected` | `sourceError(e)` | — | `errored` | `_teardown` then `outError(e)` (`ConnectableObservable.ts` 81–83) |
| T07 | terminal | `connected` | `sourceComplete` | — | `completed` | `_teardown` then `outComplete` (lines 76–79). `current` is not pushed as part of complete. |
| T08 | cancel | any non-terminal | `unsubscribe` one observer | — | same phase | `ε`. Connection unchanged. |
| T09 | cancel | `connected` | `connection.unsubscribe` | — | `silent` | `unsubSource`. Observers remain and are not completed. `current` unchanged. A later subscribe is T01 with that `current`. |
| T10 | waiting | `completed` | `subscribe` | same stopped subject | `completed` | `syncComplete` only. No `syncNext(current)` (`BehaviorSubject.ts` 20–21 plus `Subject.ts` 141–142). |
| T11 | waiting | `errored` | `subscribe` | same stopped subject | `errored` | `syncError(e)`. No `syncNext`. |
| T12 | terminal | `silent` after T09 | `connect` | subject not stopped (disconnect does not stop it) | `connected` | `subSource`. Subsequent source nexts update `current` from wherever T09 left it. |
| T13 | terminal | `completed` or `errored` | `connect` | factory returns the stopped subject | same | `subSource` onto a stopped subject. `Subject.next` drops values (`Subject.ts` 61–62). Late `subscribe` stays T10 or T11. |
| T14 | waiting | `silent` | `subscribe` | first subscriber, `connect` never called | `silent` | `syncNext(initialValue)` even though the source has emitted nothing. |

## D. Contract invariants

1. Until the subject is stopped, every `subscribe` synchronously emits the current value, which starts as `initialValue` (T01, T14, T05). This happens with zero source subscriptions.
2. Source values replace `current`. There is no buffer beyond that one value. Earlier source values are not replayed.
3. `connect` is idempotent while the connection is open (T02, T03). `subscribe` never implies `connect` (no selector, and this file does not call `refCount`).
4. Source complete notifies complete and does not also next the last value at completion time. Anyone who was already subscribed saw that value as a normal next. Anyone who subscribes after complete gets only `syncComplete` (T07, T10).
5. Source error is stored and replayed to late subscribers as `syncError(e)` (T11). `getValue` would throw that error (`BehaviorSubject.ts` 25–28); the operator path uses subscribe, not `getValue`.
6. Disconnect does not complete observers and does not clear `current` (T09).
7. The subject identity is fixed for the lifetime of the operator result. Stopping it is permanent for later `connect` fan-out (T13).
8. Deprecated. No selector overload exists in the implementation (line 21), despite `publish` and `publishReplay` having one.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Seed before connect

`publishBehavior(0)`. Subscribe A. T14/T01 `syncNext(0)`. Subscribe B. Another `syncNext(0)`. The source factory has not run. `connect()` is T02. Source emits `1` then `2`. Both observers get `outNext(1), outNext(2)`. `current` is `2`.

### E2. Late subscriber while connected

After E1, subscribe C. T05 `syncNext(2)`, then later source values. C does not see `0` or `1`.

### E3. Complete suppresses the seed for late subscribers

Source completes after emitting `2`. Observers get `outComplete` (T07) and do not get a second `2`. Subscribe D: T10 `syncComplete` only, not `syncNext(2)`.

### E4. Error

Source errors `e` after emitting `1`. Observers get `outNext(1), outError(e)`. Subscribe E: T11 `syncError(e)`, no `syncNext(1)`.

### E5. Disconnect keeps the latest value

After `current = 1` and two observers, unsubscribe the connection (T09). Observers do not complete. Subscribe F: `syncNext(1)` (T01) while the source is disconnected. `connect()` again (T12) subscribes the source; the next source value replaces `1`.

## F. Coverage and evidence

Not executed.

Denominator = 14 (T01–T14). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: single source; the synchronous seed on subscribe is in-model
- limits: `refCount` is not applied inside this file. `getValue`’s throw-on-error path is not an operator output. Connectable teardown is shared with `multicast.md`. The constant stopped subject after T13 is the `resetOnDisconnect: false` behavior named in the JSDoc.
