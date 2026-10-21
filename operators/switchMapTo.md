# switchMapTo

`switchMapTo` is a deprecated wrapper, not a const alias (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `switchMapTo.ts:59-64`). It returns `switchMap(() => innerObservable, resultSelector)` when the second argument is a function, otherwise `switchMap(() => innerObservable)`. The operator is deprecated for removal in v9 (`switchMapTo.ts:5` and `57`). The `resultSelector` overload is deprecated for removal in v8 (`switchMapTo.ts:7-11`). The forwarding contract is switch semantics on a constant projection: every accepted source value unsubscribes the previous subscription and subscribes again to the same `ObservableInput`. Nothing is queued. The source value is ignored by the projection.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | Deprecated switchMapTo(observable). Deprecated selector overloads. Operator removal v9. resultSelector removal v8. No concurrent argument |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | On each source value, resubscribe to the same inner ObservableInput and dispose the previous subscription. Emit only the latest subscription's values |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. No buffer. Same as switchMap |
| parameter domain | innerObservable: ObservableInput. Optional deprecated resultSelector. The projection closes over innerObservable and ignores T |
| payload/error domain | Output from the shared input, or selector results. Errors as switchMap. A bad innerObservable throws on each accept via innerFrom, after the previous inner was unsubscribed |
| subscription boundary | Each source value, including ones that arrive while a subscription is open, starts a new subscription. There is no drop and no queue |
| scheduler/tie ordering | Same order as switchMap: unsubscribe, then project (constant), then subscribe |
| callback assumptions | Constant project does not throw. Selector may. Resubscribe semantics are innerFrom's: cold restarts, hot does not replay |
| cleanup assumptions | Same complete-wait as switchMap: only the latest subscription. Cancel silent |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |

## B. Six-tuple

No local state in switchMapTo.ts. The six-tuple is switchMap's, with project fixed. Argument normalization is `isFunction` (`switchMapTo.ts:63`), unlike switchMap's internal truthy check, but both treat a function as the selector and the absence of one as the plain path.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = switchMap with a constant project |
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

Replacement policy, not a queue. At-capacity buffer is not a state. slot_occupied is the single live subscription to innerObservable.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SWT-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; inner=none; index=0; isComplete=false | active_empty | epsilon | no inner. Bound on the active set is 1. There is no queue, so no at-capacity buffer location | T-SWT-01 |
| SWT-02 | active_empty | outerNext(v) / source | project/innerFrom succeeds. No previous inner | eps | index consumed; subscribe inner id; project is () => innerObservable, ignoring v | slot_occupied | subscribe | exactly one inner. Sync inner notifications are later events | T-SWT-02 |
| SWT-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws (projectThrow / invalid input) | error(e) | no new inner | terminal_error | subscribe | terminal | T-SWT-03 |
| SWT-04 | slot_occupied | outerNext(v) / source | project/innerFrom of the new value succeeds. This is the switch. Not a queue and not a second concurrent inner | eps | unsubscribe the previous inner first (its complete handler does not run); then project; then subscribe the new id. Previous id must not deliver further notifications | slot_occupied | an inner was already live | only the new id is live. At-capacity-as-buffer is not applicable; the occupied slot is replaced | T-SWT-04 |
| SWT-05 | slot_occupied | outerNext(v) / source | previous inner is unsubscribed, then project or innerFrom throws | error(e) projectThrow | old inner already gone; new inner not subscribed; index consumed | terminal_error | slot was occupied | terminal; the failed value did not leave a live inner | T-SWT-05 |
| SWT-06 | slot_occupied | innerNext(id, x) / inner id | id is current; resultSelector absent | next(x) | forward | slot_occupied | current inner | same id live | T-SWT-06 |
| SWT-07 | slot_occupied | innerNext(id, x) / inner id | deprecated resultSelector returns r | next(r) | innerIndex increments as an argument of the selector | slot_occupied | selector overload | raw x hidden | T-SWT-07 |
| SWT-08 | slot_occupied | innerNext(id, x) / inner id | resultSelector throws (resultSelectorThrow), distinct from innerError | error(e) | custom inner onNext catch calls destination.error; unsubscribe inners and outer | terminal_error | selector overload | terminal; no complete | T-SWT-08 |
| SWT-09 | slot_occupied | innerError(id, e) / inner id | id is current. No inner catch | error(e) | forward error; unsubscribe outer and that inner | terminal_error | slot occupied | terminal; no complete | T-SWT-09 |
| SWT-10 | slot_occupied | innerComplete(id) / inner id | id is current; outer still open | eps | innerSubscriber:=null | active_empty | slot occupied and source still live | next outerNext will subscribe a fresh inner | T-SWT-10 |
| SWT-11 | active_empty | inner*  | no current inner | eps | none | active_empty | subscribe or previous inner already completed | unreachable | T-SWT-11 |
| SWT-12 | active_empty | outerError(e) / source | source error, no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-SWT-12 |
| SWT-13 | slot_occupied | outerError(e) / source | source error while an inner is live | error(e) | unsubscribe that inner and the outer immediately | terminal_error | slot occupied | terminal; inner does not continue | T-SWT-13 |
| SWT-14 | active_empty | outerComplete / source | no current inner | complete | isComplete:=true; checkComplete succeeds | terminal_complete | active_empty | terminal complete | T-SWT-14 |
| SWT-15 | slot_occupied | outerComplete / source | an inner is still current | eps | isComplete:=true; unsubscribe source only; keep the latest inner. Older inners are already unsubscribed | draining | slot occupied | wait for that one inner. There is nothing queued behind it | T-SWT-15 |
| SWT-16 | draining | innerNext(id, x) / inner id | id is still the latest inner | next(x) | forward | draining | outerComplete with inner live | still waiting for this inner's complete | T-SWT-16 |
| SWT-17 | draining | innerError(id, e) / inner id | latest inner errors | error(e) | unsubscribe it | terminal_error | draining | terminal; no complete | T-SWT-17 |
| SWT-18 | draining | innerComplete(id) / inner id | latest inner completes and isComplete | complete | innerSubscriber:=null; checkComplete | terminal_complete | draining | terminal complete | T-SWT-18 |
| SWT-19 | draining | outerNext / outerError / outerComplete | source already unsubscribed | eps | none | draining | outerComplete consumed | not enabled | T-SWT-19 |
| SWT-20 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-SWT-20 |
| SWT-21 | slot_occupied | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | slot_occupied | terminal silent | T-SWT-21 |
| SWT-22 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | draining | terminal silent | T-SWT-22 |
| SWT-23 | slot_occupied | outerNext then sync inner | ordering constraint: unsubscribe previous, subscribe next, then that inner's synchronous innerNext/innerComplete are separate Sigma events before any later outerNext | per those events | if the sync inner completes, location returns to active_empty before the next source value | as those events specify | slot occupied or empty | not downstream reentry | T-SWT-23 |
| SWT-24 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-SWT-24 |

Two deprecations stack: the selector (v8) and the operator (v9).

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
| I9 | Every accept projects to the same ObservableInput | switchMapTo.ts:63 |
| I10 | No concurrent parameter is forwarded | switchMap has none |
| I11 | resultSelector deprecation is on this file's overloads as well as on switchMap | switchMapTo.ts:7-15 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-SWT-1 switchMapTo: each source value resubscribes

| Field | Value |
| --- | --- |
| Scenario ID | E-SWT-1 |
| Title | switchMapTo: each source value resubscribes |
| Parameters | switchMapTo(innerObservable), no selector |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id1, a), outerNext(v2), innerNext(id2, b), innerComplete(id2), outerComplete |
| Transition IDs | SWT empty outerNext, SWT innerNext, SWT occupied outerNext (switch), SWT draining or empty complete |
| Guards | second outerNext unsubscribes id1 even though the projected input is the same reference |
| Notifications (Gamma) | next(a), next(b), complete |
| Lifecycle | two subscriptions, not overlapping |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract: most recent subscription only (switchMapTo.ts:29-31) |
| Source characterization | switchMapTo.ts:63; switchMap.ts:104-108 |

### E-SWT-2 switchMapTo: no queue while the latest subscription is open

| Field | Value |
| --- | --- |
| Scenario ID | E-SWT-2 |
| Title | switchMapTo: no queue while the latest subscription is open |
| Parameters | no selector |
| Start state | slot_occupied |
| Prefix | id1 live |
| Input word | outerNext(v2), outerNext(v3) |
| Transition IDs | SWT occupied outerNext twice |
| Guards | each one unsubscribes the previous. v2's subscription is itself unsubscribed by v3. Neither value is stored |
| Notifications (Gamma) | eps from the outerNexts themselves |
| Lifecycle | id1 unsub, id2 sub, id2 unsub, id3 sub |
| Suffix | only id3 live |
| End state | slot_occupied |
| Oracle | source characterization: switch, not concat's queue and not exhaust's drop-and-keep |
| Source characterization | switchMap.ts:103-108 |

### E-SWT-3 switchMapTo: outer complete waits for the latest resubscription

| Field | Value |
| --- | --- |
| Scenario ID | E-SWT-3 |
| Title | switchMapTo: outer complete waits for the latest resubscription |
| Parameters | no selector |
| Start state | slot_occupied |
| Prefix | latest id live |
| Input word | outerComplete, innerNext(id, x), innerComplete(id) |
| Transition IDs | SWT draining rows |
| Guards | checkComplete |
| Notifications (Gamma) | next(x), complete |
| Lifecycle | source gone; latest inner kept |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | same wait-for-latest rule as switchMap |
| Source characterization | switchMap.ts:97 and 125-128 |

### E-SWT-4 switchMapTo: selector throw and cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-SWT-4 |
| Title | switchMapTo: selector throw and cancel |
| Parameters | deprecated resultSelector on one word; plain cancel on another |
| Start state | slot_occupied |
| Prefix | subscription live |
| Input word | innerNext with throwing selector; separately cancel |
| Transition IDs | SWT resultSelectorThrow; SWT cancel |
| Guards | selector forwarded by switchMapTo.ts:63 into switchMap.ts:114 |
| Notifications (Gamma) | error(e); or eps for cancel |
| Lifecycle | full unsubscribe |
| Suffix | terminal |
| End state | terminal |
| Oracle | selector deprecated v8; operator deprecated v9; cancel is not complete |
| Source characterization | switchMapTo.ts:5-15 and 63 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **24**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/24**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| SWT-01 | not executed | static reading only; no runner |
| SWT-02 | not executed | static reading only; no runner |
| SWT-03 | not executed | static reading only; no runner |
| SWT-04 | not executed | static reading only; no runner |
| SWT-05 | not executed | static reading only; no runner |
| SWT-06 | not executed | static reading only; no runner |
| SWT-07 | not executed | static reading only; no runner |
| SWT-08 | not executed | static reading only; no runner |
| SWT-09 | not executed | static reading only; no runner |
| SWT-10 | not executed | static reading only; no runner |
| SWT-11 | not executed | static reading only; no runner |
| SWT-12 | not executed | static reading only; no runner |
| SWT-13 | not executed | static reading only; no runner |
| SWT-14 | not executed | static reading only; no runner |
| SWT-15 | not executed | static reading only; no runner |
| SWT-16 | not executed | static reading only; no runner |
| SWT-17 | not executed | static reading only; no runner |
| SWT-18 | not executed | static reading only; no runner |
| SWT-19 | not executed | static reading only; no runner |
| SWT-20 | not executed | static reading only; no runner |
| SWT-21 | not executed | static reading only; no runner |
| SWT-22 | not executed | static reading only; no runner |
| SWT-23 | not executed | static reading only; no runner |
| SWT-24 | not executed | static reading only; no runner |

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
| Limits | Forwards switchMap. No queue. Complete-wait for the latest inner only. Operator deprecated v9. resultSelector deprecated v8. |

Documented limits:

- Wrapper: `switchMap(() => innerObservable)` plus optional deprecated selector.
- Active-set bound: 1 by unsubscribe, not by queueing.
- Queue versus drop: neither. Previous subscription is cancelled; the next one starts immediately.
- Complete-wait: latest inner only.
- `resultSelector` deprecated (v8). Operator deprecated (v9).
- No tests were executed.

