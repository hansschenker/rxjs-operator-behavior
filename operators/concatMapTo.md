# concatMapTo

`concatMapTo` maps every source value to the same inner `ObservableInput` and concatenates those subscriptions (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). It is a short wrapper, not a const alias. `concatMapTo.ts:78` returns `concatMap(() => innerObservable, resultSelector)` when the second argument is a function, otherwise `concatMap(() => innerObservable)`. `concatMap` then calls `mergeMap` with concurrent `1`. The note at `concatMapTo.ts:38-39` states the same fact via `mergeMapTo`. The operator is deprecated for removal in v9 (`concatMapTo.ts:5` and `72`). `resultSelector` is deprecated for removal in v8 (`concatMapTo.ts:7` and `12`). Busy policy is queue, not drop: the warning at `concatMapTo.ts:33-36` is the unbounded FIFO.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | Deprecated concatMapTo(observable). Deprecated selector overloads with resultSelector: undefined or a function. Operator removal v9. Selector removal v8. No concurrent argument |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Subscribe to innerObservable once per source value, strictly sequentially, by queueing source values while a subscription is open |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. Unbounded queue of outer values |
| parameter domain | innerObservable: ObservableInput. Optional deprecated resultSelector. concurrent is implicitly 1 and cannot be raised through this API |
| payload/error domain | Same as concatMap, with project fixed to the constant function. Source values are not output by themselves |
| subscription boundary | At most one live subscription to innerObservable. The next subscription starts only after innerComplete of the previous one, including after the outer has completed (drain) |
| scheduler/tie ordering | None. Serial order is the queue order, which is source order |
| callback assumptions | The constant project does not throw. A bad innerObservable throws from innerFrom on every accept, including the first. Selector may throw per inner value |
| cleanup assumptions | Complete-wait for the active subscription and for every queued resubscription. Error and cancel drop the rest |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |

## B. Six-tuple

Two hops: concatMapTo normalizes arguments, concatMap fixes concurrent to 1, mergeInternals owns buffer/active/index/isComplete. No hop adds a drop policy.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = concatMap with a constant project |
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

Busy location is at-capacity by construction. Queued items are outer values; each dequeue calls () => innerObservable.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CMT-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent = 1 (fixed); no inner | T-CMT-01 |
| CMT-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-CMT-02 |
| CMT-03 | active_empty | outerNext(v) / source | active = 0 (the only below-cap state) and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_inner_at_cap | subscribe | one inner live; source value itself is not a Gamma next | T-CMT-03 |
| CMT-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-CMT-04 |
| CMT-05 | active_inner_at_cap | outerNext(v) / source | active = 1 = concurrent. There is no below-cap running location: the second source value cannot open a second inner | eps | buffer.push(v); project not called; index not consumed yet | active_inner_at_cap | subscribe, outerNext(v0) that opened the sole inner | v queued. Unbounded FIFO. This is concat's at-capacity state, not a drop | T-CMT-05 |
| CMT-06 | unreachable below-cap-with-inner | outerNext(v) / source | concurrent is fixed at 1, so active>0 already means at capacity. Row recorded to show the mergeMap 'subscribe another inner' transition is not enabled | eps | none | not a location of this machine | n/a | excluded by concurrent = 1 | T-CMT-06 |
| CMT-07 | active_inner_at_cap | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-CMT-07 |
| CMT-08 | active_inner_at_cap | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-CMT-08 |
| CMT-09 | active_inner_at_cap | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-CMT-09 |
| CMT-10 | active_inner_at_cap | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-CMT-10 |
| CMT-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-CMT-11 |
| CMT-12 | active_inner_at_cap | innerComplete(id) / inner id | buffer empty; outer still open | eps | active:=0 | active_empty | sole inner completes | next source value will subscribe immediately | T-CMT-12 |
| CMT-13 | active_inner_at_cap | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds | eps from the complete itself | active--; shift one; subscribe exactly one next inner (concurrent 1). Nested sync completion can chain further dequeues before the outer while-condition resumes | active_inner_at_cap | at least one queued source value | exactly one inner live after a non-completing dequeue; buffer shorter by the number of sync-drained items | T-CMT-13 |
| CMT-14 | active_inner_at_cap | innerComplete(id) / inner id | dequeued project throws | error(e) projectThrow | finalizer catch; stop drain | terminal_error | bad queued projection | terminal | T-CMT-14 |
| CMT-15 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-CMT-15 |
| CMT-16 | active_inner_at_cap | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-CMT-16 |
| CMT-17 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-CMT-17 |
| CMT-18 | active_inner_at_cap | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-CMT-18 |
| CMT-19 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-CMT-19 |
| CMT-20 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-CMT-20 |
| CMT-21 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-CMT-21 |
| CMT-22 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-CMT-22 |
| CMT-23 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-CMT-23 |
| CMT-24 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CMT-24 |
| CMT-25 | active_inner_at_cap | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CMT-25 |
| CMT-26 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-CMT-26 |
| CMT-27 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-CMT-27 |
| CMT-28 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-CMT-28 |

Deprecations: operator v9, resultSelector v8. Both are forwarding facts, not extra states.

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
| I10 | active is 0 or 1 | concatMap.ts:82 via concatMapTo.ts:78 |
| I11 | Each dequeued outer value starts a fresh subscribe of the same input | concatMapTo.ts:78; innerFrom |
| I12 | The queue is unbounded | concatMapTo.ts:33-36 |
| I13 | resultSelector is optional and deprecated; omitting it still concatenates | concatMapTo.ts:76-78 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-CMT-1 concatMapTo: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-1 |
| Title | concatMapTo: subscribe, one sync inner, complete |
| Parameters | concatMap of a constant projection, therefore concurrent 1; optional deprecated resultSelector |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of CMT |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | concatMapTo.ts:78 forwards to concatMap(() => innerObservable) or concatMap(() => innerObservable, resultSelector) |

### E-CMT-2 concatMapTo: ignored values are not dropped; they wait, then each one resubscribes the same input

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-2 |
| Title | concatMapTo: ignored values are not dropped; they wait, then each one resubscribes the same input |
| Parameters | concatMapTo(innerObservable) |
| Start state | s0 |
| Prefix | subscribe; outerNext(v1) has subscribed innerObservable |
| Input word | outerNext(v2), innerComplete of the first subscription, innerNext of the second subscription, innerComplete, outerComplete |
| Transition IDs | CMT enqueue row; CMT dequeue row; inner rows; draining or empty complete |
| Guards | v2 is buffered. Projection still ignores the value and returns innerObservable, but only when v2 is dequeued |
| Notifications (Gamma) | nexts from the second subscription only; then complete if the source has completed |
| Lifecycle | two sequential subscriptions to the same ObservableInput. No overlap |
| Suffix | terminal_complete if the source completed in the word; otherwise active_empty |
| End state | terminal_complete |
| Oracle | contract note at concatMapTo.ts:38-39: equivalent to mergeMapTo with concurrency 1, which is a queue. Operator deprecated for v9 (concatMapTo.ts:5 and 72). Selector deprecated for v8 (concatMapTo.ts:7 and 12) |
| Source characterization | concatMapTo.ts:74-79; concatMap.ts:82; mergeInternals.ts:52 |

### E-CMT-3 concatMapTo: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-3 |
| Title | concatMapTo: outer completes while an inner is still active |
| Parameters | concatMap of a constant projection, therefore concurrent 1 |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | CMT outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-CMT-4 concatMapTo: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-4 |
| Title | concatMapTo: inner error fails the output and drops the queue |
| Parameters | concatMap of a constant projection, therefore concurrent 1; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | CMT innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-CMT-5 concatMapTo: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-5 |
| Title | concatMapTo: cancel is silent |
| Parameters | concatMap of a constant projection, therefore concurrent 1 |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | CMT cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-CMT-6 concatMapTo: resultSelector throw

| Field | Value |
| --- | --- |
| Scenario ID | E-CMT-6 |
| Title | concatMapTo: resultSelector throw |
| Parameters | concatMapTo(innerObservable, resultSelector) |
| Start state | the single subscription is live |
| Prefix | selector overload; one accepted outer value |
| Input word | innerNext causing the selector to throw |
| Transition IDs | CMT resultSelectorThrow row |
| Guards | isFunction at concatMapTo.ts:78 selects the selector forward |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe the one inner and the outer; drop any queued outer values |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | deprecated selector; throw is not innerError |
| Source characterization | concatMapTo.ts:7-16 and 78 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **28**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/28**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| CMT-01 | not executed | static reading only; no runner |
| CMT-02 | not executed | static reading only; no runner |
| CMT-03 | not executed | static reading only; no runner |
| CMT-04 | not executed | static reading only; no runner |
| CMT-05 | not executed | static reading only; no runner |
| CMT-06 | not executed | static reading only; no runner |
| CMT-07 | not executed | static reading only; no runner |
| CMT-08 | not executed | static reading only; no runner |
| CMT-09 | not executed | static reading only; no runner |
| CMT-10 | not executed | static reading only; no runner |
| CMT-11 | not executed | static reading only; no runner |
| CMT-12 | not executed | static reading only; no runner |
| CMT-13 | not executed | static reading only; no runner |
| CMT-14 | not executed | static reading only; no runner |
| CMT-15 | not executed | static reading only; no runner |
| CMT-16 | not executed | static reading only; no runner |
| CMT-17 | not executed | static reading only; no runner |
| CMT-18 | not executed | static reading only; no runner |
| CMT-19 | not executed | static reading only; no runner |
| CMT-20 | not executed | static reading only; no runner |
| CMT-21 | not executed | static reading only; no runner |
| CMT-22 | not executed | static reading only; no runner |
| CMT-23 | not executed | static reading only; no runner |
| CMT-24 | not executed | static reading only; no runner |
| CMT-25 | not executed | static reading only; no runner |
| CMT-26 | not executed | static reading only; no runner |
| CMT-27 | not executed | static reading only; no runner |
| CMT-28 | not executed | static reading only; no runner |

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
| Limits | Forwards concatMap concurrent 1. Queues. Complete-wait. Operator deprecated v9. resultSelector deprecated v8. |

Documented limits:

- Wrapper onto `concatMap(() => innerObservable)`, hence `mergeMap` with concurrent 1.
- Queue versus drop: queues. Documented memory warning.
- Complete-wait: yes.
- `resultSelector` deprecated (v8). Operator deprecated (v9).
- Active-set bound: 1. Queue unbounded.
- No tests were executed.

