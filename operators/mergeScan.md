# mergeScan

`mergeScan` runs an accumulator that returns an `ObservableInput`, merges those inners, and threads a single piece of state (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `mergeScan.ts:70-92`). It does not use `scanInternals.ts` (that helper is for `scan` and `reduce` only). The body calls `mergeInternals` with project `(value, index) => accumulator(state, value, index)`, concurrent default `Infinity`, `onBeforeNext` equal to `(value) => { state = value }`, expand flag `false`, no scheduler, and a finalizer that clears `state` (`mergeScan.ts:79-90`). The seed is stored and is not emitted on subscribe. There is no `resultSelector`. Concurrency and the FIFO are the merge policy: a finite cap queues source values, and the accumulator runs when the value is subscribed, seeing whatever `state` is then. Every inner next overwrites `state` before it is forwarded, so concurrent inners share one cell.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | mergeScan(accumulator, seed, concurrent = Infinity). No resultSelector. No scheduler |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | On each subscribed source value, call accumulator(state, value, index) and merge the inner it returns, up to concurrent. Each inner value becomes the next state and is also emitted. Complete only after the source, the queue, and all inners are done. Do not emit the seed by itself |
| model kind | Extended/symbolic Mealy machine. Same active-set bound as mergeMap, plus an unbounded state value. Finite concurrent does not snapshot state per queued value |
| parameter domain | accumulator: (acc: R, value: T, index: number) => ObservableInput<R>. seed: R. concurrent default Infinity, not normalized (0 and NaN can hang, as in mergeMap) |
| payload/error domain | Gamma nexts are inner values, which are also the successive states. Errors: outerError, innerError, accumulator throw (projectThrow). onBeforeNext is a plain assignment and does not throw on its own |
| subscription boundary | Same as mergeMap. The accumulator is not called for a queued value. Index is the helper index, assigned at doInnerSub |
| scheduler/tie ordering | None. If two inners are live, their nexts both write `state` in arrival order, and a projection that starts between them sees the latest write |
| callback assumptions | accumulator is synchronous. It may throw. It may close over external state; the operator's own state is the `state` variable. The seed may be any R, including null or undefined; null is not a sentinel (the finalizer writes null only to drop the reference) |
| cleanup assumptions | Complete-wait is mergeInternals' checkComplete. The finalizer `state = null` runs on destination teardown (complete, error, or cancel) and emits nothing. Error unsubscribes all inners. Cancel is silent |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). scanInternals is not part of this operator. A per-inner accumulator snapshot is not what the code does. |

## B. Six-tuple

State update ordering inside the inner next (`mergeInternals.ts:74-85` with the callback from `mergeScan.ts:84-86`): `state = innerValue`, then `subscriber.next(innerValue)`. The next projection, whether it comes from a later source value or from a dequeue, reads that variable at call time (`mergeScan.ts:82`). JSDoc lines 23-27 match the code on one point: until some inner emits, later accumulations still see the seed, even if the source has emitted several values, provided those values were subscribed before any inner next. They do not claim a per-value snapshot once queueing delays the call.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) plus state: R |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C |
| lambda | Section C. Seed is not a next |
| s0 | init, state unset until subscribe sets state = seed |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| active_empty | subscribed; active=0; buffer=[]; isComplete=false | no inner |
| active_running | active>0 and below cap, or any active>0 when concurrent is Infinity; buffer empty | room for another inner |
| at_capacity | finite cap reached; FIFO may hold source values and, for expand, recursive values not yet emitted | queue location |
| draining | isComplete; work remains | outer-completed draining |
| terminal_complete / terminal_error / terminal_cancelled | stopped | no further Gamma |
| state | seed until the first inner next; then latest inner value | one cell shared by every concurrent inner; read when the accumulator is called |

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

`mergeScan` adds no Gamma kind for the seed. `next` payloads are inner values only.

## C. Transition obligations

The grid is the merge grid with the accumulator in the project role and with innerNext defined to update state before next. There is no resultSelector row: this signature does not have one. At-capacity is reachable only for a finite concurrent.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MS-01 | init / s0 | subscribe / consumer | operate/init does not throw; source subscription is established | eps | subscribe outer; active=0; buffer=[]; index=0; isComplete=false; state=seed (seed not emitted) | active_empty | epsilon | outer live; concurrent parameter (default Infinity); no inner | T-MS-01 |
| MS-02 | init / s0 | subscribe / consumer | init throws synchronously (lift catch, operate in lift.ts) | error(e) | no inner; destination errored | terminal_error | epsilon | terminal; no complete | T-MS-02 |
| MS-03 | active_empty | outerNext(v) / source | active < concurrent and project/innerFrom succeeds | eps | active:=1; index consumed; subscribe inner id for v; accumulator(state, v, index) at this moment | active_running | subscribe | one inner live; source value itself is not a Gamma next | T-MS-03 |
| MS-04 | active_empty | outerNext(v) / source | project throws, or innerFrom throws on the returned input (projectThrow / invalid ObservableInput). Distinct from outerError | error(e) | no surviving inner subscription; destination.error from OperatorSubscriber next catch or drain catch | terminal_error | subscribe | terminal. index was consumed if project was entered. no complete | T-MS-04 |
| MS-05 | active_running | outerNext(v) / source | active + 1 <= concurrent after the new subscription, i.e. active < concurrent before it. Unreachable when this would exceed a finite cap (that is the at_capacity row). With concurrent Infinity this guard stays true for every finite active set | eps | subscribe an additional inner; index consumed at subscribe time, not at a queue | active_running | subscribe, outerNext+ that opened the first inner | several inners live; their nexts may interleave | T-MS-05 |
| MS-06 | active_running or at_capacity | outerNext(v) / source | active >= concurrent (finite). False for every finite active set when concurrent is Infinity, so this row is then unreachable | eps | buffer.push(v); do not call project yet; do not assign index yet; do not emit v even for expand | at_capacity | enough accepted outerNext values to fill concurrent | FIFO buffer holds v behind earlier queued values; active unchanged | T-MS-06 |
| MS-07 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerNext(id, x) / inner id | id live; onBeforeNext does not throw. For mergeScan onBeforeNext is state:=x. Helper: onBeforeNext is whatever the caller passed (undefined for plain merge) | next(x) | state overwritten with x before the downstream next (mergeScan). No unsubscribe | same control location | inner id subscribed | state is x for every later projection, including values still sitting in the buffer | T-MS-07 |
| MS-08 | active_running (and at_capacity if a finite cap is already met and this id is one of the live inners) | innerError(id, e) / inner id | id live. No catch is installed (mergeInternals passes onError undefined) | error(e) | destination.error unsubscribes the consumer subscriber, which unsubscribes outer and every inner; buffer dropped. innerComplete flag stays false so the drain finalizer does not start new work | terminal_error | inner id subscribed | terminal; no complete; no queued inner is subscribed | T-MS-08 |
| MS-09 | active_empty | innerNext / innerError / innerComplete | no live id. Unreachable if inners only notify while subscribed | eps | none | active_empty | subscribe | excluded delivery; not a second hidden inner | T-MS-09 |
| MS-10 | active_running | innerComplete(id) / inner id | buffer empty; other inners remain; outer still open | eps | active decremented in the inner finalizer; id removed | active_running | two or more inners were live | remaining inners stay subscribed | T-MS-10 |
| MS-11 | active_running | innerComplete(id) / inner id | buffer empty; id was the last inner; isComplete is false | eps | active:=0 | active_empty | one inner was live and outer has not completed | ready to accept and subscribe immediately | T-MS-11 |
| MS-12 | at_capacity | innerComplete(id) / inner id | buffer nonempty; dequeued project succeeds; no scheduler | eps from the complete itself (the new inner's sync nexts are later events) | active--; FIFO shift; doInnerSub immediately; active++ inside doInnerSub so the while-predicate observes the cap | at_capacity if the buffer still has items or active returns to the cap, else active_running | queue was nonempty | oldest queued value is now an inner; index assigned at this dequeue | T-MS-12 |
| MS-13 | at_capacity | innerComplete(id) / inner id | buffer nonempty and the dequeued project/innerFrom throws | error(e) projectThrow | mergeInternals finalizer try/catch calls subscriber.error; no further dequeue | terminal_error | queued value whose projection throws | terminal; rest of buffer discarded by teardown | T-MS-13 |
| MS-14 | at_capacity | innerComplete(id) / inner id | buffer is empty. The slot frees and nothing is waiting | eps | active-- only | active_running if other inners remain, else active_empty | cap was full only because of live inners | below the cap again; the next outerNext subscribes immediately | T-MS-14 |
| MS-15 | active_empty | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MS-15 |
| MS-16 | active_running | outerError(e) / source | source signals error. Not a project throw | error(e) | forward via default _error; unsubscribe inners and outer; drop buffer | terminal_error | prefix that entered this location | terminal; no complete | T-MS-16 |
| MS-17 | at_capacity | outerError(e) / source | source error while the FIFO holds values or the cap is full | error(e) | drop buffer without projecting it; unsubscribe inners | terminal_error | cap was reached | terminal; queued values never subscribed | T-MS-17 |
| MS-18 | active_empty | outerComplete / source | active = 0 and buffer empty | complete | isComplete:=true; checkComplete succeeds; source subscriber finalized | terminal_complete | subscribe, and every inner already completed | terminal complete; no inner left | T-MS-18 |
| MS-19 | active_running | outerComplete / source | active > 0 or buffer nonempty | eps | isComplete:=true; unsubscribe source only; inners are siblings and stay; buffer kept | draining | an inner is in flight or values are queued | wait. Output completes only when active hits 0 and buffer is empty | T-MS-19 |
| MS-20 | at_capacity | outerComplete / source | cap full or buffer nonempty | eps | same drain entry as the running-state outerComplete row | draining | at_capacity prefix | queued values will still be subscribed as slots free | T-MS-20 |
| MS-21 | draining | innerNext(id, x) / inner id | id still live | next(x) | same inner-next rules as the non-draining location; isComplete stays true | draining | outerComplete while this id was live | still draining; no recursive projection on this instantiation | T-MS-21 |
| MS-22 | draining | innerError(id, e) / inner id | id live | error(e) | fail the output immediately; unsubscribe remaining inners; discard buffer | terminal_error | draining | terminal; no complete after error | T-MS-22 |
| MS-23 | draining | innerComplete(id) / inner id | after decrement, active > 0 or buffer still nonempty | eps | maybe FIFO-subscribe more inners while active < concurrent | draining | draining with work left | output not completed yet | T-MS-23 |
| MS-24 | draining | innerComplete(id) / inner id | after the finalizer, active = 0 and buffer is empty | complete | checkComplete; no further subscribe | terminal_complete | outer already complete and this completion finishes the bookkeeping | terminal complete | T-MS-24 |
| MS-25 | draining | outerNext / outerError / outerComplete | source was unsubscribed when it completed. Further outer notifications are excluded unless a downstream reentry, which is out of model | eps | none | draining | outerComplete already consumed | not enabled | T-MS-25 |
| MS-26 | active_empty | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MS-26 |
| MS-27 | active_running | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MS-27 |
| MS-28 | draining | cancel / consumer | consumer unsubscribes. Not a source complete | eps | unsubscribe outer and every inner; discard buffer; do not emit complete or error; additionalFinalizer runs (mergeScan clears state) | terminal_cancelled | prefix of this location | terminal silent | T-MS-28 |
| MS-29 | at_capacity | cancel / consumer | consumer unsubscribes while queued or at cap | eps | discard buffer without subscribing it; unsubscribe inners and outer | terminal_cancelled | at_capacity | terminal silent | T-MS-29 |
| MS-30 | active_empty | subscribe effect already done | seed is held and must not be emitted merely because subscription started | eps | state=seed; no next | active_empty | subscribe | downstream has not seen seed | T-MS-30 |
| MS-31 | any non-terminal | outerNext(v) / source | synchronous inner notifications during innerFrom().subscribe. These are ordinary subsequent Sigma events (innerNext*, innerComplete) ordered before the next source event. Included, not treated as downstream reentry | whatever those later events produce | nested finalizer may drain the buffer before the outer next handler returns | the location those later events specify | the outerNext that subscribed the sync inner | model them as separate rows already listed, in order | T-MS-31 |
| MS-32 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-MS-32 |

Concurrent inners are allowed by the default Infinity and by any concurrent > 1. They do not get private accumulators. The last inner next wins the single `state` cell.

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
| I10 | seed is not emitted merely by subscribe | mergeScan.ts:77; no subscriber.next in the operate callback before mergeInternals, and expand is false so source values are not emitted |
| I11 | state after a successful innerNext(id, x) is x, and the Gamma payload is also x | mergeScan.ts:84-86; mergeInternals.ts:77-85 |
| I12 | The accumulator observes state at doInnerSub time. Enqueue does not sample it | mergeScan.ts:82; mergeInternals.ts:52 versus 71 |
| I13 | concurrent is not normalized. Default Infinity | mergeScan.ts:73 |
| I14 | No public resultSelector | mergeScan.ts:70-74 |
| I15 | Complete-wait matches mergeMap, and does not emit a final state on complete beyond whatever inners already nexted | mergeInternals.ts:43-49; the comment on line 46 is not an extra next |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-MS-1 mergeScan: subscribe, one sync inner, complete

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-1 |
| Title | mergeScan: subscribe, one sync inner, complete |
| Parameters | concurrent default Infinity, not normalized; no resultSelector. accumulator plus seed. onBeforeNext writes state |
| Start state | s0 / init |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), innerNext(id1, b), innerComplete(id1), outerComplete |
| Transition IDs | the subscribe row, the below-cap outerNext row, innerNext rows, the last-inner complete row, the active_empty outerComplete row of MS |
| Guards | project succeeds; the inner is synchronous only in the sense that its notifications are the next events; concurrent allows the subscribe |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | subscribe outer; subscribe id1; unsubscribe id1; unsubscribe outer on complete |
| Suffix | terminal_complete; nothing buffered |
| End state | terminal_complete |
| Oracle | contract: projected inner values are flattened in order for a single inner, then the output completes when the source and that inner are done |
| Source characterization | mergeScan.ts:79-90 |

### E-MS-2 mergeScan: a queued source value is accumulated with the state at dequeue time, not the state at arrival time

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-2 |
| Title | mergeScan: a queued source value is accumulated with the state at dequeue time, not the state at arrival time |
| Parameters | mergeScan(accumulator, seed, 1) |
| Start state | s0 |
| Prefix | subscribe (seed not emitted); outerNext(v1) calls accumulator(seed, v1, 0) and subscribes id1; id1 emits x and state becomes x; v1's inner still open |
| Input word | outerNext(v2) while id1 live; innerNext(id1, y) so state becomes y; innerComplete(id1); the dequeue calls accumulator(y, v2, 1) |
| Transition IDs | MS enqueue row; MS innerNext state-update row; MS dequeue row |
| Guards | v2 is buffered without calling the accumulator. The later doInnerSub closes over state and reads it then (mergeScan.ts:82) |
| Notifications (Gamma) | next(x) and next(y) from id1; no next at the moment v2 arrives; then nexts from v2's inner |
| Lifecycle | one cell `state` shared across inners. With concurrent 1 the sharing is ordered by the queue. With concurrent > 1, whichever inner nexts last wins before the next projection |
| Suffix | id for v2 is live; state is whatever that inner has emitted, or y if it has not emitted yet |
| End state | active_running or at_capacity |
| Oracle | source characterization, sharper than the prose at mergeScan.ts:23-27: state is not snapshotted when the source value arrives if that value is queued. The prose is right that state stays at seed until some inner emits, and that later inners see the remembered value |
| Source characterization | mergeScan.ts:75-90; mergeInternals.ts:52 and 71 and 77 |

### E-MS-3 mergeScan: outer completes while an inner is still active

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-3 |
| Title | mergeScan: outer completes while an inner is still active |
| Parameters | concurrent default Infinity, not normalized |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1) with project subscribed and not completed |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | MS outerComplete-while-active row, draining innerNext row, draining last-complete row |
| Guards | isComplete becomes true with active > 0; checkComplete is false until the finalizer sees active = 0 and an empty buffer |
| Notifications (Gamma) | eps on outerComplete, next(a), complete |
| Lifecycle | source unsubscribed at outerComplete; id1 remains until it completes; then output completes |
| Suffix | terminal_complete. No second inner is invented |
| End state | terminal_complete |
| Oracle | source characterization: merge/concat/expand/mergeScan wait for inners and for the FIFO. They do not complete on outer complete alone |
| Source characterization | mergeInternals.ts:43-49 and 137-141 |

### E-MS-4 mergeScan: inner error fails the output and drops the queue

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-4 |
| Title | mergeScan: inner error fails the output and drops the queue |
| Parameters | concurrent default Infinity, not normalized; a second value is already queued when the cap is finite |
| Start state | at-capacity or the sole concat inner |
| Prefix | subscribe, enough outerNext values that one inner is live and at least one value is buffered when the cap is finite |
| Input word | innerError(id, e) |
| Transition IDs | MS innerError row |
| Guards | onError argument to the inner createOperatorSubscriber is undefined |
| Notifications (Gamma) | error(e) |
| Lifecycle | unsubscribe every inner and the outer; buffer discarded without project calls; no complete |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: inner error is not caught inside these operators |
| Source characterization | mergeInternals.ts:92-94; OperatorSubscriber.ts:88 uses super._error when onError is omitted; Subscriber.ts:116-121 |

### E-MS-5 mergeScan: cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-5 |
| Title | mergeScan: cancel is silent |
| Parameters | concurrent default Infinity, not normalized |
| Start state | inner live, outer open |
| Prefix | subscribe, outerNext that subscribed an inner |
| Input word | cancel |
| Transition IDs | MS cancel row for the occupied location |
| Guards | consumer unsubscribe, not a source notification |
| Notifications (Gamma) | eps |
| Lifecycle | unsubscribe outer and all inners; discard buffer |
| Suffix | terminal_cancelled; a later outerComplete is not delivered |
| End state | terminal_cancelled |
| Oracle | contract: unsubscribing does not call complete |
| Source characterization | Subscriber.ts:104-110; Observable.ts subscribe documentation that cancel is not complete |

### E-MS-6 mergeScan: accumulator throw

| Field | Value |
| --- | --- |
| Scenario ID | E-MS-6 |
| Title | mergeScan: accumulator throw |
| Parameters | mergeScan(accumulator, seed) |
| Start state | active_empty, state still seed |
| Prefix | subscribe |
| Input word | outerNext(v) and accumulator throws |
| Transition IDs | MS projectThrow row. The accumulator is the project passed to mergeInternals |
| Guards | throw is inside project, before any inner exists. Seed was not emitted |
| Notifications (Gamma) | error(e). No next |
| Lifecycle | destination error; finalizer sets state = null (mergeScan.ts:89) because teardown runs |
| Suffix | terminal_error; distinct from outerError and innerError |
| End state | terminal_error |
| Oracle | source characterization: accumulator throw is projectThrow, distinct from outerError and innerError. It is not a resultSelector; mergeScan has no resultSelector parameter |
| Source characterization | mergeScan.ts:82; mergeInternals.ts:71; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **32**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/32**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| MS-01 | not executed | static reading only; no runner |
| MS-02 | not executed | static reading only; no runner |
| MS-03 | not executed | static reading only; no runner |
| MS-04 | not executed | static reading only; no runner |
| MS-05 | not executed | static reading only; no runner |
| MS-06 | not executed | static reading only; no runner |
| MS-07 | not executed | static reading only; no runner |
| MS-08 | not executed | static reading only; no runner |
| MS-09 | not executed | static reading only; no runner |
| MS-10 | not executed | static reading only; no runner |
| MS-11 | not executed | static reading only; no runner |
| MS-12 | not executed | static reading only; no runner |
| MS-13 | not executed | static reading only; no runner |
| MS-14 | not executed | static reading only; no runner |
| MS-15 | not executed | static reading only; no runner |
| MS-16 | not executed | static reading only; no runner |
| MS-17 | not executed | static reading only; no runner |
| MS-18 | not executed | static reading only; no runner |
| MS-19 | not executed | static reading only; no runner |
| MS-20 | not executed | static reading only; no runner |
| MS-21 | not executed | static reading only; no runner |
| MS-22 | not executed | static reading only; no runner |
| MS-23 | not executed | static reading only; no runner |
| MS-24 | not executed | static reading only; no runner |
| MS-25 | not executed | static reading only; no runner |
| MS-26 | not executed | static reading only; no runner |
| MS-27 | not executed | static reading only; no runner |
| MS-28 | not executed | static reading only; no runner |
| MS-29 | not executed | static reading only; no runner |
| MS-30 | not executed | static reading only; no runner |
| MS-31 | not executed | static reading only; no runner |
| MS-32 | not executed | static reading only; no runner |

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
| Limits | Merge concurrency with one shared accumulator cell. Seed not emitted. Queue samples state at dequeue. No resultSelector. scanInternals not used. Complete-wait. |

Documented limits:

- Does not import `scanInternals`. State is a closed-over variable plus `onBeforeNext`.
- Active-set bound: `concurrent`, default `Infinity` (unbounded). Not normalized when `< 1`.
- Queue versus drop: queues. The accumulator for a queued value runs later, against the then-current state.
- Concurrent inners share one state cell. Last inner next wins.
- Complete-wait: yes. The seed is not a completion value either.
- No `resultSelector` parameter.
- No tests were executed.

