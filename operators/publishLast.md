# publishLast

Deprecated (`operators/publishLast.ts` 61–68). Removed in v8. No selector overload has ever existed (comment at line 71).

`publishLast()` (`publishLast.ts` 70–75) allocates one `AsyncSubject` and returns `new ConnectableObservable(source, () => thatSameSubject)`. Subscribers join the subject only. The source runs only after `connect()` (`observable/ConnectableObservable.ts` 43–95).

`AsyncSubject` (`AsyncSubject.ts` 8–39) does not forward `next`. `next` stores `_value` and `_hasValue` if the subject is not stopped (lines 24–28). `complete` sets `_isComplete`, and if a value was stored calls `super.next(value)` once, then `super.complete()` (lines 31–38). `error` is `Subject.error`, which does not emit the stored value. `_checkFinalizedStatuses` (lines 14–22): late subscribers after an error get `error(thrownError)`; after stop/complete they get the stored value if `_hasValue`, then `complete`. If the source completed with no value, late subscribers only `complete`.

`ConnectableObservable` on source complete calls `_teardown` then `subject.complete()` (lines 76–79). That `complete` is what releases the last value to **current** observers. `_teardown` nulls `_subject` first, but the local subject reference still completes. A later subscriber hits `getSubject`, which calls `() => sameSubject` because the subject `isStopped` (`ConnectableObservable.ts` 47–52) and then the AsyncSubject late path above. JSDoc (`publishLast.ts` 12–16 and the example at 27–51) matches: no emission until source complete, then the last value and complete, including to subscribers who arrive later.

`error` does not flush the last value (`AsyncSubject` has no special `error`). Current observers get `outError(e)` only.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `silent \| connected \| completed \| errored` | `silent` | — |
| `hasValue` | boolean | `false` | `AsyncSubject._hasValue`. |
| `last` | value or empty | empty | `AsyncSubject._value`. |
| `subjectStopped` | `none \| complete \| error(e)` | `none` | — |
| `connection` | subscription or none | none | — |
| `observers` | list | empty | People waiting for complete. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = silent`, `hasValue = false`, no connection.

### S

| Location | Meaning |
| --- | --- |
| `silent` | Not connected. Subscribers wait. No seed emission (unlike `publishBehavior`). |
| `connected` | Source subscribed. Nexts update `last` and do not fan out. |
| `completed` | `complete` has flushed `last` if any, then completed. |
| `errored` | Error stored. `last` was not flushed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Join. Sync output only if the subject is already stopped. |
| 2 | Downstream cancel | `unsubscribe` | Leave. No disconnect. |
| 3 | Source next | `sourceNext(v)` | Stored. Not an `outNext` while `connected`. |
| 4 | Source error | `sourceError(e)` | No flush of `last`. |
| 5 | Source complete | `sourceComplete` | Flushes `last` if `hasValue`, then complete. |
| 6 | Connect | `connect` | — |
| 7 | Disconnect | `connection.unsubscribe` | `_teardown` without `subject.complete`, so `last` stays private and current observers get nothing new. |
| 8 | Selector / scheduler | — | None. |

### Γ

`ε`, `subSource`, `unsubSource`, `outNext(last)` (only on the complete flush), `outComplete`, `outError(e)`, `syncNext(last)`, `syncComplete`, `syncError(e)`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `silent` | `subscribe` | not stopped | `silent` | join. `ε`. No `subSource`. |
| T02 | init | `silent` | `connect` | no live connection | `connected` | `subSource` |
| T03 | waiting | `connected` | `connect` | connection live | `connected` | `ε` |
| T04 | waiting | `connected` | `sourceNext(v)` | — | `connected` | `ε` downstream; `last := v`; `hasValue := true` (`AsyncSubject.ts` 24–28) |
| T05 | waiting | `connected` | `subscribe` | not stopped | `connected` | join. `ε`. The subscriber does not receive the current `last`. |
| T06 | terminal | `connected` | `sourceComplete` | `hasValue` | `completed` | `_teardown`, then `outNext(last)`, then `outComplete` to current observers (`ConnectableObservable.ts` 76–79, `AsyncSubject.ts` 31–37) |
| T07 | terminal | `connected` | `sourceComplete` | not `hasValue` | `completed` | `_teardown`, then `outComplete` only (`AsyncSubject.ts` 35–36 skips `super.next`) |
| T08 | per-source error | `connected` | `sourceError(e)` | — | `errored` | `_teardown`, then `outError(e)`. `last` is not emitted (`Subject.error`, `AsyncSubject` does not override `error`). |
| T09 | cancel | non-terminal | `unsubscribe` one observer | — | same | `ε`. If they leave before T06 they miss the flush. |
| T10 | cancel | `connected` | `connection.unsubscribe` | — | `silent` | `unsubSource`. Subject is not completed, so `last` is retained privately and observers are not notified (`ConnectableObservable.ts` 55–60, 84). |
| T11 | waiting | `completed` | `subscribe` | `hasValue` | `completed` | `syncNext(last)`, `syncComplete` (`AsyncSubject.ts` 18–20) |
| T12 | waiting | `completed` | `subscribe` | not `hasValue` | `completed` | `syncComplete` only |
| T13 | waiting | `errored` | `subscribe` | — | `errored` | `syncError(e)`. No `syncNext(last)`. |
| T14 | terminal | `completed` or `errored` | `connect` | factory returns the stopped subject | same | `subSource` into a stopped subject. Further source nexts are ignored by `AsyncSubject.next` because `isStopped` (line 25). A second complete is ignored (`AsyncSubject.ts` 33). |

T06’s two outputs are ordered: next, then complete, for every observer that is present when `complete()` runs. `Subject.complete` shifts observers and calls `complete` on them (`Subject.ts` 87–97), but `AsyncSubject.complete` calls `super.next` first while observers are still registered (`AsyncSubject.ts` 35–36).

## D. Contract invariants

1. No subscriber observes a source value before the source completes (T04, T05, T06). JSDoc `publishLast.ts` 12–16.
2. If the source produced one or more values, the flush emits only the last one, once, then complete (T06). Earlier values are overwritten in `last`.
3. If the source completes with zero values, the output is complete with no next (T07, T12).
4. If the source errors, the output is that error and the stored last value is not emitted, including to late subscribers (T08, T13).
5. A subscriber who arrives after a successful complete gets `last` (if any) and complete immediately (T11). The source is not subscribed again for them.
6. A subscriber who unsubscribes before complete does not get a later flush (T09).
7. User disconnect does not flush and does not complete (T10). A later `connect` can keep writing `last` on the same not-stopped subject (T02 after T10).
8. `subscribe` does not call `connect`. No selector. Deprecated.

## E. Scenario specification

Source characterization only. Not executed.

### E1. JSDoc interval

Source emits `0`, `1`, `2` and completes (`take(3)` in the JSDoc, `publishLast.ts` 22–51). Two subscribers joined before `connect`. Each `sourceNext` is T04: no observer output, `last` becomes `2`. T06: both see `outNext(2)`, `outComplete`. Side effects of the source ran once.

### E2. Late subscriber after complete

After E1, a third `subscribe` is T11: `syncNext(2), syncComplete`. No second run of the source.

### E3. Complete with no value

`connect()` on `EMPTY`. T07. Observers get `outComplete` only. A late subscriber is T12 `syncComplete`. `hasValue` stays false.

### E4. Error drops the last value

Source emits `1` then errors `e`. T04 stores `1` with no output. T08 `outError(e)`. Nobody sees `1`. A late subscriber is T13 `syncError(e)`.

### E5. Unsubscribe before complete, and a disconnect

Subscriber A joins, `connect`, source emits `1` (`last = 1`, no output). A unsubscribes (T09). Source later completes: there is no observer left, but T06 still runs; the empty observer list gets no call, and the subject is stopped with `_hasValue`. A new subscriber then takes T11 and does see `syncNext(1), syncComplete`.

Separate case: instead of completing, the user unsubscribes the connection after `last = 1` (T10). Current observers get nothing. A new subscriber joins a not-stopped subject (T01) and still gets nothing until a future complete. `connect()` again (from `silent`) can overwrite `last` with newer source values and a later complete flushes only the newest.

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
- synchronous multi-source emissions in listed order: single source; the complete-time flush is synchronous and in-model
- limits: `refCount` is not folded in. `ConnectableObservable`’s constant-subject factory is the whole reset story; there is no fresh `AsyncSubject` after complete. Parent connectable rules: `multicast.md`.
