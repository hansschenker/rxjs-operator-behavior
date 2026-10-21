# switchScan

`switchScan` is an accumulator whose inner is switched, not merged (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `switchScan.ts:24-49`). It does not import `scanInternals`. It closes over `state = seed` and calls `switchMap` with project `(value, index) => accumulator(state, value, index)` and with the deprecated `switchMap` resultSelector used only as an internal trick: `(_, innerValue) => (state = innerValue, innerValue)` (`switchScan.ts:36-42`). That selector is not a parameter of `switchScan`. The public signature is `(accumulator, seed)` only. The seed is not emitted. Because the callee is `switchMap`, a new source value unsubscribes the previous inner before the accumulator runs, nothing is queued, and state is whatever the last delivered inner value wrote, even if that inner was later switched away before completing. Outer complete waits for the latest inner only.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | switchScan(accumulator, seed). No resultSelector parameter. No concurrent parameter. The deprecated switchMap selector is an internal implementation detail (switchScan.ts:40-42) |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Call accumulator(state, value, index) on each source value, subscribe to the returned inner, unsubscribe any previous inner, emit each inner value, and store it as state. Complete when the source and the latest inner are done |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. No buffer. State value is an extra unbounded component |
| parameter domain | accumulator: (acc: R, value: T, index: number) => ObservableInput. seed: R, any value, held and not emitted |
| payload/error domain | Gamma nexts are inner values. Errors: outerError, innerError, accumulator throw (projectThrow). The internal selector is an assignment and return; it is not a user resultSelector |
| subscription boundary | switchMap's: unsubscribe previous, then call accumulator with the current state, then subscribe. The accumulator therefore does not run concurrently with an inner next of the inner it just replaced, because that inner is already unsubscribed |
| scheduler/tie ordering | None. State is updated inside the selector before subscriber.next (switchMap.ts:114 evaluates the selector as the argument of next) |
| callback assumptions | accumulator is synchronous and may throw. seed is not a sentinel. Finalizer sets state = null on teardown (switchScan.ts:45-48) and emits nothing |
| cleanup assumptions | Same as switchMap for complete-wait, error, and cancel. The operate finalizer clears state on any unsubscribe of the downstream subscriber, including complete |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Do not treat the internal selector as a public deprecated parameter of switchScan. scanInternals is not used. |

## B. Six-tuple

Order on a source value (`switchMap.ts:104` then the project at `switchScan.ts:39`): previous inner unsubscribed, then `accumulator(state, value, index)`. If the previous inner emitted nothing, state is still the older value or the seed. If it emitted, state is the last of those emissions, not rolled back on cancel. Inner values update state and are forwarded (`switchScan.ts:42`).

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with state: R and active set size <= 1 |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C |
| lambda | Section C. Seed is not lambda output |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| active_empty | subscribed; no current inner; isComplete=false | active set empty. Next outerNext will subscribe |
| slot_occupied | exactly one current inner id; isComplete=false | The switch slot. Not a queue. A new outerNext unsubscribes this id. This is the inner-running location. There is no separate at-capacity buffer location |
| draining | isComplete=true; the latest inner still current | Outer-completed. Only that inner can still emit. Nothing was queued behind it |
| terminal_complete / terminal_error / terminal_cancelled | stopped | no further Gamma |
| state | seed at subscribe; replaced by each inner next of the current inner via the internal selector | Not emitted as seed. A switched-away inner does not roll state back |

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

The internal selector does not change the payload: `next` carries the inner value. It only writes `state` first.

## C. Transition obligations

Same locations as switchMap, plus state. The public operator has no resultSelector rows for a user function. The one resultSelectorThrow row records the switchMap path the internal selector uses; the actual selector body does not throw unless assignment were to throw.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SS-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; inner=none; index=0; isComplete=false; state=seed not emitted | active_empty | epsilon | no inner. Bound on the active set is 1. There is no queue, so no at-capacity buffer location | T-SS-01 |
| SS-02 | active_empty | outerNext(v) / source | project/innerFrom succeeds. No previous inner | eps | index consumed; subscribe inner id; accumulator(state, v, index) is the project | slot_occupied | subscribe | exactly one inner. Sync inner notifications are later events | T-SS-02 |
| SS-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws (projectThrow / invalid input) | error(e) | no new inner | terminal_error | subscribe | terminal | T-SS-03 |
| SS-04 | slot_occupied | outerNext(v) / source | project/innerFrom of the new value succeeds. This is the switch. Not a queue and not a second concurrent inner | eps | unsubscribe the previous inner first (its complete handler does not run); then project; then subscribe the new id. Previous id must not deliver further notifications | slot_occupied | an inner was already live | only the new id is live. At-capacity-as-buffer is not applicable; the occupied slot is replaced | T-SS-04 |
| SS-05 | slot_occupied | outerNext(v) / source | previous inner is unsubscribed, then project or innerFrom throws | error(e) projectThrow | old inner already gone; new inner not subscribed; index consumed | terminal_error | slot was occupied | terminal; the failed value did not leave a live inner | T-SS-05 |
| SS-06 | slot_occupied | innerNext(id, x) / inner id | id is the current inner. Internal switchMap resultSelector assigns state=x then returns x. That selector is not a public switchScan parameter | next(x) | state:=x before downstream next | slot_occupied | current inner emitted | state is x even if this inner is later switched away before it completes | T-SS-06 |
| SS-07 | slot_occupied | innerNext(id, x) / inner id | internal selector throws (not expected for the comma-assignment used here, but the switchMap path would error) | error(e) resultSelectorThrow | unsubscribe current inner and outer | terminal_error | selector throw | terminal | T-SS-07 |
| SS-08 | slot_occupied | innerError(id, e) / inner id | id is current. No inner catch | error(e) | forward error; unsubscribe outer and that inner | terminal_error | slot occupied | terminal; no complete | T-SS-08 |
| SS-09 | slot_occupied | innerComplete(id) / inner id | id is current; outer still open | eps | innerSubscriber:=null | active_empty | slot occupied and source still live | next outerNext will subscribe a fresh inner | T-SS-09 |
| SS-10 | active_empty | inner*  | no current inner | eps | none | active_empty | subscribe or previous inner already completed | unreachable | T-SS-10 |
| SS-11 | active_empty | outerError(e) / source | source error, no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-SS-11 |
| SS-12 | slot_occupied | outerError(e) / source | source error while an inner is live | error(e) | unsubscribe that inner and the outer immediately | terminal_error | slot occupied | terminal; inner does not continue | T-SS-12 |
| SS-13 | active_empty | outerComplete / source | no current inner | complete | isComplete:=true; checkComplete succeeds | terminal_complete | active_empty | terminal complete | T-SS-13 |
| SS-14 | slot_occupied | outerComplete / source | an inner is still current | eps | isComplete:=true; unsubscribe source only; keep the latest inner. Older inners are already unsubscribed | draining | slot occupied | wait for that one inner. There is nothing queued behind it | T-SS-14 |
| SS-15 | draining | innerNext(id, x) / inner id | id is still the latest inner | next(x) and state:=x | forward | draining | outerComplete with inner live | still waiting for this inner's complete | T-SS-15 |
| SS-16 | draining | innerError(id, e) / inner id | latest inner errors | error(e) | unsubscribe it | terminal_error | draining | terminal; no complete | T-SS-16 |
| SS-17 | draining | innerComplete(id) / inner id | latest inner completes and isComplete | complete | innerSubscriber:=null; checkComplete | terminal_complete | draining | terminal complete | T-SS-17 |
| SS-18 | draining | outerNext / outerError / outerComplete | source already unsubscribed | eps | none | draining | outerComplete consumed | not enabled | T-SS-18 |
| SS-19 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete; switchScan finalizer sets state=null | terminal_cancelled | active_empty | terminal silent | T-SS-19 |
| SS-20 | slot_occupied | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete; switchScan finalizer sets state=null | terminal_cancelled | slot_occupied | terminal silent | T-SS-20 |
| SS-21 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete; switchScan finalizer sets state=null | terminal_cancelled | draining | terminal silent | T-SS-21 |
| SS-22 | slot_occupied | outerNext then sync inner | ordering constraint: unsubscribe previous, subscribe next, then that inner's synchronous innerNext/innerComplete are separate Sigma events before any later outerNext | per those events | if the sync inner completes, location returns to active_empty before the next source value | as those events specify | slot occupied or empty | not downstream reentry | T-SS-22 |
| SS-23 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-SS-23 |

switchScan.ts:33-43 subscribes the switchMap observable with the same downstream subscriber. The returned finalizer is an additional teardown, not a second subscription to the source.

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
| I9 | seed is not emitted on subscribe | switchScan.ts:31; switchMap does not next the seed |
| I10 | state is updated on inner values only, before they are forwarded | switchScan.ts:42; switchMap.ts:114 |
| I11 | Switching does not restore the previous state | no code writes state except the selector and the finalizer |
| I12 | No user-facing resultSelector and no concurrent argument | switchScan.ts:24-27 |
| I13 | Complete-wait is switchMap's latest-inner rule | switchMap.ts:97 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-SS-1 switchScan: seed hidden, first inner updates state

| Field | Value |
| --- | --- |
| Scenario ID | E-SS-1 |
| Title | switchScan: seed hidden, first inner updates state |
| Parameters | seed = 0; accumulator (acc, v) => of(acc + v) |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(2), innerNext(id, 2), innerComplete(id), outerComplete |
| Transition IDs | SS subscribe (no next), SS empty outerNext, SS innerNext, SS innerComplete, SS empty outerComplete |
| Guards | accumulator(0, 2, 0) runs because the slot was empty. Selector sets state = 2 |
| Notifications (Gamma) | next(2), complete. Not next(0) |
| Lifecycle | one inner |
| Suffix | terminal_complete; state cleared by finalizer after complete's unsubscribe |
| End state | terminal_complete |
| Oracle | source characterization: seed is not a next. This matches the informal 'like mergeScan but switched' doc without emitting the seed |
| Source characterization | switchScan.ts:31-43; switchMap.ts:114 |

### E-SS-2 switchScan: new source value cancels the inner and accumulates from the last emitted state

| Field | Value |
| --- | --- |
| Scenario ID | E-SS-2 |
| Title | switchScan: new source value cancels the inner and accumulates from the last emitted state |
| Parameters | seed = 0 |
| Start state | slot_occupied |
| Prefix | subscribe, outerNext(1), innerNext(id1, 10) so state is 10; id1 still open |
| Input word | outerNext(3) |
| Transition IDs | SS occupied outerNext |
| Guards | id1 unsubscribed first. accumulator(10, 3, nextIndex) then runs. State is not reverted to 0 and not left pending a queue |
| Notifications (Gamma) | eps for the outerNext itself; later innerNexts of the new inner are separate events |
| Lifecycle | unsub id1; sub id2 |
| Suffix | id2 live; state still 10 until id2 emits |
| End state | slot_occupied |
| Oracle | source characterization: switch, do not queue, do not roll back state |
| Source characterization | switchMap.ts:104-108; switchScan.ts:39-42 |

### E-SS-3 switchScan: outer complete waits for the latest inner

| Field | Value |
| --- | --- |
| Scenario ID | E-SS-3 |
| Title | switchScan: outer complete waits for the latest inner |
| Parameters | any seed |
| Start state | slot_occupied |
| Prefix | latest inner live; state = last emission |
| Input word | outerComplete, innerNext(id, x), innerComplete(id) |
| Transition IDs | SS draining rows |
| Guards | checkComplete |
| Notifications (Gamma) | next(x), complete. state becomes x before next(x) |
| Lifecycle | source unsubscribed; latest inner kept |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization via switchMap complete rule |
| Source characterization | switchMap.ts:97 and 125-128 |

### E-SS-4 switchScan: accumulator throw and cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-SS-4 |
| Title | switchScan: accumulator throw and cancel |
| Parameters | accumulator throws |
| Start state | active_empty or slot_occupied |
| Prefix | subscribed |
| Input word | outerNext(v) with accumulator throwing; separately cancel |
| Transition IDs | SS projectThrow row; SS cancel row |
| Guards | on an occupied slot the previous inner is already unsubscribed. State is not updated because the internal selector never runs |
| Notifications (Gamma) | error(e); or eps |
| Lifecycle | teardown. Finalizer nulls state. Cancel does not complete |
| Suffix | terminal |
| End state | terminal |
| Oracle | source characterization: accumulator throw is projectThrow, not a public resultSelector throw and not outerError |
| Source characterization | switchScan.ts:39 and 45-48; switchMap.ts:104-108 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **23**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/23**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| SS-01 | not executed | static reading only; no runner |
| SS-02 | not executed | static reading only; no runner |
| SS-03 | not executed | static reading only; no runner |
| SS-04 | not executed | static reading only; no runner |
| SS-05 | not executed | static reading only; no runner |
| SS-06 | not executed | static reading only; no runner |
| SS-07 | not executed | static reading only; no runner |
| SS-08 | not executed | static reading only; no runner |
| SS-09 | not executed | static reading only; no runner |
| SS-10 | not executed | static reading only; no runner |
| SS-11 | not executed | static reading only; no runner |
| SS-12 | not executed | static reading only; no runner |
| SS-13 | not executed | static reading only; no runner |
| SS-14 | not executed | static reading only; no runner |
| SS-15 | not executed | static reading only; no runner |
| SS-16 | not executed | static reading only; no runner |
| SS-17 | not executed | static reading only; no runner |
| SS-18 | not executed | static reading only; no runner |
| SS-19 | not executed | static reading only; no runner |
| SS-20 | not executed | static reading only; no runner |
| SS-21 | not executed | static reading only; no runner |
| SS-22 | not executed | static reading only; no runner |
| SS-23 | not executed | static reading only; no runner |

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
| Limits | switchMap plus one state cell. Bound 1. No queue. Seed not emitted. No public resultSelector. scanInternals not imported. Complete-wait is the latest inner. |

Documented limits:

- Built on `switchMap`, not on `scanInternals` and not on `mergeInternals`.
- Active-set bound: 1. Previous inner is unsubscribed. No FIFO.
- State is the last forwarded inner value, or the seed if none. Switching does not roll it back.
- Complete-wait: latest inner only.
- The internal `resultSelector` is not a user parameter and is not a deprecated part of this signature. `switchMap`'s selector parameter is what is deprecated.
- Seed is not emitted.
- No tests were executed.

