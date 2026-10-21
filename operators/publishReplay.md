# publishReplay

Deprecated (`operators/publishReplay.ts` 14–21, 41–44, 61–67, 77–81). Removed in v8.

`publishReplay(bufferSize?, windowTime?, selectorOrScheduler?, timestampProvider?)` (`publishReplay.ts` 83–96) normalizes arguments: if the third argument is present and not a function, it is the timestamp provider; if it is a function, it is the selector and the fourth argument is the timestamp provider. It allocates **one** `ReplaySubject(bufferSize, windowTime, timestampProvider)` immediately, then `multicast(thatSubject, selector)` (`publishReplay.ts` 95).

Without a selector, `multicast` returns a `ConnectableObservable` whose factory is `() => thatSameSubject` (`operators/multicast.ts` 86–97). `connect()` subscribes the source once (`observable/ConnectableObservable.ts` 66–87). Subscribers join the `ReplaySubject` only.

`ReplaySubject` (`ReplaySubject.ts` 47–109): buffer size `Math.max(1, bufferSize)` with default `Infinity`; window default `Infinity`. `undefined` window is not infinite: `_windowTime` becomes `NaN` and time eviction never succeeds (`NaN <= now` is false), while the count cap still works and stores timestamp slots. `next` records the value, trims, then fan-out (lines 58–66). `_subscribe` trims, joins, replays the buffer synchronously, then applies the stopped status (lines 69–85). A stopped-by-complete subject therefore replays the buffer and completes. A stopped-by-error subject replays the buffer and then errors (`Subject._checkFinalizedStatuses`, and the class JSDoc at `ReplaySubject.ts` 15–16 and 31). That error-replay is a `ReplaySubject` difference from `BehaviorSubject`.

`ConnectableObservable` still `_teardown`s before `subject.complete` / `subject.error` (`ConnectableObservable.ts` 76–84). The same subject is returned forever, so late subscribers keep hitting the stopped replay path. `connect()` after that can subscribe the source again, but `ReplaySubject.next` ignores values once `isStopped` (line 59–60).

With a selector, `multicast` is `connect(selector, { connector: () => sameReplaySubject })` (`multicast.ts` 88–94, `connect.ts` 99–108). Each subscription to the operator result runs `connect`: it subscribes the selector result first, then `source.subscribe(subject)` **again** on that same subject. Two outer subscribers mean two source subscriptions feeding one buffer. The no-selector form does not do that; it waits for a single `connect()`.

The timestamp provider is only `ReplaySubject`’s clock. It does not `observeOn` the fan-out. JSDoc equivalences to `connectable(..., { resetOnDisconnect: false })` and to `share({ resetOnError: false, resetOnComplete: false, resetOnRefCountZero: false })` (`publishReplay.ts` 16–20) describe this sticky subject. `refCount` is not applied here.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `shape` | `connectable \| selector` | selector present? | — |
| `phase` | `silent \| connected \| completed \| errored` | `silent` | Connectable shape. |
| `buffer` | queue of values, optional timestamps | empty | — |
| `bufferSize` | ≥ 1 or `Infinity` | `Math.max(1, bufferSize ?? Infinity)` | `0` becomes `1`. |
| `windowTime` | `Infinity`, number, or `NaN` | argument or `NaN` if omitted/`undefined` | — |
| `stopped` | `none \| complete \| error(e)` | `none` | — |
| `connection` | subscription or none | none | Connectable `_connection` only. |
| `sourceFeeds` | integer | `0` | Selector shape: how many `connect` executions have subscribed the source. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = silent`, empty buffer, one subject already constructed.

### S

| Location | Meaning |
| --- | --- |
| `silent` | Subject may already hold values only if a previous connection wrote them and was disconnected without stopping the subject. Initially empty. |
| `connected` | At least one source subscription is live. |
| `completed` | Subject completed. Buffer frozen. |
| `errored` | Subject errored. Buffer still replayed, then `e`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Replay then live, or replay then terminal. |
| 2 | Downstream cancel | `unsubscribe` | Leaves the subject. Connectable: does not disconnect. |
| 3 | Source next | `sourceNext(v)` | Buffer and fan-out if not stopped. |
| 4 | Source error | `sourceError(e)` | Stop, then error. Buffer kept for later replays. |
| 5 | Source complete | `sourceComplete` | Stop, then complete. Buffer kept. |
| 6 | Connect | `connect` | Connectable shape only. |
| 7 | Disconnect | `connection.unsubscribe` | `_teardown` without stopping the subject. |
| 8 | Selector / clock | `selector`, `now` | Selector shape, or finite-window trim. |

### Γ

`ε`, `replay(v)` in buffer order, `subSource`, `unsubSource`, `outNext(v)`, `outComplete`, `outError(e)`, `syncComplete`, `syncError(e)`.

## C. Transition obligations

Connectable shape:

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `silent` | `subscribe` | not stopped, buffer empty | `silent` | join. `ε`. No `subSource`. |
| T02 | init | `silent` | `connect` | no live connection | `connected` | `subSource` |
| T03 | waiting | `connected` | `connect` | connection live | `connected` | `ε` |
| T04 | emitting | `connected` | `sourceNext(v)` | not over cap and not expired | `connected` | record `v`; `outNext(v)` to current observers (`ReplaySubject.ts` 58–66) |
| T05 | emitting | `connected` | `sourceNext(v)` | count or finite window trims | `connected` | drop oldest / expired first (`ReplaySubject.ts` 88–108); then `outNext(v)`. Dropped values are absent from later replays. |
| T06 | waiting | `connected` or `silent` | `subscribe` | not stopped | same | `replay` of the current buffer synchronously (`ReplaySubject.ts` 77–81); no extra `subSource` |
| T07 | terminal | `connected` | `sourceComplete` | — | `completed` | `_teardown`; `outComplete` to current observers. Buffer retained (`ConnectableObservable.ts` 76–79). |
| T08 | per-source error | `connected` | `sourceError(e)` | — | `errored` | `_teardown`; `outError(e)`. Buffer retained. |
| T09 | waiting | `completed` | `subscribe` | — | `completed` | `replay` each remaining buffer value, then `syncComplete` (`ReplaySubject.ts` 69–85) |
| T10 | waiting | `errored` | `subscribe` | — | `errored` | `replay` buffer, then `syncError(e)` |
| T11 | cancel | non-terminal | `unsubscribe` one observer | — | same | `ε`. Source stays as it was. |
| T12 | cancel | `connected` | `connection.unsubscribe` | — | `silent` | `unsubSource`. Subject not stopped, buffer kept. Later T06 replays it. Later T02 can `subSource` again and append. |
| T13 | terminal | `completed` or `errored` | `connect` | same stopped subject | same | `subSource`, but `next`/`complete` on the stopped subject do not change the buffer (`ReplaySubject.ts` 59–60, `Async` not relevant). |

Selector shape (`connect.ts` 104–108), same subject:

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T14 | init | any not-stopped | outer `subscribe` | selector present | `connected` | `sourceFeeds++`; selector result subscribed first; then `subSource` on the shared replay subject |
| T15 | emitting | `connected` | `sourceNext(v)` from any feed | — | `connected` | one buffer record and one fan-out per source next, so two feeds duplicate |
| T16 | terminal | that outer subscriber | selector result terminates or outer `unsubscribe` | — | `sourceFeeds--` | that feed’s `unsubSource`. The subject is not reset by `connect`. Other feeds continue. |
| T17 | waiting | `completed` or `errored` | outer `subscribe` | subject already stopped by a feed | same | selector runs, but `source.subscribe(stoppedSubject)` does not revive replay. Subscribe-time `replay` plus terminal still happens for observers of the subject. |

## D. Contract invariants

1. The `ReplaySubject` is allocated once per `publishReplay(...)` call, not per source subscription (`publishReplay.ts` 95).
2. Without a selector, no source subscription exists until `connect`, and `connect` is idempotent while `_connection` is set (T02, T03).
3. Joining a live subject replays the trimmed buffer and misses nothing that is still buffered (T06). Joining before any `connect` replays nothing (T01).
4. After complete, late subscribers get the buffer then complete, and the source is not restarted for them (T07, T09). After error, late subscribers get the buffer then the same error (T08, T10). That error replay is `ReplaySubject`, not `publishBehavior`.
5. `bufferSize` is at least 1. `Infinity` does not count-trim. An omitted `windowTime` becomes `NaN` inside `ReplaySubject` and does not time-trim. An explicit finite window does, using the timestamp provider’s `now` only.
6. Disconnect keeps the buffer and does not complete observers (T12).
7. With a selector, each outer subscription adds another `source.subscribe(sameSubject)` (T14, D-equivalent of `connect.ts` 107). The connectable `connect()` refcount of one does not apply to that shape.
8. Deprecated. No `refCount` inside this function. `resetOnError` / `resetOnComplete` of `shareReplay` are different: `shareReplay` uses `resetOnError: true` and a new subject per reset. This operator keeps one subject and replays the error.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Buffer three, late subscriber

`publishReplay(3)`, `connect()`, source emits `0,1,2,3`. Observers who were already joined see each `outNext` (T04/T05). Buffer holds `1,2,3` if size is 3 (`0` trimmed; remember `Math.max`). A subscriber who joins then is T06: `replay(1), replay(2), replay(3)`, then live values. They do not see `0`.

### E2. Complete sticks

Source emits `1`, `2` and completes. Current observers get those nexts and `outComplete` (T07). A late subscriber gets T09 `replay(1), replay(2), syncComplete` and does not `subSource`.

### E3. Error replays the buffer

Source emits `1` then errors `e`. Current observers get `outNext(1), outError(e)` (T08). A late subscriber gets T10 `replay(1), syncError(e)`. This is the opposite of `shareReplay`’s `resetOnError: true`, which would drop the buffer and not replay `e`.

### E4. Disconnect then replay

`connect`, emit `1`, unsubscribe the connection (T12). Observers do not complete. A new subscriber gets `replay(1)` (T06) while disconnected. `connect` again (T02) appends later values onto that buffer.

### E5. Selector double-subscribe

`publishReplay(Infinity, Infinity, shared => merge(shared, shared))`. One outer `subscribe` is T14: one `subSource`, and `merge` subscribes `shared` twice, so each source value is observed twice by `merge` but recorded once if both subscriptions see the same `subject.next`. A second outer `subscribe` is another T14: `sourceFeeds = 2`, a second `subSource` on the same `ReplaySubject`. If the source is cold, its side effects run twice and the buffer receives both sequences. That is D7, not `publishReplay()` without a selector.

## F. Coverage and evidence

Not executed.

Denominator = 17 (T01–T17). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded, except replay aborting when `subscriber.closed` (`ReplaySubject.ts` 79)
- synchronous multi-source emissions in listed order: selector feeds are in-model; values from one feed stay ordered
- limits: Concrete clocks are not executed. Omitted `windowTime` is the `NaN` window from `ReplaySubject`, not a silent `Infinity`, unless the caller passes `Infinity`. `refCount` composition is outside this file. `connect` ordering is in `connect.md`. `shareReplay.md` is the non-deprecated replay operator and does not share this sticky-error policy.
