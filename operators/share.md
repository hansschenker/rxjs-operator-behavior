# share

`share(options?)` (`operators/share.ts` 142–243) returns a referentially transparent operator whose **result** closes over connection state (lines 144–159). Defaults, from the destructure at line 143:

- `connector = () => new Subject()`
- `resetOnError = true`
- `resetOnComplete = true`
- `resetOnRefCountZero = true`

Each of the three reset options may instead be `false` or a notifier factory (`ShareConfig`, lines 8–46). `handleReset` (lines 245–267): `true` calls `reset` immediately and returns no subscription; `false` does nothing; a factory subscribes to `innerFrom(on(...args))` and calls `reset` on that notifier’s first `next` only.

This is not “a multicast and nothing else”. The machine tracks `refCount`, a single `connection` to the source, a `subject`, the flags `hasCompleted` / `hasErrored`, and an optional pending reset subscription.

Per subscriber (`share.ts` 180–240):

1. `refCount++`. If not `hasErrored` and not `hasCompleted`, cancel a pending reset (a resubscribe aborts a delayed refCount reset).
2. `dest = subject = subject ?? connector()`.
3. Register the refCount teardown **before** `dest.subscribe(subscriber)`, so a synchronous terminal is visible to the teardown (lines 192–206).
4. `dest.subscribe(subscriber)`.
5. If `connection` is unset and `refCount > 0`, assign `connection = new SafeSubscriber(...)` **before** `innerFrom(source).subscribe(connection)` (lines 212–239). A reentrant subscribe sees `connection` already set and does not open a second source subscription.

`reset` (lines 167–171) clears `connection`, `subject`, `hasCompleted`, and `hasErrored`. It does not unsubscribe. `resetAndUnsubscribe` (lines 172–178) captures `connection`, resets, then unsubscribes that connection. Error and complete handlers call `handleReset(reset, ...)`, not `resetAndUnsubscribe`, and they set the flag **before** `handleReset`, then call `dest.error` / `dest.complete` **after** it (lines 226–237). The source `SafeSubscriber` still unsubscribes itself in `Subscriber._error` / `_complete`’s `finally` (`Subscriber.ts` 116–129).

Default `Subject` replays neither values nor, after a true reset, the terminal: `reset()` nulls `subject` before `dest.error`, so the next subscriber gets a new subject. If `resetOnError` is `false`, `hasErrored` stays true, the same subject is retained, and `Subject._checkFinalizedStatuses` re-emits `thrownError` to late subscribers (`Subject.ts` 136–144). `resetOnComplete: false` similarly re-completes late subscribers and does not resubscribe the source. A `ReplaySubject` connector would replay its buffer before that stored error or complete; the default connector does not.

`resetOnRefCountZero` runs only from the subscriber teardown when `refCount` hits `0` and both terminal flags are false (lines 197–205). A terminal reset that already cleared the flags can therefore also observe this teardown; `connection` is already undefined, so the extra `resetAndUnsubscribe` is a no-op on the source. If the terminal policy is `false`, the flags stay true and this teardown does not reset.

Notifier factories: only a `next` resets (`share.ts` 259–264). The notifier’s `complete` is a no-op (`SafeSubscriber` with no complete handler). The notifier’s `error` hits `SafeSubscriber`’s missing-error path (`Subscriber.ts` 170–172, 246–248) and is not a modeled reset. A new subscriber before the notifier’s next calls `cancelReset` (line 183) and keeps the same subject and connection.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `cold \| hot \| pendingReset \| completedHold \| erroredHold` | `cold` | `cold`: no subject. `hot`: connected, `refCount ≥ 1`. `pendingReset`: `refCount = 0`, connection still alive, waiting on a refCount notifier. `*Hold`: terminal flag set and subject retained. |
| `refCount` | integer | `0` | Subscribers currently joined to `dest`. |
| `subject` | `SubjectLike \| none` | none | `connector()` result. |
| `connection` | `SafeSubscriber \| none` | none | The single source subscription. |
| `hasCompleted` | boolean | `false` | Set true before the complete reset decision. Cleared if that reset runs sync. |
| `hasErrored` | boolean | `false` | Same for error. |
| `resetSub` | subscription or none | none | Pending notifier. |
| `connector`, `resetOnError`, `resetOnComplete`, `resetOnRefCountZero` | config | defaults above | Immutable for the operator result. |

Per-subscriber identity is not a field. Downstream reentrancy that subscribes again to this same shared observable during a source `next` is partly in-model: the connection assignment prevents a second `subSource`. Arbitrary reentrant `unsubscribe` graphs beyond the refCount teardown are excluded.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)` with `s₀ = cold`. `S` is `phase` times the fields. The shared machine is one per operator result, not one per subscriber.

### S

| Location | Meaning |
| --- | --- |
| `cold` | No subject, no connection. Next `subscribe` will connect. |
| `hot` | Source connected. `refCount ≥ 1`. |
| `pendingReset` | `refCount = 0`, source still connected, notifier not yet nexted. |
| `completedHold` | Source completed, `resetOnComplete` did not clear state. Late subscribers sync-complete. |
| `erroredHold` | Source errored, `resetOnError` did not clear state. Late subscribers sync-error with the same `e`. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | `refCount` 0→1 is the cold start. `refCount` k→k+1 joins `dest`. |
| 2 | Downstream cancel | `unsubscribe` | One subscriber. `refCount` 1→0 is the reset decision. |
| 3 | Source next | `sourceNext(v)` | `connection`’s next: `dest.next(v)`. |
| 4 | Source error | `sourceError(e)` | Sets `hasErrored`, then reset policy, then `dest.error(e)`. |
| 5 | Source complete | `sourceComplete` | Sets `hasCompleted`, then reset policy, then `dest.complete()`. |
| 6 | Late join while held | `subscribe` in `*Hold` | Not a new source subscription. |
| 7 | Notifier | `notifierNext`, `notifierComplete` | Only if the active reset option is a factory. |
| 8 | Connector | `connector()` | Internal. No user scheduler. `shareReplay` supplies a different connector; this file’s default is `Subject`. |

### Γ

`ε`, `subSource`, `unsubSource`, `outNext(v)` to every current subject observer, `outError(e)` to every current observer, `outComplete` to every current observer, `syncError(e)` or `syncComplete` to one new subscriber (subject already stopped), `newSubject`.

`outNext(v)` is fan-out in observer-list order (`Subject.ts` 59–70). No replay on the default subject.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `cold` | `subscribe` | `refCount` was `0` | `hot` | `newSubject`; join that subscriber to it; `refCount := 1`; `subSource` (`share.ts` 181–239) |
| T02 | waiting | `hot` | `subscribe` | `refCount ≥ 1`, flags clear | `hot` | join existing subject; `refCount++`. No second `subSource`. No replay. |
| T03 | emitting | `hot` | `sourceNext(v)` | — | `hot` | `outNext(v)` to current observers |
| T04 | per-source error | `hot` or `pendingReset` | `sourceError(e)` | `resetOnError = true` | `cold` | flag set, `reset()` sync (flags cleared, subject dropped), then `outError(e)` to observers of the old subject. Source unsubscribed by the `SafeSubscriber` finally. New subscribers do not see `e`. |
| T05 | per-source error | `hot` or `pendingReset` | `sourceError(e)` | `resetOnError = false` | `erroredHold` | `outError(e)` on the retained subject; `hasErrored` stays true; no `subSource` later |
| T06 | per-source error | `hot` or `pendingReset` | `sourceError(e)` | `resetOnError` is a factory | `erroredHold` until notifier | `hasErrored := true`; subscribe notifier with `e`. No reset yet. Then `outError(e)`. |
| T07 | terminal | `hot` or `pendingReset` | `sourceComplete` | `resetOnComplete = true` | `cold` | same shape as T04 with `outComplete` and no retained completion |
| T08 | terminal | `hot` or `pendingReset` | `sourceComplete` | `resetOnComplete = false` | `completedHold` | `outComplete`; subject retained; no resubscribe |
| T09 | terminal | `hot` or `pendingReset` | `sourceComplete` | factory | `completedHold` until notifier | `hasCompleted := true`; arm notifier; then `outComplete` |
| T10 | cancel | `hot` | `unsubscribe` | after decrement `refCount > 0` | `hot` | `ε` for everyone else. That subscriber leaves the subject. |
| T11 | cancel | `hot` | `unsubscribe` | decrement hits `0`, not `hasErrored`, not `hasCompleted`, `resetOnRefCountZero = true` | `cold` | `unsubSource`; `reset()` (`resetAndUnsubscribe`, lines 172–178 and 203–205) |
| T12 | cancel | `hot` | `unsubscribe` | hits `0`, flags clear, `resetOnRefCountZero = false` | `hot` with `refCount = 0` | `ε`. Connection and subject stay. Phase is the zero-subscriber hot state (still not `cold`). |
| T13 | cancel | `hot` | `unsubscribe` | hits `0`, flags clear, factory | `pendingReset` | arm notifier. Source stays connected. |
| T14 | waiting | `pendingReset` | `notifierNext` | refCount factory | `cold` | `unsubSource`; `reset()`; notifier unsubscribed (lines 260–263) |
| T15 | waiting | `pendingReset` | `subscribe` | arrives before notifier next | `hot` | `cancelReset` (line 183); `refCount := 1`; join the **same** subject; no new `subSource` |
| T16 | waiting | `erroredHold` | `subscribe` | `resetOnError` was false, or factory has not nexted | `erroredHold` | `syncError(e)` from `Subject` (`Subject.ts` 139–140). No `subSource`. `refCount` still increments and then the subscriber tears down. |
| T17 | waiting | `completedHold` | `subscribe` | complete was not reset | `completedHold` | `syncComplete`. No replay of values (default `Subject`). No `subSource`. |
| T18 | waiting | `erroredHold` or `completedHold` | `notifierNext` | matching factory | `cold` | `reset()` only (not `resetAndUnsubscribe`). Connection is already dead from the source terminal. |
| T19 | waiting | `pendingReset` | `notifierComplete` | — | `pendingReset` | `ε`. Complete does not reset. |
| T20 | terminal | any | `unsubscribe` while `hasErrored` or `hasCompleted` | teardown guard line 203 fails | same | `ε` besides the subscriber leaving. Does not apply `resetOnRefCountZero`. |
| T21 | init | `cold` | `subscribe` | synchronous source terminal inside T01 drops `refCount` to `0` before line 217’s check | `cold` | subject join and the terminal outputs of T04/T07, but the `refCount > 0` guard skips `subSource` if teardown already ran. Prevents the leak called out at lines 212–217. |

T12’s location is still “connected with zero listeners”. A later `subscribe` is T02’s join without `subSource`, except `refCount` was `0`: the code path is the same `subject ?? connector()` which finds the existing subject, and `!connection` is false, so it does not resubscribe. Call that T12b, counted below.

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T22 | init | zero-subscriber hot (after T12) | `subscribe` | connection still set, flags clear | `hot` | join existing subject; `refCount := 1`; no `subSource`; no replay |

## D. Contract invariants

1. There is at most one `connection`. The field is assigned before `source.subscribe` (lines 219–239).
2. `refCount` equals the number of subscribers whose teardown has not run. `0 → 1` from `cold` is the only default `subSource`. `1 → 0` applies `resetOnRefCountZero` only when both terminal flags are false.
3. Default config (`true, true, true`, line 143): after error, current subscribers get `outError(e)` and the next subscription is cold (T04). The error is not replayed. After complete, current subscribers get `outComplete` and the next subscription is cold (T07). After the last unsubscribe while the source is still open, the source is unsubscribed (T11) and the next subscription is cold.
4. `resetOnError: false` replays `e` to late subscribers through the same `Subject` (T05, T16) and does not resubscribe. `resetOnComplete: false` sync-completes late subscribers (T08, T17) and does not resubscribe. Default `Subject` does not replay nexts in either hold state. A custom `ReplaySubject` connector would (`ReplaySubject._subscribe`, and the JSDoc at `share.ts` 17–20).
5. A refCount notifier’s next resets and unsubscribes the source (T14). A subscribe that arrives first cancels that notifier and keeps the connection (T15). That is the delayed-reset example in the JSDoc (lines 105–136).
6. Error and complete are forwarded to whoever is subscribed at that moment. Reset does not swallow the terminal for those subscribers (JSDoc lines 61–64). It only changes what a **later** subscriber sees.
7. `connector` is not invoked until the first subscriber that finds `subject` unset (line 190). `share()` is safe to pass to static `pipe` because the closed-over state lives in the function returned at line 153, not in a shared execution of the factory itself (lines 144–152).
8. Notifier `error` is not a reset. Notifier `complete` is not a reset (T19).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two subscribers, default config

`interval` piped through `share()`, as in the JSDoc (lines 75–83). First `subscribe` is T01: one `subSource`, `refCount = 1`. Second `subscribe` is T02: `refCount = 2`, no second processing of the source. Each `sourceNext(v)` is T03 to both, in subject observer order. Neither subscriber sees the other’s private upstream.

### E2. Last unsubscribe resets

Default `resetOnRefCountZero`. One subscriber, source open. `unsubscribe` is T11: `unsubSource`, subject dropped, phase `cold`. A later `subscribe` is T01 again: new `Subject`, new `subSource`. Values emitted during the gap are gone. No replay.

### E3. `resetOnRefCountZero: false`

Same gap. T12 leaves the connection up. The later subscriber is T22: it does not restart the source and does not see past nexts (default `Subject`). It does see later `sourceNext`s via T03.

### E4. Error reset versus error hold

Default `resetOnError: true`. Source errors `e`. Current subscribers get `outError(e)` (T04). A new `subscribe` is T01, not `syncError(e)`. With `resetOnError: false`, those current subscribers still get `outError(e)` (T05), and a new `subscribe` is T16 `syncError(e)` with no `subSource`. The JSDoc distinction at lines 15–20 is this pair of rows.

### E5. Complete hold

`resetOnComplete: false` (this is what `shareReplay` selects, not the `share()` default). Source completes. Subscribers get `outComplete` (T08). A late subscriber gets T17 `syncComplete` and no values. Default `share()` is T07 instead: the late subscriber starts a fresh source subscription.

### E6. Delayed refCount reset

`resetOnRefCountZero: () => timer(...)`. Last `unsubscribe` is T13, source stays connected. A subscribe before the timer is T15: same subject, notifier cancelled, no new `subSource`. If the timer nexts first, T14 goes `cold` and unsubscribes the source; the following subscribe is T01 and the source starts over. This is the second JSDoc example (lines 105–136).

## F. Coverage and evidence

Not executed.

Denominator = 22 (T01–T22). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded, except the single reentrant `subscribe` that the connection assignment is written to tolerate
- synchronous multi-source emissions in listed order: not a multi-source operator; fan-out order is `Subject`’s current observer snapshot
- limits: Notifier `error` is unhandled by `handleReset` and is not a transition to `cold`. Custom `SubjectLike` connectors that are not `Subject` / `ReplaySubject` / `BehaviorSubject` / `AsyncSubject` are assumed only to implement `next` / `error` / `complete` / `subscribe`. The interaction where T04’s subscriber teardowns run `resetOnRefCountZero` after `reset()` has already cleared the flags is a no-op on `connection` and is not a second source unsubscribe. `shareReplay`’s chosen config is specified in `shareReplay.md`, not by changing these defaults.
