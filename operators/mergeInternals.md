# mergeInternals

`mergeInternals` is not a public operator. It is the internal merge-strategy helper used by `mergeMap`, `mergeScan`, and `expand` (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `src/internal/operators/mergeInternals.ts:21-149`). Callers pass the source, the downstream subscriber, a projection, a concurrency limit, and optional hooks: `onBeforeNext`, an `expand` flag, an `innerSubScheduler`, and an `additionalFinalizer`. The machine below is that helper with those flags kept symbolic. Public wrappers instantiate them. There is no `resultSelector` inside this function; deprecated selectors are applied by the wrappers before a value reaches `subscriber.next`.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | Internal helper mergeInternals(source, subscriber, project, concurrent, onBeforeNext?, expand?, innerSubScheduler?, additionalFinalizer?). Not an OperatorFunction. No public overloads |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Subscribe to projected inners up to `concurrent`, FIFO-buffer the rest, forward inner nexts (after onBeforeNext, or recursively when expand is set), wait for the buffer and all inners after the outer completes, and fail fast on any inner or outer error |
| model kind | Extended/symbolic Mealy machine. Active-set cardinality is bounded by a finite concurrent; the buffer and payload domain are still unbounded. concurrent Infinity leaves the active set unbounded |
| parameter domain | project: (T, index) => ObservableInput. concurrent: number, not defaulted and not normalized here (callers choose). expand boolean. scheduler optional. onBeforeNext optional (R) => void |
| payload/error domain | Outer payloads T; inner payloads R; errors are any value the source, an inner, project, onBeforeNext, or innerFrom throws or notifies. projectThrow and onBeforeNext throw are distinct from outerError and innerError |
| subscription boundary | The helper subscribes to `source` once (line 136). It subscribes to an inner only inside doInnerSub (line 71). Cancel or destination error unsubscribes the downstream subscriber and therefore every child OperatorSubscriber (outer and inners) |
| scheduler/tie ordering | No scheduler on the fast path. innerSubScheduler is read only when draining the buffer (lines 118-119). Same-turn ordering is ordinary JavaScript call order. Sync inner notifications are later Sigma events |
| callback assumptions | project and onBeforeNext are synchronous. Throws are caught by the outer or inner OperatorSubscriber next wrapper, or by the finalizer try/catch at lines 104-128 when the throw happens on a dequeue |
| cleanup assumptions | Inner success finalizer decrements active and may dequeue only if innerComplete was set (lines 99-129). Error and cancel leave innerComplete false, so they do not start new inners. additionalFinalizer runs from the teardown returned at lines 146-148, which operate/subscribe adds on the consumer |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Grouped reentrancy from downstream during next is out of model. The stale comment at line 46 about emitting state on complete is not what the code does: checkComplete only calls subscriber.complete() |

## B. Six-tuple

The helper is the Mealy machine that the merge-family operators share. `outerNext` either calls `doInnerSub` or `buffer.push` (`mergeInternals.ts:52`). `doInnerSub` optionally emits when `expand` is true (line 59), increments `active` (line 63), then subscribes to `innerFrom(project(value, index++))` (line 71). Inner next either updates via `onBeforeNext` and forwards, or, in expand mode, feeds the value back to `outerNext` (lines 74-86). Completion of the output is the conjunction `isComplete && !buffer.length && !active` (lines 47-49).

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with flags (expand, onBeforeNext, scheduler) as parameters of the machine |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C. Flags select which innerNext rows are enabled |
| lambda | Section C Notifications column. checkComplete contributes complete only in the draining-finished row |
| s0 | init, before the helper subscribes to source |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| active_empty | subscribed; active=0; buffer=[]; isComplete=false | no inner. Next accepted value is subscribed immediately |
| active_running | active>0 and (concurrent is Infinity or active<concurrent); buffer empty | Room remains for another inner. With the default Infinity this is every busy state |
| at_capacity | concurrent is finite and active>=concurrent; buffer FIFO may be empty or not | Further values wait. Unreachable while concurrent is Infinity |
| draining | isComplete=true; active>0 or buffer nonempty | Outer-completed, inners and/or queue remain. Output not yet completed |
| terminal_complete / terminal_error / terminal_cancelled | Subscriber stopped | No further Gamma |
| state (data) | seed at subscribe; thereafter the latest inner value passed to onBeforeNext | Not emitted as a seed. mergeScan writes it on every inner next |
| scheduler (data) | optional; only the helper/expand drain loop reads it | Absent on the fast path |

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

Rows cover init, active with no inner, active with inners below a finite cap, at-capacity, outer-completed draining, and the terminals. Where a row mentions both expand and non-expand behavior, the guard names the flag. `resultSelector` is not a symbol of this helper.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MI-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false; state=seed (seed not emitted) | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-MI-01 |
| MI-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-MI-02 |
| MI-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; project(v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-MI-03 |
| MI-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-MI-04 |
| MI-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-MI-05 |
| MI-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-MI-06 |
| MI-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; onBeforeNext does not throw. For mergeScan onBeforeNext is state:=x. Helper: onBeforeNext is whatever the caller passed (undefined for plain merge) | next(x) after onBeforeNext; helper expand flag false in this row | state overwritten with x before the downstream next (mergeScan). No unsubscribe | same control location | inner id subscribed | state is x for every later projection, including values still sitting in the buffer | T-MI-07 |
| MI-08 | active_running | innerNext(id, x) / inner id | expand flag true and active < concurrent. Same recursive path expand uses | next(x) | doInnerSub(x): emit then project | active_running | helper called with expand true | recursive inner live | T-MI-08 |
| MI-09 | at_capacity | innerNext(id, x) / inner id | expand flag true and active >= concurrent | eps | buffer.push(x); emission deferred until dequeue | at_capacity | expand true and cap full | x queued, not yet emitted | T-MI-09 |
| MI-10 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-MI-10 |
| MI-11 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-MI-11 |
| MI-12 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-MI-12 |
| MI-13 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-MI-13 |
| MI-14 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-MI-14 |
| MI-15 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-MI-15 |
| MI-16 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-MI-16 |
| MI-17 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MI-17 |
| MI-18 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MI-18 |
| MI-19 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-MI-19 |
| MI-20 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-MI-20 |
| MI-21 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-MI-21 |
| MI-22 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-MI-22 |
| MI-23 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; a recursive expand child can prolong the drain | T-MI-23 |
| MI-24 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-MI-24 |
| MI-25 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-MI-25 |
| MI-26 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-MI-26 |
| MI-27 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-MI-27 |
| MI-28 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MI-28 |
| MI-29 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MI-29 |
| MI-30 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MI-30 |
| MI-31 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-MI-31 |
| MI-32 | at_capacity | innerComplete(id) / inner id | innerSubScheduler is set (expand's deprecated scheduler). The while loop calls executeSchedule instead of doInnerSub | eps in this turn | buffer items are shifted and scheduled. active is NOT incremented until the scheduled doInnerSub runs, so a single drain schedules the whole remaining buffer. queueScheduler delay 0 flushes synchronously inside schedule(), which restores the cap. async/asap schedulers do not | draining or at_capacity, scheduler-dependent | expand called with a scheduler and the buffer was nonempty | see limits: async scheduler can overshoot concurrent and checkComplete can complete before deferred work runs | T-MI-32 |
| MI-33 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-MI-33 |
| MI-34 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-MI-34 |

Scheduler note (`mergeInternals.ts:113-122`, `executeSchedule.ts:19-35`): the while-condition reads `active` before a deferred `doInnerSub` can increment it. `queueScheduler` with delay 0 flushes inside `schedule`, so the increment is visible and the cap holds. `asyncScheduler` / `asapScheduler` return before the work runs, so one drain schedules every currently buffered value. Those actions are children of `subscriber`. If `checkComplete` then sees `active === 0` and an empty buffer, it completes and unsubscribes the actions, dropping the deferred work. Only `expand` passes a scheduler today.

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
| I10 | When expand is false, source values are never themselves Gamma nexts; only inner values are, after onBeforeNext | mergeInternals.ts:79-85 |
| I11 | When expand is true, a value is emitted only inside doInnerSub, so a value that is merely buffered is not yet visible downstream | lines 52-53 versus 59 |
| I12 | onBeforeNext runs before subscriber.next on the non-expand path, so mergeScan's state update is visible to a synchronous downstream reentry only if that reentry were allowed; it is excluded. It IS visible to a later projection in the same turn after this next returns | lines 74-85 |
| I13 | additionalFinalizer is not a notification. It runs on destination teardown | lines 146-148 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-MI-1 mergeInternals: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-1 |
| Title | mergeInternals: subscribe, one sync inner, complete |
| Parameters | concurrent = 2 for the queue scenario; Infinity elsewhere; expand flag false unless noted; onBeforeNext undefined; no resultSelector in this helper |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of MI |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | mergeInternals.ts:52-93 and 136-141, expand flag false |

### E-MI-2 mergeInternals: finite concurrent queues instead of dropping

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-2 |
| Title | mergeInternals: finite concurrent queues instead of dropping |
| Parameters | concurrent = 1; expand false; no scheduler |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) subscribed as id1 and still open |
| Input word | outerNext(v2), innerNext(id1, a), innerComplete(id1), innerNext(id2, b), innerComplete(id2), outerComplete |
| Transition IDs | MI at-capacity enqueue row, then MI dequeue-on-complete row, then inner next and complete rows |
| Guards | second outerNext sees active >= 1; project(v2) runs only in the finalizer after id1 completes |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | v2 sits in buffer while id1 is live; then one subscribe of id2; no overlap |
| Suffix | terminal_complete; buffer empty |
| End state | terminal_complete |
| Oracle | source characterization: over-cap values are buffered, not dropped. This is the same queue concatMap relies on |
| Source characterization | mergeInternals.ts:52-53 and 109-125 |

### E-MI-3 mergeInternals: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-3 |
| Title | mergeInternals: outer completes while an inner is still active |
| Parameters | concurrent = 2 for the queue scenario; Infinity elsewhere; expand flag false unless noted; onBeforeNext undefined |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | MI outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-MI-4 mergeInternals: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-4 |
| Title | mergeInternals: inner error fails the output and drops the queue |
| Parameters | concurrent = 2 for the queue scenario; Infinity elsewhere; expand flag false unless noted; onBeforeNext undefined; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | MI innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-MI-5 mergeInternals: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-5 |
| Title | mergeInternals: cancel is silent |
| Parameters | concurrent = 2 for the queue scenario; Infinity elsewhere; expand flag false unless noted; onBeforeNext undefined |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | MI cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-MI-6 mergeInternals: project throw on a fresh outer value

| Field | Value |
| --- | --- |
| Scenario ID | E-MI-6 |
| Title | mergeInternals: project throw on a fresh outer value |
| Parameters | expand false; project throws |
| Start state | active_empty |
| Prefix | subscribe |
| Input word | outerNext(v) |
| Transition IDs | MI active_empty projectThrow row |
| Guards | throw originates in project or innerFrom, caught by the outer OperatorSubscriber next wrapper |
| Notifications (Gamma) | error(e) and nothing else. No next of v |
| Lifecycle | active was incremented and index consumed, then the destination errors and tears the subscription down. No inner source remains |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | source characterization: projectThrow is not an outerError notification. The source did not error; the callback did |
| Source characterization | mergeInternals.ts:63-71; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **34**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/34**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| MI-01 | not executed | static reading only; no runner |
| MI-02 | not executed | static reading only; no runner |
| MI-03 | not executed | static reading only; no runner |
| MI-04 | not executed | static reading only; no runner |
| MI-05 | not executed | static reading only; no runner |
| MI-06 | not executed | static reading only; no runner |
| MI-07 | not executed | static reading only; no runner |
| MI-08 | not executed | static reading only; no runner |
| MI-09 | not executed | static reading only; no runner |
| MI-10 | not executed | static reading only; no runner |
| MI-11 | not executed | static reading only; no runner |
| MI-12 | not executed | static reading only; no runner |
| MI-13 | not executed | static reading only; no runner |
| MI-14 | not executed | static reading only; no runner |
| MI-15 | not executed | static reading only; no runner |
| MI-16 | not executed | static reading only; no runner |
| MI-17 | not executed | static reading only; no runner |
| MI-18 | not executed | static reading only; no runner |
| MI-19 | not executed | static reading only; no runner |
| MI-20 | not executed | static reading only; no runner |
| MI-21 | not executed | static reading only; no runner |
| MI-22 | not executed | static reading only; no runner |
| MI-23 | not executed | static reading only; no runner |
| MI-24 | not executed | static reading only; no runner |
| MI-25 | not executed | static reading only; no runner |
| MI-26 | not executed | static reading only; no runner |
| MI-27 | not executed | static reading only; no runner |
| MI-28 | not executed | static reading only; no runner |
| MI-29 | not executed | static reading only; no runner |
| MI-30 | not executed | static reading only; no runner |
| MI-31 | not executed | static reading only; no runner |
| MI-32 | not executed | static reading only; no runner |
| MI-33 | not executed | static reading only; no runner |
| MI-34 | not executed | static reading only; no runner |

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
| Limits | See limits prose. Decision records the hang on non-positive concurrent, the scheduler drain hole, and the unbounded FIFO. |

Documented limits:

- The helper does not clamp `concurrent`. `active < concurrent` is the only gate (`mergeInternals.ts:52`). `Infinity` never queues. `0`, negatives, and `NaN` queue forever and can prevent completion.
- The FIFO is unbounded. A finite `concurrent` bounds only the set of subscribed inners.
- The deprecated expand scheduler does not schedule the fast path, and an async scheduler does not preserve the cap across a drain (see section C notes).
- `checkComplete` does not emit accumulator state, despite the comment on line 46.
- No tests were executed.

