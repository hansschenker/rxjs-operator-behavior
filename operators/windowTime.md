# windowTime

`windowTime` emits nested observables bounded by time (`windowTime.ts` 106–207). The fully tabulated machine is span-only: one window opens at subscribe, source values are forwarded into it, the window completes when `windowTimeSpan` elapses, and another window is opened immediately (`restartOnClose`). `maxWindowSize` can complete a window early after that many values. Source `complete` completes every open inner and the outer. Source `error` errors every open inner and the outer. `cancel` clears timers and nulls the record list but does not complete the subjects. The creation-interval overload is a second table: windows are started on a repeating schedule and are not restarted on close, so a gap drops values. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/windowTime.ts`. Not deprecated. JSDoc says `maxWindowCount` in one place (line 42) and `maxWindowSize` in the signature (line 99); the parameter is `maxWindowSize`.

## A. Identity, contract, and scope

- Operator/overload: three signatures (12–23), parsed like `bufferTime` (107–109).
  - `windowTime(span, scheduler?)`
  - `windowTime(span, creationInterval, scheduler?)`
  - `windowTime(span, creationInterval | null | void, maxWindowSize, scheduler?)`
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 34–45. Span-only reopens when a window closes. Creation interval opens on the interval. `maxWindowSize` completes a window after that many `next`s and, in span-only mode, opens the next immediately.
- Model kind: timed and extended, not finite. Record list and `seen` counters are data, not a finite control set.
- Parameter domain: `scheduler = popScheduler(otherArgs) ?? asyncScheduler` (107). `windowCreationInterval = otherArgs[0] ?? null` (108). `maxWindowSize = otherArgs[1] || Infinity` (109), so `0` becomes `Infinity`. Creation interval `>= 0` selects the repeating schedule (146–150). Otherwise `restartOnClose = true` (152). Negative span is scheduler-defined and excluded.
- Payload/error domain: outer `next` is `Observable<T>`. Inner `next` is `T`. Terminal inner signals use the same `complete` or `error` as the outer (`terminate`, 169–173).
- Subscription boundary: `startWindow` during subscribe emits the first observable and schedules its close (154, 130–143). Source is subscribed after that (175–191). Each window has a `Subscription` added to the destination (132–133) that owns the span timer (142).
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. Micro-trace required when span fire, max size, and source complete meet. Ordinary model: no reentrancy, even though `loop` copies the record array (163) for that reason.
- Callback assumptions: no user selector. `closeWindow` completes the subject, unsubscribes its timer, removes the record, then maybe `startWindow` (118–123). Downstream throw is an observer fault.
- Cleanup assumptions: the function returned to `operate` sets `windowRecords = null` (196–199) and does not complete subjects. Timers die because their subscriptions were added to the destination. `cancel` therefore leaves inner subjects open and silent, and does not outer-`complete`. Source `terminate` calls `subscriber.unsubscribe()` after notifying (169–173), which runs that teardown.
- Explicit exclusions: reentrancy; `maxWindowSize === 0` as a real cap; negative creation interval (treated as span-only); per-inner-subscriber model.

Inner contract stored on each record: `Subject` plus `seen` count. Outer machine does not track who subscribed to `asObservable()`.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open([W0]) after the synchronous first outer next
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(records)` | `{ window, subs, seen }[]`, `restartOnClose` | Span-only normally one record. Interval mode zero or more. |
| `Stopped` | `windowRecords = null` | Terminal outer. Subjects may already be completed or errored, or, after cancel, left open. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | `startWindow` (154). |
| `sourceNext(v)` | yes | source | Forward to each window; maybe close on max size (178–184). |
| `sourceError(e)` | yes | source | `terminate(error)` (189). |
| `sourceComplete` | yes | source | `terminate(complete)` (187). |
| `cancel` | yes | unsubscribe | Timers cleared; subjects not completed (196–199). |
| `spanFired(record)` | yes | per-window timer (142) | `closeWindow`. |
| `creationFired` | yes, interval mode | repeating schedule (150) | `startWindow`. |
| user callback | no | — | None. |
| timer error | no | scheduler actions do not error | Inapplicable. |

### Γ

Outer: `none` | `next(Observable)` | `error(e)` | `complete`. Inner `next`/`complete`/`error` are effects on stored subjects. Micro-trace required at close.

## C. Transition obligations

### Span-only, fully specified

`restartOnClose = true`. Default `maxWindowSize = Infinity`.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | span-only | outer `next(W0)` | record `{seen:0}`; span timer due at `span` (130–143, 154) | `Open([W0])` | ε | source subscribed after | S01 |
| T02 | `Open` | `sourceNext(v)` | `seen+1 < max` for each record | outer `none` | `window.next(v)`; `seen++` (180–183) | same windows | T01 | — | S01 |
| T03 | `Open([W])` | `spanFired` | — | outer `next(W')` because restart | `W.complete()`, timer unsubscribed, record removed, `startWindow` (118–123) | `Open([W'])` | T01 or T02 | `W'` has no prior values | S01 |
| T04 | `Open` | `sourceNext(v)` | `maxWindowSize <= ++seen` | outer `next(W')` in span-only | `v` is delivered first (181), then `closeWindow` (183) which restarts | `Open([W'])` | T02 | `v` is in the closed window, not in `W'` | S02 |
| T05 | `Open` | `sourceComplete` | — | outer `complete` | every open window `complete`, then outer `complete`, then `subscriber.unsubscribe()` (169–173, 187) | `Stopped` | T01 | includes an empty window if nothing arrived | S03 |
| T06 | `Open` | `sourceError(e)` | — | outer `error(e)` | every open window `error(e)`, then outer `error`, then unsubscribe (189) | `Stopped` | T02 | inners do not `complete` | S04 |
| T07 | `Open` | `cancel` | — | outer `none` | span subs unsubscribed; `windowRecords=null` (196–199); subjects not completed or unsubscribed; no outer `complete` | `Stopped` | T02 | inner subscribers do not see `complete` | S05 |
| T08 | `Stopped` | `spanFired` | records null or subs dead | `none` | `startWindow` no-ops if `windowRecords` is null (131) | `Stopped` | T05–T07 | none | — |

### Creation-interval overload (`creationInterval >= 0`)

`restartOnClose = false`.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T20 | ∅ | `subscribe` | — | outer `next(W0)` | immediate window plus repeating `startWindow` after one interval (146–154) | `Open([W0])` | ε | — | S06 |
| T21 | `Open` | `creationFired` | records non-null | outer `next(Wnew)` | new record and its own span timer | more records | T20 | — | S06 |
| T22 | `Open` | `spanFired(record)` | no restart | outer `none` | that subject `complete`s; record removed; no replacement (123) | fewer records | T20 | gap if none remain | S06 |
| T23 | `Open` | `sourceNext(v)` | — | outer `none` unless max size closes and somehow restarts (it does not) | `v` goes only to records in the copied list (180–183). Empty list drops `v` | same | T22 | — | S06 |
| T24 | `Open` | `sourceComplete` / `sourceError(e)` | — | complete or error every still-open window, then the outer | repeating schedule cleared by `subscriber.unsubscribe()` inside `terminate` | `Stopped` | T20 | none | S06 |
| T25 | `Open` | `cancel` | — | outer `none` | same as T07; repeating schedule cleared; subjects left open | `Stopped` | T20 | none | S05 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Span-only emits a window observable during subscribe, before source subscription (154 vs 175). |
| I02 | Span fire completes that inner and, if `restartOnClose`, emits a new inner immediately (118–123). |
| I03 | A value that hits `maxWindowSize` is inside the window that then completes (181 before 183). |
| I04 | `maxWindowSize` `0` is stored as `Infinity` (line 109). |
| I05 | Source `complete` completes open inners and the outer. Source `error` errors open inners and the outer. This differs from `bufferTime`, which drops partial arrays on error and emits them on complete. |
| I06 | `cancel` does not complete open inners and does not complete the outer. Timers do not fire later. |
| I07 | Creation-interval mode does not open a window on close. If `creationInterval > span`, values in the gap are in no window. The first window still starts at t=0 (154), not after one interval. |
| I08 | JSDoc `maxWindowCount` (line 42) is the `maxWindowSize` parameter (line 99). |

## E. Scenario specification

### S01 Span close reopens

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: `windowTime(10)`, virtual scheduler, no max
- prefix: `subscribe` at t=0 (outer `next(W0)`), `sourceNext(a)` at t=4
- target event: span at t=10
- expected notifications: `W0` sees `a` then `complete`; outer `next(W1)` at t=10
- lifecycle: `W0`’s timer unsubscribed; `W1`’s timer due at t=20
- suffix: `Open([W1])`
- final state: `Open([W1])`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`windowTime.ts` 118–143, 178–184)

### S02 maxWindowSize

- Test ID: S02
- Covered row IDs: T04
- Starting state: `Open([W0])`, span 100, `maxWindowSize = 2`
- Reset/fixture: `windowTime(100, null, 2, scheduler)`
- prefix: `subscribe`, `sourceNext(a)`
- target event: `sourceNext(b)`
- expected notifications: `W0` sees `a`,`b` then `complete`; outer `next(W1)`; `b` is not also sent to `W1`
- lifecycle: span timer of `W0` unsubscribed inside `closeWindow`; new span starts
- suffix: `Open([W1])`
- final state: `Open([W1])`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (181–183, 118–123)

### S03 Source complete

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Open([W0])` with or without values
- Reset/fixture: span not yet fired
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `W0.complete()` (even if empty) and outer `complete`. No extra window
- lifecycle: `terminate` unsubscribes the destination, so the span timer is cleared
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (169–173, 187)

### S04 Source error

- Test ID: S04
- Covered row IDs: T06
- Starting state: `Open([W0])` after `sourceNext(a)`
- Reset/fixture: span armed
- prefix: value `a` already in `W0`
- target event: `sourceError(e)`
- expected notifications: `W0.error(e)`, outer `error(e)`. Not `complete`
- lifecycle: timer cleared by `terminate`’s unsubscribe
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (line 189). Contrast `bufferTime.ts` 158, which does not emit the partial.

### S05 Cancel

- Test ID: S05
- Covered row IDs: T07, T25
- Starting state: `Open([W0])` with an inner subscriber
- Reset/fixture: span-only, and the same idea in interval mode
- prefix: `subscribe`, `sourceNext(a)`
- target event: `cancel`
- expected notifications: outer none; `W0` does not `complete`
- lifecycle: span subscription unsubscribed; record list nulled; subject still open
- suffix: advancing time must not complete `W0` or emit `W1`
- final state: outer `Stopped`; subject not terminated
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (196–199 versus 118–123)

### S06 Creation interval gap

- Test ID: S06
- Covered row IDs: T20, T21, T22, T23, T24
- Starting state: unsubscribed
- Reset/fixture: `windowTime(5, 10)` so span 5, creation 10
- prefix: `subscribe` at t=0 emits `W0`
- target event: span at t=5 completes `W0` and does not open `W1`; a source value at t=7; creation at t=10 opens `W1`
- expected notifications: outer `next(W0)` at 0, outer `next(W1)` at 10. The value at t=7 is in neither window. Source complete would complete whatever is open
- lifecycle: `restartOnClose` false (146–152)
- suffix: `Open([W1])` after t=10 if not completed
- final state: `Open([W1])`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (146–154, 118–123, 180–183)

## F. Coverage and evidence

Denominator = 14 (T01–T08, T20–T25). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S05 | not executed |
| T08 | none | not executed |
| T20 | S06 | not executed |
| T21 | S06 | not executed |
| T22 | S06 | not executed |
| T23 | S06 | not executed |
| T24 | S06 | not executed |
| T25 | S05 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Tie order is assumed. Reentrancy excluded despite the defensive array copy. `maxWindowSize === 0` means unlimited because of `||`. Cancel does not terminate inners. Inner subscribers are not modeled.
- Contract vs 7.8.2 characterization: JSDoc 34–45 matches the two schedules and the max-size close. The name `maxWindowCount` in the prose is the code’s `maxWindowSize`. Error-versus-complete inner termination is `terminate` (169–189), sharper than the one sentence at lines 38–40.
- Tests still required: S01–S06 on `TestScheduler`, including error versus complete, unsubscribe during a span, and `creationInterval > span`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
