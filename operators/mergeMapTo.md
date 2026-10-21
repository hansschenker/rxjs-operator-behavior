# mergeMapTo

`mergeMapTo` is a deprecated thin wrapper, not a one-line alias (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `mergeMapTo.ts:62-74`). Both the overload banner (`mergeMapTo.ts:5`) and the implementation JSDoc (`mergeMapTo.ts:60`) say it will be removed in v9 and should be replaced by `mergeMap(() => result)`. The `resultSelector` overload is additionally deprecated for removal in v8 (`mergeMapTo.ts:11-12`). Forwarding: if the second argument is a function, `mergeMap(() => innerObservable, resultSelector, concurrent)`; if it is a number, that number is concurrent; otherwise `mergeMap(() => innerObservable, concurrent)` with concurrent default `Infinity` (`mergeMapTo.ts:65-73`). Concurrency, queueing, complete-wait, and error policy are exactly `mergeMap`'s. The projection ignores the source value and always returns the same `ObservableInput`.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | Deprecated mergeMapTo(innerObservable, concurrent?). Deprecated resultSelector overload mergeMapTo(innerObservable, resultSelector, concurrent?). Removal of the operator: v9. Removal of resultSelector: v8 |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | For every accepted source value, subscribe again to the same inner ObservableInput and merge those subscriptions under concurrent, queueing source values past the cap |
| model kind | Extended/symbolic Mealy machine. Same bounds as mergeMap. The constant projection does not by itself bound anything |
| parameter domain | innerObservable: ObservableInput. concurrent default Infinity. resultSelector optional function, deprecated. Numeric second argument is concurrent (mergeMapTo.ts:70-72) |
| payload/error domain | Source values are not emitted unless the inner emits them. Output is ObservedValueOf of innerObservable, or selector results. Errors as mergeMap, plus selector throws |
| subscription boundary | Each accepted (dequeued or immediate) source value opens one subscription to innerObservable via innerFrom. Overlapping subscriptions up to concurrent. Queued source values do not yet subscribe |
| scheduler/tie ordering | None. Resubscription order is source order because the FIFO preserves it and index is assigned at subscribe time |
| callback assumptions | The constant arrow function does not throw. resultSelector, if supplied, is synchronous and may throw. innerFrom may throw if innerObservable is not a valid input, and that happens on each accept |
| cleanup assumptions | Same complete-wait and fail-fast as mergeMap / mergeInternals |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). The wrapper does not add state of its own. |

## B. Six-tuple

There is no separate state machine in `mergeMapTo.ts`. After argument normalization the operator is `mergeMap` with project `() => innerObservable`. The six-tuple is that machine. Outer values are still the things that get queued, because `mergeInternals` buffers the source value and calls project only in `doInnerSub`.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) of mergeMap with a constant project |
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
| active_empty | subscribed; active=0; buffer=[]; isComplete=false | no inner. Next accepted value is subscribed immediately |
| active_running | active>0 and (concurrent is Infinity or active<concurrent); buffer empty | Room remains for another inner. With the default Infinity this is every busy state |
| at_capacity | concurrent is finite and active>=concurrent; buffer FIFO may be empty or not | Further values wait. Unreachable while concurrent is Infinity |
| draining | isComplete=true; active>0 or buffer nonempty | Outer-completed, inners and/or queue remain. Output not yet completed |
| terminal_complete / terminal_error / terminal_cancelled | Subscriber stopped | No further Gamma |

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

Transitions match mergeMap. The project guard is 'return the closed-over innerObservable and innerFrom it'. Source values are queue elements, not output payloads.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MMT-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-MMT-01 |
| MMT-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-MMT-02 |
| MMT-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-MMT-03 |
| MMT-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-MMT-04 |
| MMT-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-MMT-05 |
| MMT-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-MMT-06 |
| MMT-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-MMT-07 |
| MMT-08 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-MMT-08 |
| MMT-09 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-MMT-09 |
| MMT-10 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-MMT-10 |
| MMT-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-MMT-11 |
| MMT-12 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-MMT-12 |
| MMT-13 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-MMT-13 |
| MMT-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-MMT-14 |
| MMT-15 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-MMT-15 |
| MMT-16 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-MMT-16 |
| MMT-17 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MMT-17 |
| MMT-18 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MMT-18 |
| MMT-19 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-MMT-19 |
| MMT-20 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-MMT-20 |
| MMT-21 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-MMT-21 |
| MMT-22 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-MMT-22 |
| MMT-23 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-MMT-23 |
| MMT-24 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-MMT-24 |
| MMT-25 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-MMT-25 |
| MMT-26 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-MMT-26 |
| MMT-27 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-MMT-27 |
| MMT-28 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MMT-28 |
| MMT-29 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MMT-29 |
| MMT-30 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MMT-30 |
| MMT-31 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-MMT-31 |
| MMT-32 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-MMT-32 |
| MMT-33 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-MMT-33 |

Deprecation is part of the forwarding contract, not an extra state. Both call shapes end in mergeMap.ts:81-94.

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
| I10 | Every doInnerSub projects to the same ObservableInput reference | mergeMapTo.ts:68 and 73 |
| I11 | Queue entries are outer values; the shared input is subscribed only when a slot is taken | mergeInternals.ts:52 versus 71 |
| I12 | Default concurrent is Infinity, so the default does not queue | mergeMapTo.ts:65 |
| I13 | resultSelector deprecation is real JSDoc, and the operator deprecation (v9) is a second, wider deprecation | mergeMapTo.ts:5, 11, 60 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-MMT-1 mergeMapTo: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-1 |
| Title | mergeMapTo: subscribe, one sync inner, complete |
| Parameters | concurrent default Infinity; constant projection () => innerObservable. resultSelector optional and deprecated |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of MMT |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | mergeMapTo.ts:73 returns mergeMap(() => innerObservable, concurrent) |

### E-MMT-2 mergeMapTo: outer values above the cap are queued, then each dequeued value resubscribes the same inner ObservableInput

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-2 |
| Title | mergeMapTo: outer values above the cap are queued, then each dequeued value resubscribes the same inner ObservableInput |
| Parameters | mergeMapTo(innerObservable, 1) |
| Start state | s0 |
| Prefix | subscribe; outerNext(v1) subscribed to innerObservable as id1 |
| Input word | outerNext(v2), innerComplete(id1), innerNext(id2, b), innerComplete(id2), outerComplete |
| Transition IDs | MMT enqueue; MMT dequeue; inner rows; empty complete |
| Guards | The FIFO stores v2, not a subscription. On dequeue the projection ignores v2 and returns the same innerObservable reference |
| Notifications (Gamma) | next(b), complete. v1 and v2 themselves are not output unless the shared inner emits them |
| Lifecycle | serial resubscribe of innerObservable. Cold inputs restart; a hot Subject does not replay |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract: same as mergeMap with a constant projection. Queue when over cap. The operator is deprecated for removal in v9 (mergeMapTo.ts:5 and 60) |
| Source characterization | mergeMapTo.ts:62-74; mergeInternals.ts:52 and 113-122 |

### E-MMT-3 mergeMapTo: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-3 |
| Title | mergeMapTo: outer completes while an inner is still active |
| Parameters | concurrent default Infinity |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | MMT outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-MMT-4 mergeMapTo: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-4 |
| Title | mergeMapTo: inner error fails the output and drops the queue |
| Parameters | concurrent default Infinity; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | MMT innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-MMT-5 mergeMapTo: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-5 |
| Title | mergeMapTo: cancel is silent |
| Parameters | concurrent default Infinity |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | MMT cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-MMT-6 mergeMapTo: resultSelector throw on an inner value

| Field | Value |
| --- | --- |
| Scenario ID | E-MMT-6 |
| Title | mergeMapTo: resultSelector throw on an inner value |
| Parameters | mergeMapTo(innerObservable, resultSelector, concurrent) function selector |
| Start state | inner live via the deprecated path |
| Prefix | subscribe; outerNext accepted |
| Input word | innerNext whose mapped selector throws |
| Transition IDs | MMT resultSelectorThrow row |
| Guards | isFunction(resultSelector) at mergeMapTo.ts:67 forwards to mergeMap(() => innerObservable, resultSelector, concurrent) |
| Notifications (Gamma) | error(e) |
| Lifecycle | all inners unsubscribed |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | JSDoc: resultSelector removed in v8 (mergeMapTo.ts:11-12). Operator itself removed in v9 |
| Source characterization | mergeMapTo.ts:11-18 and 67-68 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **33**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/33**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| MMT-01 | not executed | static reading only; no runner |
| MMT-02 | not executed | static reading only; no runner |
| MMT-03 | not executed | static reading only; no runner |
| MMT-04 | not executed | static reading only; no runner |
| MMT-05 | not executed | static reading only; no runner |
| MMT-06 | not executed | static reading only; no runner |
| MMT-07 | not executed | static reading only; no runner |
| MMT-08 | not executed | static reading only; no runner |
| MMT-09 | not executed | static reading only; no runner |
| MMT-10 | not executed | static reading only; no runner |
| MMT-11 | not executed | static reading only; no runner |
| MMT-12 | not executed | static reading only; no runner |
| MMT-13 | not executed | static reading only; no runner |
| MMT-14 | not executed | static reading only; no runner |
| MMT-15 | not executed | static reading only; no runner |
| MMT-16 | not executed | static reading only; no runner |
| MMT-17 | not executed | static reading only; no runner |
| MMT-18 | not executed | static reading only; no runner |
| MMT-19 | not executed | static reading only; no runner |
| MMT-20 | not executed | static reading only; no runner |
| MMT-21 | not executed | static reading only; no runner |
| MMT-22 | not executed | static reading only; no runner |
| MMT-23 | not executed | static reading only; no runner |
| MMT-24 | not executed | static reading only; no runner |
| MMT-25 | not executed | static reading only; no runner |
| MMT-26 | not executed | static reading only; no runner |
| MMT-27 | not executed | static reading only; no runner |
| MMT-28 | not executed | static reading only; no runner |
| MMT-29 | not executed | static reading only; no runner |
| MMT-30 | not executed | static reading only; no runner |
| MMT-31 | not executed | static reading only; no runner |
| MMT-32 | not executed | static reading only; no runner |
| MMT-33 | not executed | static reading only; no runner |

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
| Limits | Forwards mergeMap queue and complete-wait. Operator deprecated v9. resultSelector deprecated v8. Constant projection. |

Documented limits:

- Not an alias constant. It is a wrapper that forwards to `mergeMap`.
- Queue versus drop: queues, like `mergeMap`.
- Complete-wait: waits for inners and the FIFO.
- `resultSelector` deprecated (v8). The operator itself is deprecated (v9).
- Same non-positive `concurrent` hang as `mergeMap`.
- Resubscribing one cold Observable restarts it; a hot input does not replay. That is `innerFrom` of the same reference, not extra policy in this file.
- No tests were executed.

