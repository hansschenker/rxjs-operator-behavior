# windowCount

`windowCount(windowSize, startWindowEvery = 0)` emits nested observables of at most `windowSize` source values (`windowCount.ts` 68–128). `startWindowEvery > 0` is the start period; otherwise the period is `windowSize` (line 69). The first window is emitted at subscribe, before any source value (72–77). On each value the operator forwards it to every open window, may complete the oldest window, then may emit a new window (82–108). The new window does not contain the value that caused it to open. Source `complete` completes every still-open inner, then the outer, and does not emit an extra window at complete time — but a window may already have been opened on the value that filled the previous one, so an exact multiple leaves an empty inner that then completes. Source `error` errors every open inner and the outer (116–120). `cancel` does not complete or unsubscribe those subjects; finalize only drops the operator’s references (122–125). Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/windowCount.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `windowCount<T>(windowSize: number, startWindowEvery: number = 0)` (`windowCount.ts` 68).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 16–23, with the code’s own caveat at lines 100–103: windows are emitted when the start count is reached, which is after the value is forwarded to already-open windows, not including that value in the new window. JSDoc line 19–20 says completion or error “emits the current window”; the window observables were already emitted when opened. Complete/error only terminate inners that are still open.
- Model kind: extended, not finite. The list of open subjects and `count` grow with the source. Not a finite automaton.
- Parameter domain: `startEvery = startWindowEvery > 0 ? startWindowEvery : windowSize` (line 69). Documented positive integers. `windowSize <= 0` makes the close predicate `count - windowSize + 1` succeed immediately and is excluded. `startWindowEvery === 0` selects non-overlapping `windowSize` windows.
- Payload/error domain: outer items are `Observable<T>` (`asObservable`). Inner items are `T`. The same `err` is sent to each open subject and then the outer (116–120).
- Subscription boundary: one source subscriber. Subjects are not added to the destination. Inner subscribers are outside this machine; they observe the subjects.
- Scheduler and tie ordering: none. No clock. The micro-trace is the ordered inner `next` / inner `complete` / outer `next` inside one `sourceNext` (86–108).
- Callback assumptions: no selector. Ordinary model: no reentrancy. `starts` is assigned `[]` and only nulled in finalize (73, 123); it is unused by the transitions.
- Cleanup assumptions: finalize (122–125) nulls `windows` and `starts` and does not `complete`, `error`, or `unsubscribe` them. Contrast `window.ts` 90–95 and `windowToggle.ts` 119–128. After `cancel`, open subjects stay open and silent because the source is unsubscribed. No outer `complete`.
- Explicit exclusions: reentrancy; non-positive sizes; modeling each inner subscriber; promising that `cancel` completes inners (it does not).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open([W0], count = 0) after the initial outer next
```

Inner contract stored as data: each `Subject` receives `next` while it is in the list, then exactly one of `complete` (size or source complete) or `error` (source error). `cancel` does neither.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(windows, count)` | list of subjects oldest-first; `count` values already fully processed | `s₀` has `[W0]`, `count = 0`, and `W0` has already been emitted. |
| `Stopped` | list dropped or terminated | — |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | T01. |
| `sourceNext(v)` | yes | source | Lines 82–108. |
| `sourceError(e)` | yes | source | Lines 116–120. |
| `sourceComplete` | yes | source | Lines 110–114. |
| `cancel` | yes | unsubscribe | Finalize only (122–125). |
| inner/timer/selector | no | — | None. |

### Γ

Outer: `none` | `next(Observable)` | `error(e)` | `complete`. A single `sourceNext` may also complete an old inner and emit a new outer window. That ordered triple is required as a micro-trace.

## C. Transition obligations

`startEvery` as in line 69. Close test uses `count` before it is incremented: `c = count - windowSize + 1`, close oldest if `c >= 0 && c % startEvery === 0` (94–97). Then `++count % startEvery === 0` opens a window (104–107).

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | outer `next(W0)` | `windows=[W0]`, `count=0` (72–77) | `Open([W0], 0)` | ε | source | S01 |
| T02 | `Open` | `sourceNext(v)` | close predicate false and open predicate false | outer `none` | `v` to every open window (86–88); `count++` | same windows, `count+1` | T01 | — | S01 |
| T03 | `Open` | `sourceNext(v)` | close predicate true | outer `none` from the close itself | forward `v` to current windows including the one that becomes full; `windows.shift().complete()` (94–97) | oldest removed | T02 | the full window’s last value is `v` | S01 |
| T04 | `Open` | `sourceNext(v)` | after increment, `count % startEvery === 0` | outer `next(Wnew)` | push `Wnew` (104–107). `Wnew` did not receive `v` | list plus `Wnew` | often same step as T03 when `startEvery === windowSize` | — | S01 |
| T05 | `Open` non-empty | `sourceComplete` | — | outer `complete` | every remaining subject `complete`d, oldest first (111–113), then outer `complete` | `Stopped` | T01 or T04 | empty leftover window completes with no values | S02 |
| T06 | `Open` | `sourceError(e)` | — | outer `error(e)` | every remaining subject `error(e)` then outer `error` (117–119) | `Stopped` | T02 | inners do not `complete` | S03 |
| T07 | `Open` | `cancel` | — | outer `none` | subjects left open; refs nulled (122–125); no outer `complete` | `Stopped` | T02 | late inner subscribers hang on an open subject | S04 |
| T08 | overlap | `sourceNext` | `startEvery < windowSize` | as T02–T04 | `v` is forwarded to all currently open windows before any open of a new one | several windows contain `v` | T01 | — | S05 |
| T09 | gap | `sourceNext` | `startEvery > windowSize` and the list is empty | outer `none` or a later `next(Wnew)` | `v` is forwarded to nobody if `windows` is empty (86–88); close predicate may be false | possibly a new window after `count` increments | T03 | `v` is in no window | S05 |
| T10 | `Stopped` | source | — | `none` | inapplicable | `Stopped` | terminal | none | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | An outer window is emitted at subscribe even if the source is empty or synchronous-complete. |
| I02 | A value is sent to windows that are already open, then the oldest may complete, then a new window may be emitted without that value. |
| I03 | For `startEvery === windowSize`, windows do not overlap. Each (except a trailing partial or a boundary-opened empty window) carries `windowSize` values. |
| I04 | When a value both fills a window and lands on a start boundary, the filled window is completed and a new empty window is emitted in that same `sourceNext`, before the operator waits for another value (94–107). Source complete then completes that empty window (T05). |
| I05 | `bufferCount` does not open the next buffer until the next value. This operator does open the next window at the boundary. They are not the same shape. |
| I06 | Source `error` errors open inners. It does not `complete` them. Contrast `bufferCount`, which emits no partial array on error. |
| I07 | Source `complete` completes open inners, including a partial and including an empty boundary window, then completes the outer. |
| I08 | `cancel` does not complete inners and does not complete the outer. |
| I09 | If `startEvery > windowSize`, some values are forwarded to an empty list and appear in no window (T09). |

## E. Scenario specification

### S01 Non-overlapping size 3

- Test ID: S01
- Covered row IDs: T01, T02, T03, T04
- Starting state: unsubscribed
- Reset/fixture: `windowCount(3)`; inners subscribed when emitted
- prefix: `subscribe` → outer `next(W0)`
- target event: `sourceNext` of `a`, `b`, `c`
- expected notifications: outer `next(W1)` on `c`. Inner `W0` sees `a`,`b`,`c` then `complete`. `W1` has seen nothing. No outer notification on `a` or `b`
- lifecycle: close uses `c = 2 - 3 + 1 = 0`, `0 % 3 === 0`; then `count` becomes 3, `3 % 3 === 0` opens `W1`
- suffix: `Open([W1], 3)`
- final state: `Open([W1], 3)`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`windowCount.ts` 86–108)

### S02 Complete after an exact boundary, and complete with no values

- Test ID: S02
- Covered row IDs: T05
- Starting state: after S01, or immediately after T01
- Reset/fixture: `windowCount(3)`
- prefix: either no values, or exactly three values
- target event: `sourceComplete`
- expected notifications: no extra outer `next`. Every open inner `complete`s, then outer `complete`. After exact three values, `W1` completes with zero inner values. After zero source values, `W0` completes with zero inner values
- lifecycle: lines 111–114
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 Error forwards to open inners

- Test ID: S03
- Covered row IDs: T06
- Starting state: `Open([W0], 1)` after one value of `windowCount(3)`
- Reset/fixture: inner subscribed
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `W0.error(e)` then outer `error(e)`. Not a `complete`, and no array-like partial
- lifecycle: lines 116–120
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S04 Cancel leaves inners open

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Open([W0])` with an inner subscriber
- Reset/fixture: `windowCount(3)`, one value forwarded
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: outer none; inner does not `complete` or `error`
- lifecycle: finalize nulls the array only (122–125). Source unsubscribed so no further `next`
- suffix: the inner subscriber is still waiting
- final state: `Stopped` for the outer machine; subject not terminated
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization. Contrast `window.ts` 90–95.

### S05 Overlap and gap

- Test ID: S05
- Covered row IDs: T08, T09
- Starting state: `Open([W0], 0)`
- Reset/fixture: `windowCount(3, 1)` and a separate `windowCount(2, 3)`
- prefix: `subscribe`
- target event: three source values
- expected notifications: `(3, 1)` opens a new window after every value; each value is delivered to windows already open, not to the window opened by that same value; the oldest completes once it has 3 values. `(2, 3)` completes `W0` on the second value and does not open the next window until the third value, so the third value is forwarded to an empty list and is in no window; outer `next(W1)` happens on that third value
- lifecycle: lines 86–108
- suffix: `Open` with whatever windows remain
- final state: `Open`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization, including the TODO at lines 100–103

## F. Coverage and evidence

Denominator = 10 (T01–T10). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S01 | not executed |
| T05 | S02 | not executed |
| T06 | S03 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | S05 | not executed |
| T10 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. The close/open arithmetic is specified for positive `windowSize` and `startEvery`. Empty windows at exact boundaries are real. `cancel` does not terminate inners. Reentrancy excluded. Inner subscribers are not individually modeled.
- Contract vs 7.8.2 characterization: JSDoc 16–23 is close but “emits the current window” on complete/error overstates the complete path: the observable was emitted earlier; complete only terminates it. The TODO at 100–103 is part of the source characterization of when a window is emitted.
- Tests still required: S01–S05, especially exact-multiple complete (empty trailing window) versus `bufferCount` of the same sizes, and unsubscribe while an inner is subscribed.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
