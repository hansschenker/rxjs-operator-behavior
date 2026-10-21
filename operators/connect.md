# connect

`connect(selector, config?)` (`operators/connect.ts` 99–109) uses `config.connector` or the default `() => new Subject()` (`connect.ts` 22–24). On each subscription to the operator result, `operate` runs:

1. `subject = connector()` (line 105). A new subject per **outer** subscription, unless the caller’s factory returns a shared instance (as `multicast` / `publishReplay` do).
2. `innerFrom(selector(fromSubscribable(subject))).subscribe(subscriber)` (line 106). `fromSubscribable` (`observable/fromSubscribable.ts` 15–17) is an observable whose subscribe is `subject.subscribe`. The selector therefore sees a multicast observable that is not yet connected to the source.
3. `subscriber.add(source.subscribe(subject))` (line 107). The source is subscribed only after the selector’s observable has been subscribed. That source subscription is a child of the downstream subscriber.

The machine is not a hot share across outer subscribers. Two subscribers to `source.pipe(connect(selector))` run steps 1–3 twice. Sharing happens only among the subscriptions that **one** selector invocation makes to `shared`. JSDoc (`connect.ts` 30–47, 92–96) states the order and the synchronous-source reason: `share` would refCount 0→1→0 on a fully synchronous source before a second consumer could join, whereas `connect` lets the selector attach every consumer before `subSource`.

Lifetime follows the selector’s returned observable because that subscription’s destination is the downstream subscriber, and the source subscription was added to the same subscriber. Selector-result complete or error completes or errors the downstream and unsubscribes the source. Downstream `unsubscribe` does the same. Unsubscribing one inner `shared` subscriber does not unsubscribe the source; the source subscription is not parented to those inner subscribers.

Default `Subject` does not replay. A `connector` that returns a `ReplaySubject` replays according to that subject; this file does not construct one.

`multicast(subjectFactory, selector)` and `publish(selector)` are callers of this function. Their extra “same subject” factory is their specification, not a second path here.

## A. Identity, contract, and scope

| Field | Domain | Initial per outer subscribe | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| selecting \| connected \| completed \| errored \| cancelled` | `idle` | One execution per outer subscriber. |
| `subject` | `SubjectLike` | `connector()` | The multicast bus for this execution. |
| `sourceSub` | subscription or none | none until step 3 | Child of the downstream subscriber. |
| `selectorSub` | subscription | step 2 | Forwards to the downstream subscriber. |
| `innerObservers` | subject observers | whoever the selector subscribed | — |

There is no `refCount` field. Inner unsubscribes only leave the subject.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. A second outer `subscribe` is a second machine, not a transition of the first, unless `connector` returns an aliased subject. Aliasing is a limit; the rows assume a fresh subject.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Operator not subscribed. |
| `selecting` | Selector has been called and its result subscribed. Source not yet subscribed. This location is only visible if the selector result’s subscribe returns before step 3; synchronous selector subscriptions to `shared` happen here. |
| `connected` | Source is subscribed to `subject`. |
| `completed` | Selector result completed. Source unsubscribed. |
| `errored` | Selector result or source errored. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Runs the selector, then connects. |
| 2 | Downstream cancel | `unsubscribe` | Drops `sourceSub` and the selector subscription. |
| 3 | Source next | `sourceNext(v)` | `subject.next(v)` after `connected`. |
| 4 | Source error | `sourceError(e)` | `subject.error(e)`, which errors selector-side observers. |
| 5 | Source complete | `sourceComplete` | `subject.complete()`. |
| 6 | Shared subscribe | `sharedSubscribe` | Selector (or something it built) subscribes to `fromSubscribable(subject)`. |
| 7 | Selector terminal | `selectorNext(v)`, `selectorError(e)`, `selectorComplete` | The observable **returned** by the selector, not the source. |
| 8 | Connector | `connector()` | Once per outer subscribe. No scheduler in this file. |

### Γ

`ε`, `newSubject`, `subShared` (a join to the subject), `subSource`, `unsubSource`, `outNext(v)` (from the selector result, not automatically from the source), `outError(e)`, `outComplete`.

Source notifications are not downstream notifications unless the selector’s observable forwards them. `subject.next` delivers to inner observers only.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | selector runs and subscribes to `shared` any number of times without terminating | `selecting` then `connected` | `newSubject`; each `sharedSubscribe` is `subShared`; then subscribe selector result to the downstream subscriber; then `subSource` (`connect.ts` 105–107). If this is synchronous, `selecting` does not rest. |
| T02 | waiting | `selecting` | `sharedSubscribe` | source not connected yet | `selecting` | `subShared`. No source side effect yet. |
| T03 | init | `selecting` | end of selector subscribe | step 3 | `connected` | `subSource` |
| T04 | emitting | `connected` | `sourceNext(v)` | — | `connected` | `subject.next(v)` to current inner observers. Downstream `outNext` only if an inner path is the selector result’s emission. |
| T05 | per-source error | `connected` | `sourceError(e)` | subject forwards `e` into selector-side subscribers | `errored` if that errors the selector result; else `connected` | Inner observers receive `error(e)`. If the selector result errors, `outError(e)` and `unsubSource` because the downstream subscriber unsubscribes its children (line 107). |
| T06 | per-source complete | `connected` | `sourceComplete` | subject completes inner observers | `completed` if the selector result completes; else `connected` | Same coupling as T05 with `outComplete`. A selector that ignores shared-complete (it already completed, or it merged with something still open) stays `connected` until its own result terminates. The source subscription is already complete, so it is idle, but it remains a child until the downstream unsubscribes. |
| T07 | emitting | `connected` | `selectorNext(v)` | — | `connected` | `outNext(v)` |
| T08 | terminal | `connected` or `selecting` | `selectorComplete` | — | `completed` | `outComplete`, `unsubSource` if `subSource` already happened |
| T09 | per-source error | `connected` or `selecting` | `selectorError(e)` | — | `errored` | `outError(e)`, `unsubSource` if connected |
| T10 | cancel | `selecting` or `connected` | `unsubscribe` | — | `cancelled` | `unsubSource` if connected; selector subscription torn down. No `outComplete`. |
| T11 | cancel | `connected` | one inner `shared` subscriber unsubscribes | other inners remain; selector result still open | `connected` | `ε` downstream. `sourceSub` stays. |
| T12 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |
| T13 | init | `idle` | `subscribe` | selector throws synchronously | `errored` | `outError(e)` via `operate`’s try/catch (`util/lift.ts` 22–27). No `subSource`. |
| T14 | init | `idle` | second outer `subscribe` | fresh `connector()` | a new machine at T01 | The first machine is unchanged. Two source subscriptions. |

T01’s order is the contract: every synchronous `sharedSubscribe` inside the selector’s subscribe happens before T03. A fully synchronous source then fans out to all of those inners inside T03’s `subSource` (the JSDoc `of(1..5)` example, `connect.ts` 52–90).

## D. Contract invariants

1. For one outer subscription there is one `connector()` call and at most one `source.subscribe(subject)` (lines 105 and 107).
2. That `subSource` is ordered after the selector result has been subscribed, so synchronous source values are visible to every inner subscription the selector made synchronously (JSDoc lines 30–36, 45–47).
3. Downstream notifications are exactly the selector result’s notifications (T07–T09), not the raw source, unless the selector returns `shared` itself.
4. The source subscription’s lifetime is the downstream subscriber’s lifetime, which ends when the selector result terminates or the caller unsubscribes (T08–T10).
5. Inner `unsubscribe` does not disconnect the source (T11).
6. A second outer subscriber does not join the first subject when the default connector is used (T14).
7. There is no refCount reset policy and no replay in the default connector. Complete and error behave as `Subject`: late `sharedSubscribe` after the subject stopped gets `syncComplete` or `syncError` (`Subject.ts` 136–144) and misses values.
8. `publish(selector)` is this operator with the default connector. `multicast(factory, selector)` is this operator with that factory (`operators/multicast.ts` 88–94).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Three views of a sync source

The JSDoc pattern (`connect.ts` 63–71): selector returns `merge` of three pipes on `shared` (all, even, odd) over `of(1,2,3,4,5)`. T01/T02 attach three observers before T03. One `subSource`. Each source value is delivered to all three inners, and `merge` forwards the mapped results as `outNext`. The log shape in the JSDoc (one “subscription started”, then per value the source log and the derived logs) is this single `subSource`. A second subscriber to the connect result is T14: a second source subscription and a second subject.

### E2. Selector returns `shared` directly

`connect(shared => shared)`. T03 `subSource`. Each `sourceNext(v)` is observed by the one inner, which is the selector result, so T04 plus T07 `outNext(v)`. `sourceComplete` completes the subject, which completes the selector result: T06/T08 `outComplete` and the source child is released. This is a one-subscriber multicast with extra machinery, not a share across two outer subscribers.

### E3. Selector completes early

`connect(shared => shared.pipe(take(1)))`. Source emits `1` then `2`. `outNext(1)` (T07). `take(1)` completes the selector result (T08) `outComplete` and `unsubSource`. `2` is not subscribed anymore. No second value.

### E4. Source errors through the selector

Selector returns `shared`. `sourceError(e)` is `subject.error(e)`, the selector subscription errors, T05/T09 `outError(e)`, `unsubSource`. No `outComplete`.

### E5. Cancel does not complete

Source is connected and has emitted `1` (`outNext(1)`). Downstream `unsubscribe` is T10. No `outComplete`. The source is unsubscribed. A later resubscribe is a new machine (T14), not a continuation of the old subject.

### E6. One inner drops, source stays

Selector merges two subscriptions to `shared` and only completes when both inner views complete. One inner unsubscribes early (T11). The source stays connected. The other inner still receives `sourceNext`. Downstream has not seen `outComplete`.

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
- synchronous multi-source emissions in listed order: one source; synchronous multi-subscribe to `shared` inside the selector is in-model (T02 before T03)
- limits: A `connector` that returns the same subject to two outer machines aliases buffers and can `subSource` twice; that alias is specified for the callers in `publishReplay.md` and `multicast.md`, not as the default here. Selector-result behavior of arbitrary pipes (`merge`, `take`) is not expanded. `SubjectLike` implementations other than `Subject` contribute their own subscribe-time replay and are not re-derived in this file.
