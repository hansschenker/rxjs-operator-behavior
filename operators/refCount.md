# refCount

Deprecated (`operators/refCount.ts` 60–63). Replaced by `share`, with the equivalence depending on the connectable that precedes it. The implementation (`refCount.ts` 65–119) assumes `source` is a `ConnectableObservable`: it reads and writes `_refCount`, reads `_connection`, and calls `connect()` (`observable/ConnectableObservable.ts` 17–19, 66–95).

On each subscriber (`refCount.ts` 66–117):

1. `_refCount++` on the connectable.
2. Build an `OperatorSubscriber` that forwards next, error, and complete (the handlers are `undefined`, so `Subscriber` defaults apply) and whose finalize is the decrement logic (lines 71–111).
3. `source.subscribe(refCounter)`, which joins the connectable’s subject (`ConnectableObservable._subscribe`, lines 43–45).
4. If that subscriber is still open, `connection = source.connect()` (lines 115–117). `connect` is idempotent while `_connection` is set (`ConnectableObservable.ts` 67–68).

Finalize (`refCount.ts` 71–110), when this subscriber unsubscribes, including after a forwarded complete or error:

- If `_refCount <= 0`, return without decrementing. `ConnectableObservable` source terminals call `_teardown`, which sets `_refCount = 0` before `subject.complete` / `subject.error` (`ConnectableObservable.ts` 55–60, 76–84). The subsequent observer teardown therefore sees `<= 0` and does not disconnect a second time.
- Else decrement. If the result is still `> 0`, return. Other subscribers keep the connection.
- If the result is `0`, unsubscribe `_connection` only when it exists and either this finalizer never observed a local `connection` or the local reference is identical to `_connection` (lines 102–108). The comment at lines 77–100 is the synchronous case `publish(), refCount(), take(n)` where `connect()` has not yet assigned the local `connection` but `_connection` is already set, and the finalizer must still unsubscribe that shared connection.
- Then `subscriber.unsubscribe()`.

`refCount` does not choose the subject and does not implement `share`’s `resetOnError` / `resetOnComplete` flags. After a source terminal, `_teardown` has already dropped `_connection` and zeroed the count. A later subscriber increments the count, joins `getSubject()`, and if the factory returns the same stopped subject the join sync-completes or sync-errors and `refCounter.closed` skips `connect()` (lines 115–117). The finalize then decrements the count it just incremented. Net connect count returns to `0`. No new source subscription. That late path is T08 below.

Observer unsubscribe while the source is still open is the true refCount disconnect: the last one unsubscribes `_connection`, which runs the connectable finalizer `_teardown` (`ConnectableObservable.ts` 84) and does **not** complete the subject. The JSDoc example (`refCount.ts` 32–52) is the 0→1 connect and the “still one execution no matter how many subscribers” rule.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| connected \| silent \| completed \| errored` | `idle` | `silent` is count `0` after a user-driven disconnect, subject not stopped. |
| `count` | integer | connectable `_refCount`, normally `0` | — |
| `connection` | subscription or none | connectable `_connection` | — |
| `localConn[subscriber]` | subscription or none | none until step 4 | The identity check in the finalizer. |
| `subjectStopped` | `none \| complete \| error(e)` | from the connectable’s subject | This operator does not reset it. |

The connectable’s subject kind (`Subject`, `BehaviorSubject`, `AsyncSubject`, `ReplaySubject`) decides sync values on join. Those outputs are inherited, not redefined here.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle` with `count = 0` and no connection. One machine per connectable the operator is applied to.

### S

| Location | Meaning |
| --- | --- |
| `idle` | `count = 0`, no connection, subject not stopped. |
| `connected` | `count ≥ 1` and `_connection` live. |
| `silent` | `count = 0` after the last unsubscribe disconnected. Subject still not stopped. |
| `completed` | Source completed; connectable tore down; subject completed. |
| `errored` | Source errored; subject holds `e`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Increments `count`, joins subject, maybe `connect`. |
| 2 | Downstream cancel | `unsubscribe` | Decrements. Last one may `unsubSource`. |
| 3 | Source next | `sourceNext(v)` | Forwarded by the default subscriber to every joined observer. |
| 4 | Source error | `sourceError(e)` | Connectable `_teardown` then subject error, which errors these subscribers. |
| 5 | Source complete | `sourceComplete` | `_teardown` then subject complete. |
| 6 | Connect | internal `connect()` | Not a user call. Fired from step 4 when the subscriber is still open. |
| 7 | Subject sync terminal | on join of a stopped subject | Skips `connect()`. |
| 8 | Scheduler / selector | — | None in this file. |

### Γ

`ε`, `joinSubject`, `subSource`, `unsubSource`, `outNext(v)`, `outError(e)`, `outComplete`, plus whatever the subject emits synchronously on join (seed, replay, `syncComplete`, `syncError`). Those sync subject outputs are named `subjectSync(...)`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` or `silent` | `subscribe` | after join, `refCounter` still open; `count` was `0` | `connected` | `count := 1`; `joinSubject`; `subSource` via `connect()` (`refCount.ts` 69, 113–117) |
| T02 | waiting | `connected` | `subscribe` | `refCounter` stays open; connection already live | `connected` | `count++`; `joinSubject`; `connect()` returns the existing connection (`ConnectableObservable.ts` 67–68). No second `subSource`. |
| T03 | emitting | `connected` | `sourceNext(v)` | — | `connected` | `outNext(v)` to each current refCount subscriber |
| T04 | cancel | `connected` | `unsubscribe` | decrement leaves `count ≥ 1` | `connected` | `ε`. Connection kept (`refCount.ts` 72–74, the `0 < --count` return). |
| T05 | cancel | `connected` | `unsubscribe` | decrement leaves `count = 0`, and `_connection` exists and matches the local connection or the local connection was not assigned yet | `silent` | `unsubSource` (lines 102–108). Subject is not completed by `refCount`. `_teardown` also zeros `count` and nulls `_subject` on the connectable (`ConnectableObservable.ts` 55–59). |
| T06 | per-source error | `connected` | `sourceError(e)` | — | `errored` | connectable `_teardown` sets `count = 0` and clears `_connection`, then `outError(e)`. Each subscriber’s finalize takes the `_refCount <= 0` early return and does not unsubscribe again (`refCount.ts` 72, `ConnectableObservable.ts` 81–83). |
| T07 | terminal | `connected` | `sourceComplete` | — | `completed` | same teardown order as T06, then `outComplete` (`ConnectableObservable.ts` 76–79) |
| T08 | waiting | `completed` or `errored` | `subscribe` | `getSubject` returns a stopped subject, so join sync-terminates and `refCounter.closed` | same | `count` increments then the finalize decrements it back to `0` (the `<= 0` short-circuit does **not** apply, because `_teardown` already set `0` and this subscribe incremented it to `1`). `connect()` is skipped (lines 115–117). Output is the subject’s `syncComplete` or `syncError(e)` only. No `subSource`. |
| T09 | init | `connected` | `subscribe` | synchronous source terminal during `joinSubject`, before `connect()` returns to line 115 | `completed` or `errored` | The comment at lines 77–100. `connect()` may already have set `_connection` from a previous subscriber, or from this call if `connect` ran far enough. If this subscriber is closed before line 115, this call does not assign `localConn`. Finalize still drops `_connection` when `count` hits `0` because `!localConn` is allowed (line 106). |
| T10 | cancel | `idle` | `unsubscribe` with `count` already `0` | defensive | `idle` | early return (line 72). No decrement. |
| T11 | terminal | `silent` | `subscribe` | subject not stopped (T05’s `_teardown` nulls `_subject`, so `getSubject` calls the factory) | `connected` or `silent` | If the factory returns a fresh open subject, T01: `subSource` again. If the factory returns the same not-stopped subject, T01 as well: new `connect()`, same subject, buffer/seed intact. If the factory returns a stopped subject, T08. |
| T12 | terminal | terminal phases | further `sourceNext` | no connection | same | `ε` |

T11 is the composition point with `publish` / `publishBehavior` / `publishLast` / `publishReplay`, whose factories return one subject forever. After T07 the subject is stopped, so the next subscribe is T08, not a reconnect. After T05 `_teardown` nulls `_subject` but does not stop the subject; `getSubject` invokes the factory and gets that same still-open subject back, then T01’s `connect` subscribes the source again.

## D. Contract invariants

1. `count` is the number of refCount subscribers currently joined, except in the window where a source terminal has forced it to `0` via `_teardown` before individual finalizers run (T06, T07).
2. `subSource` happens on the transition that moves `count` from `0` to `1` while the subscriber is still open (T01), and not on T02.
3. `unsubSource` from this operator happens only when a finalize decrements to `0` and the connection identity check passes (T05, T09). It does not happen merely because the source completed (the connectable already tore down).
4. Forwarded next, error, and complete are the subject’s notifications. `refCount` does not filter values.
5. The last live unsubscribe does not complete downstream by itself. It disconnects. Downstream completion happens only if the subject completes.
6. A synchronous take/unsubscribe that races the assignment of `localConn` still disconnects the shared `_connection` when it is the last subscriber (T09, `refCount.ts` 102–108).
7. Deprecated. It is not `share`. In particular it does not reset a `ReplaySubject` on error, and it does not allocate a new subject unless the connectable’s factory does.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two subscribers, one source execution

`interval.pipe(publish(), refCount())` as in the JSDoc (`refCount.ts` 32–47). First `subscribe` is T01: `count = 1`, `subSource`. Second is T02: `count = 2`, no second `subSource`. Each `sourceNext(n)` is T03 to both. Unsubscribing one is T04. Unsubscribing the other is T05 `unsubSource`.

### E2. Connectable without refCount

Not this operator, stated to mark the boundary: `publish()` alone stays `idle` with subscribers on the subject and no `subSource` until `connect()`. `refCount` is what calls `connect` in E1.

### E3. Source completes with two subscribers

T07: `_teardown` zeros `count`, clears the connection, then both subscribers get `outComplete`. Their finalizers see `count <= 0` and do not call `unsubscribe` on a connection. A later subscriber is T08: subject sync-completes (plain `publish` / `Subject`), `connect()` is skipped, `count` returns to `0`.

### E4. Synchronous `take` during connect

`range(0, 10).pipe(publish(), refCount(), take(5))` (comment at `refCount.ts` 85–92). The source emits synchronously inside `connect`. `take(5)` unsubscribes the refCount subscriber before line 115 stores `localConn`. T09: this is the only subscriber, so the finalize’s `count` hits `0`, `localConn` is null, `_connection` is set, and `unsubSource` runs. The source does not keep emitting through `10`.

### E5. Error

Source errors `e` while `count ≥ 1`. T06 `outError(e)` to current subscribers, connection cleared, `count` forced to `0`. No `outComplete`. A later subscriber on `publishLast` / `AsyncSubject` or plain `Subject` takes T08 `syncError(e)`. On `publishReplay`, T08 replays the buffer and then `syncError(e)`, because that is the subject, not because `refCount` buffers.

### E6. Last unsubscribe then resubscribe, source still open

T05 disconnects and `_teardown` drops the connectable’s `_subject` pointer but the `publish()` factory still returns the same open `Subject`. T11/T01 connects again. Values that were emitted in the previous connection are not replayed (`Subject`). `publishBehavior` would `syncNext` the latest seed on the new join because the `BehaviorSubject` was not stopped by T05. `publishReplay` would replay its retained buffer. Those sync outputs are `subjectSync`, then a new `subSource`.

## F. Coverage and evidence

Not executed.

Denominator = 12 (T01–T12). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: single source; the synchronous `take` race in T09 is in-model
- limits: The operator is unspecified for a source that is not a `ConnectableObservable` (`_refCount` / `connect` are unguarded). Subject-specific sync values are delegated to `publish.md`, `publishBehavior.md`, `publishLast.md`, and `publishReplay.md`. `share`’s reset flags are not simulated here; the JSDoc equivalence is documentation only (`refCount.ts` 17–18, 60–63).
