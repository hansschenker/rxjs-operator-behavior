# concatMap

`concatMap` projects each source value to an inner and flattens those inners one at a time (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The body is a forwarder: `isFunction(resultSelector) ? mergeMap(project, resultSelector, 1) : mergeMap(project, 1)` (`concatMap.ts:82`). The file itself says this is `mergeMap` with concurrency 1 (`concatMap.ts:41-42`). `resultSelector` is still in the type overloads and is deprecated for removal in v8 (`concatMap.ts:9` and `14`); the implementation JSDoc also mentions it (`concatMap.ts:74-75`). There is no separate concurrent parameter. While the single inner is active, later source values are appended to `mergeInternals`' unbounded FIFO. They are not dropped. The warning at `concatMap.ts:36-39` is that warning: a fast source and slow inners grow that buffer without a cap.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | concatMap(project). Deprecated: concatMap(project, undefined) and concatMap(project, resultSelector). No numeric concurrent parameter. Selector removal: v8 |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Serialize inners. Subscribe to the next projected inner only after the previous inner completes. Preserve source order via an unbounded queue. Forward inner values or selector results. Complete after the source, the queue, and the last inner are done |
| model kind | Extended/symbolic Mealy machine. The active set is bounded by 1. The queue is not bounded, so S is not finite |
| parameter domain | project: (T, index) => ObservableInput. Optional deprecated resultSelector: (outer, inner, outerIndex, innerIndex) => R. concurrent is not a user parameter; it is the constant 1 |
| payload/error domain | Output is ObservedValueOf or selector result. Errors: outerError, innerError, projectThrow, resultSelectorThrow |
| subscription boundary | One outer subscription. At most one inner subscription. Further source values stay as buffered values until that inner completes |
| scheduler/tie ordering | None. Order is strict source order. No interleaving of two inners' subscriptions. A synchronous inner runs to its next events before the following source value is processed, and if it completes synchronously the next buffered or following value can start in the same turn |
| callback assumptions | project runs at subscribe time of that inner, which for queued values is dequeue time. Selector runs on each inner next of the rewritten map |
| cleanup assumptions | Outer complete while the inner or the buffer remains does not complete the output (concat still waits). Outer error or inner error unsubscribes and drops the buffer. Cancel is silent |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). A second simultaneous inner is excluded by concurrent 1, not by an extra guard in concatMap.ts. |

## B. Six-tuple

The machine is mergeMap's machine specialized to concurrent = 1. Locations `active_running` (below cap with an inner) are unreachable: as soon as one inner exists, the next source value queues. The occupied location is named `active_inner_at_cap` so the required at-capacity case is explicit. `index` is still assigned when the inner is actually subscribed, which matches source order because the queue is FIFO.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with concurrent fixed at 1 |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C |
| lambda | Section C |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| active_empty | subscribed; active=0; buffer=[]; isComplete=false | no inner |
| active_inner_at_cap | active=1; FIFO buffer; isComplete=false | Running and at-capacity coincide; concurrent is 1 |
| draining | isComplete; work remains | outer-completed draining |
| terminal_complete / terminal_error / terminal_cancelled | stopped | no further Gamma |

### Sigma (eight categories)

Every input is one of the eight categories below. A project-function throw, a `resultSelector` throw, or an accumulator throw is not an extra input symbol. It is a user-callback outcome of the input that invoked the callback (`outerNext`, or `innerNext` when expand feeds a value back into projection, or `innerNext` when a selector runs). Those outcomes are distinct from `outerError` and `innerError`.

| # | Category | Symbol | Origin |
| --- | --- | --- | --- |
| 1 | subscribe | subscribe | Consumer subscribes to the operator output |
| 2 | outerNext | outerNext(v) | Upstream source next |
| 3 | outerError | outerError(e) | Upstream source error |
| 4 | outerComplete | outerComplete | Upstream source complete |
| 5 | innerNext | innerNext(id, v) | Notification from an inner subscription this operator opened |
| 6 | innerError | innerError(id, e) | Error from an inner subscription this operator opened |
| 7 | innerComplete | innerComplete(id) | Complete from an inner subscription this operator opened |
| 8 | cancel | cancel | Consumer unsubscribes; not a source notification |

### Gamma record

A Gamma record is one downstream notification, or the step emits the empty sequence `eps`.

- `next(v)`: a value delivered through `subscriber.next`.
- `error(e)`: a terminal error. No `complete` follows.
- `complete`: a terminal complete. Emitted only by `checkComplete` when the outer source has completed, the FIFO is empty, and `active` is 0 (`mergeInternals.ts:43-49`).
- Lifecycle actions (subscribe, unsubscribe, enqueue, drop) are not Gamma. They are the Lifecycle column.

`error` and `complete` are mutually exclusive. `cancel` emits `eps` and moves to `terminal_cancelled`.

## C. Transition obligations

At-capacity is the steady busy state. The row that would subscribe a second inner while one is active is recorded as unreachable. Draining still subscribes queued projections after outer complete, one at a time.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CM-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent = 1 (fixed); no inner | T-CM-01 |
| CM-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-CM-02 |
| CM-03 | active_empty | outerNext(v) / source | active = 0 (the only below-cap state) and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_inner_at_cap | subscribe | one inner live; source value itself is not a Gamma next | T-CM-03 |
| CM-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-CM-04 |
| CM-05 | active_inner_at_cap | outerNext(v) / source | active = 1 = concurrent. There is no below-cap running location: the second source value cannot open a second inner | eps | buffer.push(v); project not called; index not consumed yet | active_inner_at_cap | subscribe, outerNext(v0) that opened the sole inner | v queued. Unbounded FIFO. This is concat's at-capacity state, not a drop | T-CM-05 |
| CM-06 | unreachable below-cap-with-inner | outerNext(v) / source | concurrent is fixed at 1, so active>0 already means at capacity. Row recorded to show the mergeMap 'subscribe another inner' transition is not enabled | eps | none | not a location of this machine | n/a | excluded by concurrent = 1 | T-CM-06 |
| CM-07 | active_inner_at_cap | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-CM-07 |
| CM-08 | active_inner_at_cap | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-CM-08 |
| CM-09 | active_inner_at_cap | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-CM-09 |
| CM-10 | active_inner_at_cap | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-CM-10 |
| CM-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-CM-11 |
| CM-12 | active_inner_at_cap | innerComplete(id) / inner id | buffer empty; outer still open | eps | active:=0 | active_empty | sole inner completes | next source value will subscribe immediately | T-CM-12 |
| CM-13 | active_inner_at_cap | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds | eps from the complete itself | active--; shift one; subscribe exactly one next inner (concurrent 1). Nested sync completion can chain further dequeues before the outer while-condition resumes | active_inner_at_cap | at least one queued source value | exactly one inner live after a non-completing dequeue; buffer shorter by the number of sync-drained items | T-CM-13 |
| CM-14 | active_inner_at_cap | innerComplete(id) / inner id | dequeued project throws | error(e) projectThrow | finalizer catch; stop drain | terminal_error | bad queued projection | terminal | T-CM-14 |
| CM-15 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-CM-15 |
| CM-16 | active_inner_at_cap | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-CM-16 |
| CM-17 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-CM-17 |
| CM-18 | active_inner_at_cap | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-CM-18 |
| CM-19 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-CM-19 |
| CM-20 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-CM-20 |
| CM-21 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-CM-21 |
| CM-22 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-CM-22 |
| CM-23 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-CM-23 |
| CM-24 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CM-24 |
| CM-25 | active_inner_at_cap | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CM-25 |
| CM-26 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CM-26 |
| CM-27 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-CM-27 |
| CM-28 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-CM-28 |

concatMap.ts does not mention a buffer; the buffer is mergeInternals.ts:32. The memory warning at concatMap.ts:36-39 is the observable consequence.

## D. Contract invariants

| ID | Invariant | Source |
| --- | --- | --- |
| I1 | No Gamma is emitted from s0 before subscribe | operator runs inside subscribe / operate |
| I2 | active counts inner subscriptions that have entered doInnerSub and not yet finished the success finalizer. A project throw increments active and then errors, so the count is not observed in a stable state | mergeInternals.ts:63 and 107-108 |
| I3 | A value is projected and its index is consumed only in doInnerSub, which runs immediately when active < concurrent and otherwise only on a later FIFO dequeue | mergeInternals.ts:52-53 and 113-122 |
| I4 | The buffer is a FIFO (push / shift). Queued values are source values (and, when expand is on, not-yet-emitted recursive values), never already-open subscriptions | mergeInternals.ts:32 and 114 |
| I5 | Inner error and outer error both end in terminal_error, unsubscribe every inner, and do not emit complete. There is no inner catch | mergeInternals.ts:94; OperatorSubscriber default _error; Subscriber.ts:116-121 |
| I6 | outerComplete does not by itself complete the output when active > 0 or the buffer is nonempty. The source subscription is released; inners continue | mergeInternals.ts:137-141 and 43-49 |
| I7 | cancel unsubscribes outer and all inners, discards the buffer, and emits neither complete nor error | Subscriber.unsubscribe does not call complete; Observable.ts docs on unsubscribe |
| I8 | After a terminal location, further inputs produce eps | Subscriber.isStopped |
| I9 | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). | task exclusion plus innerFrom sync subscribe behavior |
| I10 | active is 0 or 1 | mergeMap called with concurrent 1 at concatMap.ts:82 |
| I11 | buffer length may grow without bound while the single inner has not completed | concatMap.ts:36-39; mergeInternals.ts:53 |
| I12 | Subscriptions of inners do not overlap | concurrent 1 and active++ before the next outerNext can be processed on the same turn only if the previous inner already completed |
| I13 | resultSelector does not raise concurrency. The call still passes 1 | concatMap.ts:82 |
| I14 | Complete-wait includes the queue: a completed source with a nonempty buffer stays in draining | mergeInternals.ts:47 and 137-141 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-CM-1 concatMap: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-1 |
| Title | concatMap: subscribe, one sync inner, complete |
| Parameters | concurrent fixed at 1 via mergeMap(project, 1) or mergeMap(project, resultSelector, 1); resultSelector optional, deprecated, removed in v8 |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of CM |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | concatMap.ts:82 returns mergeMap(project, 1). Note at concatMap.ts:41-42 |

### E-CM-2 concatMap: the second source value is queued, not merged and not dropped

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-2 |
| Title | concatMap: the second source value is queued, not merged and not dropped |
| Parameters | concatMap(project) with no selector |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1), inner id1 still open |
| Input word | outerNext(v2), outerNext(v3), innerComplete(id1), innerNext(id2, b), innerComplete(id2) |
| Transition IDs | CM enqueue rows (twice), CM dequeue row, CM innerNext, CM innerComplete-to-empty or another dequeue |
| Guards | active is 1, so every new source value hits the buffer. project(v2) runs only after id1 completes, and project(v3) only after id2 completes if id2 did not itself complete synchronously |
| Notifications (Gamma) | next(b) when id2 emits. v2 and v3 are not emitted as themselves |
| Lifecycle | buffer grows without a bound while id1 is open. Memory warning in concatMap.ts:36-39 is this FIFO |
| Suffix | if id2 is still open and v3 remains buffered: active_inner_at_cap with buffer=[v3] |
| End state | active_inner_at_cap |
| Oracle | contract: concatMap is mergeMap with concurrency 1 (concatMap.ts:41-42). Queue, unbounded. Not exhaust (no drop) and not switch (no unsubscribe of id1) |
| Source characterization | concatMap.ts:36-42 and 78-83; mergeInternals.ts:32 and 52 |

### E-CM-3 concatMap: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-3 |
| Title | concatMap: outer completes while an inner is still active |
| Parameters | concurrent fixed at 1 via mergeMap(project, 1) or mergeMap(project, resultSelector, 1) |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | CM outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-CM-4 concatMap: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-4 |
| Title | concatMap: inner error fails the output and drops the queue |
| Parameters | concurrent fixed at 1 via mergeMap(project, 1) or mergeMap(project, resultSelector, 1); a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | CM innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-CM-5 concatMap: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-5 |
| Title | concatMap: cancel is silent |
| Parameters | concurrent fixed at 1 via mergeMap(project, 1) or mergeMap(project, resultSelector, 1) |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | CM cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-CM-6 concatMap: resultSelector throw

| Field | Value |
| --- | --- |
| Scenario ID | E-CM-6 |
| Title | concatMap: resultSelector throw |
| Parameters | concatMap(project, resultSelector) |
| Start state | the sole inner is live |
| Prefix | deprecated overload subscribed; one outer value accepted |
| Input word | innerNext that makes the selector throw |
| Transition IDs | CM resultSelectorThrow row |
| Guards | isFunction(resultSelector) ? mergeMap(project, resultSelector, 1) : mergeMap(project, 1) at concatMap.ts:82 |
| Notifications (Gamma) | error(e) |
| Lifecycle | the one inner and the outer are unsubscribed; the FIFO is discarded |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | JSDoc deprecation at concatMap.ts:9 and 14. Throw is resultSelectorThrow, not innerError |
| Source characterization | concatMap.ts:9-18 and 82; mergeMap.ts:86-88 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **28**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/28**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| CM-01 | not executed | static reading only; no runner |
| CM-02 | not executed | static reading only; no runner |
| CM-03 | not executed | static reading only; no runner |
| CM-04 | not executed | static reading only; no runner |
| CM-05 | not executed | static reading only; no runner |
| CM-06 | not executed | static reading only; no runner |
| CM-07 | not executed | static reading only; no runner |
| CM-08 | not executed | static reading only; no runner |
| CM-09 | not executed | static reading only; no runner |
| CM-10 | not executed | static reading only; no runner |
| CM-11 | not executed | static reading only; no runner |
| CM-12 | not executed | static reading only; no runner |
| CM-13 | not executed | static reading only; no runner |
| CM-14 | not executed | static reading only; no runner |
| CM-15 | not executed | static reading only; no runner |
| CM-16 | not executed | static reading only; no runner |
| CM-17 | not executed | static reading only; no runner |
| CM-18 | not executed | static reading only; no runner |
| CM-19 | not executed | static reading only; no runner |
| CM-20 | not executed | static reading only; no runner |
| CM-21 | not executed | static reading only; no runner |
| CM-22 | not executed | static reading only; no runner |
| CM-23 | not executed | static reading only; no runner |
| CM-24 | not executed | static reading only; no runner |
| CM-25 | not executed | static reading only; no runner |
| CM-26 | not executed | static reading only; no runner |
| CM-27 | not executed | static reading only; no runner |
| CM-28 | not executed | static reading only; no runner |

## G. Review decision

| Field | Value |
| --- | --- |
| Decision | accept with documented limits |
| Reviewer | source-derived analysis (Grok) |
| Date | 2026-10-21 |
| Version | 7.8.2 |
| Commit | e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| Mutations | none |
| Tests | not executed |
| Limits | Active set bound 1. Unbounded FIFO (queue, not drop). Complete-wait. resultSelector deprecated. |

Documented limits:

- Forwarder onto `mergeMap` with the concurrent argument `1`, optionally with the deprecated `resultSelector`.
- Queue versus drop: queues. The file warns that the queue is unbounded.
- Complete-wait: yes.
- `resultSelector` is in the signature and JSDoc-deprecated (v8).
- Active-set bound: 1. That bound does not make the Mealy machine finite.
- No tests were executed.

