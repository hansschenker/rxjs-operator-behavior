# combineAll

`combineAll.ts` is a one-line alias: `export const combineAll = combineLatestAll` (`combineAll.ts:6`), RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791. The JSDoc says it was renamed to `combineLatestAll` and will be removed in v8 (`combineAll.ts:3-5`). The callee is `joinAllInternals(combineLatest, project)` (`combineLatestAll.ts:48-50`). The alias forwards both overloads, including the optional live `project`. That `project` is not a deprecated `resultSelector`; the deprecation on this file is the rename only. The behavioral contract is collect-until-outer-complete, then `combineLatest`: no inner subscription while the source is still open, no concurrent cap, snapshots only after every inner has emitted, complete-wait for every inner, fail-fast on inner error.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | const combineAll = combineLatestAll. Overloads forwarded: no-arg array output, and optional project. Alias removal in v8. project is not deprecated |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Identical to combineLatestAll |
| model kind | Same extended/symbolic Mealy machine as combineLatestAll |
| parameter domain | Optional project, forwarded. No concurrent |
| payload/error domain | Same as combineLatestAll |
| subscription boundary | Same collect-then-subscribe boundary |
| scheduler/tie ordering | Same as combineLatest: index order, no scheduler |
| callback assumptions | Same as combineLatestAll |
| cleanup assumptions | Same as combineLatestAll |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). No extra branch in combineAll.ts. |

## B. Six-tuple

Function identity. The six-tuple is combineLatestAll's. The alias does not wrap the project or change when inners subscribe.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) = the combineLatestAll machine |
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
| collecting | same as combineLatestAll | no inners yet |
| joining | same as combineLatestAll | outer-completed combine |
| terminal_* | stopped | no further Gamma |

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

Gamma records are `next(v)`, `error(e)`, `complete`, or `eps`. During collection every outer next is `eps`. After the outer completes, `next` values are the join's snapshots or tuples, optionally passed through `project`. `complete` with zero nexts is a legal word (empty collection, combineLatest inner that completes before emitting, or zip that cannot form a tuple). `cancel` emits `eps`.

## C. Transition obligations

Same combine grid as combineLatestAll under the prefix COA. Included so the alias file has its own full model of the forwarding contract.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| COA-01 | init / s0 | subscribe / consumer | pipe subscribes toArray, which subscribes the source. No inner ObservableInput is subscribed | eps | buf:=[]; collecting | collecting | epsilon | active inner set is empty. This is the active-no-inner location. No concurrent cap | T-COA-01 |
| COA-02 | collecting | outerNext(v) / source | v is stored by reference. toArray/reduce does not call innerFrom | eps | buf.push(v) | collecting | subscribe | still no inner subscription. A hot v may emit elsewhere; this operator does not see it. A cold v does not start | T-COA-02 |
| COA-03 | collecting | outerError(e) / source | toArray/reduce has no custom onError, so the array is not emitted | error(e) | discard buf; never call joinFn; no inner subscribe | terminal_error | collecting | terminal; no complete; no partial join | T-COA-03 |
| COA-04 | collecting | cancel / consumer | consumer unsubscribes during collection | eps | unsubscribe source; discard buf; no complete | terminal_cancelled | collecting | terminal silent | T-COA-04 |
| COA-05 | collecting | innerNext / innerError / innerComplete | no inner has been subscribed. Unreachable under the subscription boundary | eps | none | collecting | subscribe | excluded | T-COA-05 |
| COA-06 | collecting | outerComplete / source | buf is empty. toArray emits [] and completes. combineLatest([]) is from([]), which completes with no next and does not call project | complete | subscribe the empty join, which completes synchronously; project is not applied | terminal_complete | subscribe then outerComplete with no values | terminal complete; zero next notifications. At-capacity does not apply | T-COA-06 |
| COA-07 | collecting | outerComplete / source | buf has one or more inputs and joining them succeeds in subscribing | eps | toArray emits the array once; mergeMap projects it by joinFn and subscribes; source of toArray is already complete so mergeMap is in its wait-for-the-one-inner state. Inners subscribe now, in index order, synchronously when no scheduler is passed (joinAllInternals passes none) | joining | one or more outerNext values, then outerComplete | THIS is the outer-completed phase. Inners are subscribed only after outer complete, not when they arrived. Active set size equals buf.length, which is unbounded, so the machine stays extended/symbolic. No concurrent parameter | T-COA-07 |
| COA-08 | collecting | outerComplete / source | joinFn or an innerFrom inside the join throws while subscribing the collected inputs (invalid ObservableInput) | error(e) | inners already subscribed in the loop are unsubscribed by the error teardown; later inputs are not subscribed | terminal_error | outer completed with a bad collected input | terminal. This is a subscribe-time failure of the join, not an outerError | T-COA-08 |
| COA-09 | joining | innerNext(id, x) / inner id | not every collected inner has produced a first value yet | eps | store latest[id]:=x; if this was id's first value, decrement remainingFirst. Do not emit the pre-first values that were overwritten | joining | outer already complete; inners subscribed | still waiting for a first value from every inner. No at-capacity queue of outers (collection is finished) | T-COA-09 |
| COA-10 | joining | innerNext(id, x) / inner id | this next makes remainingFirst hit 0, or remainingFirst is already 0. Optional project is absent or returns r | next(snapshot array) or next(project(...snapshot)) once project is present | emit a copy of the latest array in collection order. mapOneOrManyArgs spreads that array into project | joining | every inner has now emitted at least once | later nexts from any inner emit again with the updated slot | T-COA-10 |
| COA-11 | joining | innerNext(id, x) / inner id | optional project throws (projectThrow). Not a deprecated resultSelector; the parameter is live | error(e) | map OperatorSubscriber sends destination.error; unsubscribe every inner | terminal_error | a snapshot was about to be projected | terminal; no complete | T-COA-11 |
| COA-12 | joining | innerComplete(id) / inner id | other inners still active | eps | active--. If id never emitted, remainingFirst stays > 0, so a later snapshot is impossible | joining | joining | if some inner completed with no value, the output can still only complete, never next, once the rest finish | T-COA-12 |
| COA-13 | joining | innerComplete(id) / inner id | this completion brings the combineLatest active count to 0 | complete | no extra next is synthesized. If no snapshot was ever emitted, the output completes with zero nexts | terminal_complete | all collected inners have completed | terminal complete. mergeMap then completes because its only inner completed and its source (toArray) is already complete | T-COA-13 |
| COA-14 | joining | innerError(id, e) / inner id | any collected inner errors. No catch inside combineLatest, zip, or the mergeMap that hosts them | error(e) | unsubscribe every other inner and the outer join immediately | terminal_error | joining | terminal; no complete | T-COA-14 |
| COA-15 | joining | outerNext / outerError / outerComplete | the source already completed into toArray before joining. Further outer notifications are not enabled | eps | none | joining | outerComplete already consumed | not enabled | T-COA-15 |
| COA-16 | joining | cancel / consumer | consumer unsubscribes while the join is live | eps | unsubscribe every inner; no complete | terminal_cancelled | joining | terminal silent | T-COA-16 |
| COA-17 | collecting | outerComplete with synchronous inners | after subscribe-all, synchronous innerNext/innerComplete are separate Sigma events before the join subscribe call returns. Included. A downstream subscriber calling back into the source during a next is excluded | per those events | combineLatest subscribes in index order and does not use zip's subscriber.closed loop check. A synchronous error still tears the subscriber down. Synchronous inner nexts are separate Sigma events and can emit a snapshot once every inner has a first value | as those events specify | outerComplete of a non-empty buf | synchronous inner behavior is in the model | T-COA-17 |
| COA-18 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-COA-18 |

One-line alias. Do not describe project as a deprecated resultSelector.

## D. Contract invariants

| ID | Invariant | Source |
| --- | --- | --- |
| I1 | No inner is subscribed during collection | joinAllInternals.ts:20-25 uses toArray before mergeMap(joinFn) |
| I2 | toArray emits one array, and only on source complete. Source error emits no array | toArray.ts:14-16 and 41-43; reduce/scanInternals default error path |
| I3 | Empty collection completes with no next | combineLatest.ts:203-207 from([]); zip.ts:116 EMPTY |
| I4 | After a non-empty collection, inners subscribe in index order with no scheduler | combineLatest.ts:248-283; zip.ts:77-78; joinAllInternals passes no scheduler |
| I5 | An inner error fails the output and unsubscribes the other inners. No catch is added by the helper | combineLatest and zip use createOperatorSubscriber without onError |
| I6 | cancel during collection or during joining emits eps | unsubscribe is not complete |
| I7 | Optional project runs on each join emission via mapOneOrManyArgs, spreading arrays. It is not a deprecated resultSelector | joinAllInternals.ts:27; mapOneOrManyArgs.ts:6-16 |
| I8 | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). |
| I9 | combineAll and combineLatestAll are the same function | combineAll.ts:6 |
| I10 | Subscription of inners waits for outer complete | combineLatestAll.ts:49; joinAllInternals.ts:21-25 |
| I11 | Snapshot and complete rules are combineLatest's | combineLatest.ts:257-276 |
| I12 | The rename is the only deprecation. project stays | combineAll.ts:3-5; combineLatestAll.ts:7-8 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-COA-1 combineAll: alias collects before subscribing

| Field | Value |
| --- | --- |
| Scenario ID | E-COA-1 |
| Title | combineAll: alias collects before subscribing |
| Parameters | combineAll() |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), outerNext(in2), outerComplete, innerNext(id1, a), innerNext(id2, b) |
| Transition IDs | COA collect, COA outerComplete, COA snapshot rows |
| Guards | no inner subscription in the prefix before outerComplete |
| Notifications (Gamma) | next([a, b]) |
| Lifecycle | subscribe both after outer complete |
| Suffix | joining |
| End state | joining |
| Oracle | forwarded contract of combineLatestAll.ts:11-14 |
| Source characterization | combineAll.ts:6; joinAllInternals.ts:19-25; combineLatest.ts:265-268 |

### E-COA-2 combineAll: alias does not have a concurrency queue

| Field | Value |
| --- | --- |
| Scenario ID | E-COA-2 |
| Title | combineAll: alias does not have a concurrency queue |
| Parameters | combineAll() |
| Start state | collecting |
| Prefix | many outerNext values |
| Input word | further outerNext values, still no outerComplete |
| Transition IDs | COA collecting outerNext |
| Guards | each value is pushed by toArray. None is subscribed. There is no active>=concurrent gate |
| Notifications (Gamma) | eps |
| Lifecycle | buf grows. active inner set stays empty |
| Suffix | still collecting |
| End state | collecting |
| Oracle | source characterization: not mergeAll's concurrent queue |
| Source characterization | toArray via joinAllInternals.ts:23 |

### E-COA-3 combineAll: waits until every inner has a value, then waits for all to complete

| Field | Value |
| --- | --- |
| Scenario ID | E-COA-3 |
| Title | combineAll: waits until every inner has a value, then waits for all to complete |
| Parameters | combineAll() |
| Start state | joining |
| Prefix | two inners subscribed; only id1 has emitted a |
| Input word | innerComplete is not yet; innerNext(id2, b); later both complete |
| Transition IDs | COA snapshot row; COA last complete row |
| Guards | remainingFirst hits 0 on id2 |
| Notifications (Gamma) | next([a, b]), then complete |
| Lifecycle | both inners stay until they complete |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | combineLatest first-value rule and all-complete rule |
| Source characterization | combineLatest.ts:265-276 |

### E-COA-4 combineAll: inner error and cancel match the callee

| Field | Value |
| --- | --- |
| Scenario ID | E-COA-4 |
| Title | combineAll: inner error and cancel match the callee |
| Parameters | combineAll() |
| Start state | joining and collecting |
| Prefix | as appropriate |
| Input word | innerError; cancel |
| Transition IDs | COA innerError; COA cancel |
| Guards | alias adds no catch |
| Notifications (Gamma) | error(e); eps |
| Lifecycle | unsubscribe |
| Suffix | terminal |
| End state | terminal |
| Oracle | fail-fast inner error; silent cancel. Alias deprecation does not change them |
| Source characterization | combineAll.ts:3-6; Subscriber.ts:104-121 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **18**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/18**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| COA-01 | not executed | static reading only; no runner |
| COA-02 | not executed | static reading only; no runner |
| COA-03 | not executed | static reading only; no runner |
| COA-04 | not executed | static reading only; no runner |
| COA-05 | not executed | static reading only; no runner |
| COA-06 | not executed | static reading only; no runner |
| COA-07 | not executed | static reading only; no runner |
| COA-08 | not executed | static reading only; no runner |
| COA-09 | not executed | static reading only; no runner |
| COA-10 | not executed | static reading only; no runner |
| COA-11 | not executed | static reading only; no runner |
| COA-12 | not executed | static reading only; no runner |
| COA-13 | not executed | static reading only; no runner |
| COA-14 | not executed | static reading only; no runner |
| COA-15 | not executed | static reading only; no runner |
| COA-16 | not executed | static reading only; no runner |
| COA-17 | not executed | static reading only; no runner |
| COA-18 | not executed | static reading only; no runner |

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
| Limits | Alias of combineLatestAll. Collect-then-combine. No resultSelector deprecation beyond the rename. project forwarded. No concurrent cap. |

Documented limits:

- One-line alias of `combineLatestAll`. Callee read through `joinAllInternals(combineLatest, project)`.
- Inners subscribe only after outer complete.
- No concurrent limit, so no queue-versus-drop policy of the mergeMap kind. All collected inputs are subscribed together.
- Complete-wait: every joined inner. Snapshots require a first value from each.
- Optional `project` is live, not a deprecated `resultSelector`.
- The alias itself is deprecated for removal in v8.
- No tests were executed.

