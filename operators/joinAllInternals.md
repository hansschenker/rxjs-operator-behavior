# joinAllInternals

`joinAllInternals` is not a public operator. It is the shared collector for `combineLatestAll` and `zipAll` (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791, `joinAllInternals.ts:9-29`). The comment at lines 9-14 says it collects every inner source and, only once the source completes, joins them with the supplied static function. The implementation is `pipe(toArray(), mergeMap(sources => joinFn(sources)), project ? mapOneOrManyArgs(project) : identity)`. Inners are not subscribed when they arrive. There is no concurrent parameter. `project`, if passed, is a live mapping of each joined emission, not a deprecated `resultSelector`. The higher-order rule is therefore not 'combine whatever inners are currently active'. It is 'buffer the inputs, then subscribe to all of them together'.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | Internal helper joinAllInternals(joinFn, project?). Not an OperatorFunction export by itself. joinFn is combineLatest or zip. project is optional |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | Collect every source emission until the source completes or errors. On complete, subscribe to joinFn(collected) exactly once and forward its notifications, optionally through project. On source error, fail without joining |
| model kind | Extended/symbolic Mealy machine. The collected list is unbounded. After outer complete the active set is that entire list (or empty). No concurrent cap makes it finite |
| parameter domain | joinFn: (ObservableInput[]) => Observable. project: optional (...values) => R. No concurrent. No scheduler |
| payload/error domain | Collected payloads are ObservableInputs. Output payloads are join emissions or project results. Errors: outerError before join, innerError after join, projectThrow, innerFrom throw while the join subscribes |
| subscription boundary | Source subscribed by toArray. Zero inner subscriptions until outer complete. Then one mergeMap inner, which is the join observable, which subscribes each collected input. mergeMap concurrency is irrelevant because toArray emits a single array |
| scheduler/tie ordering | No scheduler is passed. combineLatest and zip subscribe from index 0 upward synchronously. Sync notifications from an early inner are Sigma events before later inners are subscribed. zip stops the loop if the subscriber is already closed (zip.ts:77) |
| callback assumptions | joinFn is combineLatest or zip and returns an Observable without subscribing. project is synchronous and may throw when a tuple or snapshot is delivered. identity-as-operator is used when project is omitted (pipe of identity returns the source unchanged) |
| cleanup assumptions | Source error skips joinFn. Join error unsubscribes remaining inners. Join complete completes the mergeMap (its source is already complete) and therefore the output. Cancel discards the buffer or the live join and does not complete |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). This helper does not implement the combine or zip emission rule itself; those are joinFn. Both are guarded in section C because both callers exist. |

## B. Six-tuple

Phases are collecting, then joining. `toArray` (`toArray.ts:37-44`) is `reduce` pushing into a seed array and emitting that array on complete. `mergeMap` then subscribes to exactly one inner, `joinFn(array)` (`joinAllInternals.ts:25`). The output completes when that inner completes. There is no location in which some inners are subscribed and the outer is still open.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) parameterized by joinFn and project |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C. Guards name combineLatest versus zip when the rule differs |
| lambda | Section C |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| collecting | buf: ObservableInput[]; no inners; outer open | active set empty. No at-capacity location: every arrival is stored |
| joining | outer complete; join subscribed; per-strategy buffers or latest-slots | the outer-completed phase. Active set size equals the collected length, which is unbounded |
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

init, collecting (active, no inner subscribed), joining (outer completed, inners running), and terminals. At-capacity is not applicable; the note is on the outerComplete row. Both combineLatest and zip guards are included because this helper is shared.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JA-01 | init / s0 | subscribe / consumer | pipe subscribes toArray, which subscribes the source. No inner ObservableInput is subscribed | eps | buf:=[]; collecting | collecting | epsilon | active inner set is empty. This is the active-no-inner location. No concurrent cap | T-JA-01 |
| JA-02 | collecting | outerNext(v) / source | v is stored by reference. toArray/reduce does not call innerFrom | eps | buf.push(v) | collecting | subscribe | still no inner subscription. A hot v may emit elsewhere; this operator does not see it. A cold v does not start | T-JA-02 |
| JA-03 | collecting | outerError(e) / source | toArray/reduce has no custom onError, so the array is not emitted | error(e) | discard buf; never call joinFn; no inner subscribe | terminal_error | collecting | terminal; no complete; no partial join | T-JA-03 |
| JA-04 | collecting | cancel / consumer | consumer unsubscribes during collection | eps | unsubscribe source; discard buf; no complete | terminal_cancelled | collecting | terminal silent | T-JA-04 |
| JA-05 | collecting | innerNext / innerError / innerComplete | no inner has been subscribed. Unreachable under the subscription boundary | eps | none | collecting | subscribe | excluded | T-JA-05 |
| JA-06 | collecting | outerComplete / source | buf is empty. toArray emits [] and completes. mergeMap subscribes joinFn([]). combineLatest([]) completes with no next (from empty). zip([]) is EMPTY, complete with no next | complete | subscribe the empty join, which completes synchronously; project is not applied | terminal_complete | subscribe then outerComplete with no values | terminal complete; zero next notifications. At-capacity does not apply | T-JA-06 |
| JA-07 | collecting | outerComplete / source | buf has one or more inputs and joining them succeeds in subscribing | eps | toArray emits the array once; mergeMap projects it by joinFn and subscribes; source of toArray is already complete so mergeMap is in its wait-for-the-one-inner state. Inners subscribe now, in index order, synchronously when no scheduler is passed (joinAllInternals passes none) | joining | one or more outerNext values, then outerComplete | THIS is the outer-completed phase. Inners are subscribed only after outer complete, not when they arrived. Active set size equals buf.length, which is unbounded, so the machine stays extended/symbolic. No concurrent parameter | T-JA-07 |
| JA-08 | collecting | outerComplete / source | joinFn or an innerFrom inside the join throws while subscribing the collected inputs (invalid ObservableInput) | error(e) | inners already subscribed in the loop are unsubscribed by the error teardown; later inputs are not subscribed | terminal_error | outer completed with a bad collected input | terminal. This is a subscribe-time failure of the join, not an outerError | T-JA-08 |
| JA-09 | joining | innerNext(id, x) / inner id | joinFn is combineLatest. not every collected inner has produced a first value yet | eps | store latest[id]:=x; if this was id's first value, decrement remainingFirst. Do not emit the pre-first values that were overwritten | joining | outer already complete; inners subscribed | still waiting for a first value from every inner. No at-capacity queue of outers (collection is finished) | T-JA-09 |
| JA-10 | joining | innerNext(id, x) / inner id | joinFn is combineLatest. this next makes remainingFirst hit 0, or remainingFirst is already 0. Optional project is absent or returns r | next(snapshot array) or next(project(...snapshot)) once project is present | emit a copy of the latest array in collection order. mapOneOrManyArgs spreads that array into project | joining | every inner has now emitted at least once | later nexts from any inner emit again with the updated slot | T-JA-10 |
| JA-11 | joining | innerNext(id, x) / inner id | joinFn is combineLatest. optional project throws (projectThrow). Not a deprecated resultSelector; the parameter is live | error(e) | map OperatorSubscriber sends destination.error; unsubscribe every inner | terminal_error | a snapshot was about to be projected | terminal; no complete | T-JA-11 |
| JA-12 | joining | innerComplete(id) / inner id | joinFn is combineLatest. other inners still active | eps | active--. If id never emitted, remainingFirst stays > 0, so a later snapshot is impossible | joining | joining | if some inner completed with no value, the output can still only complete, never next, once the rest finish | T-JA-12 |
| JA-13 | joining | innerComplete(id) / inner id | joinFn is combineLatest. this completion brings the combineLatest active count to 0 | complete | no extra next is synthesized. If no snapshot was ever emitted, the output completes with zero nexts | terminal_complete | all collected inners have completed | terminal complete. mergeMap then completes because its only inner completed and its source (toArray) is already complete | T-JA-13 |
| JA-14 | joining | innerNext(id, x) / inner id | joinFn is zip. after push, some inner buffer is still empty | eps | buffers[id].push(x). No tuple yet | joining | joining | x is held until every index has a buffered value | T-JA-14 |
| JA-15 | joining | innerNext(id, x) / inner id | joinFn is zip. this push makes every buffer nonempty. project absent or returns | next(array of shifted heads) or next(project(...heads)) | shift one value from each buffer in index order; if some buffer is now empty AND that source has completed, also complete | joining or terminal_complete if the complete-side guard fires in the same next | a full index-aligned tuple became available | leftover buffers stay for the next tuple. project is the post-map, not zip's own resultSelector (joinAllInternals calls zip(sources) with no selector) | T-JA-15 |
| JA-16 | joining | innerNext(id, x) / inner id | joinFn is zip. project throws on the emitted tuple | error(e) projectThrow | unsubscribe all inners | terminal_error | tuple ready | terminal | T-JA-16 |
| JA-17 | joining | innerComplete(id) / inner id | joinFn is zip. buffers[id] is empty | complete | cannot form another tuple; other inners unsubscribed by the downstream complete; their buffered leftovers are dropped and not emitted | terminal_complete | a source completed with nothing left to pair | terminal complete. An empty inner therefore yields complete and no next | T-JA-17 |
| JA-18 | joining | innerComplete(id) / inner id | joinFn is zip. buffers[id] is still nonempty | eps | mark that source completed; keep pairing until a shift empties it | joining | source completed ahead of its buffer | further tuples can still be emitted from the leftover | T-JA-18 |
| JA-19 | joining | innerError(id, e) / inner id | any collected inner errors. No catch inside combineLatest, zip, or the mergeMap that hosts them | error(e) | unsubscribe every other inner and the outer join immediately | terminal_error | joining | terminal; no complete | T-JA-19 |
| JA-20 | joining | outerNext / outerError / outerComplete | the source already completed into toArray before joining. Further outer notifications are not enabled | eps | none | joining | outerComplete already consumed | not enabled | T-JA-20 |
| JA-21 | joining | cancel / consumer | consumer unsubscribes while the join is live | eps | unsubscribe every inner; no complete | terminal_cancelled | joining | terminal silent | T-JA-21 |
| JA-22 | collecting | outerComplete with synchronous inners | after subscribe-all, synchronous innerNext/innerComplete are separate Sigma events before the join subscribe call returns. Included. A downstream subscriber calling back into the source during a next is excluded | per those events | zip's for-loop stops if subscriber.closed; combineLatest does not use that check. Synchronous inner notifications are separate Sigma events either way | as those events specify | outerComplete of a non-empty buf | synchronous inner behavior is in the model | T-JA-22 |
| JA-23 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-JA-23 |

mergeMap's own queue is not observable here: toArray emits one value. If that value's join errors, mergeMap fails. project is applied downstream of the join, so a projectThrow happens after the join has already assembled a snapshot or tuple.

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
| I9 | The helper never calls combineLatest or zip until toArray has emitted | pipe order joinAllInternals.ts:20-27 |
| I10 | project omitted means the identity function is used as a pipe step, i.e. no extra map | joinAllInternals.ts:27 |
| I11 | A hot inner's pre-subscription emissions are invisible. A cold inner starts at join time | ordinary subscribe, because no earlier subscribe exists |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-JA-1 joinAllInternals: collect then complete with an empty list

| Field | Value |
| --- | --- |
| Scenario ID | E-JA-1 |
| Title | joinAllInternals: collect then complete with an empty list |
| Parameters | either joinFn; no project |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerComplete |
| Transition IDs | JA subscribe, JA empty outerComplete |
| Guards | buf empty |
| Notifications (Gamma) | complete |
| Lifecycle | toArray emits []; join subscribes and completes sync; no inner source |
| Suffix | terminal_complete; zero nexts |
| End state | terminal_complete |
| Oracle | source characterization: empty combineLatest and empty zip both complete without a next |
| Source characterization | joinAllInternals.ts:20-25; combineLatest.ts:203-207; zip.ts:58 and 116 |

### E-JA-2 joinAllInternals: source error does not subscribe inners

| Field | Value |
| --- | --- |
| Scenario ID | E-JA-2 |
| Title | joinAllInternals: source error does not subscribe inners |
| Parameters | any joinFn |
| Start state | collecting |
| Prefix | subscribe, outerNext(in1), outerNext(in2) |
| Input word | outerError(e) |
| Transition IDs | JA collecting outerError |
| Guards | toArray/reduce forwards error and does not emit the array |
| Notifications (Gamma) | error(e) |
| Lifecycle | in1 and in2 were never subscribed |
| Suffix | terminal_error |
| End state | terminal_error |
| Oracle | source characterization: collection is not a join. Contrast with mergeAll, which would already have subscribed in1 |
| Source characterization | toArray.ts:14-16; joinAllInternals.ts:21-23 |

### E-JA-3 joinAllInternals: outer complete is what starts the inners

| Field | Value |
| --- | --- |
| Scenario ID | E-JA-3 |
| Title | joinAllInternals: outer complete is what starts the inners |
| Parameters | joinFn = combineLatest; two cold inners; no project |
| Start state | collecting |
| Prefix | outerNext(in1), outerNext(in2), no inner notifications yet because they are cold and unsubscribed |
| Input word | outerComplete, then innerNext(id1, a), innerNext(id2, b) |
| Transition IDs | JA non-empty outerComplete; JA combine waiting innerNext; JA combine first-snapshot innerNext |
| Guards | neither inner had a subscription before outerComplete. Snapshot waits for both first values |
| Notifications (Gamma) | eps until both have a value, then next([a, b]) |
| Lifecycle | both subscribed in order 0, 1 after outer complete |
| Suffix | joining; further nexts are new snapshots |
| End state | joining |
| Oracle | source characterization of the helper comment at joinAllInternals.ts:9-14, plus combineLatest's first-value gate |
| Source characterization | joinAllInternals.ts:19-25; combineLatest.ts:244-269 |

### E-JA-4 joinAllInternals: cancel while collecting, and project throw while joining

| Field | Value |
| --- | --- |
| Scenario ID | E-JA-4 |
| Title | joinAllInternals: cancel while collecting, and project throw while joining |
| Parameters | project provided on the second word |
| Start state | collecting, then joining |
| Prefix | as the location |
| Input word | cancel during collect; separately a join emission whose project throws |
| Transition IDs | JA cancel; JA projectThrow rows |
| Guards | project is mapOneOrManyArgs, live, not deprecated |
| Notifications (Gamma) | eps; error(e) |
| Lifecycle | cancel drops buf. projectThrow unsubscribes inners |
| Suffix | terminal_cancelled or terminal_error |
| End state | terminal |
| Oracle | source characterization: cancel is not complete. projectThrow is not innerError |
| Source characterization | joinAllInternals.ts:27; map.ts:54-57; Subscriber.ts:104-110 |

## F. Coverage and evidence

Denominator is the number of rows in section C: **23**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/23**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| JA-01 | not executed | static reading only; no runner |
| JA-02 | not executed | static reading only; no runner |
| JA-03 | not executed | static reading only; no runner |
| JA-04 | not executed | static reading only; no runner |
| JA-05 | not executed | static reading only; no runner |
| JA-06 | not executed | static reading only; no runner |
| JA-07 | not executed | static reading only; no runner |
| JA-08 | not executed | static reading only; no runner |
| JA-09 | not executed | static reading only; no runner |
| JA-10 | not executed | static reading only; no runner |
| JA-11 | not executed | static reading only; no runner |
| JA-12 | not executed | static reading only; no runner |
| JA-13 | not executed | static reading only; no runner |
| JA-14 | not executed | static reading only; no runner |
| JA-15 | not executed | static reading only; no runner |
| JA-16 | not executed | static reading only; no runner |
| JA-17 | not executed | static reading only; no runner |
| JA-18 | not executed | static reading only; no runner |
| JA-19 | not executed | static reading only; no runner |
| JA-20 | not executed | static reading only; no runner |
| JA-21 | not executed | static reading only; no runner |
| JA-22 | not executed | static reading only; no runner |
| JA-23 | not executed | static reading only; no runner |

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
| Limits | Internal collector. No subscribe-until-outer-complete. No concurrent cap. project is live. Join rule depends on joinFn. |

Documented limits:

- Not a user-facing operator. Callers are `combineLatestAll` and `zipAll`.
- Inners are not subscribed as they arrive. There is no 'currently active inner' set during collection.
- No concurrent parameter and no at-capacity queue of subscriptions. The collected array is unbounded.
- `project` is optional and not deprecated.
- Empty input completes with no `next`.
- No tests were executed.

