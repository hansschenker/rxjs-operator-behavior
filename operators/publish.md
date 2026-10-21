# publish

Deprecated (JSDoc `operators/publish.ts` 12–18, 30–32, 86–89). Removed in v8.

`publish(selector?)` (`publish.ts` 91–93):

- With `selector`: `(source) => connect(selector)(source)`. Default `connect` connector is `() => new Subject()` (`operators/connect.ts` 22–24, 99–108). Equivalent, per JSDoc, to `connect(selector)`.
- Without `selector`: `(source) => multicast(new Subject())(source)`. `new Subject()` runs when `publish()` is called, once. `multicast` wraps that instance as `() => sameSubject` and returns a `ConnectableObservable` (`operators/multicast.ts` 82–98, `observable/ConnectableObservable.ts` 32–95).

No selector means subscribers only join that `Subject` until `connect()`. `Subject` does not replay. After the source terminates, `ConnectableObservable` nulls `_subject` and then completes or errors the same subject (`ConnectableObservable.ts` 76–84). The next `getSubject` calls the factory, gets that stopped subject back, and late subscribers receive the stored terminal (`Subject.ts` 136–144) without a new source subscription unless `connect()` is called again. A second `connect()` after teardown does call `source.subscribe` again, but `Subject.next` on a stopped subject drops values (`Subject.ts` 59–62). JSDoc’s `resetOnDisconnect: false` equivalence (`publish.ts` 13–14) is this constant subject.

`publish(), refCount()` is not what this operator does by itself. The JSDoc equivalence is `share({ resetOnError: false, resetOnComplete: false, resetOnRefCountZero: false })` (`publish.ts` 16–17). The `refCount` operator is specified separately.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `shape` | `connectable \| selector` | — | — |
| `phase` | `idle \| silent \| connected \| completed \| errored` | `idle` | Connectable shape. |
| `subject` | the one `Subject` allocated in `publish()` | stopped flag, `thrownError` | Constant factory. |
| `connection` | subscription or none | none | `ConnectableObservable._connection`. |
| `observers` | list | empty | `Subject.observers`. |

Selector shape: no shared phase across outer subscribers. Each subscribe uses a **new** `Subject` because `connect`’s default factory allocates (`connect.ts` 23). That is the opposite of the no-selector constant subject.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle` for the connectable returned by `publish()`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Subject exists (it was built in `publish()`), no connection. |
| `silent` | One or more observers, source not connected. They receive nothing from a plain `Subject`. |
| `connected` | `connect()` has subscribed the source. |
| `completed` | Source completed; subject stopped by complete. |
| `errored` | Source errored; subject stores `e`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Joins the subject only, in the connectable shape. |
| 2 | Downstream cancel | `unsubscribe` | Leaves the subject. Does not disconnect. |
| 3 | Source next | `sourceNext(v)` | Fan-out iff `connected` and subject not stopped. |
| 4 | Source error | `sourceError(e)` | Teardown then `subject.error`. |
| 5 | Source complete | `sourceComplete` | Teardown then `subject.complete`. |
| 6 | Connect | `connect` | — |
| 7 | Disconnect | `connection.unsubscribe` | `_teardown` without a terminal notification. |
| 8 | Selector | `selector(shared)` | Only `publish(selector)`, delegated to `connect`. |

### Γ

`ε`, `subSource`, `unsubSource`, `outNext(v)`, `outError(e)`, `outComplete`, `syncComplete`, `syncError(e)`.

No `replay(v)` . `publish` is not `publishReplay`.

## C. Transition obligations

Connectable shape:

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | subject not stopped | `silent` | join subject. `ε`. No `subSource`. |
| T02 | waiting | `silent` or `connected` | `subscribe` | subject not stopped | same | another join. `ε`. |
| T03 | init | `silent` or `idle` | `connect` | no live connection | `connected` | `subSource` (`ConnectableObservable.ts` 66–87) |
| T04 | waiting | `connected` | `connect` | connection live | `connected` | `ε` |
| T05 | emitting | `connected` | `sourceNext(v)` | — | `connected` | `outNext(v)` to current observers, snapshot order (`Subject.ts` 63–68) |
| T06 | per-source error | `connected` | `sourceError(e)` | — | `errored` | `_teardown` then `outError(e)` (`ConnectableObservable.ts` 81–83) |
| T07 | terminal | `connected` | `sourceComplete` | — | `completed` | `_teardown` then `outComplete` (lines 76–79) |
| T08 | cancel | `silent` or `connected` | `unsubscribe` one observer | connection not unsubscribed by this | same, or `idle` if no observers and no connection | `ε`. Source connection unchanged. |
| T09 | cancel | `connected` | `connection.unsubscribe` | — | `idle` | `unsubSource` via `_teardown` (line 84). Observers stay subscribed and are not completed. |
| T10 | waiting | `completed` | `subscribe` | constant stopped subject | `completed` | `syncComplete` (`Subject.ts` 141–142). No `subSource`. |
| T11 | waiting | `errored` | `subscribe` | constant stopped subject | `errored` | `syncError(e)` (`Subject.ts` 139–140) |
| T12 | terminal | `idle` after T09 | `connect` | subject may already be the same object | `connected` | `subSource` again, but if the subject is stopped, later `sourceNext` is dropped inside `Subject.next` |
| T13 | terminal | any terminal | source notification with no connection | — | same | `ε` |

Selector shape:

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T14 | init | `idle` | `subscribe` | `publish(selector)` | one `connect` execution | new `Subject`; selector subscribed; then `subSource` (`connect.ts` 104–108) |
| T15 | terminal | that execution | selector result completes, errors, or downstream unsubscribes | — | done | `unsubSource` because the source subscription was added to the downstream subscriber |

## D. Contract invariants

1. `publish()` without a selector does not subscribe the source at operator-subscribe time. `connect` does, once, until teardown (T01 versus T03).
2. The subject is allocated once per `publish()` call and reused for every `getSubject`, including after it has stopped (T10, T11).
3. There is no value replay. A subscriber who joins `connected` after `sourceNext(v)` misses `v`.
4. Source error and complete reach current observers and are replayed as terminals to late subscribers. They are not replayed as nexts.
5. Unsubscribing an observer does not unsubscribe the source (T08). Unsubscribing the connection does, and it does not complete the observers (T09).
6. `publish(selector)` is `connect(selector)` with a fresh `Subject` per subscription to the result, not the constant subject from a previous `publish()` call. Multicasting happens among subscriptions the selector makes to `shared`, and the source is connected after the selector result is subscribed.
7. The operator is deprecated. `refCount` after it is a different machine (`refCount.md`).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two observers after connect

`publish()` then two subscribers, then `connect()`. T01, T02, T03. Source emits `1` then `2`. Both observers get `outNext(1), outNext(2)` (T05). One observer unsubscribes (T08). The other still gets the next source value. The source is still connected.

### E2. Missed value

`connect()` first, source emits `1`, then a new subscriber joins (T02). That subscriber does not get `1`. They get later values only. This is ordinary `Subject` behavior, not `ReplaySubject`.

### E3. Complete is sticky for late subscribers

Source completes after observers saw `1`. T07 `outComplete`. A new subscriber gets T10 `syncComplete` and not `1`. Calling `connect()` again hits T12: the source can be subscribed, but the stopped subject does not forward new nexts.

### E4. Error is sticky

Source errors `e`. Observers get `outError(e)` (T06). A late subscriber gets T11 `syncError(e)`. No `outComplete`.

### E5. Selector shares inside one subscribe

`publish(shared => merge(shared.pipe(map(x => x + 'a')), shared.pipe(map(x => x + 'b'))))`. T14: both inner subscriptions attach to one new `Subject` before `subSource`. One source value `1` yields both `'1a'` and `'1b'` from a single source subscription. A second subscriber to the outer result is a second T14 with a different `Subject` and a second `subSource`. The JSDoc `merge` of three taps (`publish.ts` 56–75) is this pattern.

## F. Coverage and evidence

Not executed.

Denominator = 15 (T01–T15). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: single source; selector-internal multi-subscribe is in-model for T14
- limits: `refCount` composition is not inlined; see `refCount.md` and the JSDoc equivalence, which is not a second implementation in this file. Selector details beyond T14–T15 live in `connect.md`. Connectable teardown details shared with `multicast.md`.
