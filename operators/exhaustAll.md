# exhaustAll

`exhaustAll` drops higher-order inners that arrive while one inner is still subscribed (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The body is `return exhaustMap(identity)` (`exhaustAll.ts:49-51`). There is no `resultSelector` and no concurrent argument. The informal docs (`exhaustAll.ts:18-20`) match the gate in `exhaustMap`: a new inner is ignored until the previous one completes. Ignored inners are not queued. A bad `ObservableInput` that arrives while busy is dropped without calling `innerFrom`, so it does not error; the same bad value while idle errors when `innerFrom` runs.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | exhaustAll(): OperatorFunction<O, ObservedValueOf<O>>. No parameters |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Subscribe to the first inner ObservableInput, ignore later ones until it completes, then take the next one that arrives after that. Fail if the active inner or the source errors |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. No buffer |
| parameter domain | None. project is identity |
| payload/error domain | Source values are ObservableInputs. Output is their payloads. innerFrom throw only on an accepted value |
| subscription boundary | Subscribe on accept only. Busy arrivals are not subscribed. Not delayed until outer complete |
| scheduler/tie ordering | Same as exhaustMap. A sync-completing inner frees the slot before the next source value in the same turn |
| callback assumptions | identity does not throw. innerFrom may, only if the value was accepted |
| cleanup assumptions | Wait for the active inner after outer complete. No queue to drain. Cancel silent |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). No selector. |

## B. Six-tuple

Forwarding: exhaustMap(identity). The drop decision happens before identity's return value is passed to innerFrom, because project runs only inside the accept branch. identity is that project.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = exhaustMap with identity |
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
| active_empty | subscribed; innerSub=null; isComplete=false | next outer value is accepted |
| busy | exactly one inner; isComplete=false | Inner-running. Also the exhaust 'at capacity' policy, which is drop rather than a buffer location. No queue state exists |
| draining | isComplete; the one inner still live | Wait for that inner only. Dropped values are already gone |
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

Gamma records are `next(v)`, `error(e)`, `complete`, or `eps`. Dropped outer values produce `eps` and no queue entry. `complete` fires when the source has completed and `innerSub` is null (`exhaustMap.ts:88` and `exhaustMap.ts:93-95`). `cancel` emits `eps`.

## C. Transition obligations

No selector rows. busy outerNext is the drop. There is no at-capacity buffer location.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EA-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; innerSub=null; index=0; isComplete=false | active_empty | epsilon | no inner. Active-set bound is 1. No queue location exists | T-EA-01 |
| EA-02 | active_empty | outerNext(v) / source | innerSub is null and project/innerFrom succeeds | eps | create inner subscriber, index consumed, subscribe id; identity, so v is the ObservableInput | busy | subscribe | one inner live. This busy location is the exhaust analogue of at-capacity, but the policy is drop, not buffer | T-EA-02 |
| EA-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws after innerSub was assigned to a not-yet-subscribed OperatorSubscriber | error(e) projectThrow | index consumed; dangling inner subscriber is a child and is torn down by destination.error; no inner source | terminal_error | subscribe | terminal | T-EA-03 |
| EA-04 | busy | outerNext(v) / source | innerSub is non-null. The value is ignored. Project is not called. Index is not incremented. Nothing is enqueued | eps | drop v | busy | an inner is already live | same inner remains; v is gone. A dropped invalid ObservableInput does not throw | T-EA-04 |
| EA-05 | busy | innerNext(id, x) / inner id | id is the one live inner | next(x) | super._next forward | busy | accepted inner | same inner | T-EA-05 |
| EA-06 | busy | innerError(id, e) / inner id | no catch | error(e) | forward; unsubscribe outer and inner | terminal_error | busy | terminal; no complete | T-EA-06 |
| EA-07 | busy | innerComplete(id) / inner id | outer still open | eps | innerSub:=null | active_empty | busy | the next outerNext is eligible; values that were dropped are not replayed | T-EA-07 |
| EA-08 | active_empty | inner* | no inner | eps | none | active_empty | subscribe | unreachable | T-EA-08 |
| EA-09 | active_empty | outerError(e) / source | no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-EA-09 |
| EA-10 | busy | outerError(e) / source | inner live | error(e) | unsubscribe inner and outer immediately | terminal_error | busy | terminal | T-EA-10 |
| EA-11 | active_empty | outerComplete / source | no inner | complete | isComplete:=true; !innerSub so subscriber.complete() | terminal_complete | active_empty | terminal complete | T-EA-11 |
| EA-12 | busy | outerComplete / source | inner live | eps | isComplete:=true; do not complete yet; source unsubscribed; inner kept. No queued work exists | draining | busy | wait only for the active inner | T-EA-12 |
| EA-13 | draining | innerNext(id, x) / inner id | active inner | next(x) | forward | draining | outerComplete while busy | still draining | T-EA-13 |
| EA-14 | draining | innerError(id, e) / inner id | active inner errors | error(e) | unsubscribe | terminal_error | draining | terminal; no complete | T-EA-14 |
| EA-15 | draining | innerComplete(id) / inner id | isComplete and this clears innerSub | complete | innerSub:=null; subscriber.complete() | terminal_complete | draining | terminal complete | T-EA-15 |
| EA-16 | draining | outerNext(v) / source | source already unsubscribed; also, even if a late value were observed, busy/draining policy would drop it. Modeled as not enabled | eps | none | draining | outerComplete consumed | not enabled | T-EA-16 |
| EA-17 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-EA-17 |
| EA-18 | busy | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | busy | terminal silent | T-EA-18 |
| EA-19 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | draining | terminal silent | T-EA-19 |
| EA-20 | active_empty | outerNext then sync innerComplete | ordering: subscribe, then synchronous innerNext* and innerComplete are separate events. A sync-completing inner returns to active_empty before the next source value, so that next value is NOT dropped | per those events | nested complete handler clears innerSub | active_empty if the inner completed sync | active_empty | included synchronous inner behavior | T-EA-20 |
| EA-21 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-EA-21 |

A dropped invalid inner does not throw. That follows from exhaustMap.ts:85-90, not from a special case in exhaustAll.ts.

## D. Contract invariants

| ID | Invariant | Source |
| --- | --- | --- |
| I1 | At most one inner is subscribed | exhaustMap.ts:85 |
| I2 | An outer value that arrives while innerSub is non-null is dropped: no enqueue, no project, no index increment | exhaustMap.ts:84-91 |
| I3 | There is no buffer field | exhaustMap.ts:77-99 |
| I4 | complete Gamma iff isComplete and innerSub is null | exhaustMap.ts:88 and 93-95 |
| I5 | Inner error fails the output. No catch | onError omitted at exhaustMap.ts:86 |
| I6 | Dropped values are not replayed when the inner completes | innerSub set to null without reading a queue |
| I7 | cancel is silent | unsubscribe is not complete |
| I8 | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |
| I9 | project is identity | exhaustAll.ts:50 |
| I10 | No resultSelector | exhaustAll.ts:49-51 |
| I11 | Only accepted inners are passed to innerFrom | exhaustMap.ts:90 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-EA-1 exhaustAll: first inner is taken

| Field | Value |
| --- | --- |
| Scenario ID | E-EA-1 |
| Title | exhaustAll: first inner is taken |
| Parameters | exhaustAll() |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), innerNext(id1, a), innerComplete(id1), outerComplete |
| Transition IDs | EA accept, innerNext, innerComplete, empty outerComplete |
| Guards | idle |
| Notifications (Gamma) | next(a), complete |
| Lifecycle | one subscription |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract exhaustAll.ts:14-20 |
| Source characterization | exhaustAll.ts:50; exhaustMap.ts:85-95 |

### E-EA-2 exhaustAll: later inners are dropped, not queued

| Field | Value |
| --- | --- |
| Scenario ID | E-EA-2 |
| Title | exhaustAll: later inners are dropped, not queued |
| Parameters | exhaustAll() |
| Start state | busy |
| Prefix | in1 subscribed |
| Input word | outerNext(in2), outerNext(in3), innerComplete(id1), outerNext(in4) |
| Transition IDs | EA drop rows; EA innerComplete to empty; EA accept |
| Guards | in2 and in3 never reach innerFrom. in4 does |
| Notifications (Gamma) | only in1's remaining values, then in4's values |
| Lifecycle | no subscription for in2 or in3 |
| Suffix | id4 live |
| End state | busy |
| Oracle | source characterization: drop, unlike concatAll (queue) and switchAll (replace) |
| Source characterization | exhaustMap.ts:85-91 |

### E-EA-3 exhaustAll: outer complete waits for the active inner

| Field | Value |
| --- | --- |
| Scenario ID | E-EA-3 |
| Title | exhaustAll: outer complete waits for the active inner |
| Parameters | exhaustAll() |
| Start state | busy |
| Prefix | id1 live |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | EA draining rows |
| Guards | no queued inner can extend the drain |
| Notifications (Gamma) | next(a), complete |
| Lifecycle | id1 kept |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization via exhaustMap complete rule |
| Source characterization | exhaustMap.ts:93-95 |

### E-EA-4 exhaustAll: idle bad inner errors; busy bad inner is dropped; cancel is silent

| Field | Value |
| --- | --- |
| Scenario ID | E-EA-4 |
| Title | exhaustAll: idle bad inner errors; busy bad inner is dropped; cancel is silent |
| Parameters | exhaustAll() |
| Start state | active_empty and busy |
| Prefix | as appropriate |
| Input word | outerNext(bad) while empty; outerNext(bad) while busy; cancel |
| Transition IDs | EA projectThrow; EA drop; EA cancel |
| Guards | only the idle bad value calls innerFrom |
| Notifications (Gamma) | error(e); eps; eps |
| Lifecycle | error tears down; drop keeps the current inner; cancel unsubscribes it without complete |
| Suffix | terminal or still busy after the drop word |
| End state | per word |
| Oracle | source characterization of identity plus the accept gate |
| Source characterization | exhaustAll.ts:50; innerFrom.ts:41; exhaustMap.ts:85 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **21**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/21**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| EA-01 | not executed | static reading only; no runner |
| EA-02 | not executed | static reading only; no runner |
| EA-03 | not executed | static reading only; no runner |
| EA-04 | not executed | static reading only; no runner |
| EA-05 | not executed | static reading only; no runner |
| EA-06 | not executed | static reading only; no runner |
| EA-07 | not executed | static reading only; no runner |
| EA-08 | not executed | static reading only; no runner |
| EA-09 | not executed | static reading only; no runner |
| EA-10 | not executed | static reading only; no runner |
| EA-11 | not executed | static reading only; no runner |
| EA-12 | not executed | static reading only; no runner |
| EA-13 | not executed | static reading only; no runner |
| EA-14 | not executed | static reading only; no runner |
| EA-15 | not executed | static reading only; no runner |
| EA-16 | not executed | static reading only; no runner |
| EA-17 | not executed | static reading only; no runner |
| EA-18 | not executed | static reading only; no runner |
| EA-19 | not executed | static reading only; no runner |
| EA-20 | not executed | static reading only; no runner |
| EA-21 | not executed | static reading only; no runner |

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
| Limits | exhaustMap(identity). Drop, no queue. Bound 1. No resultSelector. Complete-wait for the active inner. |

Documented limits:

- Body is `exhaustMap(identity)`.
- Active-set bound: 1.
- Queue versus drop: drops while busy. Does not unsubscribe the active inner (that would be switchAll).
- Complete-wait: the active inner only.
- No `resultSelector`.
- No tests were executed.

