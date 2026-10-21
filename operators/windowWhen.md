# windowWhen

`windowWhen(closingSelector)` emits non-overlapping nested observables (`windowWhen.ts` 54–124). The first window is opened during subscribe. The closing observable is subscribed with both `next` and `complete` mapped to `openWindow` (line 99), so either signal completes the current inner, emits a new one, and calls `closingSelector` again. That differs from `bufferWhen`, whose closing `complete` is `noop`. Source `complete` completes the current inner and the outer. Source `error` and closing `error` error the current inner and the outer. A `closingSelector` throw does the same after the new window has already been emitted (87–92). `cancel` unsubscribes the closer and drops the `window` reference (116–121) but does not complete or unsubscribe the subject. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/windowWhen.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `windowWhen<T>(closingSelector: () => ObservableInput<any>): OperatorFunction<T, Observable<T>>` (`windowWhen.ts` 54).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 19–23 and the `@param` note at lines 47–49: the notifier signals on `next` or `complete`. The code matches that note (`openWindow` is both the next and the complete handler, line 99). `bufferWhen` does not.
- Model kind: extended/timed, not finite. One current subject and one closing subscription.
- Parameter domain: nullary `closingSelector`, called on every open including the first (102–103, 89).
- Payload/error domain: outer `next` is `Observable<T>`. Inner `next` is `T`. `handleError` does `window.error(err)` then `subscriber.error(err)` (63–66).
- Subscription boundary: `openWindow()` before `source.subscribe` (103–106). Closing subscriber is parented to the destination. `openWindow` unsubscribes the previous closer before completing the old window (77–80).
- Scheduler and tie ordering: no scheduler in this file. A synchronous closing `next` or `complete` recurses into `openWindow` on the subscribe stack. `EMPTY` completes synchronously, which calls `openWindow` again, which subscribes to `EMPTY` again: unbounded synchronous recursion. That is excluded from the ordinary model. Micro-trace required for one closing signal that completes the old window and emits the new one. Same-virtual-time order for timed closers is an assumption, not a proof.
- Callback assumptions: selector throw is caught inside `openWindow` (87–92), not only by `operate`. Order: previous closer unsubscribed, old window `complete`d if any, new subject created, outer `next` of the new window, then selector. On throw, `handleError` errors the new window and the outer. The old window was already completed. Initial throw: there is no old window (`window` starts unset), the new window was already outer-nexted, then both error.
- Cleanup assumptions: finalize unsubscribes `closingSubscriber` and nulls `window` (116–121). It does not `complete` or `unsubscribe` the subject. `cancel` does not outer-complete. Contrast `window.ts` 90–95 and `windowToggle.ts` 124–127.
- Explicit exclusions: synchronous notifiers that complete or `next` forever (`EMPTY`, `of(0)`); reentrancy from the consumer; per-inner-subscriber model.

Inner contract: the current `Subject` receives source `next`s until `complete` (closing signal or source complete), `error` (`handleError`), or it is simply abandoned on `cancel` (left open).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open(W0) after the initial openWindow succeeds
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(W)` | current subject and closing subscriber | Source values go to `W`. |
| `Stopped` | `window` nulled or terminal error/complete delivered | — |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | `openWindow` then source subscribe (103–106). |
| `sourceNext(v)` | yes | source | `window.next(v)` (109). |
| `sourceError(e)` | yes | source | `handleError` (115). |
| `sourceComplete` | yes | source | `W.complete()` then outer `complete` (110–113). |
| `cancel` | yes | unsubscribe | Finalize 116–121. No outer `complete`. Subject not completed. |
| `closingNext` | yes | closer | `openWindow` (99). |
| `closingComplete` | yes | closer | also `openWindow` (99). Not a no-op. |
| `closingError(e)` | yes | closer | `handleError` (99). |
| `selectorThrow(e)` | yes | user callback | After the new window is emitted (84–92). |
| `timerFired` | no | — | Only if the user’s closer is timed. |

### Γ

Outer: `next(Observable)` | `none` | `error(e)` | `complete`. Closing `next` and closing `complete` both produce an inner `complete` plus an outer `next` of a new observable. Micro-trace required for that pair.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | selector returns an input that does not synchronously reopen forever | outer `next(W0)` | create `W0`, emit it, subscribe closer (74–99, 103) | `Open(W0)` | ε | source subscribe follows (106) | S01 |
| T02 | `Open(W)` | `sourceNext(v)` | — | outer `none` | `W.next(v)` (109) | `Open(W)` | T01 | — | S01 |
| T03 | `Open(W)` | `closingNext` | new selector returns | outer `next(W')` | unsubscribe closer; `W.complete()`; emit `W'` (77–84); subscribe new closer | `Open(W')` | T02 | `W` gets no further values | S01 |
| T04 | `Open(W)` | `closingComplete` | new selector returns | outer `next(W')` | same `openWindow` as T03 (line 99 second callback) | `Open(W')` | T01 | not the `bufferWhen` noop | S02 |
| T05 | `Open(W)` | `sourceComplete` | — | outer `complete` | `W.complete()` then outer `complete` (111–113). No new window | `Stopped` | T01 or T02 | inner may be empty | S03 |
| T06 | `Open(W)` | `sourceError(e)` or `closingError(e)` | — | outer `error(e)` | `W.error(e)` then outer `error` (63–66, 115, 99) | `Stopped` | T02 | `W` does not `complete` | S04 |
| T07 | during `openWindow` | `selectorThrow(e)` | new `W'` already outer-nexted; old `W` already completed if it existed | outer `next(W')` already sent, then outer `error(e)` and `W'.error(e)` | lines 80–92 | `Stopped` | T03 or T01 | old window is complete, not errored | S05 |
| T08 | `Open(W)` | `cancel` | — | outer `none` | closer unsubscribed; `window` ref nulled (116–121); `W` not completed or unsubscribed; no outer `complete` | `Stopped` | T02 | inner subscriber still waiting | S06 |
| T09 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T10 | `Open` | closing signal is sync `EMPTY` | complete handler is `openWindow` | — | unbounded recursion; excluded | — | T01 | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | The first outer `next` happens during subscribe, before the source is subscribed (103–106). |
| I02 | Both closing `next` and closing `complete` close the current inner and open a new one (line 99). |
| I03 | A closing signal completes the old inner; it does not error it. |
| I04 | Source `complete` completes the current inner and the outer, and does not open another window. |
| I05 | Source `error` and closing `error` error the current inner and the outer. |
| I06 | Selector throw emits the new window first, completes the old one if any, then errors the new window and the outer (80–92). |
| I07 | `cancel` does not complete the current inner and does not complete the outer. It does unsubscribe the closer. |
| I08 | This is not `bufferWhen`: closing `complete` is a boundary here and is ignored there (`bufferWhen.ts` 69). |
| I09 | A closing observable that completes synchronously without a later asynchronous boundary (`EMPTY`) recurses without bound (T10). That is outside the ordinary model. |

## E. Scenario specification

### S01 Closing next rotates the window

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: first closer emits one `next` and does not complete synchronously in a loop
- prefix: `subscribe` (outer `next(W0)`), `sourceNext(a)`
- target event: `closingNext`
- expected notifications: `W0` sees `a` then `complete`; outer `next(W1)`
- lifecycle: first closer unsubscribed inside `openWindow` before `W0.complete`
- suffix: `Open(W1)`
- final state: `Open(W1)`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`windowWhen.ts` 74–99, 109)

### S02 Closing complete also rotates

- Test ID: S02
- Covered row IDs: T04
- Starting state: `Open(W0)`
- Reset/fixture: closer completes without `next`, and the next selector returns a notifier that stays open (so recursion stops)
- prefix: `subscribe`, `sourceNext(a)`
- target event: `closingComplete`
- expected notifications: `W0` `complete` after `a`; outer `next(W1)`; output stays open
- lifecycle: complete handler is `openWindow`, not `noop` (line 99)
- suffix: `Open(W1)`
- final state: `Open(W1)`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization and contract (JSDoc 47–49). Contrast `bufferWhen.ts` 69.

### S03 Source complete

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Open(W0)`, possibly with no values
- Reset/fixture: closer still open
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `W0.complete()` and outer `complete`. No `W1`
- lifecycle: closer unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (110–113)

### S04 Errors

- Test ID: S04
- Covered row IDs: T06
- Starting state: `Open(W0)` after `sourceNext(a)`
- Reset/fixture: separate source-error and closing-error runs
- prefix: `sourceNext(a)`
- target event: `sourceError(e)` or `closingError(e)`
- expected notifications: `W0.error(e)`, outer `error(e)`. Not `complete`
- lifecycle: `handleError` 63–66
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Selector throw after the new window is emitted

- Test ID: S05
- Covered row IDs: T07
- Starting state: `Open(W0)` with value `a`, and a second run at initial subscribe
- Reset/fixture: the selector call that opens the next window throws `e`; initial run throws on the first call
- prefix: `sourceNext(a)` and a closing signal, or just `subscribe`
- target event: `openWindow`’s `closingSelector()`
- expected notifications: outer `next(W')` (and `W0.complete()` if `W0` existed), then `W'.error(e)` and outer `error(e)`
- lifecycle: lines 77–92. Initial call has no old window to complete
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Cancel leaves the subject open

- Test ID: S06
- Covered row IDs: T08
- Starting state: `Open(W0)` with an inner subscriber
- Reset/fixture: closer live
- prefix: `subscribe`, `sourceNext(a)`
- target event: `cancel`
- expected notifications: outer none; `W0` does not `complete`
- lifecycle: closer unsubscribed (119); `window` reference nulled; subject not unsubscribed
- suffix: inner subscriber still attached and not completed
- final state: outer `Stopped`; subject not terminated
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (116–121). Contrast `windowToggle.ts` 124–127.

## F. Coverage and evidence

Denominator = 10 (T01–T10). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S05 | not executed |
| T08 | S06 | not executed |
| T09 | none | not executed |
| T10 | none (excluded) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Synchronous `EMPTY` / `of(0)` closers recurse without a termination metric; they are excluded rather than given a cycle in `δ`. `cancel` does not terminate the inner subject. Tie order for timed closers is assumed. Reentrancy excluded.
- Contract vs 7.8.2 characterization: JSDoc 47–49 matches “next or complete.” The informal text at 21–22 says “emits an item,” which understates complete. The implementation uses both. Do not copy `bufferWhen`’s complete row here.
- Tests still required: S01–S06, including a closer that only completes, source error versus source complete, selector throw on the second window, and unsubscribe with an active inner subscriber.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
