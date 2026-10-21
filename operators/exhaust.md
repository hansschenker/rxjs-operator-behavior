# exhaust

`exhaust.ts` is a one-line alias: `export const exhaust = exhaustAll` (`exhaust.ts:6`), RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791. The JSDoc says it was renamed to `exhaustAll` and will be removed in v8 (`exhaust.ts:3-5`). The callee `exhaustAll` is `exhaustMap(identity)` (`exhaustAll.ts:49-51`). So `exhaust` forwards the exhaust drop policy: at most one inner, further higher-order values ignored rather than queued or switched, complete-wait only for the active inner, no `resultSelector`, no concurrent argument. This file adds no function body of its own.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | const exhaust = exhaustAll. No parameters. No resultSelector. Alias deprecated, removal in v8 (exhaust.ts:3-5) |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Identical to exhaustAll: drop inner ObservableInputs while one is active |
| model kind | Same extended/symbolic Mealy machine as exhaustAll. Active-set bound 1. No buffer |
| parameter domain | None. Forwarded project is identity. concurrent is not a parameter |
| payload/error domain | Same as exhaustAll |
| subscription boundary | Same as exhaustAll / exhaustMap |
| scheduler/tie ordering | Same as exhaustMap. None |
| callback assumptions | Same as exhaustAll |
| cleanup assumptions | Same as exhaustAll |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). No independent control flow in exhaust.ts. |

## B. Six-tuple

Function identity: exhaust === exhaustAll === exhaustMap(identity) as composed behavior. delta and lambda do not consult exhaust.ts beyond the export.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = the exhaustAll machine |
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

Same grid as exhaustAll, prefixed EXH, because the alias forwards that contract. No selector. No queue location.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXH-01 | init / s0 | subscribe / consumer | subscription established | eps | subscribe outer; innerSub=null; index=0; isComplete=false | active_empty | epsilon | no inner. Active-set bound is 1. No queue location exists | T-EXH-01 |
| EXH-02 | active_empty | outerNext(v) / source | innerSub is null and project/innerFrom succeeds | eps | create inner subscriber, index consumed, subscribe id; identity, so v is the ObservableInput | busy | subscribe | one inner live. This busy location is the exhaust analogue of at-capacity, but the policy is drop, not buffer | T-EXH-02 |
| EXH-03 | active_empty | outerNext(v) / source | project throws or innerFrom throws after innerSub was assigned to a not-yet-subscribed OperatorSubscriber | error(e) projectThrow | index consumed; dangling inner subscriber is a child and is torn down by destination.error; no inner source | terminal_error | subscribe | terminal | T-EXH-03 |
| EXH-04 | busy | outerNext(v) / source | innerSub is non-null. The value is ignored. Project is not called. Index is not incremented. Nothing is enqueued | eps | drop v | busy | an inner is already live | same inner remains; v is gone. A dropped invalid ObservableInput does not throw | T-EXH-04 |
| EXH-05 | busy | innerNext(id, x) / inner id | id is the one live inner | next(x) | super._next forward | busy | accepted inner | same inner | T-EXH-05 |
| EXH-06 | busy | innerError(id, e) / inner id | no catch | error(e) | forward; unsubscribe outer and inner | terminal_error | busy | terminal; no complete | T-EXH-06 |
| EXH-07 | busy | innerComplete(id) / inner id | outer still open | eps | innerSub:=null | active_empty | busy | the next outerNext is eligible; values that were dropped are not replayed | T-EXH-07 |
| EXH-08 | active_empty | inner* | no inner | eps | none | active_empty | subscribe | unreachable | T-EXH-08 |
| EXH-09 | active_empty | outerError(e) / source | no inner | error(e) | unsubscribe outer | terminal_error | active_empty | terminal | T-EXH-09 |
| EXH-10 | busy | outerError(e) / source | inner live | error(e) | unsubscribe inner and outer immediately | terminal_error | busy | terminal | T-EXH-10 |
| EXH-11 | active_empty | outerComplete / source | no inner | complete | isComplete:=true; !innerSub so subscriber.complete() | terminal_complete | active_empty | terminal complete | T-EXH-11 |
| EXH-12 | busy | outerComplete / source | inner live | eps | isComplete:=true; do not complete yet; source unsubscribed; inner kept. No queued work exists | draining | busy | wait only for the active inner | T-EXH-12 |
| EXH-13 | draining | innerNext(id, x) / inner id | active inner | next(x) | forward | draining | outerComplete while busy | still draining | T-EXH-13 |
| EXH-14 | draining | innerError(id, e) / inner id | active inner errors | error(e) | unsubscribe | terminal_error | draining | terminal; no complete | T-EXH-14 |
| EXH-15 | draining | innerComplete(id) / inner id | isComplete and this clears innerSub | complete | innerSub:=null; subscriber.complete() | terminal_complete | draining | terminal complete | T-EXH-15 |
| EXH-16 | draining | outerNext(v) / source | source already unsubscribed; also, even if a late value were observed, busy/draining policy would drop it. Modeled as not enabled | eps | none | draining | outerComplete consumed | not enabled | T-EXH-16 |
| EXH-17 | active_empty | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | active_empty | terminal silent | T-EXH-17 |
| EXH-18 | busy | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | busy | terminal silent | T-EXH-18 |
| EXH-19 | draining | cancel / consumer | consumer unsubscribes | eps | unsubscribe outer and the active inner if any; no complete | terminal_cancelled | draining | terminal silent | T-EXH-19 |
| EXH-20 | active_empty | outerNext then sync innerComplete | ordering: subscribe, then synchronous innerNext* and innerComplete are separate events. A sync-completing inner returns to active_empty before the next source value, so that next value is NOT dropped | per those events | nested complete handler clears innerSub | active_empty if the inner completed sync | active_empty | included synchronous inner behavior | T-EXH-20 |
| EXH-21 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-EXH-21 |

One-line alias. The rename deprecation is not a runtime branch.

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
| I9 | exhaust and exhaustAll are the same function object | exhaust.ts:6 |
| I10 | The composed project is identity and the policy is drop | exhaustAll.ts:50; exhaustMap.ts:85 |
| I11 | No resultSelector is introduced by the alias | exhaust.ts has no signature of its own |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-EXH-1 exhaust: alias accepts the first inner

| Field | Value |
| --- | --- |
| Scenario ID | E-EXH-1 |
| Title | exhaust: alias accepts the first inner |
| Parameters | exhaust() |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), innerNext(id, a), innerComplete(id), outerComplete |
| Transition IDs | EXH accept and complete rows |
| Guards | same as exhaustAll |
| Notifications (Gamma) | next(a), complete |
| Lifecycle | one inner |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | forwarding contract of exhaustAll |
| Source characterization | exhaust.ts:6; exhaustAll.ts:50; exhaustMap.ts:85-95 |

### E-EXH-2 exhaust: alias drops rather than queues

| Field | Value |
| --- | --- |
| Scenario ID | E-EXH-2 |
| Title | exhaust: alias drops rather than queues |
| Parameters | exhaust() |
| Start state | busy |
| Prefix | one inner live |
| Input word | outerNext(in2), innerComplete, outerNext(in3) |
| Transition IDs | EXH drop; EXH complete-to-empty; EXH accept |
| Guards | in2 ignored |
| Notifications (Gamma) | values of in1 then in3 only |
| Lifecycle | in2 never subscribed |
| Suffix | in3 live |
| End state | busy |
| Oracle | source characterization of the callee: drop, not concatAll's queue |
| Source characterization | exhaustMap.ts:85 |

### E-EXH-3 exhaust: alias waits for the active inner

| Field | Value |
| --- | --- |
| Scenario ID | E-EXH-3 |
| Title | exhaust: alias waits for the active inner |
| Parameters | exhaust() |
| Start state | busy |
| Prefix | inner live |
| Input word | outerComplete, innerComplete |
| Transition IDs | EXH draining rows |
| Guards | isComplete && innerSub |
| Notifications (Gamma) | complete after the inner's remaining nexts |
| Lifecycle | inner kept |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | same complete-wait as exhaustMap |
| Source characterization | exhaustMap.ts:93-95 |

### E-EXH-4 exhaust: alias inner error and cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-EXH-4 |
| Title | exhaust: alias inner error and cancel |
| Parameters | exhaust() |
| Start state | busy |
| Prefix | inner live |
| Input word | innerError(id, e); separately cancel |
| Transition IDs | EXH innerError; EXH cancel |
| Guards | no catch added by the alias |
| Notifications (Gamma) | error(e); eps |
| Lifecycle | unsubscribe |
| Suffix | terminal |
| End state | terminal |
| Oracle | callee fail-fast; cancel is not complete. Alias deprecation does not change either |
| Source characterization | exhaust.ts:3-6; Subscriber.ts:104-121 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **21**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/21**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| EXH-01 | not executed | static reading only; no runner |
| EXH-02 | not executed | static reading only; no runner |
| EXH-03 | not executed | static reading only; no runner |
| EXH-04 | not executed | static reading only; no runner |
| EXH-05 | not executed | static reading only; no runner |
| EXH-06 | not executed | static reading only; no runner |
| EXH-07 | not executed | static reading only; no runner |
| EXH-08 | not executed | static reading only; no runner |
| EXH-09 | not executed | static reading only; no runner |
| EXH-10 | not executed | static reading only; no runner |
| EXH-11 | not executed | static reading only; no runner |
| EXH-12 | not executed | static reading only; no runner |
| EXH-13 | not executed | static reading only; no runner |
| EXH-14 | not executed | static reading only; no runner |
| EXH-15 | not executed | static reading only; no runner |
| EXH-16 | not executed | static reading only; no runner |
| EXH-17 | not executed | static reading only; no runner |
| EXH-18 | not executed | static reading only; no runner |
| EXH-19 | not executed | static reading only; no runner |
| EXH-20 | not executed | static reading only; no runner |
| EXH-21 | not executed | static reading only; no runner |

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
| Limits | One-line alias of exhaustAll, which is exhaustMap(identity). Drop, no queue, no resultSelector. Alias deprecated for v8. |

Documented limits:

- One-line alias. Callee read: `exhaustAll` then `exhaustMap(identity)`.
- Active-set bound: 1.
- Queue versus drop: drops. No buffer.
- Complete-wait: the active inner only.
- No `resultSelector` and no concurrent argument.
- Alias deprecated, removal in v8 (`exhaust.ts:4`).
- No tests were executed.

