# switchMap

`switchMap` projects each source value to an inner and emits only from the most recent one (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `switchMap.ts:85-131`). It does not use `mergeInternals`. On every source value it unsubscribes the previous inner (`switchMap.ts:104`), then subscribes to `innerFrom(project(value, outerIndex))` (`switchMap.ts:108`). There is no queue and no concurrent argument. The active set is bounded by 1 because the previous inner is dropped, not because values wait. `resultSelector` is still an optional second parameter and is deprecated for removal in v8 (`switchMap.ts:11-20`). The implementation applies it inline on inner next (`switchMap.ts:112-114`) rather than by calling `map`, which the comment says is smaller. The output completes only when the source has completed and there is no current inner (`switchMap.ts:95-97`).

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | switchMap(project). Deprecated: switchMap(project, undefined) and switchMap(project, resultSelector), removal of the selector in v8 (switchMap.ts:11-20). No concurrent parameter |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | On each source value, cancel the previous inner and subscribe to the new projection. Forward that inner's values, or the deprecated selector's results. When the source completes, wait only for the latest inner if one is active, then complete. Any error fails immediately |
| model kind | Extended/symbolic Mealy machine. Active-set bound is 1. No buffer. Still not finite, because values and indexes are unbounded. At-capacity-as-queue is not a location; the occupied slot is replaced |
| parameter domain | project: (T, index) => ObservableInput. resultSelector optional deprecated function (outer, inner, outerIndex, innerIndex) => R |
| payload/error domain | Output is ObservedValueOf or selector result. Errors: outerError, innerError, projectThrow (after the previous inner was already unsubscribed), resultSelectorThrow |
| subscription boundary | One outer subscription. At most one inner. Switching unsubscribes the old inner without emitting complete for it. The new inner is a new id |
| scheduler/tie ordering | None. Unsubscribe, then project, then subscribe, in that order (switchMap.ts:104-123). Synchronous notifications from the new inner are the next Sigma events and can clear the slot before the next source value |
| callback assumptions | project and resultSelector are synchronous. resultSelector is invoked as resultSelector(value, innerValue, outerIndex, innerIndex++) only when it is truthy (switchMap.ts:114). Index increments even if the selector then throws |
| cleanup assumptions | Outer complete leaves the latest inner in place (draining). Outer error unsubscribes it and errors. Inner error does the same. Cancel unsubscribes both and does not complete. The inner complete handler sets innerSubscriber = null; unsubscribe of a replaced inner does not run that handler |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). No hidden queue of the values that were switched away. |

## B. Six-tuple

Data is `(inner: none | id, index: nat, isComplete: bool, outerValue and outerIndex captured per inner, innerIndex)`. `checkComplete` is `isComplete && !innerSubscriber && subscriber.complete()` (`switchMap.ts:97`). The previous inner is unsubscribed before `project` (`switchMap.ts:104-108`), so a projectThrow leaves no inner at all.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0), active set size <= 1, no buffer component |
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
| active_empty | subscribed; no current inner; isComplete=false | active set empty. Next outerNext will subscribe |
| slot_occupied | exactly one current inner id; isComplete=false | The switch slot. Not a queue. A new outerNext unsubscribes this id. This is the inner-running location. There is no separate at-capacity buffer location |
| draining | isComplete=true; the latest inner still current | Outer-completed. Only that inner can still emit. Nothing was queued behind it |
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

Gamma records are `next(v)`, `error(e)`, `complete`, or `eps`, with the same mutual exclusion as the merge family. `complete` is emitted only by `checkComplete` when `isComplete` is set and `innerSubscriber` is null (`switchMap.ts:97`). The latest inner's values are the only `next` values. Unsubscribing a previous inner emits no Gamma. `cancel` emits `eps`.

## C. Transition obligations

Locations required by the brief: init, active with no inner, active with the inner running (`slot_occupied`), outer-completed draining, and terminals. At-capacity queue rows are intentionally absent; the slot_occupied outerNext row is the replacement policy, and it says so.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SW-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; inner=none; index=0; isComplete=false | active_empty | epsilon | no inner. Bound on the active set is 1. There is no queue, so no at-capacity buffer location | T-SW-01 |
| SW-02 | active_empty | outerNext(v) / source | project/innerFrom succeeds. No previous inner | eps | index consumed; subscribe inner id | slot_occupied | subscribe | exactly one inner. Sync inner notifications are later events | T-SW-02 |
| SW-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws (projectThrow / invalid input) | error(e) | no new inner | terminal_error | subscribe | terminal | T-SW-03 |
| SW-04 | slot_occupied | outerNext(v) / source | project/innerFrom of the new value succeeds. This is the switch. Not a queue and not a second concurrent inner | eps | unsubscribe the previous inner first (its complete handler does not run); then project; then subscribe the new id. Previous id must not deliver further notifications | slot_occupied | an inner was already live | only the new id is live. At-capacity-as-buffer is not applicable; the occupied slot is replaced | T-SW-04 |
| SW-05 | slot_occupied | outerNext(v) / source | previous inner is unsubscribed, then project or innerFrom throws | error(e) projectThrow | old inner already gone; new inner not subscribed; index consumed | terminal_error | slot was occupied | terminal; the failed value did not leave a live inner | T-SW-05 |
| SW-06 | slot_occupied | innerNext(id, x) / inner id | id is current; resultSelector absent | next(x) | forward | slot_occupied | current inner | same id live | T-SW-06 |
| SW-07 | slot_occupied | innerNext(id, x) / inner id | deprecated resultSelector returns r | next(r) | innerIndex increments as an argument of the selector | slot_occupied | selector overload | raw x hidden | T-SW-07 |
| SW-08 | slot_occupied | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow), distinct from innerError | error(e) | custom inner onNext catch calls destination.error; unsubscribe inners and outer | terminal_error | selector overload | terminal; no complete | T-SW-08 |
| SW-09 | slot_occupied | innerError(id, e) / inner id | id is current. No inner catch | error(e) | forward error; unsubscribe outer and that inner | terminal_error | slot occupied | terminal; no complete | T-SW-09 |
| SW-10 | slot_occupied | innerComplete(id) / inner id | id is current; outer still open | eps | innerSubscriber:=null | active_empty | slot occupied and source still live | next outerNext will subscribe a fresh inner | T-SW-10 |
| SW-11 | active_empty | inner*  | no current inner | eps | none | active_empty | subscribe or previous inner already completed | unreachable | T-SW-11 |
| SW-12 | active_empty | outerError(e) / source | source error, no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-SW-12 |
| SW-13 | slot_occupied | outerError(e) / source | source error while an inner is live | error(e) | unsubscribe that inner and the outer immediately | terminal_error | slot occupied | terminal; inner does not continue | T-SW-13 |
| SW-14 | active_empty | outerComplete / source | no current inner | complete | isComplete:=true; checkComplete succeeds | terminal_complete | active_empty | terminal complete | T-SW-14 |
| SW-15 | slot_occupied | outerComplete / source | an inner is still current | eps | isComplete:=true; unsubscribe source only; keep the latest inner. Older inners are already unsubscribed | draining | slot occupied | wait for that one inner. There is nothing queued behind it | T-SW-15 |
| SW-16 | draining | innerNext(id, x) / inner id | id is still the latest inner | next(x) | forward | draining | outerComplete with inner live | still waiting for this inner's complete | T-SW-16 |
| SW-17 | draining | innerError(id, e) / inner id | latest inner errors | error(e) | unsubscribe it | terminal_error | draining | terminal; no complete | T-SW-17 |
| SW-18 | draining | innerComplete(id) / inner id | latest inner completes and isComplete | complete | innerSubscriber:=null; checkComplete | terminal_complete | draining | terminal complete | T-SW-18 |
| SW-19 | draining | outerNext / outerError / outerComplete | source already unsubscribed | eps | none | draining | outerComplete consumed | not enabled | T-SW-19 |
| SW-20 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-SW-20 |
| SW-21 | slot_occupied | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | slot_occupied | terminal silent | T-SW-21 |
| SW-22 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | draining | terminal silent | T-SW-22 |
| SW-23 | slot_occupied | outerNext then sync inner | ordering constraint: unsubscribe previous, subscribe next, then that inner's synchronous innerNext/innerComplete are separate Sigma events before any later outerNext | per those events | if the sync inner completes, location returns to active_empty before the next source value | as those events specify | slot occupied or empty | not downstream reentry | T-SW-23 |
| SW-24 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-SW-24 |

innerIndex is local to the outer next handler (switchMap.ts:105) and therefore resets per inner. It advances only when the selector is called.

## D. Contract invariants

| ID | Invariant | Source |
| --- | --- | --- |
| I1 | At most one inner is current | switchMap.ts:90 and 104-108 |
| I2 | A new outerNext unsubscribes the previous inner before project runs | switchMap.ts:104 then 108 |
| I3 | No FIFO of outer values exists in this operator | switchMap.ts has no buffer |
| I4 | complete Gamma iff the source has completed and innerSubscriber is null | switchMap.ts:97 |
| I5 | Inner error and outer error fail the output and unsubscribe the current inner. No inner catch | no onError override on either createOperatorSubscriber |
| I6 | cancel emits eps and unsubscribes outer and the current inner | subscriber teardown |
| I7 | Unsubscribed inners are not modeled as still notifying | Subscriber isStopped |
| I8 | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |
| I9 | resultSelector is optional. Absent means the inner value is forwarded unchanged | switchMap.ts:114 |
| I10 | JSDoc deprecates resultSelector for v8 | switchMap.ts:11 and 16 |
| I11 | The latest inner continues after outer complete; older inners are already unsubscribed and do not resume | switchMap.ts:125-128 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-SW-1 switchMap: sync inners do not overlap

| Field | Value |
| --- | --- |
| Scenario ID | E-SW-1 |
| Title | switchMap: sync inners do not overlap |
| Parameters | no resultSelector |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(1), innerNext(id1,1), innerNext(id1,1), innerComplete(id1), outerNext(2), innerNext(id2,2), innerComplete(id2), outerComplete |
| Transition IDs | SW subscribe, SW empty outerNext, SW innerNext, SW innerComplete to empty, SW empty outerNext again, SW empty outerComplete |
| Guards | each inner completes before the next source value, so unsubscribe-previous is a no-op |
| Notifications (Gamma) | next(1), next(1), next(2) (and whatever else that inner emitted), complete |
| Lifecycle | sequential ids; never two live |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract example shape in switchMap.ts:48-59: each projection is flattened, and a completed inner does not survive the next source value |
| Source characterization | switchMap.ts:102-128 |

### E-SW-2 switchMap: a new outer value unsubscribes the previous inner and does not queue it

| Field | Value |
| --- | --- |
| Scenario ID | E-SW-2 |
| Title | switchMap: a new outer value unsubscribes the previous inner and does not queue it |
| Parameters | no selector |
| Start state | s0 |
| Prefix | subscribe, outerNext(v1), id1 live and has emitted a |
| Input word | outerNext(v2), innerNext(id2, b), and no further notification from id1 |
| Transition IDs | SW slot_occupied outerNext row; SW innerNext row |
| Guards | id1.unsubscribe() runs before project(v2). id1's complete handler does not run |
| Notifications (Gamma) | next(b) only, after the prefix's next(a). No next from id1 after the switch |
| Lifecycle | unsub id1; sub id2 |
| Suffix | only id2 live; v1 has no queued continuation |
| End state | slot_occupied |
| Oracle | contract: switchMap stops emitting from the earlier inner (switchMap.ts:36-39). Source characterization: it does not remember v1 |
| Source characterization | switchMap.ts:103-108 |

### E-SW-3 switchMap: outer complete waits for the latest inner only

| Field | Value |
| --- | --- |
| Scenario ID | E-SW-3 |
| Title | switchMap: outer complete waits for the latest inner only |
| Parameters | no selector |
| Start state | slot_occupied |
| Prefix | subscribe, outerNext(v1), id1 live; an earlier id0 was already unsubscribed |
| Input word | outerComplete, innerNext(id1, z), innerComplete(id1) |
| Transition IDs | SW outerComplete while occupied; SW draining innerNext; SW draining innerComplete |
| Guards | isComplete && innerSubscriber keeps checkComplete false until the inner completes |
| Notifications (Gamma) | next(z), complete |
| Lifecycle | source unsubscribed; id1 kept; id0 stays dead |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization: switch waits for the latest inner if one is active, and does not wait for inners it already unsubscribed |
| Source characterization | switchMap.ts:95-97 and 125-128 |

### E-SW-4 switchMap: inner error and cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-SW-4 |
| Title | switchMap: inner error and cancel |
| Parameters | no selector |
| Start state | slot_occupied |
| Prefix | id1 live |
| Input word | first word: innerError(id1, e). second word from a fresh subscribe: cancel |
| Transition IDs | SW innerError row; SW cancel row |
| Guards | no onError callback |
| Notifications (Gamma) | first word: error(e). second word: eps |
| Lifecycle | both words unsubscribe the inner and the outer. cancel does not complete |
| Suffix | terminal_error or terminal_cancelled |
| End state | terminal |
| Oracle | source characterization: inner error fails the outer; cancel is not complete |
| Source characterization | switchMap.ts:109-114 uses default error path; Subscriber.ts:116-121 and 104-110 |

### E-SW-5 switchMap: project throw after switching, and resultSelector throw

| Field | Value |
| --- | --- |
| Scenario ID | E-SW-5 |
| Title | switchMap: project throw after switching, and resultSelector throw |
| Parameters | one word with a throwing project; one word with a deprecated selector that throws |
| Start state | slot_occupied |
| Prefix | id1 live |
| Input word | outerNext(v2) with project throwing; separately, innerNext with resultSelector throwing |
| Transition IDs | SW projectThrow-while-occupied row; SW resultSelectorThrow row |
| Guards | unsubscribe of id1 already happened before project threw. Selector throw is inside the inner next wrapper |
| Notifications (Gamma) | error(e) in each word. No next of the failed projection |
| Lifecycle | no new inner on projectThrow; selector path unsubscribes the current inner |
| Suffix | terminal_error. Distinct from outerError and from innerError |
| End state | terminal_error |
| Oracle | JSDoc: resultSelector deprecated (switchMap.ts:11-20). Both throws are user-callback outcomes |
| Source characterization | switchMap.ts:104-114; OperatorSubscriber.ts:67-74 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **24**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/24**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| SW-01 | not executed | static reading only; no runner |
| SW-02 | not executed | static reading only; no runner |
| SW-03 | not executed | static reading only; no runner |
| SW-04 | not executed | static reading only; no runner |
| SW-05 | not executed | static reading only; no runner |
| SW-06 | not executed | static reading only; no runner |
| SW-07 | not executed | static reading only; no runner |
| SW-08 | not executed | static reading only; no runner |
| SW-09 | not executed | static reading only; no runner |
| SW-10 | not executed | static reading only; no runner |
| SW-11 | not executed | static reading only; no runner |
| SW-12 | not executed | static reading only; no runner |
| SW-13 | not executed | static reading only; no runner |
| SW-14 | not executed | static reading only; no runner |
| SW-15 | not executed | static reading only; no runner |
| SW-16 | not executed | static reading only; no runner |
| SW-17 | not executed | static reading only; no runner |
| SW-18 | not executed | static reading only; no runner |
| SW-19 | not executed | static reading only; no runner |
| SW-20 | not executed | static reading only; no runner |
| SW-21 | not executed | static reading only; no runner |
| SW-22 | not executed | static reading only; no runner |
| SW-23 | not executed | static reading only; no runner |
| SW-24 | not executed | static reading only; no runner |

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
| Limits | Active bound 1 by replacement, not by a queue. Complete-wait is only the latest inner. resultSelector deprecated. No concurrent parameter. |

Documented limits:

- Active-set bound: 1. No FIFO. Switched-away inners are unsubscribed.
- Queue versus drop: neither. The previous subscription is cancelled.
- Complete-wait: if a latest inner exists when the source completes, the output waits for it. Otherwise it completes immediately.
- `resultSelector` is in the signature and JSDoc-deprecated for v8.
- A throwing project still unsubscribes the previous inner first.
- No tests were executed.

