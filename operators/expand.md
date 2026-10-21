# expand

`expand` recursively projects every source value and every output value, merging those inners (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `expand.ts:73-95`). It calls `mergeInternals` with `onBeforeNext` undefined, the expand flag `true`, and the optional scheduler (`expand.ts:80-93`). Default concurrent is `Infinity`. Line 78 normalizes any concurrent that is `< 1` after a falsy coalesce to `Infinity`, so `0`, negatives, and `NaN` do not hang the way they can in `mergeMap`. There is no `resultSelector`. The scheduler argument is deprecated for removal in v8 (`expand.ts:12-15`); the suggested replacement is `subscribeOn` inside the projection. Recursion is not a second operator: an inner next in expand mode calls `outerNext` (`mergeInternals.ts:79-82`), and `doInnerSub` emits the value before projecting it (`mergeInternals.ts:59`).

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | expand(project, concurrent?, scheduler?). The overload that takes a scheduler is deprecated (expand.ts:12-15), removal in v8. No resultSelector |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Emit each accepted value, subscribe to project(value), and do the same for every value those inners emit, concurrently up to the cap, queueing the rest. Complete when the source has completed and every recursive inner and the queue are done |
| model kind | Extended/symbolic Mealy machine. Finite concurrent bounds simultaneously subscribed branches, not the depth or the queue. Infinity bounds nothing |
| parameter domain | project: (value, index) => ObservableInput. concurrent default Infinity, and (concurrent // 0) < 1 becomes Infinity (expand.ts:78). scheduler optional, deprecated, used only when the helper drains its buffer |
| payload/error domain | Output values are the source values and the recursive inner values, each emitted when doInnerSub runs. Errors: outerError, innerError, projectThrow. A projectThrow on an accepted value is preceded by next of that value |
| subscription boundary | Outer subscribed once. Each doInnerSub opens one inner. Recursive inners count toward active. Queued values are not yet subscribed and not yet emitted |
| scheduler/tie ordering | Fast path is synchronous and unscheduled even if a scheduler was passed. The scheduler is consulted only at mergeInternals.ts:118-119. queueScheduler delay 0 runs the drain inline and preserves the cap. async and asap schedulers can release the whole buffer and can be cancelled by a same-turn checkComplete |
| callback assumptions | project is synchronous. It is applied to source values and to inner values. Index counts every doInnerSub, including recursive ones |
| cleanup assumptions | Same complete-wait as merge: isComplete && empty buffer && active=0. A recursive child opened during the drain keeps the output open. Error and cancel tear down every live branch and the buffer |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Deep synchronous recursion can overflow the stack when concurrent is Infinity because nothing yields. That is a runtime limit of the sync path, not a separate state. |

## B. Six-tuple

Emission rule: `expand && subscriber.next(value)` happens at the start of `doInnerSub`, not when the value is buffered (`mergeInternals.ts:59`). Recursive rule: the inner next handler calls `outerNext(innerValue)` instead of `subscriber.next` (`mergeInternals.ts:79-82`). So a below-cap inner value is emitted and reprojected. An at-cap inner value is only queued. The scheduler does not wrap the initial subscribe.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with expand flag true |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C |
| lambda | Section C. next(v) is part of lambda for an accepted doInnerSub, before the inner exists |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| active_empty | subscribed; active=0; buffer=[]; isComplete=false | no inner |
| active_running | active>0 and below cap, or any active>0 when concurrent is Infinity; buffer empty | room for another inner |
| at_capacity | finite cap reached; FIFO may hold source values and, for expand, recursive values not yet emitted | queue location |
| draining | isComplete; work remains | outer-completed draining |
| terminal_complete / terminal_error / terminal_cancelled | stopped | no further Gamma |
| scheduler | optional third argument | drain-only |

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

For expand, an accepted value produces `next(v)` from the input that causes `doInnerSub(v)`, which may be `outerNext` or a below-cap `innerNext`. A queued value produces `eps` until dequeue.

## C. Transition obligations

The grid is the helper grid with the expand flag forced on. At-capacity applies to both source values and recursive values. The scheduler row is enabled only if the caller passed a scheduler.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EX-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-EX-01 |
| EX-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-EX-02 |
| EX-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | next(v) then no further Gamma from this input itself | emit v, then active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; v already delivered because expand emits before project | T-EX-03 |
| EX-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | next(v), then error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-EX-04 |
| EX-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | next(v) | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-EX-05 |
| EX-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-EX-06 |
| EX-07 | active_running | innerNext(id, x) / inner id | id is live and active < concurrent so outerNext(x) calls doInnerSub. x is NOT forwarded by the inner handler directly | next(x) | recursive subscribe: active increases; project(x, newIndex); the value is both output and a new outer-like input | active_running | an inner was subscribed and then emitted x while a slot was free | new inner for x is live; parent inner id still live until it completes | T-EX-07 |
| EX-08 | at_capacity | innerNext(id, x) / inner id | id live and active >= concurrent | eps | buffer.push(x); x is not emitted until a later doInnerSub dequeues it | at_capacity | concurrent live recursive or source inners | x sits in the same FIFO as queued source values; emission is delayed | T-EX-08 |
| EX-09 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-EX-09 |
| EX-10 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-EX-10 |
| EX-11 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-EX-11 |
| EX-12 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-EX-12 |
| EX-13 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | next(dequeued value) from doInnerSub, then no Gamma from the completing id itself. The new inner's own notifications are later Sigma events | active--; FIFO shift; doInnerSub immediately; expand emits the dequeued value before project; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue; that value has been emitted | T-EX-13 |
| EX-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | next(dequeued value), then error(e) projectThrow | expand already emitted inside doInnerSub before project threw; mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-EX-14 |
| EX-15 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-EX-15 |
| EX-16 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-EX-16 |
| EX-17 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-EX-17 |
| EX-18 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-EX-18 |
| EX-19 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-EX-19 |
| EX-20 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-EX-20 |
| EX-21 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-EX-21 |
| EX-22 | draining | innerNext(id, x) / inner id | id still live and, for expand, either emitted-and-projected or queued if the cap is full | next(x) if under cap, else eps and queue x | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; a recursive expand child can prolong the drain | T-EX-22 |
| EX-23 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-EX-23 |
| EX-24 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-EX-24 |
| EX-25 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-EX-25 |
| EX-26 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-EX-26 |
| EX-27 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-EX-27 |
| EX-28 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-EX-28 |
| EX-29 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error | terminal_cancelled | prefix of this location | terminal silent | T-EX-29 |
| EX-30 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-EX-30 |
| EX-31 | at_capacity | innerComplete(id) / inner id | innerSubScheduler is set (expand's deprecated scheduler). The while loop calls executeSchedule instead of doInnerSub | eps in this turn | buffer items are shifted and scheduled. active is NOT incremented until the scheduled doInnerSub runs, so a single drain schedules the whole remaining buffer. queueScheduler delay 0 flushes synchronously inside schedule(), which restores the cap. async/asap schedulers do not | draining or at_capacity, scheduler-dependent | expand called with a scheduler and the buffer was nonempty | see limits: async scheduler can overshoot concurrent and checkComplete can complete before deferred work runs | T-EX-31 |
| EX-32 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-EX-32 |
| EX-33 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-EX-33 |

Normalization: `expand.ts:78`. Scheduler hole: see mergeInternals notes. With the default concurrent Infinity the buffer is unused, so the deprecated scheduler is a no-op on that default. That is source behavior of 7.8.2, not the historical hope that the scheduler always trampolines recursion.

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
| I10 | Every value that is subscribed has been, or is in the same doInnerSub, emitted downstream. Buffered values have been neither subscribed nor emitted | mergeInternals.ts:52 and 59 |
| I11 | Recursive inners count in active. The cap is not 'source inners only' | active++ in every doInnerSub, including those entered from innerNext |
| I12 | concurrent < 1 is rewritten to Infinity before mergeInternals sees it | expand.ts:78 |
| I13 | No resultSelector parameter exists | expand.ts:73-77 |
| I14 | Complete-wait includes recursive descendants and the FIFO | mergeInternals.ts:47 with the expand flag |
| I15 | A scheduler argument does not schedule doInnerSub on the active < concurrent path | mergeInternals.ts:52 versus 118 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-EX-1 expand: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-1 |
| Title | expand: subscribe, one sync inner, complete |
| Parameters | concurrent default Infinity; values < 1 are normalized to Infinity (expand.ts:78); no resultSelector. optional deprecated scheduler |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of EX |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | expand.ts:79-93 calls mergeInternals with expand flag true |

### E-EX-2 expand: at a finite cap, both new source values and recursive inner values are queued and not emitted until doInnerSub

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-2 |
| Title | expand: at a finite cap, both new source values and recursive inner values are queued and not emitted until doInnerSub |
| Parameters | expand(project, 1) with no scheduler |
| Start state | s0 |
| Prefix | subscribe; outerNext(v0) emitted next(v0) and subscribed id0, which is still open, so active=1 |
| Input word | innerNext(id0, x), then innerComplete(id0), then the dequeued x is emitted and projected |
| Transition IDs | EX at_capacity innerNext row (queue, eps); EX dequeue row which for expand emits on doInnerSub |
| Guards | active >= 1 so outerNext(x) only buffer.push(x). Emission of x is inside doInnerSub, which has not run. After id0 completes, doInnerSub(x) runs: next(x), then project(x) |
| Notifications (Gamma) | eps when x arrives; next(x) only when it is dequeued |
| Lifecycle | x shares the FIFO with any queued source values. No second subscription while id0 is open |
| Suffix | a new inner for x is live; x has been delivered |
| End state | active_inner at cap if concurrent is 1 |
| Oracle | source characterization: expand does not emit a recursive value at arrival time when the cap is full, because emission is in doInnerSub (mergeInternals.ts:59) and the cap path does not call doInnerSub (line 52). This is stricter than a reading of the prose that says every output value is re-emitted immediately |
| Source characterization | expand.ts:75-93; mergeInternals.ts:52-53 and 59 and 79-82 |

### E-EX-3 expand: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-3 |
| Title | expand: outer completes while an inner is still active |
| Parameters | concurrent default Infinity; values < 1 are normalized to Infinity (expand.ts:78) |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | EX outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-EX-4 expand: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-4 |
| Title | expand: inner error fails the output and drops the queue |
| Parameters | concurrent default Infinity; values < 1 are normalized to Infinity (expand.ts:78); a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | EX innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-EX-5 expand: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-5 |
| Title | expand: cancel is silent |
| Parameters | concurrent default Infinity; values < 1 are normalized to Infinity (expand.ts:78) |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | EX cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-EX-6 expand: project throws after the value was already emitted

| Field | Value |
| --- | --- |
| Scenario ID | E-EX-6 |
| Title | expand: project throws after the value was already emitted |
| Parameters | expand(project) default Infinity |
| Start state | active_empty |
| Prefix | subscribe |
| Input word | outerNext(v) whose project throws |
| Transition IDs | EX projectThrow row on active_empty |
| Guards | doInnerSub calls subscriber.next(v) before project (mergeInternals.ts:59 then 71) |
| Notifications (Gamma) | next(v), then error(e) |
| Lifecycle | no recursive inner is subscribed; destination errors |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | source characterization: projectThrow is ordered after the expand emission of that same value. It is not outerError |
| Source characterization | mergeInternals.ts:59-71; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **33**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/33**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| EX-01 | not executed | static reading only; no runner |
| EX-02 | not executed | static reading only; no runner |
| EX-03 | not executed | static reading only; no runner |
| EX-04 | not executed | static reading only; no runner |
| EX-05 | not executed | static reading only; no runner |
| EX-06 | not executed | static reading only; no runner |
| EX-07 | not executed | static reading only; no runner |
| EX-08 | not executed | static reading only; no runner |
| EX-09 | not executed | static reading only; no runner |
| EX-10 | not executed | static reading only; no runner |
| EX-11 | not executed | static reading only; no runner |
| EX-12 | not executed | static reading only; no runner |
| EX-13 | not executed | static reading only; no runner |
| EX-14 | not executed | static reading only; no runner |
| EX-15 | not executed | static reading only; no runner |
| EX-16 | not executed | static reading only; no runner |
| EX-17 | not executed | static reading only; no runner |
| EX-18 | not executed | static reading only; no runner |
| EX-19 | not executed | static reading only; no runner |
| EX-20 | not executed | static reading only; no runner |
| EX-21 | not executed | static reading only; no runner |
| EX-22 | not executed | static reading only; no runner |
| EX-23 | not executed | static reading only; no runner |
| EX-24 | not executed | static reading only; no runner |
| EX-25 | not executed | static reading only; no runner |
| EX-26 | not executed | static reading only; no runner |
| EX-27 | not executed | static reading only; no runner |
| EX-28 | not executed | static reading only; no runner |
| EX-29 | not executed | static reading only; no runner |
| EX-30 | not executed | static reading only; no runner |
| EX-31 | not executed | static reading only; no runner |
| EX-32 | not executed | static reading only; no runner |
| EX-33 | not executed | static reading only; no runner |

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
| Limits | Recursive merge. concurrent < 1 becomes Infinity. Queue at a finite cap delays emission. Scheduler is drain-only and deprecated. No resultSelector. Complete-wait includes the recursion. |

Documented limits:

- Active-set bound: the normalized concurrent, or unbounded when it is Infinity (the default, and also any concurrent < 1).
- Queue versus drop: a finite cap queues. Queued recursive values are not emitted until dequeued.
- Complete-wait: the outer completion waits for every recursive inner and for the queue.
- No `resultSelector`.
- `scheduler` is deprecated (v8) and, in this commit, only affects buffer drain. Default Infinity makes it a no-op. Async drain can overshoot the cap and can be cancelled by `checkComplete`.
- Synchronous recursion is unbounded in stack when the cap never trips.
- No tests were executed.

