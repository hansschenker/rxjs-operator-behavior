# windowToggle

`windowToggle(openings, closingSelector)` emits a nested observable when `openings` emits and completes that inner when the per-opening closing observable emits `next` (`windowToggle.ts` 56–131). Nothing is emitted at subscribe. Closing `complete` is `noop`, so the window stays open; `EMPTY` does not close it. Openings `complete` does not complete the outer or the open inners. Source values are forwarded to every open window. Source `complete` completes every open inner and then the outer. Source `error`, openings `error`, and closing `error` error every open inner and the outer (`handleError`, 63–68). `closingSelector` throw is caught locally and uses that same path (84–89). `cancel` unsubscribes remaining subjects (119–128) and does not outer-complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/windowToggle.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `windowToggle<T, O>(openings, closingSelector: (openValue: O) => ObservableInput<any>)` (`windowToggle.ts` 56–59).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 21–25. Windows exist only between an opening and a closing `next`. The example at lines 37–38 passes `EMPTY` for some openings. `EMPTY` completes without `next`, and the complete handler is `noop` (line 93), so those windows are not closed by `EMPTY`. Code wins over the example.
- Model kind: extended, not finite. The list of open subjects is unbounded.
- Parameter domain: `openings` subscribed once (70). `closingSelector(openValue)` once per opening (85).
- Payload/error domain: outer `next` is `Observable<T>`. Inner `next` is `T`. `handleError` applies one `err` to every currently open subject, then the outer (63–67). Subjects already completed by a closing `next` are not in the list.
- Subscription boundary: openings subscriber first (70–97), source second (100–130). The outer `next(window)` happens before the closing subscription (91–93), after the selector try (84–89). Each closer is an `OperatorSubscriber` on the destination, also added to a local `closingSubscription` (93).
- Scheduler and tie ordering: none in this file. Producer same-time order is an assumption, not a proof. Micro-trace required for opening versus source versus closing in one turn. The source path copies `windows` before forwarding (105–109) because of reentrancy; ordinary model still excludes reentrancy.
- Callback assumptions: `closingSelector` throw ≠ source error, but `handleError` makes it an outer error and errors windows already open, including the one just pushed (74–88) if the throw happens after `windows.push`. Looking at order: push (75), then try selector (84–88), then outer `next` (91). A throw happens before outer `next` of that window, but the subject is already in `windows`, so `handleError` will `error` it and any older windows, then outer-`error`. The new window was not emitted to the outer. Closing `next` completes that one window only (77–80). Closing `complete` does not.
- Cleanup assumptions: source-subscriber finalize unsubscribes every remaining subject (119–128). That is `unsubscribe`, not `complete`. Openings `error` uses the default error handler (no fourth argument on the openings subscriber, 70–96), which does not call `handleError`. So an openings `error` outer-errors via the default path and does not walk the window list. Destination teardown still runs the source subscriber’s finalize if that subscriber is unsubscribed as a child, which will unsubscribe remaining subjects. Order: default `destination.error` unsubscribes children, which runs finalize. Inner subjects get `unsubscribe`, not `error`, on the openings-error path. Closing `error` does call `handleError` (93). This split is source characterization.
- Explicit exclusions: reentrancy; treating the `EMPTY` example as normative; a per-inner-subscriber machine.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle([])
```

Inner contract: a subject is emitted, receives source `next`s while it stays in `windows`, then `complete` on its closing `next` or on source complete, or `error` on `handleError`, or `unsubscribe` on cancel / openings-error teardown.

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Collecting(windows)` | list of open `Subject<T>` with closers | Source and openings subscribed. |
| `Stopped` | list empty after terminal handling | — |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | No outer `next` yet. |
| `sourceNext(v)` | yes | source | To every open window (103–109). Dropped if the list is empty. |
| `sourceError(e)` | yes | source | `handleError` (118). |
| `sourceComplete` | yes | source | Complete each window, then outer (111–116). |
| `cancel` | yes | unsubscribe | Finalize unsubscribes windows (119–128). No outer `complete`. |
| `openingsNext(o)` | yes | openings | Create subject, selector, outer `next`, subscribe closer (73–93). |
| `openingsComplete` | yes | openings | `noop` (95). |
| `openingsError(e)` | yes | openings | Default outer `error`. Not `handleError`. Finalize unsubscribes windows. |
| `closingNext` | yes | that closer | `closeWindow` (77–80, 93). |
| `closingComplete` | yes | closer | `noop` (93). Window stays open. |
| `closingError(e)` | yes | closer | `handleError` (93). |
| `selectorThrow(e)` | yes | user callback | `handleError` (86–88). |
| `timerFired` | no | — | Not in this file. |

### Γ

Outer: `none` | `next(Observable)` | `error(e)` | `complete`. Inner effects are on stored subjects. Micro-trace required around `openingsNext` and `handleError`.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | subscribe openings, then source (70, 100) | `Collecting([])` | ε | openings | S01 |
| T02 | `Collecting` | `openingsNext(o)` | selector returns | outer `next(W)` | push `W`, subscribe closer, then emit `W` (74–93) | list plus `W` | T01 | source values enter `W` | S01 |
| T03 | `Collecting` | `sourceNext(v)` | list non-empty | outer `none` | `W.next(v)` for a copy of the list (105–109) | same list | T02 | — | S01 |
| T04 | `Collecting([])` | `sourceNext(v)` | — | `none` | loop over empty copy | unchanged; `v` dropped | T01 | — | S02 |
| T05 | `Collecting` | `closingNext` for `W` | — | outer `none` | remove `W`, `W.complete()`, unsubscribe that closer (77–80) | `W` gone | T03 | other windows stay | S01 |
| T06 | `Collecting` | `closingComplete` | — | `none` | closer ends; `W` stays open | same | T02 | — | S03 |
| T07 | `Collecting` | `openingsComplete` | — | `none` | openings end; windows stay | same | T02 | — | S03 |
| T08 | `Collecting` | `sourceComplete` | — | outer `complete` | each window `complete` oldest-first, then outer (111–116) | `Stopped` | T02 | inners get `complete` | S04 |
| T09 | `Collecting` | `sourceError(e)` or `closingError(e)` or `selectorThrow(e)` | — | outer `error(e)` | `handleError`: each open window `error(e)`, then outer (63–67, 86–88, 93, 118) | `Stopped` | T02 | inners do not `complete` | S05 |
| T10 | `Collecting` | `openingsError(e)` | — | outer `error(e)` | default error, not `handleError` (openings subscriber has no error callback, 70–96). Child teardown runs source finalize, which `unsubscribe`s remaining subjects (124–127) rather than `error`ing them | `Stopped` | T02 | inners not `error`ed by `handleError` | S06 |
| T11 | `Collecting` | `cancel` | — | outer `none` | finalize unsubscribes subjects (124–127); no outer `complete` | `Stopped` | T03 | late subscribe sees a closed subject | S07 |
| T12 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T13 | `Collecting([])` | `sourceComplete` | — | outer `complete` | while-loop emits no inner terminal | `Stopped` | T01 | none | S02 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | No window is emitted until an openings `next`. |
| I02 | The outer `next` for a window happens only after `closingSelector` returns successfully (84–91). |
| I03 | A closing `next` completes that inner only. It does not complete the outer. |
| I04 | A closing `complete` does not complete the inner. `EMPTY` is not a closer. |
| I05 | Openings `complete` does not complete the outer or the inners. |
| I06 | Source `complete` completes each open inner, then the outer. An empty open window is completed with no values. |
| I07 | `handleError` (source error, closing error, selector throw) errors each open inner, then the outer. |
| I08 | Openings `error` is not `handleError`. Inners are unsubscribed during teardown, not errored by the loop at 63–67. |
| I09 | `cancel` unsubscribes open subjects and does not outer-complete. |
| I10 | A source value is delivered to every window open at that step, using a copy of the list (105–109). |

## E. Scenario specification

### S01 Open, forward, close

- Test ID: S01
- Covered row IDs: T01, T02, T03, T05
- Starting state: unsubscribed
- Reset/fixture: one opening; closer emits `next` later
- prefix: `subscribe`, `openingsNext(o)` (outer `next(W)`), `sourceNext(a)`
- target event: `closingNext`
- expected notifications: no further outer `next`. `W` sees `a` then `complete`
- lifecycle: closer unsubscribed; `W` removed
- suffix: `Collecting([])`
- final state: `Collecting([])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`windowToggle.ts` 73–93, 103–109)

### S02 Value with no window; complete with none

- Test ID: S02
- Covered row IDs: T04, T13
- Starting state: `Collecting([])`
- Reset/fixture: no openings
- prefix: `subscribe`, `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: outer `complete` only. `a` was forwarded to no subject
- lifecycle: none
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 EMPTY and openings complete do not close

- Test ID: S03
- Covered row IDs: T06, T07
- Starting state: `Collecting([W])` after an opening
- Reset/fixture: `closingSelector` returns `EMPTY`; openings later complete
- prefix: `openingsNext(o)`
- target event: synchronous `closingComplete` from `EMPTY`, then `openingsComplete`
- expected notifications: outer still only the original `next(W)`. `W` does not complete
- lifecycle: both notifiers ended; source still subscribed
- suffix: later source values still enter `W`
- final state: `Collecting([W])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 93 and 95). The example at 37–38 does not match this if `EMPTY` is expected to close the window.

### S04 Source complete

- Test ID: S04
- Covered row IDs: T08
- Starting state: two open windows, one of which has seen `a`
- Reset/fixture: two openings
- prefix: openings and one source value after both are open
- target event: `sourceComplete`
- expected notifications: each window `complete` (the empty one completes with no values), then outer `complete`
- lifecycle: closers torn down with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (111–116)

### S05 handleError paths

- Test ID: S05
- Covered row IDs: T09
- Starting state: `Collecting([W])` with `a` already forwarded, and a separate run where the selector throws on the next opening
- Reset/fixture: source error, closing error, selector throw
- prefix: one open window
- target event: `sourceError(e)` or `closingError(e)` or `openingsNext` whose selector throws
- expected notifications: `W.error(e)` and outer `error(e)`. On selector throw, the new subject is errored too if it was pushed, and it is not outer-nexted (throw is before line 91)
- lifecycle: `handleError` 63–67
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Openings error does not use handleError

- Test ID: S06
- Covered row IDs: T10
- Starting state: `Collecting([W])`
- Reset/fixture: openings error with `e`
- prefix: window already emitted and subscribed
- target event: `openingsError(e)`
- expected notifications: outer `error(e)`. `W` is unsubscribed in finalize, not sent `error(e)` by the while-loop
- lifecycle: openings subscriber has no `onError` (70–96); source finalize 124–127 runs because destination unsubscribe tears down children
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S07 Cancel

- Test ID: S07
- Covered row IDs: T11
- Starting state: `Collecting([W])`
- Reset/fixture: inner subscriber attached
- prefix: opening and a source value
- target event: `cancel`
- expected notifications: outer none; `W` does not `complete`
- lifecycle: finalize unsubscribes `W` (124–127)
- suffix: late use of `W` sees a closed subject
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 13 (T01–T13). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S01 | not executed |
| T06 | S03 | not executed |
| T07 | S03 | not executed |
| T08 | S04 | not executed |
| T09 | S05 | not executed |
| T10 | S06 | not executed |
| T11 | S07 | not executed |
| T12 | none | not executed |
| T13 | S02 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. The openings-error versus `handleError` split is subtle and should be re-read against `Subscriber` child teardown order if a test disagrees; the claim is that openings has no custom error handler (line 95 is `noop` for complete, and `onError` is omitted) while finalize lives on the source subscriber. Reentrancy excluded. `EMPTY` example is not honored by the code.
- Contract vs 7.8.2 characterization: JSDoc 21–25 matches closing `next`. It does not say closing `complete` is ignored. The example at 32–39 is not a reliable oracle.
- Tests still required: S01–S07, especially `EMPTY` as a closer, openings error versus closing error, and selector throw.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
