# mergeMap

`mergeMap` projects each source value to an `ObservableInput` and merges those inners, subscribing to at most `concurrent` of them at once (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The implementation (`mergeMap.ts:81-94`) is a thin policy front on `mergeInternals`. The default concurrency is `Infinity` (`mergeMap.ts:84`), so the default machine never queues. A numeric second argument is concurrency, not a selector (`mergeMap.ts:89-91`). A function second argument is the deprecated `resultSelector` (`mergeMap.ts:13-24` and `86-88`): it is still in the signature, the JSDoc marks it deprecated for removal in v8, and the runtime rewrites the projection as `project` followed by `map(resultSelector)`. `concatMap` is this operator with `concurrent` 1. This file's machine is the general one.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | mergeMap(project, concurrent?): OperatorFunction. Deprecated: mergeMap(project, undefined, concurrent?) and mergeMap(project, resultSelector, concurrent?). resultSelector JSDoc: removed in v8, use an inner map (mergeMap.ts:13-24) |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Flatten projected inners concurrently. When the active set is at the cap, buffer source values in order and subscribe later. Forward inner values, optionally through the deprecated selector. Complete only after the source, the buffer, and every inner are done. Any inner or outer error fails the output |
| model kind | Extended/symbolic Mealy machine. Finite concurrent bounds the subscribed set by that integer; Infinity does not. The queue is unbounded either way once a finite cap is in force, and always the value domain is unbounded |
| parameter domain | project: (value: T, index: number) => ObservableInput. concurrent: number, default Infinity. If the second argument is a function it is resultSelector and the third is concurrent (default Infinity). If the second argument is a number it replaces concurrent. No runtime clamp |
| payload/error domain | Output values are ObservedValueOf of the projected input, or the resultSelector result. Errors: outerError, innerError, projectThrow, innerFrom throw, resultSelectorThrow |
| subscription boundary | One outer subscription per downstream subscribe (mergeInternals.ts:136). Inner subscriptions start in doInnerSub only. At most `concurrent` inners when concurrent is a positive finite number and no scheduler is involved (mergeMap passes no scheduler) |
| scheduler/tie ordering | None. Tie break is call-stack order. Two live inners do not run their next handlers reentrantly on one turn unless one next synchronously causes the other, which would be downstream or source reentry. Sync emissions from the inner just subscribed are ordered immediately after that outerNext |
| callback assumptions | project and resultSelector are synchronous. Selector path calls the original project once per subscribed (not merely queued) outer value, from the wrapper at mergeMap.ts:88 |
| cleanup assumptions | Inherited from mergeInternals: wait for inners after outer complete; error unsubscribes all; cancel unsubscribes all with no complete. Selector path adds a map subscriber per inner, torn down with that inner |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |

## B. Six-tuple

`mergeMap` without a selector is exactly one `mergeInternals` run with the user project, the resolved concurrent, and the expand flag left undefined/false (`mergeMap.ts:93`). With a selector, the public function returns another `mergeMap` whose project is `(a, i) => map(b => resultSelector(a, b, i, ii))(innerFrom(project(a, i)))` and whose concurrent is the third argument (`mergeMap.ts:86-88`). The state variables `buffer`, `active`, `index`, and `isComplete` live in the helper (`mergeInternals.ts:32-38`).

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) parameterized by project, concurrent, and optional resultSelector |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C |
| lambda | Section C. Selector rows apply only on the deprecated overload |
| s0 | init, not subscribed |

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

The table is the helper machine with expand off, onBeforeNext absent, and no scheduler, plus the deprecated selector outcomes on innerNext. At-capacity rows are real only for a finite concurrent; under the default Infinity their guard is false.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MM-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-MM-01 |
| MM-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-MM-02 |
| MM-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-MM-03 |
| MM-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-MM-04 |
| MM-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-MM-05 |
| MM-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-MM-06 |
| MM-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; resultSelector absent (or this instantiation has no selector) | next(x) | forward; innerIndex would increment only on the deprecated selector path | same control location | inner id subscribed | id still live; other inners unaffected | T-MM-07 |
| MM-08 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | deprecated resultSelector is a function and returns r. mergeMap implements this by mapping inside the projected observable, so the selector runs as that inner map's project | next(r) | no change to active set | same control location | deprecated overload subscribe, then inner id | selector result delivered; raw x is not delivered | T-MM-08 |
| MM-09 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow). Distinct from innerError | error(e) | unsubscribe outer and every inner; discard buffer | terminal_error | deprecated selector installed | terminal; no complete | T-MM-09 |
| MM-10 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-MM-10 |
| MM-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-MM-11 |
| MM-12 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-MM-12 |
| MM-13 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-MM-13 |
| MM-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-MM-14 |
| MM-15 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-MM-15 |
| MM-16 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-MM-16 |
| MM-17 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MM-17 |
| MM-18 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MM-18 |
| MM-19 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-MM-19 |
| MM-20 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-MM-20 |
| MM-21 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-MM-21 |
| MM-22 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-MM-22 |
| MM-23 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-MM-23 |
| MM-24 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-MM-24 |
| MM-25 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-MM-25 |
| MM-26 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-MM-26 |
| MM-27 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-MM-27 |
| MM-28 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MM-28 |
| MM-29 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MM-29 |
| MM-30 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-MM-30 |
| MM-31 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-MM-31 |
| MM-32 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-MM-32 |
| MM-33 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-MM-33 |

Default `concurrent = Infinity` (`mergeMap.ts:84`). `active < Infinity` is true for every finite active count, so `buffer` stays empty on that default. Passing `0` or `NaN` is not normalized here (contrast `expand.ts:78`). That is a limit, not the documented happy path.

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
| I10 | Under concurrent Infinity the buffer length stays 0 | mergeInternals.ts:52 with concurrent Infinity |
| I11 | A finite concurrent bounds the number of simultaneously subscribed inners by that number on the sync path. It does not bound the buffer | lines 52-53 and 32 |
| I12 | resultSelector, when present, does not change concurrency or queue policy. It only changes the Gamma payload of innerNext | mergeMap.ts:86-88 |
| I13 | Queued values do not increment index and do not run project until dequeue, so a selector also does not run until then | mergeInternals.ts:71 versus 52 |
| I14 | Outer complete with work remaining is silent; complete Gamma waits for the drain | mergeInternals.ts:43-49 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-MM-1 mergeMap: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-1 |
| Title | mergeMap: subscribe, one sync inner, complete |
| Parameters | default concurrent Infinity unless a finite number is passed; resultSelector omitted in the happy path; the deprecated overload is scenario 6's sibling note and the selector rows |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of MM |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | mergeMap.ts:93 delegates to mergeInternals.ts:71-86 with expand false |

### E-MM-2 mergeMap: finite concurrent queues FIFO and does not drop

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-2 |
| Title | mergeMap: finite concurrent queues FIFO and does not drop |
| Parameters | mergeMap(project, 2) so the second argument is a number, not a resultSelector (mergeMap.ts:89-91) |
| Start state | s0 |
| Prefix | subscribe; outerNext(v1) and outerNext(v2) both subscribed (active=2); neither inner completed |
| Input word | outerNext(v3), innerComplete(id1), innerNext(id3, z) |
| Transition IDs | MM enqueue row while at_capacity; MM dequeue row; MM innerNext row |
| Guards | active >= 2 on v3, so project(v3) is not called yet. After id1 completes, active drops and v3 is shifted |
| Notifications (Gamma) | eps for v3's arrival; next(z) only after id3 is subscribed and emits |
| Lifecycle | buffer=[v3] while two inners live; then subscribe id3 for v3 |
| Suffix | id2 and id3 live; v1's inner is gone; not terminal |
| End state | active_running or at_capacity depending on whether active is still 2 |
| Oracle | source characterization, matching the concurrent parameter contract: extra inners wait in an unbounded buffer. They are not dropped (that is exhaustMap) and they do not cancel the previous inner (that is switchMap) |
| Source characterization | mergeMap.ts:84 default Infinity; mergeMap.ts:89-93; mergeInternals.ts:31-33 and 52-53 and 109-122 |

### E-MM-3 mergeMap: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-3 |
| Title | mergeMap: outer completes while an inner is still active |
| Parameters | default concurrent Infinity unless a finite number is passed |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | MM outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-MM-4 mergeMap: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-4 |
| Title | mergeMap: inner error fails the output and drops the queue |
| Parameters | default concurrent Infinity unless a finite number is passed; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | MM innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-MM-5 mergeMap: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-5 |
| Title | mergeMap: cancel is silent |
| Parameters | default concurrent Infinity unless a finite number is passed |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | MM cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-MM-6 mergeMap: deprecated resultSelector throw

| Field | Value |
| --- | --- |
| Scenario ID | E-MM-6 |
| Title | mergeMap: deprecated resultSelector throw |
| Parameters | mergeMap(project, resultSelector, concurrent) with a function resultSelector |
| Start state | an inner of the rewritten projection is live |
| Prefix | subscribe of the deprecated overload; outerNext whose inner has emitted |
| Input word | innerNext(id, x) such that the inner map's resultSelector throws |
| Transition IDs | MM resultSelectorThrow row |
| Guards | isFunction(resultSelector) took mergeMap.ts:86-88, which maps each inner value through resultSelector |
| Notifications (Gamma) | error(e). The raw inner value is not forwarded |
| Lifecycle | map's OperatorSubscriber catches the throw and errors the mergeMap inner, which errors the destination and unsubscribes every inner |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | JSDoc contract: resultSelector is deprecated and will be removed in v8 (mergeMap.ts:13 and 19). Its throw is its own outcome, not innerError |
| Source characterization | mergeMap.ts:13-24 and 86-88; map.ts:54-57; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **33**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/33**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| MM-01 | not executed | static reading only; no runner |
| MM-02 | not executed | static reading only; no runner |
| MM-03 | not executed | static reading only; no runner |
| MM-04 | not executed | static reading only; no runner |
| MM-05 | not executed | static reading only; no runner |
| MM-06 | not executed | static reading only; no runner |
| MM-07 | not executed | static reading only; no runner |
| MM-08 | not executed | static reading only; no runner |
| MM-09 | not executed | static reading only; no runner |
| MM-10 | not executed | static reading only; no runner |
| MM-11 | not executed | static reading only; no runner |
| MM-12 | not executed | static reading only; no runner |
| MM-13 | not executed | static reading only; no runner |
| MM-14 | not executed | static reading only; no runner |
| MM-15 | not executed | static reading only; no runner |
| MM-16 | not executed | static reading only; no runner |
| MM-17 | not executed | static reading only; no runner |
| MM-18 | not executed | static reading only; no runner |
| MM-19 | not executed | static reading only; no runner |
| MM-20 | not executed | static reading only; no runner |
| MM-21 | not executed | static reading only; no runner |
| MM-22 | not executed | static reading only; no runner |
| MM-23 | not executed | static reading only; no runner |
| MM-24 | not executed | static reading only; no runner |
| MM-25 | not executed | static reading only; no runner |
| MM-26 | not executed | static reading only; no runner |
| MM-27 | not executed | static reading only; no runner |
| MM-28 | not executed | static reading only; no runner |
| MM-29 | not executed | static reading only; no runner |
| MM-30 | not executed | static reading only; no runner |
| MM-31 | not executed | static reading only; no runner |
| MM-32 | not executed | static reading only; no runner |
| MM-33 | not executed | static reading only; no runner |

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
| Limits | Unbounded FIFO when concurrent is finite; Infinity never queues; non-positive concurrent can hang; resultSelector still accepted but deprecated. |

Documented limits:

- Active-set bound: `concurrent` if it is a positive finite number; otherwise unbounded (`Infinity` default).
- Queue versus drop: this operator queues. It does not drop.
- Complete-wait: outer complete waits for the FIFO and for every inner.
- `resultSelector` remains callable and is deprecated in the JSDoc for removal in v8.
- Non-positive / NaN `concurrent` is not coerced to Infinity (unlike `expand`). Completion can wedge because `checkComplete` requires an empty buffer.
- No tests were executed.

