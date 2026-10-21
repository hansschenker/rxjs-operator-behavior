# shareReplay

`shareReplay` (`operators/shareReplay.ts` 155–173) is a fixed `share` configuration plus a `ReplaySubject` connector. It is not a separate multicaster.

Config object (`shareReplay.ts` 162–163): `bufferSize = Infinity`, `windowTime = Infinity`, `refCount = false`, `scheduler` from the object if present.

Positional (`shareReplay.ts` 164–166): `bufferSize = argument ?? Infinity`, `windowTime` stays the second argument (**undefined if omitted**), `scheduler` is the third argument, and `refCount` stays `false`. The positional form never enables refCount. JSDoc (`shareReplay.ts` 33–36, 39–43) says the default refCount is false and that the object overload is what turns it on. That matches the code.

Both forms return (`shareReplay.ts` 167–172):

```
share({
  connector: () => new ReplaySubject(bufferSize, windowTime, scheduler),
  resetOnError: true,
  resetOnComplete: false,
  resetOnRefCountZero: refCount, // false unless the config object says true
})
```

`ReplaySubject` (`ReplaySubject.ts` 47–56, 58–109): `_bufferSize = Math.max(1, bufferSize)` so `0` and negatives become `1`, while `Infinity` stays `Infinity`. `_infiniteTimeWindow = (windowTime === Infinity)`. A config object therefore gets a true infinite window. A positional call that omits `windowTime` passes `undefined`, `undefined === Infinity` is false, and `_windowTime = Math.max(1, undefined)` is `NaN`. Expiry timestamps are `now + NaN`, and `NaN <= now` is false, so the time trim never deletes (`ReplaySubject.ts` 99–108). Count trim still works, with timestamp slots doubling the array (`ReplaySubject.ts` 93–95). Passing an explicit numeric `windowTime` uses real timestamps and the `scheduler` argument only as `TimestampProvider.now` (`ReplaySubject.ts` 44–46, 61). It is not `observeOn`. The parameter JSDoc at `shareReplay.ts` 149–150 (“scheduler where connected observers will be invoked”) does not match this call.

Reset policy, inherited from `share.ts` 226–237 and 197–205:

- `resetOnError: true`. Current subscribers get the error. `reset()` drops the subject before `dest.error`. The next subscriber builds a new `ReplaySubject` and a new source subscription. The error is not replayed. Buffered values from the failed attempt are not replayed. This is the JSDoc line “an errored source can be retried” (`shareReplay.ts` 21).
- `resetOnComplete: false`. The same `ReplaySubject` is retained and stopped. A late subscriber gets the buffered values, then complete (`ReplaySubject._subscribe` 69–85, `Subject._checkFinalizedStatuses`). The source is not resubscribed. This is “a successfully completed source will stay cached forever” (`shareReplay.ts` 20–21).
- `resetOnRefCountZero` is false by default, so the last unsubscribe does not unsubscribe the source and does not clear the buffer (`share.ts` T12 / T22 in `share.md`). `refCount: true` in the config object selects `share`’s 1→0 `resetAndUnsubscribe`, which drops the subject. The next subscriber does not see the old buffer.

The `scheduler` argument is not an emission scheduler. Window eviction uses `timestampProvider.now()` only when the window is finite.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `cold \| hot \| completedHold \| erroredThenCold` | `cold` | Error does not rest in a hold phase under the forced `resetOnError: true`, except momentarily inside the error handler. |
| `refCount` | integer | `0` | `share`’s counter. |
| `buffer` | value queue, optional timestamps | empty | `ReplaySubject._buffer`. |
| `bufferSize` | integer ≥ 1 or `Infinity` | as above | After `Math.max(1, _)`. |
| `windowTime` | `Infinity` or number or `NaN` | config `Infinity`; positional may be `NaN` | — |
| `refCountMode` | boolean | `false` unless config `refCount: true` | Copied into `resetOnRefCountZero`. |
| `connection` | present or not | absent | Same single connection as `share`. |
| `stoppedComplete` | boolean | `false` | True while `resetOnComplete: false` has left the replay subject completed. |

`share`’s `hasErrored` does not stay true after the synchronous `reset()`.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = cold`. `δ` / `λ` include `share`’s refCount rules restricted to this config. Full reset algebra is in `share.md`; rows here are the ones this config can take.

### S

| Location | Meaning |
| --- | --- |
| `cold` | No subject, or a reset just cleared it. |
| `hot` | Connected, subject alive, `refCount ≥ 0`. `refCount = 0` with `refCountMode = false` stays `hot`. |
| `completedHold` | Source completed. Buffer frozen. Late subscribers are replayed then completed. |
| `cancelled` | Not a distinct location when `refCountMode` is false. With `refCountMode` true, 1→0 returns to `cold`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | 0→1 connects if `cold`. Joining `completedHold` replays. |
| 2 | Downstream cancel | `unsubscribe` | 1→0 resets only if `refCountMode`. |
| 3 | Source next | `sourceNext(v)` | Appended to the replay buffer, then fan-out. |
| 4 | Source error | `sourceError(e)` | Delivered, then state goes `cold`. |
| 5 | Source complete | `sourceComplete` | Delivered, then `completedHold`. |
| 6 | Replay read | internal on subscribe | Buffer walk in `ReplaySubject._subscribe`. |
| 7 | Time trim | `now` via timestamp provider | Only if `windowTime` is a finite number. |
| 8 | Config | positional versus object | Selects `refCountMode` and whether `windowTime` is `Infinity` or `NaN`. No separate user event. |

### Γ

`ε`, `subSource`, `unsubSource`, `outNext(v)` live, `replay(v)` synchronous on subscribe, `outError(e)`, `outComplete`, `syncComplete` after a replay on a stopped subject.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `cold` | `subscribe` | — | `hot` | new `ReplaySubject`; `refCount := 1`; `subSource`. Buffer empty, so no `replay`. |
| T02 | waiting | `hot` | `subscribe` | source not completed; `refCount` was ≥ 0 and connection exists | `hot` | `replay` of the current buffer in FIFO order (`ReplaySubject.ts` 77–81); `refCount++`; no second `subSource` |
| T03 | emitting | `hot` | `sourceNext(v)` | — | `hot` | push `v` (and a timestamp if the window is not infinite); trim; `outNext(v)` to current observers (`ReplaySubject.ts` 58–66) |
| T04 | per-source error | `hot` | `sourceError(e)` | always, because `resetOnError` is true | `cold` | `outError(e)` to current observers; subject and buffer dropped; source subscription ends. Late subscribers do not get `e` or the old buffer (`share.ts` 226–230). |
| T05 | terminal | `hot` | `sourceComplete` | `resetOnComplete` is false | `completedHold` | `outComplete` to current observers; buffer kept; connection not replaced; no resubscribe (`share.ts` 232–236) |
| T06 | waiting | `completedHold` | `subscribe` | — | `completedHold` | `replay` each buffered value, then `syncComplete` (`ReplaySubject.ts` 69–85). `refCount` moves, but T05’s `hasCompleted` blocks `resetOnRefCountZero` (`share.ts` 203) and blocks a new `subSource`. |
| T07 | cancel | `hot` | `unsubscribe` | `refCount` stays ≥ 1 | `hot` | that subscriber leaves. Buffer unchanged. |
| T08 | cancel | `hot` | `unsubscribe` | hits `0` and `refCountMode = false` | `hot` | `ε`. Source stays connected. Buffer stays. (`share.ts` 255–256 via `handleReset` on `false`.) |
| T09 | init | `hot` with `refCount = 0` | `subscribe` | `refCountMode = false` | `hot` | T02’s replay of whatever the still-running source has buffered; no new `subSource` |
| T10 | cancel | `hot` | `unsubscribe` | hits `0` and `refCountMode = true` | `cold` | `unsubSource`; subject dropped, so the buffer is gone (`share.ts` `resetAndUnsubscribe`) |
| T11 | waiting | `hot` | `sourceNext(v)` | finite `windowTime` and `now` past a timestamp | `hot` | those expired entries are spliced out before fan-out and before any later replay (`ReplaySubject.ts` 88–108) |
| T12 | waiting | `hot` | `sourceNext(v)` | more than `bufferSize` values retained | `hot` | oldest dropped. `bufferSize` `Infinity` skips the count splice (`ReplaySubject.ts` 95). |
| T13 | terminal | `completedHold` or `cold` | further source notifications | connection already ended | same | `ε`. A `cold` machine has no connection until T01. |
| T14 | per-source error | `cold` | `subscribe` after T04 | — | `hot` | same as T01. This is the retry. The previous `e` is not replayed. |

Positional `windowTime === undefined` takes T12 for the count and does not take a successful T11 time eviction (timestamps are `NaN`). Config-object default `windowTime: Infinity` skips both the timestamp push and T11 (`ReplaySubject.ts` 39–40, 62).

## D. Contract invariants

1. `refCount` defaults false. The positional signature `shareReplay(bufferSize, windowTime, scheduler)` does not set it (`shareReplay.ts` 161–166).
2. `bufferSize` defaults to `Infinity`. After the `ReplaySubject` constructor it is at least `1`.
3. Completed sources stay cached (`resetOnComplete: false`). Late subscribers see up to `bufferSize` values (and only those inside a real time window), then complete, and do not resubscribe the source.
4. Errored sources do not stay cached (`resetOnError: true`). Current subscribers error; the next subscription is a new buffer and a new source subscription.
5. With default refCount, `refCount` 1→0 does not unsubscribe the source. The JSDoc example at `shareReplay.ts` 134–139 is this fact. `refCount: true` does unsubscribe and the next subscriber loses the buffer (T10 then T01).
6. Live `sourceNext` both updates the buffer and is delivered to current subscribers. Subscribe-time delivery of the buffer is synchronous and ordered, and it stops if the new subscriber closes mid-replay (`ReplaySubject.ts` 79).
7. The third positional argument / config `scheduler` is a timestamp provider for the window, not an emission scheduler. Infinite window never calls it.
8. Omitted positional `windowTime` does not mean “infinite window” inside `ReplaySubject`, even though the config-object default is `Infinity`. Time-based eviction does not fire for `NaN` deadlines. Count-based eviction still does.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Late subscriber sees the last three

`shareReplay(3)` positional. `refCountMode` is false. `windowTime` is the `NaN` case; the count cap is 3. Source emits `0,1,2,3,4`. Current subscribers see each of those live (T03/T12); the buffer holds `2,3,4`. A subscriber who joins then gets T02 `replay(2), replay(3), replay(4)`, then live `5` when the source emits it. This is the JSDoc “sub C” story (`shareReplay.ts` 47–87) restricted to the buffer rule. The example’s wall-clock delays are not part of the machine.

### E2. Complete is sticky

Source emits `1`, `2` and completes. `bufferSize` infinite. Subscribers see `1`, `2`, `outComplete` (T03, T05). A subscriber who arrives after that gets `replay(1), replay(2), syncComplete` (T06) and does not cause `subSource`.

### E3. Error can be retried

Source emits `1` then errors `e`. Current subscribers see `outNext(1), outError(e)`. Phase `cold` (T04). A new `subscribe` is T14/T01: empty buffer, new `subSource`. They do not see `1` and do not see `e` until the new subscription errors.

### E4. Default refCount leaves the source running

One subscriber receives `0` and unsubscribes. T08: no `unsubSource`. The source’s next value `1` is still pushed into the buffer (T03 with an empty observer list). A new subscriber gets `replay` including `1` if it is still inside the buffer (T09) and does not restart the source. With `{ bufferSize: 1, refCount: true }`, the unsubscribe is T10 instead: source unsubscribed, buffer gone, and the new subscriber is T01.

### E5. Finite window

`shareReplay({ bufferSize: Infinity, windowTime: 1000, refCount: false })`. A value whose stored deadline is `<= now` at the next trim is removed (T11) and is absent from a later T02 replay. Values younger than the window remain. No `observeOn` is inserted. Positional `shareReplay(Infinity, 1000)` is the same window, still with `refCountMode` false.

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
- ordinary downstream reentrancy: excluded, except `ReplaySubject`’s documented stop-when-`subscriber.closed` during replay
- synchronous multi-source emissions in listed order: single source; replay order is buffer order
- limits: Clock values are whatever `TimestampProvider.now` returns; no concrete scheduler is executed. The `NaN` window from an omitted positional `windowTime` is an implementation fact (D8), not the config-object default. `share` notifier factories are not exposed by `shareReplay` (the three reset knobs are constants). Parent transitions: `share.md`.
