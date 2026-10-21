# flatMap

`flatMap.ts` is a one-line alias: `export const flatMap = mergeMap` (`flatMap.ts:6`), RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791. The JSDoc above it says it was renamed to `mergeMap` and will be removed in v8 (`flatMap.ts:3-5`). Because the export is the same function, every `mergeMap` overload is forwarded, including the default `concurrent = Infinity`, the numeric-concurrent argument, the FIFO queue at a finite cap, complete-wait, fail-fast on inner error, and the deprecated `resultSelector` overloads declared on `mergeMap.ts:13-24`. This document is the forwarding contract, not a second algorithm.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | const flatMap = mergeMap. Overloads are mergeMap's: (project, concurrent?), and deprecated (project, resultSelector, concurrent?). Alias removal targeted at v8 (flatMap.ts:3-5). resultSelector removal targeted at v8 on the target function |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Identical to mergeMap. No behavior is added or removed by this module |
| model kind | Same extended/symbolic Mealy machine as mergeMap |
| parameter domain | Same as mergeMap. Default concurrent Infinity. Function second argument means deprecated resultSelector |
| payload/error domain | Same as mergeMap |
| subscription boundary | Same as mergeMap / mergeInternals |
| scheduler/tie ordering | None, same as mergeMap |
| callback assumptions | Same as mergeMap |
| cleanup assumptions | Same as mergeMap |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). This file contains no independent control flow to exclude. |

## B. Six-tuple

Identity of functions means `delta` and `lambda` are mergeMap's. The alias does not wrap, so it does not add a subscriber, a queue, or a deprecation check of its own. The deprecation is documentary.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = the mergeMap machine |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C, identical in structure to mergeMap |
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

Rows are the mergeMap grid under the id prefix FM. Reading flatMap.ts alone shows only the alias; the guards cite mergeMap.ts and mergeInternals.ts because that is the callee.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FM-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-FM-01 |
| FM-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-FM-02 |
| FM-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-FM-03 |
| FM-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-FM-04 |
| FM-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-FM-05 |
| FM-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-FM-06 |
| FM-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-FM-07 |
| FM-08 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-FM-08 |
| FM-09 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-FM-09 |
| FM-10 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-FM-10 |
| FM-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-FM-11 |
| FM-12 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-FM-12 |
| FM-13 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-FM-13 |
| FM-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-FM-14 |
| FM-15 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-FM-15 |
| FM-16 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-FM-16 |
| FM-17 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-FM-17 |
| FM-18 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-FM-18 |
| FM-19 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-FM-19 |
| FM-20 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-FM-20 |
| FM-21 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-FM-21 |
| FM-22 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-FM-22 |
| FM-23 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-FM-23 |
| FM-24 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-FM-24 |
| FM-25 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-FM-25 |
| FM-26 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-FM-26 |
| FM-27 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-FM-27 |
| FM-28 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-FM-28 |
| FM-29 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-FM-29 |
| FM-30 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-FM-30 |
| FM-31 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-FM-31 |
| FM-32 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-FM-32 |
| FM-33 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-FM-33 |

One-line alias. No extra transition exists for the rename.

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
| I10 | flatMap and mergeMap are the same function object, so they cannot diverge | flatMap.ts:6 |
| I11 | Default concurrent Infinity and queue-on-finite-cap are inherited unchanged | mergeMap.ts:84 and 89-93 |
| I12 | resultSelector remains in the forwarded signature and remains deprecated | mergeMap.ts:13-24 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-FM-1 flatMap: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-1 |
| Title | flatMap: subscribe, one sync inner, complete |
| Parameters | identical to mergeMap, default concurrent Infinity; identical deprecated resultSelector overloads, because the export is the same function object |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of FM |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | flatMap.ts:6 exports the mergeMap function. Behavior is mergeMap.ts:81-94 |

### E-FM-2 flatMap: same queue-at-capacity contract as mergeMap

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-2 |
| Title | flatMap: same queue-at-capacity contract as mergeMap |
| Parameters | flatMap(project, 1) |
| Start state | s0 |
| Prefix | subscribe; one inner live |
| Input word | outerNext(v2) while that inner is live; innerComplete; then the queued projection's innerNext |
| Transition IDs | FM enqueue row and FM dequeue row |
| Guards | concurrent 1. Second value is buffered |
| Notifications (Gamma) | no next for the queued outer value itself; next of whatever its inner later emits |
| Lifecycle | FIFO of length 1; then a single subscribe |
| Suffix | the dequeued inner is the only active inner |
| End state | active_running if concurrent were higher; with 1, at_capacity while that inner lives |
| Oracle | source characterization: flatMap does not have a separate implementation. Queue versus drop is mergeMap's queue |
| Source characterization | flatMap.ts:3-6; mergeMap.ts:84-93; mergeInternals.ts:52 |

### E-FM-3 flatMap: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-3 |
| Title | flatMap: outer completes while an inner is still active |
| Parameters | identical to mergeMap, default concurrent Infinity |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | FM outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-FM-4 flatMap: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-4 |
| Title | flatMap: inner error fails the output and drops the queue |
| Parameters | identical to mergeMap, default concurrent Infinity; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | FM innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-FM-5 flatMap: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-5 |
| Title | flatMap: cancel is silent |
| Parameters | identical to mergeMap, default concurrent Infinity |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | FM cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-FM-6 flatMap: project throw

| Field | Value |
| --- | --- |
| Scenario ID | E-FM-6 |
| Title | flatMap: project throw |
| Parameters | any concurrent; project throws |
| Start state | active_empty |
| Prefix | subscribe |
| Input word | outerNext(v) |
| Transition IDs | FM projectThrow row |
| Guards | same catch as mergeMap |
| Notifications (Gamma) | error(e) |
| Lifecycle | teardown; no inner |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | source characterization via the aliased function. The deprecation on flatMap.ts:3-5 is the rename, removed in v8. The resultSelector deprecation is inherited from mergeMap.ts:13-24 |
| Source characterization | flatMap.ts:6; mergeMap.ts:86-93; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **33**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/33**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| FM-01 | not executed | static reading only; no runner |
| FM-02 | not executed | static reading only; no runner |
| FM-03 | not executed | static reading only; no runner |
| FM-04 | not executed | static reading only; no runner |
| FM-05 | not executed | static reading only; no runner |
| FM-06 | not executed | static reading only; no runner |
| FM-07 | not executed | static reading only; no runner |
| FM-08 | not executed | static reading only; no runner |
| FM-09 | not executed | static reading only; no runner |
| FM-10 | not executed | static reading only; no runner |
| FM-11 | not executed | static reading only; no runner |
| FM-12 | not executed | static reading only; no runner |
| FM-13 | not executed | static reading only; no runner |
| FM-14 | not executed | static reading only; no runner |
| FM-15 | not executed | static reading only; no runner |
| FM-16 | not executed | static reading only; no runner |
| FM-17 | not executed | static reading only; no runner |
| FM-18 | not executed | static reading only; no runner |
| FM-19 | not executed | static reading only; no runner |
| FM-20 | not executed | static reading only; no runner |
| FM-21 | not executed | static reading only; no runner |
| FM-22 | not executed | static reading only; no runner |
| FM-23 | not executed | static reading only; no runner |
| FM-24 | not executed | static reading only; no runner |
| FM-25 | not executed | static reading only; no runner |
| FM-26 | not executed | static reading only; no runner |
| FM-27 | not executed | static reading only; no runner |
| FM-28 | not executed | static reading only; no runner |
| FM-29 | not executed | static reading only; no runner |
| FM-30 | not executed | static reading only; no runner |
| FM-31 | not executed | static reading only; no runner |
| FM-32 | not executed | static reading only; no runner |
| FM-33 | not executed | static reading only; no runner |

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
| Limits | Alias of mergeMap. Same queue, same complete-wait, same deprecated resultSelector. Alias itself deprecated for v8. |

Documented limits:

- One-line alias of `mergeMap`. The callee was read; the contract is not reimplemented here.
- Queue versus drop: queues when `concurrent` is finite; default `Infinity` does not queue.
- Complete-wait: yes, including the FIFO.
- `resultSelector`: still accepted, JSDoc-deprecated on `mergeMap`.
- Alias deprecation: removed in v8 (`flatMap.ts:4`).
- No tests were executed.

