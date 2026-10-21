# switchAll

`switchAll` flattens a higher-order source by keeping only the latest inner (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The body is `return switchMap(identity)` (`switchAll.ts:63-65`). `identity` (`identity.ts:43-45`) means the source value is the `ObservableInput`. There is no `resultSelector` and no concurrent argument. The JSDoc states the completion rule that the code implements: the result completes only if the source completes and any currently subscribed inner has also completed (`switchAll.ts:17-19`). A new inner unsubscribes the previous one. Inners are not queued and are not held until the outer completes.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | switchAll(): OperatorFunction<O, ObservedValueOf<O>>. No parameters |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Subscribe to each inner ObservableInput emitted by the source, unsubscribing from the previous one. Emit that inner's values. Complete when the source and the current inner (if any) are complete |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. No buffer |
| parameter domain | None. project is identity. No resultSelector |
| payload/error domain | Source payload is ObservableInput<T>. Output is T. A bad payload throws from innerFrom after the previous inner was unsubscribed, which is a project/convert throw, not outerError |
| subscription boundary | Subscribe on arrival, not on outer complete. At most one inner. The previous inner is unsubscribed first |
| scheduler/tie ordering | Same as switchMap. No scheduler |
| callback assumptions | identity does not throw. innerFrom may |
| cleanup assumptions | Draining keeps only the latest inner. Error fails immediately. Cancel is silent |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Selector rows of switchMap are not reachable: switchAll passes one argument. |

## B. Six-tuple

Forwarding: switchMap(identity). The occupied slot holds the latest higher-order value's subscription. There is still no queue, so a burst of inners leaves only the last one subscribed; the others are unsubscribed if they had been subscribed, and if a later value arrives synchronously during the previous subscribe's sync emissions, those are ordered events that can switch again before the turn ends.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = switchMap with identity |
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

No selector rows. At-capacity queue is not used. slot_occupied means one inner Observable is subscribed.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; inner=none; index=0; isComplete=false | active_empty | epsilon | no inner. Bound on the active set is 1. There is no queue, so no at-capacity buffer location | T-SA-01 |
| SA-02 | active_empty | outerNext(v) / source | project/innerFrom succeeds. No previous inner | eps | index consumed; subscribe inner id; project is identity, so v itself must be an ObservableInput | slot_occupied | subscribe | exactly one inner. Sync inner notifications are later events | T-SA-02 |
| SA-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws (projectThrow / invalid input) | error(e) | no new inner | terminal_error | subscribe | terminal | T-SA-03 |
| SA-04 | slot_occupied | outerNext(v) / source | project/innerFrom of the new value succeeds. This is the switch. Not a queue and not a second concurrent inner | eps | unsubscribe the previous inner first (its complete handler does not run); then project; then subscribe the new id. Previous id must not deliver further notifications | slot_occupied | an inner was already live | only the new id is live. At-capacity-as-buffer is not applicable; the occupied slot is replaced | T-SA-04 |
| SA-05 | slot_occupied | outerNext(v) / source | previous inner is unsubscribed, then project or innerFrom throws | error(e) projectThrow | old inner already gone; new inner not subscribed; index consumed | terminal_error | slot was occupied | terminal; the failed value did not leave a live inner | T-SA-05 |
| SA-06 | slot_occupied | innerNext(id, x) / inner id | id is the current inner. identity projection; no resultSelector parameter on this operator | next(x) | forward | slot_occupied | current inner | same id live | T-SA-06 |
| SA-07 | slot_occupied | innerError(id, e) / inner id | id is current. No inner catch | error(e) | forward error; unsubscribe outer and that inner | terminal_error | slot occupied | terminal; no complete | T-SA-07 |
| SA-08 | slot_occupied | innerComplete(id) / inner id | id is current; outer still open | eps | innerSubscriber:=null | active_empty | slot occupied and source still live | next outerNext will subscribe a fresh inner | T-SA-08 |
| SA-09 | active_empty | inner*  | no current inner | eps | none | active_empty | subscribe or previous inner already completed | unreachable | T-SA-09 |
| SA-10 | active_empty | outerError(e) / source | source error, no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-SA-10 |
| SA-11 | slot_occupied | outerError(e) / source | source error while an inner is live | error(e) | unsubscribe that inner and the outer immediately | terminal_error | slot occupied | terminal; inner does not continue | T-SA-11 |
| SA-12 | active_empty | outerComplete / source | no current inner | complete | isComplete:=true; checkComplete succeeds | terminal_complete | active_empty | terminal complete | T-SA-12 |
| SA-13 | slot_occupied | outerComplete / source | an inner is still current | eps | isComplete:=true; unsubscribe source only; keep the latest inner. Older inners are already unsubscribed | draining | slot occupied | wait for that one inner. There is nothing queued behind it | T-SA-13 |
| SA-14 | draining | innerNext(id, x) / inner id | id is still the latest inner | next(x) | forward | draining | outerComplete with inner live | still waiting for this inner's complete | T-SA-14 |
| SA-15 | draining | innerError(id, e) / inner id | latest inner errors | error(e) | unsubscribe it | terminal_error | draining | terminal; no complete | T-SA-15 |
| SA-16 | draining | innerComplete(id) / inner id | latest inner completes and isComplete | complete | innerSubscriber:=null; checkComplete | terminal_complete | draining | terminal complete | T-SA-16 |
| SA-17 | draining | outerNext / outerError / outerComplete | source already unsubscribed | eps | none | draining | outerComplete consumed | not enabled | T-SA-17 |
| SA-18 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-SA-18 |
| SA-19 | slot_occupied | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | slot_occupied | terminal silent | T-SA-19 |
| SA-20 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the current inner if any; no complete | terminal_cancelled | draining | terminal silent | T-SA-20 |
| SA-21 | slot_occupied | outerNext then sync inner | ordering constraint: unsubscribe previous, subscribe next, then that inner's synchronous innerNext/innerComplete are separate Sigma events before any later outerNext | per those events | if the sync inner completes, location returns to active_empty before the next source value | as those events specify | slot occupied or empty | not downstream reentry | T-SA-21 |
| SA-22 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-SA-22 |

switchAll.ts:17-19 matches checkComplete in the callee. Higher-order subscribe-on-arrival is the opposite of joinAllInternals.

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
| I9 | project is identity | switchAll.ts:64 |
| I10 | No resultSelector parameter | switchAll.ts:63-65 |
| I11 | Completion requires the source and the current inner, not any previous inner | switchAll.ts:17-19 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-SA-1 switchAll: only the latest inner is subscribed

| Field | Value |
| --- | --- |
| Scenario ID | E-SA-1 |
| Title | switchAll: only the latest inner is subscribed |
| Parameters | switchAll() |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), innerNext(id1, a), outerNext(in2), innerNext(id2, b) |
| Transition IDs | SA empty outerNext; SA innerNext; SA occupied outerNext; SA innerNext |
| Guards | identity. in1 is unsubscribed before in2 is subscribed |
| Notifications (Gamma) | next(a), next(b) |
| Lifecycle | unsub id1; sub id2 |
| Suffix | only id2 live |
| End state | slot_occupied |
| Oracle | contract switchAll.ts:13-19 |
| Source characterization | switchAll.ts:64; switchMap.ts:104-108 |

### E-SA-2 switchAll: no queue of pending inners

| Field | Value |
| --- | --- |
| Scenario ID | E-SA-2 |
| Title | switchAll: no queue of pending inners |
| Parameters | switchAll() |
| Start state | slot_occupied |
| Prefix | id1 live |
| Input word | outerNext(in2), outerNext(in3) |
| Transition IDs | SA occupied outerNext twice |
| Guards | each arrival replaces. in2 does not wait for in1 to complete |
| Notifications (Gamma) | eps |
| Lifecycle | three subscription attempts, only the last remains |
| Suffix | id3 live; in1 and in2 are not stored |
| End state | slot_occupied |
| Oracle | source characterization: not concatAll's FIFO and not exhaustAll's drop-while-keeping the first |
| Source characterization | switchMap.ts:103-108 |

### E-SA-3 switchAll: outer complete with a live inner waits; with none, completes

| Field | Value |
| --- | --- |
| Scenario ID | E-SA-3 |
| Title | switchAll: outer complete with a live inner waits; with none, completes |
| Parameters | switchAll() |
| Start state | either active_empty or slot_occupied |
| Prefix | as the start location |
| Input word | outerComplete, and if occupied then innerComplete |
| Transition IDs | SA empty outerComplete or SA occupied outerComplete plus draining complete |
| Guards | checkComplete |
| Notifications (Gamma) | complete, possibly after further nexts from the latest inner |
| Lifecycle | source unsubscribed; latest inner kept only if it existed |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | JSDoc switchAll.ts:17-19 |
| Source characterization | switchMap.ts:97 |

### E-SA-4 switchAll: bad inner after a good one errors, and cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-SA-4 |
| Title | switchAll: bad inner after a good one errors, and cancel is silent |
| Parameters | switchAll() |
| Start state | slot_occupied |
| Prefix | id1 live |
| Input word | outerNext(bad); separately, cancel from a good state |
| Transition IDs | SA projectThrow-while-occupied; SA cancel |
| Guards | unsubscribe id1 first; identity returns bad; innerFrom throws |
| Notifications (Gamma) | error(e); or eps |
| Lifecycle | id1 already unsubscribed before the throw; cancel unsubscribes whoever is current |
| Suffix | terminal |
| End state | terminal |
| Oracle | source characterization: invalid ObservableInput is not outerError. Cancel does not complete |
| Source characterization | innerFrom.ts:41; switchMap.ts:104-108; Subscriber.ts:104-110 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **22**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/22**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| SA-01 | not executed | static reading only; no runner |
| SA-02 | not executed | static reading only; no runner |
| SA-03 | not executed | static reading only; no runner |
| SA-04 | not executed | static reading only; no runner |
| SA-05 | not executed | static reading only; no runner |
| SA-06 | not executed | static reading only; no runner |
| SA-07 | not executed | static reading only; no runner |
| SA-08 | not executed | static reading only; no runner |
| SA-09 | not executed | static reading only; no runner |
| SA-10 | not executed | static reading only; no runner |
| SA-11 | not executed | static reading only; no runner |
| SA-12 | not executed | static reading only; no runner |
| SA-13 | not executed | static reading only; no runner |
| SA-14 | not executed | static reading only; no runner |
| SA-15 | not executed | static reading only; no runner |
| SA-16 | not executed | static reading only; no runner |
| SA-17 | not executed | static reading only; no runner |
| SA-18 | not executed | static reading only; no runner |
| SA-19 | not executed | static reading only; no runner |
| SA-20 | not executed | static reading only; no runner |
| SA-21 | not executed | static reading only; no runner |
| SA-22 | not executed | static reading only; no runner |

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
| Limits | switchMap(identity). Bound 1. No queue. No resultSelector. Complete-wait for the current inner only. |

Documented limits:

- Body is `switchMap(identity)`.
- Active-set bound: 1.
- Queue versus drop: previous inner is unsubscribed; the new one is subscribed immediately. Nothing is queued.
- Complete-wait: source plus the current inner, if any.
- No `resultSelector`.
- No tests were executed.

