# combineLatestAll

`combineLatestAll` collects a higher-order source and, after that source completes, combines the collected inners with `combineLatest` (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The body is `return joinAllInternals(combineLatest, project)` (`combineLatestAll.ts:48-50`). The JSDoc is explicit and matches the helper: it flattens by applying `combineLatest` when the observable-of-observables completes (`combineLatestAll.ts:11-14`). It does not combine 'every currently active inner' as inners arrive, and it does not use `mergeInternals`. Once subscribed, `combineLatest` emits nothing until every collected inner has emitted at least once, then emits a snapshot array (a copy) on every later inner next, and completes when every inner completes (`combineLatest.ts:237-276`). An inner that completes without a value makes a snapshot impossible; the output still completes when all inners have completed, with zero nexts (`combineLatest.ts:92-102` and `271-276`). `project`, if passed, is a live function from the latest values to a result (`combineLatestAll.ts:7-8` and `43-44`). It is not marked deprecated. There is no concurrent limit.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | combineLatestAll(): arrays of latest values. combineLatestAll(project): project(...latest) -> R. project is not deprecated |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Buffer inner ObservableInputs until the source completes, subscribe to all of them, wait until each has produced a value, then emit combined snapshots until all complete |
| model kind | Extended/symbolic Mealy machine. Collected set unbounded. After subscribe, the active set is the whole collection. No concurrent bound |
| parameter domain | Optional project: (...T) => R. No concurrent. No resultSelector deprecation on this parameter |
| payload/error domain | Source payloads are ObservableInputs. Output is T[] or R. Errors: outerError during collect, innerError during join, projectThrow, invalid input while the join subscribes |
| subscription boundary | No inner subscription before outer complete. After that, every collected input is subscribed, in order, with no cap. Pre-complete emissions of hot inners are missed |
| scheduler/tie ordering | No scheduler. Index order. combineLatest keeps only the latest value per inner before the first full snapshot; earlier values from a fast inner are overwritten and never emitted as their own snapshots |
| callback assumptions | project is synchronous, applied by mapOneOrManyArgs to the snapshot array, so it is called with one argument per inner. It may throw |
| cleanup assumptions | All inners completing produces complete, even if no snapshot was ever emitted. Any inner error unsubscribes the rest immediately. Cancel is silent. There is no partial flush of a snapshot on complete |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Not mergeAll. Not a running combine of a changing set. |

## B. Six-tuple

The machine is the helper specialized to `joinFn = combineLatest`. Snapshot guard: `remainingFirstValues` hits 0 (`combineLatest.ts:265-268`), then every next does `subscriber.next(values.slice())` (`combineLatest.ts:268`). The helper's project, if any, maps that array afterwards. `combineLatest([])` completes without a next (`combineLatest.ts:203-207`).

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with joinFn = combineLatest |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C, combine guards only |
| lambda | Section C |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| collecting | buf of ObservableInputs; no subscriptions | active, no inner. No at-capacity state |
| joining | subscribed set = buf; latest slots; remainingFirst | outer-completed. Emit only when every slot has been written at least once |
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

Zip-specific rows are not included. The outer-completed phase is `joining`. At-capacity is explicitly not a location.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CL-01 | init / s0 | subscribe / consumer | pipe subscribes toArray, which subscribes the source. No inner ObservableInput is subscribed | eps | buf:=[]; collecting | collecting | epsilon | active inner set is empty. This is the active-no-inner location. No concurrent cap | T-CL-01 |
| CL-02 | collecting | outerNext(v) / source | v is stored by reference. toArray/reduce does not call innerFrom | eps | buf.push(v) | collecting | subscribe | still no inner subscription. A hot v may emit elsewhere; this operator does not see it. A cold v does not start | T-CL-02 |
| CL-03 | collecting | outerError(e) / source | toArray/reduce has no custom onError, so the array is not emitted | error(e) | discard buf; never call joinFn; no inner subscribe | terminal_error | collecting | terminal; no complete; no partial join | T-CL-03 |
| CL-04 | collecting | cancel / consumer | consumer unsubscribes during collection | eps | unsubscribe source; discard buf; no complete | terminal_cancelled | collecting | terminal silent | T-CL-04 |
| CL-05 | collecting | innerNext / innerError / innerComplete | no inner has been subscribed. Unreachable under the subscription boundary | eps | none | collecting | subscribe | excluded | T-CL-05 |
| CL-06 | collecting | outerComplete / source | buf is empty. toArray emits [] and completes. combineLatest([]) is from([]), which completes with no next and does not call project | complete | subscribe the empty join, which completes synchronously; project is not applied | terminal_complete | subscribe then outerComplete with no values | terminal complete; zero next notifications. At-capacity does not apply | T-CL-06 |
| CL-07 | collecting | outerComplete / source | buf has one or more inputs and joining them succeeds in subscribing | eps | toArray emits the array once; mergeMap projects it by joinFn and subscribes; source of toArray is already complete so mergeMap is in its wait-for-the-one-inner state. Inners subscribe now, in index order, synchronously when no scheduler is passed (joinAllInternals passes none) | joining | one or more outerNext values, then outerComplete | THIS is the outer-completed phase. Inners are subscribed only after outer complete, not when they arrived. Active set size equals buf.length, which is unbounded, so the machine stays extended/symbolic. No concurrent parameter | T-CL-07 |
| CL-08 | collecting | outerComplete / source | joinFn or an innerFrom inside the join throws while subscribing the collected inputs (invalid ObservableInput) | error(e) | inners already subscribed in the loop are unsubscribed by the error teardown; later inputs are not subscribed | terminal_error | outer completed with a bad collected input | terminal. This is a subscribe-time failure of the join, not an outerError | T-CL-08 |
| CL-09 | joining | innerNext(id, x) / inner id | not every collected inner has produced a first value yet | eps | store latest[id]:=x; if this was id's first value, decrement remainingFirst. Do not emit the pre-first values that were overwritten | joining | outer already complete; inners subscribed | still waiting for a first value from every inner. No at-capacity queue of outers (collection is finished) | T-CL-09 |
| CL-10 | joining | innerNext(id, x) / inner id | this next makes remainingFirst hit 0, or remainingFirst is already 0. Optional project is absent or returns r | next(snapshot array) or next(project(...snapshot)) once project is present | emit a copy of the latest array in collection order. mapOneOrManyArgs spreads that array into project | joining | every inner has now emitted at least once | later nexts from any inner emit again with the updated slot | T-CL-10 |
| CL-11 | joining | innerNext(id, x) / inner id | optional project throws (projectThrow). Not a deprecated resultSelector; the parameter is live | error(e) | map OperatorSubscriber sends destination.error; unsubscribe every inner | terminal_error | a snapshot was about to be projected | terminal; no complete | T-CL-11 |
| CL-12 | joining | innerComplete(id) / inner id | other inners still active | eps | active--. If id never emitted, remainingFirst stays > 0, so a later snapshot is impossible | joining | joining | if some inner completed with no value, the output can still only complete, never next, once the rest finish | T-CL-12 |
| CL-13 | joining | innerComplete(id) / inner id | this completion brings the combineLatest active count to 0 | complete | no extra next is synthesized. If no snapshot was ever emitted, the output completes with zero nexts | terminal_complete | all collected inners have completed | terminal complete. mergeMap then completes because its only inner completed and its source (toArray) is already complete | T-CL-13 |
| CL-14 | joining | innerError(id, e) / inner id | any collected inner errors. No catch inside combineLatest, zip, or the mergeMap that hosts them | error(e) | unsubscribe every other inner and the outer join immediately | terminal_error | joining | terminal; no complete | T-CL-14 |
| CL-15 | joining | outerNext / outerError / outerComplete | the source already completed into toArray before joining. Further outer notifications are not enabled | eps | none | joining | outerComplete already consumed | not enabled | T-CL-15 |
| CL-16 | joining | cancel / consumer | consumer unsubscribes while the join is live | eps | unsubscribe every inner; no complete | terminal_cancelled | joining | terminal silent | T-CL-16 |
| CL-17 | collecting | outerComplete with synchronous inners | after subscribe-all, synchronous innerNext/innerComplete are separate Sigma events before the join subscribe call returns. Included. A downstream subscriber calling back into the source during a next is excluded | per those events | combineLatest subscribes in index order and does not use zip's subscriber.closed loop check. A synchronous error still tears the subscriber down. Synchronous inner nexts are separate Sigma events and can emit a snapshot once every inner has a first value | as those events specify | outerComplete of a non-empty buf | synchronous inner behavior is in the model | T-CL-17 |
| CL-18 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-CL-18 |

Latest-value overwrite before the first snapshot is combineLatest.ts:257-264: values[i] = value, and next happens only when remainingFirstValues is 0. The emitted array is a shallow copy (values.slice()).

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
| I9 | joinFn is combineLatest | combineLatestAll.ts:49 |
| I10 | No emission until every collected inner has emitted once, unless the collection is empty (complete, no next) or an inner errors | combineLatest.ts:244-269 |
| I11 | Completion of all inners completes the output even when remainingFirst never hit 0 | combineLatest.ts:271-276 |
| I12 | project is optional and not a deprecated resultSelector | combineLatestAll.ts:10-20 and 48-49 |
| I13 | There is no concurrent parameter | combineLatestAll.ts:48-50 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-CL-1 combineLatestAll: two inners, snapshot after both have values

| Field | Value |
| --- | --- |
| Scenario ID | E-CL-1 |
| Title | combineLatestAll: two inners, snapshot after both have values |
| Parameters | no project |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), outerNext(in2), outerComplete, innerNext(id1, a), innerNext(id2, b), innerNext(id1, a2) |
| Transition IDs | CL collect rows, CL outerComplete, CL wait innerNext, CL snapshot innerNext twice |
| Guards | no subscribe before outerComplete. First snapshot only on id2's first value. id1's a is held and then replaced in the second snapshot |
| Notifications (Gamma) | next([a, b]), next([a2, b]) |
| Lifecycle | both inners subscribed only after outerComplete, order 0 then 1 |
| Suffix | joining; not complete |
| End state | joining |
| Oracle | contract combineLatestAll.ts:11-20 together with combineLatest.ts:92-110 |
| Source characterization | combineLatestAll.ts:48-50; combineLatest.ts:257-269 |

### E-CL-2 combineLatestAll: source error subscribes nothing

| Field | Value |
| --- | --- |
| Scenario ID | E-CL-2 |
| Title | combineLatestAll: source error subscribes nothing |
| Parameters | no project |
| Start state | collecting |
| Prefix | two inners collected |
| Input word | outerError(e) |
| Transition IDs | CL outerError |
| Guards | toArray does not emit |
| Notifications (Gamma) | error(e) |
| Lifecycle | no innerFrom on the collected inputs |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: this is not mergeAll, which would already be subscribed |
| Source characterization | joinAllInternals.ts:21-23; toArray.ts:14-16 |

### E-CL-3 combineLatestAll: an inner completes with no value, then everyone completes

| Field | Value |
| --- | --- |
| Scenario ID | E-CL-3 |
| Title | combineLatestAll: an inner completes with no value, then everyone completes |
| Parameters | no project; two inners |
| Start state | joining |
| Prefix | outer completed; both subscribed; neither has nexted |
| Input word | innerComplete(id1), innerNext(id2, b), innerComplete(id2) |
| Transition IDs | CL innerComplete while others active; CL innerNext while remainingFirst > 0; CL last innerComplete |
| Guards | id1 never wrote a slot, so remainingFirst cannot hit 0. Last completion drives active to 0 |
| Notifications (Gamma) | complete. No next |
| Lifecycle | both inners end |
| Suffix | terminal_complete with an empty next-word |
| End state | terminal_complete |
| Oracle | combineLatest docs at combineLatest.ts:97-102 and the active-- complete path at 271-276 |
| Source characterization | combineLatest.ts:271-276 |

### E-CL-4 combineLatestAll: inner error, project throw, and cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-CL-4 |
| Title | combineLatestAll: inner error, project throw, and cancel |
| Parameters | project on the throw word only |
| Start state | joining or collecting |
| Prefix | as required |
| Input word | innerError(id, e) after a snapshot was possible; project throws on a snapshot; cancel while collecting |
| Transition IDs | CL innerError; CL projectThrow; CL cancel |
| Guards | project spreads the snapshot array |
| Notifications (Gamma) | error(e); error(e); eps |
| Lifecycle | inner error unsubscribes the other inners. cancel does not complete |
| Suffix | terminal |
| End state | terminal |
| Oracle | source characterization: no inner catch. project is live, not a deprecated resultSelector. Cancel is silent |
| Source characterization | combineLatest.ts:109-110; joinAllInternals.ts:27; Subscriber.ts:104-121 |

### E-CL-5 combineLatestAll: empty source

| Field | Value |
| --- | --- |
| Scenario ID | E-CL-5 |
| Title | combineLatestAll: empty source |
| Parameters | no project |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerComplete |
| Transition IDs | CL empty outerComplete |
| Guards | combineLatest([]) |
| Notifications (Gamma) | complete |
| Lifecycle | no inners |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization via from([]) inside combineLatest |
| Source characterization | combineLatest.ts:203-207 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **18**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/18**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| CL-01 | not executed | static reading only; no runner |
| CL-02 | not executed | static reading only; no runner |
| CL-03 | not executed | static reading only; no runner |
| CL-04 | not executed | static reading only; no runner |
| CL-05 | not executed | static reading only; no runner |
| CL-06 | not executed | static reading only; no runner |
| CL-07 | not executed | static reading only; no runner |
| CL-08 | not executed | static reading only; no runner |
| CL-09 | not executed | static reading only; no runner |
| CL-10 | not executed | static reading only; no runner |
| CL-11 | not executed | static reading only; no runner |
| CL-12 | not executed | static reading only; no runner |
| CL-13 | not executed | static reading only; no runner |
| CL-14 | not executed | static reading only; no runner |
| CL-15 | not executed | static reading only; no runner |
| CL-16 | not executed | static reading only; no runner |
| CL-17 | not executed | static reading only; no runner |
| CL-18 | not executed | static reading only; no runner |

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
| Limits | Collect-then-combineLatest. No concurrent cap. Waits for a first value from every inner. project is live. Not a running merge of active inners. |

Documented limits:

- Body is `joinAllInternals(combineLatest, project)`.
- Inners are subscribed only after the outer completes. The active set before that is empty.
- No concurrent parameter. The collected list is unbounded, so the model stays extended.
- Emission rule after subscribe: every inner must have produced one value. Latest-only before that. Then every next emits a full snapshot.
- An inner that completes with no value suppresses snapshots; overall completion still happens when all inners complete.
- `project` is not deprecated. There is no `resultSelector` parameter by that name.
- Queue versus drop does not apply to source values: they are all collected. They are not inner-subscribed early.
- No tests were executed.

