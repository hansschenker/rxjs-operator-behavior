# exhaustMap

`exhaustMap` projects source values to inners, but only when no inner is already active (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `exhaustMap.ts:68-99`). If `innerSub` is non-null, the source value is ignored (`exhaustMap.ts:85`). It is not queued, and `index` is not incremented. The active set is bounded by 1 by dropping, not by switching and not by buffering. `resultSelector` is deprecated for removal in v8 (`exhaustMap.ts:13-18`). When it is truthy, the function does not use the `operate` path; it returns `source.pipe(exhaustMap(a => innerFrom(project(a, i)).pipe(map(selector))))` (`exhaustMap.ts:72-76`). The non-deprecated path forwards inner values with `onNext` left undefined, so `super._next` delivers them (`OperatorSubscriber.ts:75`, `Subscriber.ts:112-114`). Completion waits for the active inner if there is one (`exhaustMap.ts:93-95` and `88`).

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | exhaustMap(project). Deprecated: exhaustMap(project, undefined) and exhaustMap(project, resultSelector), selector removal in v8 (exhaustMap.ts:13-22). No concurrent parameter |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Subscribe to the projection of a source value only if no projected inner is active. Otherwise drop the source value. Forward the active inner. When it completes, the next source value may start a new one. If the source completes first, wait for the active inner, then complete |
| model kind | Extended/symbolic Mealy machine. Active-set bound 1. No buffer, so the dropped values do not enlarge S. Payloads and index still do |
| parameter domain | project: (T, index) => ObservableInput. Optional deprecated resultSelector. The implementation tests truthiness (`if (resultSelector)`), not isFunction, at exhaustMap.ts:72 |
| payload/error domain | Output is inner values, or selector results on the deprecated path. Errors: outerError, innerError, projectThrow, resultSelectorThrow. A dropped value produces none of these, even if it would have been a bad projection |
| subscription boundary | One outer subscription. Zero or one inner. Dropped values never become subscriptions. Index counts only accepted values |
| scheduler/tie ordering | None. The check `if (!innerSub)` happens before project (exhaustMap.ts:85-90). A synchronous inner that completes before the next source value returns the machine to active_empty, so that next value is accepted. That ordering is in the model |
| callback assumptions | project is synchronous and runs only when accepted. On the deprecated path the selector runs in map, per inner value. The plain path does not catch a throw from destination.next |
| cleanup assumptions | inner complete sets innerSub = null and completes the output only if isComplete. Outer error and inner error unsubscribe immediately. Cancel is silent and does not flush anything, because nothing was stored |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Do not invent a queue. exhaustMap.ts has no buffer. |

## B. Six-tuple

The gate is `if (!innerSub)` (`exhaustMap.ts:85`). The inner subscriber is created and assigned before `project` (`exhaustMap.ts:86-90`), so a projectThrow has already installed a child subscriber that teardown will remove, and has already consumed `index`. There is still no inner source in that case. Docs at `exhaustMap.ts:38-41` match the gate: new projections are ignored until the previous inner completes.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0), /active/ <= 1, no buffer |
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

init, active_empty, busy (inner running, which is also the drop policy and therefore the stand-in for at-capacity), draining, terminals. Every active location has outer next, outer error, outer complete, inner next/error/complete where an inner exists, and cancel.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EM-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; innerSub=null; index=0; isComplete=false | active_empty | epsilon | no inner. Active-set bound is 1. No queue location exists | T-EM-01 |
| EM-02 | active_empty | outerNext(v) / source | innerSub is null and project/innerFrom succeeds | eps | create inner subscriber, index consumed, subscribe id | busy | subscribe | one inner live. This busy location is the exhaust analogue of at-capacity, but the policy is drop, not buffer | T-EM-02 |
| EM-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws after innerSub was assigned to a not-yet-subscribed OperatorSubscriber | error(e) projectThrow | index consumed; dangling inner subscriber is a child and is torn down by destination.error; no inner source | terminal_error | subscribe | terminal | T-EM-03 |
| EM-04 | busy | outerNext(v) / source | innerSub is non-null. The value is ignored. Project is not called. Index is not incremented. Nothing is enqueued | eps | drop v | busy | an inner is already live | same inner remains; v is gone. A dropped invalid ObservableInput does not throw | T-EM-04 |
| EM-05 | busy | innerNext(id, x) / inner id | non-deprecated path: onNext is undefined, so super._next forwards x | next(x) | forward. This path does not wrap destination.next in the operator's own try/catch | busy | accepted inner | same inner | T-EM-05 |
| EM-06 | busy | innerNext(id, x) / inner id | deprecated resultSelector path: exhaustMap rewrites project to innerFrom(project).pipe(map(selector)). Selector returns r | next(r) | map forwards selector result | busy | selector overload | raw x hidden | T-EM-06 |
| EM-07 | busy | innerNext(id, x) / inner id | resultSelector throws inside that map (resultSelectorThrow) | error(e) | map's OperatorSubscriber calls destination.error; exhaust inner forwards it; unsubscribe | terminal_error | selector overload | terminal; no complete | T-EM-07 |
| EM-08 | busy | innerError(id, e) / inner id | no catch | error(e) | forward; unsubscribe outer and inner | terminal_error | busy | terminal; no complete | T-EM-08 |
| EM-09 | busy | innerComplete(id) / inner id | outer still open | eps | innerSub:=null | active_empty | busy | the next outerNext is eligible; values that were dropped are not replayed | T-EM-09 |
| EM-10 | active_empty | inner* | no inner | eps | none | active_empty | subscribe | unreachable | T-EM-10 |
| EM-11 | active_empty | outerError(e) / source | no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-EM-11 |
| EM-12 | busy | outerError(e) / source | inner live | error(e) | unsubscribe inner and outer immediately | terminal_error | busy | terminal | T-EM-12 |
| EM-13 | active_empty | outerComplete / source | no inner | complete | isComplete:=true; !innerSub so subscriber.complete() | terminal_complete | active_empty | terminal complete | T-EM-13 |
| EM-14 | busy | outerComplete / source | inner live | eps | isComplete:=true; do not complete yet; source unsubscribed; inner kept. No queued work exists | draining | busy | wait only for the active inner | T-EM-14 |
| EM-15 | draining | innerNext(id, x) / inner id | active inner | next(x) | forward | draining | outerComplete while busy | still draining | T-EM-15 |
| EM-16 | draining | innerError(id, e) / inner id | active inner errors | error(e) | unsubscribe | terminal_error | draining | terminal; no complete | T-EM-16 |
| EM-17 | draining | innerComplete(id) / inner id | isComplete and this clears innerSub | complete | innerSub:=null; subscriber.complete() | terminal_complete | draining | terminal complete | T-EM-17 |
| EM-18 | draining | outerNext(v) / source | source already unsubscribed; also, even if a late value were observed, busy/draining policy would drop it. Modeled as not enabled | eps | none | draining | outerComplete consumed | not enabled | T-EM-18 |
| EM-19 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-EM-19 |
| EM-20 | busy | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | busy | terminal silent | T-EM-20 |
| EM-21 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | draining | terminal silent | T-EM-21 |
| EM-22 | active_empty | outerNext then sync innerComplete | ordering: subscribe, then synchronous innerNext* and innerComplete are separate events. A sync-completing inner returns to active_empty before the next source value, so that next value is NOT dropped | per those events | nested complete handler clears innerSub | active_empty if the inner completed sync | active_empty | included synchronous inner behavior | T-EM-22 |
| EM-23 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-EM-23 |

Truthiness versus isFunction matters only for a non-function truthy second argument, which the types do not allow. The model assumes the second argument is either omitted or a function.

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
| I9 | index increments only on the accept path | exhaustMap.ts:90 |
| I10 | resultSelector is deprecated and, when present, is implemented by recursing into exhaustMap with a mapped project | exhaustMap.ts:13-18 and 72-76 |
| I11 | The plain path's inner next is super._next, so this operator itself does not convert a destination.next throw into destination.error | OperatorSubscriber.ts:67-75 |
| I12 | Complete-wait is the one active inner, never a queue | exhaustMap.ts:93-95 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-EM-1 exhaustMap: an idle source value is projected

| Field | Value |
| --- | --- |
| Scenario ID | E-EM-1 |
| Title | exhaustMap: an idle source value is projected |
| Parameters | no selector |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(v1), innerNext(id, a), innerComplete(id), outerComplete |
| Transition IDs | EM empty outerNext, EM innerNext, EM innerComplete to empty, EM empty outerComplete |
| Guards | innerSub was null |
| Notifications (Gamma) | next(a), complete |
| Lifecycle | one inner, then none |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | contract exhaustMap.ts:34-41 |
| Source characterization | exhaustMap.ts:84-95 |

### E-EM-2 exhaustMap: values that arrive while busy are dropped and not queued

| Field | Value |
| --- | --- |
| Scenario ID | E-EM-2 |
| Title | exhaustMap: values that arrive while busy are dropped and not queued |
| Parameters | no selector |
| Start state | busy |
| Prefix | subscribe, outerNext(v1), id1 still open, index is 1 |
| Input word | outerNext(v2), outerNext(v3), innerNext(id1, a), innerComplete(id1), outerNext(v4) |
| Transition IDs | EM busy outerNext drop rows; EM innerNext; EM innerComplete to empty; EM empty outerNext |
| Guards | v2 and v3 see innerSub set. project is not called. index stays 1 until v4 |
| Notifications (Gamma) | next(a), then nexts from v4's inner. No notification for v2 or v3 |
| Lifecycle | id1 stays. No buffer entry. v4 opens id4 |
| Suffix | id4 live if it has not completed. v2 and v3 are unrecoverable |
| End state | slot busy or empty depending on v4's inner |
| Oracle | source characterization: ignore, do not queue. This is the difference from concatMap and from switchMap |
| Source characterization | exhaustMap.ts:84-91 |

### E-EM-3 exhaustMap: outer complete waits for the active inner

| Field | Value |
| --- | --- |
| Scenario ID | E-EM-3 |
| Title | exhaustMap: outer complete waits for the active inner |
| Parameters | no selector |
| Start state | busy |
| Prefix | id1 live |
| Input word | outerComplete, innerNext(id1, a), innerComplete(id1) |
| Transition IDs | EM busy outerComplete, EM draining innerNext, EM draining innerComplete |
| Guards | isComplete && innerSub delays complete |
| Notifications (Gamma) | next(a), complete |
| Lifecycle | source unsubscribed; id1 kept; nothing else to drain |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization: exhaust waits for the active inner and for nothing else |
| Source characterization | exhaustMap.ts:88 and 93-95 |

### E-EM-4 exhaustMap: inner error, project throw, selector throw, cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-EM-4 |
| Title | exhaustMap: inner error, project throw, selector throw, cancel |
| Parameters | selector only on the selector word |
| Start state | busy or active_empty as appropriate |
| Prefix | as required by each word |
| Input word | innerError(id, e); outerNext while empty whose project throws; innerNext whose selector throws; cancel |
| Transition IDs | EM innerError; EM projectThrow; EM resultSelectorThrow; EM cancel |
| Guards | drops do not apply to these words |
| Notifications (Gamma) | error(e) three times across three words; eps for cancel |
| Lifecycle | unsubscribe. Cancel does not complete. A dropped sibling value is not involved |
| Suffix | terminal |
| End state | terminal |
| Oracle | selector JSDoc deprecated (exhaustMap.ts:13). projectThrow and resultSelectorThrow are not innerError. Inner error is not caught. Cancel is silent |
| Source characterization | exhaustMap.ts:72-90; map.ts:54-57; Subscriber.ts:104-121 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **23**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/23**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| EM-01 | not executed | static reading only; no runner |
| EM-02 | not executed | static reading only; no runner |
| EM-03 | not executed | static reading only; no runner |
| EM-04 | not executed | static reading only; no runner |
| EM-05 | not executed | static reading only; no runner |
| EM-06 | not executed | static reading only; no runner |
| EM-07 | not executed | static reading only; no runner |
| EM-08 | not executed | static reading only; no runner |
| EM-09 | not executed | static reading only; no runner |
| EM-10 | not executed | static reading only; no runner |
| EM-11 | not executed | static reading only; no runner |
| EM-12 | not executed | static reading only; no runner |
| EM-13 | not executed | static reading only; no runner |
| EM-14 | not executed | static reading only; no runner |
| EM-15 | not executed | static reading only; no runner |
| EM-16 | not executed | static reading only; no runner |
| EM-17 | not executed | static reading only; no runner |
| EM-18 | not executed | static reading only; no runner |
| EM-19 | not executed | static reading only; no runner |
| EM-20 | not executed | static reading only; no runner |
| EM-21 | not executed | static reading only; no runner |
| EM-22 | not executed | static reading only; no runner |
| EM-23 | not executed | static reading only; no runner |

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
| Limits | Drop while busy, no queue. Active bound 1. Complete-wait for that inner only. resultSelector deprecated. Plain inner next does not wrap destination.next. |

Documented limits:

- Active-set bound: 1.
- Queue versus drop: drops. No buffer. Dropped values do not increment `index` and are not replayed.
- Complete-wait: the active inner only.
- `resultSelector` deprecated (v8), implemented by a recursive `exhaustMap` plus `map`.
- Non-deprecated inner `next` uses `super._next` and does not catch `destination.next` throws.
- `if (resultSelector)` is truthiness, not `isFunction`.
- No tests were executed.

