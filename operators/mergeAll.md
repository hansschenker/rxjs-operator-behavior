# mergeAll

`mergeAll` flattens a higher-order source by subscribing to inner `ObservableInput`s as they arrive, up to `concurrent` at a time (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The whole function is `return mergeMap(identity, concurrent)` with `concurrent` defaulting to `Infinity` (`mergeAll.ts:64-66`). It is not a one-line rename of another export; it is a one-expression forwarder onto `mergeMap` with `identity` as the projection (`identity.ts:43-45`). There is no `resultSelector`. Overflow queues inside `mergeInternals`; it is not dropped. Inners are subscribed when accepted, not held until the outer completes (that later behavior belongs to `combineLatestAll` / `zipAll`).

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | mergeAll(concurrent: number = Infinity): OperatorFunction<O, ObservedValueOf<O>>. No resultSelector overload |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | For each source value, treat it as an inner ObservableInput and merge it, with the same concurrency queue as mergeMap. Complete when the source has completed, nothing is buffered, and no inner is active. Inner or outer error fails the output |
| model kind | Extended/symbolic Mealy machine. Same bound story as mergeMap: finite concurrent bounds the subscribed set only |
| parameter domain | concurrent default Infinity. The source payload must be an ObservableInput at the moment it is subscribed, which may be later than arrival if it was queued |
| payload/error domain | Outer payload is ObservableInput<T>. Output payload is T. Errors: outerError, innerError, innerFrom throw on a bad input (the identity 'project' itself does not throw) |
| subscription boundary | Outer subscribed once. Each accepted inner subscribed in doInnerSub. Queued inners are not subscribed. Cap is concurrent |
| scheduler/tie ordering | None. Arrival order is FIFO for the queue. Live inners interleave by notification order |
| callback assumptions | identity is total and synchronous. innerFrom is synchronous and throws on a bad input before subscribe |
| cleanup assumptions | Same as mergeInternals. Docs at mergeAll.ts:16-18 match the code: output completes only after inners complete, and an inner error is emitted immediately |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). No resultSelector. No expand recursion. |

## B. Six-tuple

Forwarding contract: `mergeMap(identity, concurrent)` (`mergeAll.ts:65`). The Mealy machine is the mergeMap machine with project fixed to identity and with the selector rows unused because this overload cannot pass a function in the selector slot. A numeric argument is only concurrency.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) parameterized by concurrent |
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

Same transition grid as mergeMap with identity projection. Selector rows are present in the shared grid but their guard (deprecated resultSelector is a function) is unreachable through mergeAll's signature. Treat them as not enabled.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MA-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-MA-01 |
| MA-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-MA-02 |
| MA-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-MA-03 |
| MA-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-MA-04 |
| MA-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-MA-05 |
| MA-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-MA-06 |
| MA-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-MA-07 |
| MA-08 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-MA-08 |
| MA-09 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-MA-09 |
| MA-10 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-MA-10 |
| MA-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-MA-11 |
| MA-12 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-MA-12 |
| MA-13 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-MA-13 |
| MA-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-MA-14 |
| MA-15 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-MA-15 |
| MA-16 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-MA-16 |
| MA-17 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MA-17 |
| MA-18 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MA-18 |
| MA-19 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-MA-19 |
| MA-20 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-MA-20 |
| MA-21 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-MA-21 |
| MA-22 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-MA-22 |
| MA-23 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-MA-23 |
| MA-24 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-MA-24 |
| MA-25 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-MA-25 |
| MA-26 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-MA-26 |
| MA-27 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-MA-27 |
| MA-28 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MA-28 |
| MA-29 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MA-29 |
| MA-30 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MA-30 |
| MA-31 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-MA-31 |
| MA-32 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-MA-32 |
| MA-33 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-MA-33 |

Unreachable selector rows are retained so the forwarding onto mergeMap stays visible, and marked by the resultSelector guard. mergeAll.ts itself never calls isFunction.

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
| I10 | project is identity, so the queued or subscribed value is the source value unchanged | mergeAll.ts:65; identity.ts:43-45 |
| I11 | Bad inputs error at innerFrom time, which is subscribe time, not enqueue time | innerFrom.ts:41; mergeInternals.ts:71 |
| I12 | Default Infinity does not queue | mergeAll.ts:64; mergeMap.ts:84 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-MA-1 mergeAll: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-1 |
| Title | mergeAll: subscribe, one sync inner, complete |
| Parameters | mergeAll(concurrent) defaults concurrent to Infinity; no resultSelector parameter. project is identity |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of MA |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | mergeAll.ts:64-66 returns mergeMap(identity, concurrent); identity.ts:43-45 |

### E-MA-2 mergeAll: inner ObservableInputs that arrive above the cap are queued, not subscribed and not dropped

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-2 |
| Title | mergeAll: inner ObservableInputs that arrive above the cap are queued, not subscribed and not dropped |
| Parameters | mergeAll(1) |
| Start state | s0 |
| Prefix | subscribe; outerNext(innerA) subscribed and still open |
| Input word | outerNext(innerB), innerNext(idA, a), innerComplete(idA), innerNext(idB, b), innerComplete(idB), outerComplete |
| Transition IDs | MA enqueue row; MA dequeue-on-complete row; inner notification rows |
| Guards | identity does not throw. innerFrom(innerB) runs only when idA completes. If innerB is not a valid ObservableInput, that failure is a projectThrow at dequeue time, not at enqueue time |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | innerB is held as a value in the FIFO. It is not subscribed while idA is active |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract in mergeAll.ts:59-62: concurrent is the max number of inner Observables subscribed at once. Source characterization of the overflow: queue via mergeInternals, same as mergeMap |
| Source characterization | mergeAll.ts:64-66; mergeInternals.ts:52-53 |

### E-MA-3 mergeAll: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-3 |
| Title | mergeAll: outer completes while an inner is still active |
| Parameters | mergeAll(concurrent) defaults concurrent to Infinity |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | MA outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-MA-4 mergeAll: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-4 |
| Title | mergeAll: inner error fails the output and drops the queue |
| Parameters | mergeAll(concurrent) defaults concurrent to Infinity; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | MA innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-MA-5 mergeAll: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-5 |
| Title | mergeAll: cancel is silent |
| Parameters | mergeAll(concurrent) defaults concurrent to Infinity |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | MA cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-MA-6 mergeAll: invalid ObservableInput while a slot is free

| Field | Value |
| --- | --- |
| Scenario ID | E-MA-6 |
| Title | mergeAll: invalid ObservableInput while a slot is free |
| Parameters | mergeAll() default Infinity |
| Start state | active_empty |
| Prefix | subscribe |
| Input word | outerNext(notAnObservableInput) |
| Transition IDs | MA projectThrow row on active_empty |
| Guards | identity returns the value; innerFrom throws createInvalidObservableTypeError inside doInnerSub |
| Notifications (Gamma) | error(e) |
| Lifecycle | no inner stays subscribed |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | source characterization: higher-order identity projection fails at subscribe time of that inner, as a callback/conversion throw, not as outerError |
| Source characterization | mergeAll.ts:65; innerFrom.ts:41; mergeInternals.ts:71 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **33**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/33**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| MA-01 | not executed | static reading only; no runner |
| MA-02 | not executed | static reading only; no runner |
| MA-03 | not executed | static reading only; no runner |
| MA-04 | not executed | static reading only; no runner |
| MA-05 | not executed | static reading only; no runner |
| MA-06 | not executed | static reading only; no runner |
| MA-07 | not executed | static reading only; no runner |
| MA-08 | not executed | static reading only; no runner |
| MA-09 | not executed | static reading only; no runner |
| MA-10 | not executed | static reading only; no runner |
| MA-11 | not executed | static reading only; no runner |
| MA-12 | not executed | static reading only; no runner |
| MA-13 | not executed | static reading only; no runner |
| MA-14 | not executed | static reading only; no runner |
| MA-15 | not executed | static reading only; no runner |
| MA-16 | not executed | static reading only; no runner |
| MA-17 | not executed | static reading only; no runner |
| MA-18 | not executed | static reading only; no runner |
| MA-19 | not executed | static reading only; no runner |
| MA-20 | not executed | static reading only; no runner |
| MA-21 | not executed | static reading only; no runner |
| MA-22 | not executed | static reading only; no runner |
| MA-23 | not executed | static reading only; no runner |
| MA-24 | not executed | static reading only; no runner |
| MA-25 | not executed | static reading only; no runner |
| MA-26 | not executed | static reading only; no runner |
| MA-27 | not executed | static reading only; no runner |
| MA-28 | not executed | static reading only; no runner |
| MA-29 | not executed | static reading only; no runner |
| MA-30 | not executed | static reading only; no runner |
| MA-31 | not executed | static reading only; no runner |
| MA-32 | not executed | static reading only; no runner |
| MA-33 | not executed | static reading only; no runner |

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
| Limits | Same queue and complete-wait as mergeMap. No resultSelector. Identity projection. |

Documented limits:

- Forwarder: `mergeMap(identity, concurrent)`, default `Infinity`.
- Queue, not drop, when a finite cap is set (`mergeAll.ts:43` even documents `mergeAll(2)`).
- Complete-wait for inners and for the queue.
- No `resultSelector` on this signature.
- `mergeAll(0)` / `mergeAll(NaN)` inherits the mergeMap hang. Not the documented contract (`mergeAll.ts:59-60` says a maximum number of inners).
- No tests were executed.

