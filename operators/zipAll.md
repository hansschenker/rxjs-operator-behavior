# zipAll

`zipAll` collects higher-order inputs and, after the source completes, zips them by index (RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791). The body is `return joinAllInternals(zip, project)` (`zipAll.ts:18-20`). The JSDoc says it collects all inner sources and, once the source completes, subscribes and combines their values by index (`zipAll.ts:6-8`). That is the same collector as `combineLatestAll`, with `zip` instead of `combineLatest`. Inners are not subscribed as they arrive. `zip` (`zip.ts:53-117`) gives each source a buffer. When every buffer is nonempty it shifts one value from each and emits an array (`zip.ts:86-90`). It completes when any source completes with an empty buffer (`zip.ts:102-105`), or when a shift leaves a completed source's buffer empty (`zip.ts:93-95`). Leftover values in other buffers are dropped. `zip([])` is `EMPTY`, which completes with no next (`zip.ts:58` and `116`). `project` is optional and is applied by the helper after `zip`, not as `zip`'s own resultSelector (`joinAllInternals.ts:25` calls `zip(sources)` with one argument). It is not deprecated in `zipAll.ts`. There is no concurrent parameter.

## A. Identity, contract, and scope


| Field | Value |
| --- | --- |
| operator/overload | zipAll() and zipAll(project). project is optional and not deprecated in this file. No concurrent |
| version/commit | RxJS 7.8.2 commit e5351d02e225e275ac0e497c7b66eaa5f0c88791 |
| intended behavior | When the source completes, subscribe to every collected inner and emit index-aligned tuples until one inner can no longer contribute |
| model kind | Extended/symbolic Mealy machine. Collected list unbounded. No concurrent cap. Per-inner buffers during joining are a second unbounded store |
| parameter domain | Optional project: (...values) => R. No resultSelector parameter on zipAll itself |
| payload/error domain | Output is T[] or R. Errors: outerError during collect, innerError during zip, projectThrow, invalid ObservableInput at join subscribe |
| subscription boundary | No inner subscribe before outer complete. Then all collected inputs, in a for-loop that aborts if the subscriber closes (zip.ts:77). Not a mergeMap concurrency queue |
| scheduler/tie ordering | No scheduler. Synchronous emissions during subscribe are ordered events and can complete the zip before later sources are subscribed, which drops those later subscriptions |
| callback assumptions | project is synchronous and may throw on a tuple. zip itself is called without a resultSelector; the helper maps afterwards |
| cleanup assumptions | Completing because one buffer is exhausted unsubscribes the other inners and drops their leftovers. Inner error fails immediately. Cancel is silent. Empty collection completes with no next |
| explicit exclusions | Ordinary model includes synchronous inner notifications as separate Sigma events ordered immediately after the subscribe that provoked them. It excludes reentrant calls from a downstream subscriber back into the source during delivery. It also assumes an inner that has been unsubscribed produces no further modeled notifications (a stopped Subscriber does not forward them; Subscriber.ts:81-88 and 255-258). Not combineLatestAll's latest-value rule. Not mergeAll. |

## B. Six-tuple

Specializing the helper to `zip` changes only the joining guards. Collection is still `toArray`. A tuple is emitted only when `buffers.every(buffer => buffer.length)` (`zip.ts:86`). Completion on a source is `!buffers[sourceIndex].length && subscriber.complete()` (`zip.ts:105`). So an empty inner completes the output with no next, and a longer inner does not stretch the output past the shortest one.

### Six-tuple

| Component | Definition |
| --- | --- |
| M | (S, Sigma, Gamma, delta, lambda, s0) with joinFn = zip |
| S | control location crossed with the data store named in the S table. Not a finite set: payloads, indexes, and (where present) the buffer or the collected-inner list are unbounded |
| Sigma | the eight categories in the Sigma table |
| Gamma | finite sequences of notification records {next: optional value, error: optional error, complete: bool}. At most one terminal record. eps is the empty sequence |
| delta | Section C, zip guards only |
| lambda | Section C |
| s0 | init |

### S (control locations and data)

| Location | Data invariant at entry | Role |
| --- | --- | --- |
| init | unsubscribed | s0 |
| collecting | buf of ObservableInputs; no subscriptions | no inner. No at-capacity gate |
| joining | one buffer and one completed flag per collected index | outer-completed zip. Emit by index alignment, not by latest-value |
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

Combine-latest snapshot rows are not included. Draining in the merge sense is this joining phase: the outer is already complete before any inner next.

Columns: ID, State/data, Input/origin, Guard, Notifications, Lifecycle, Next state, Prefix, Suffix, Test IDs. Prefix is a representative word from `s0` that establishes the row's pre-state. Suffix is the residual obligation after the transition (who is still subscribed, what remains buffered, or that the machine is terminal). `eps` means no downstream notification. Synchronous inner notifications that RxJS delivers inside `subscribe` are separate later input events, ordered immediately after the input that caused the subscription. They are in the model. What is excluded is a downstream subscriber re-entering the source during delivery.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ZA-01 | init / s0 | subscribe / consumer | pipe subscribes toArray, which subscribes the source. No inner ObservableInput is subscribed | eps | buf:=[]; collecting | collecting | epsilon | active inner set is empty. This is the active-no-inner location. No concurrent cap | T-ZA-01 |
| ZA-02 | collecting | outerNext(v) / source | v is stored by reference. toArray/reduce does not call innerFrom | eps | buf.push(v) | collecting | subscribe | still no inner subscription. A hot v may emit elsewhere; this operator does not see it. A cold v does not start | T-ZA-02 |
| ZA-03 | collecting | outerError(e) / source | toArray/reduce has no custom onError, so the array is not emitted | error(e) | discard buf; never call joinFn; no inner subscribe | terminal_error | collecting | terminal; no complete; no partial join | T-ZA-03 |
| ZA-04 | collecting | cancel / consumer | consumer unsubscribes during collection | eps | unsubscribe source; discard buf; no complete | terminal_cancelled | collecting | terminal silent | T-ZA-04 |
| ZA-05 | collecting | innerNext / innerError / innerComplete | no inner has been subscribed. Unreachable under the subscription boundary | eps | none | collecting | subscribe | excluded | T-ZA-05 |
| ZA-06 | collecting | outerComplete / source | buf is empty. toArray emits [] and completes. zip([]) returns EMPTY, which completes with no next and does not call project | complete | subscribe the empty join, which completes synchronously; project is not applied | terminal_complete | subscribe then outerComplete with no values | terminal complete; zero next notifications. At-capacity does not apply | T-ZA-06 |
| ZA-07 | collecting | outerComplete / source | buf has one or more inputs and joining them succeeds in subscribing | eps | toArray emits the array once; mergeMap projects it by joinFn and subscribes; source of toArray is already complete so mergeMap is in its wait-for-the-one-inner state. Inners subscribe now, in index order, synchronously when no scheduler is passed (joinAllInternals passes none) | joining | one or more outerNext values, then outerComplete | THIS is the outer-completed phase. Inners are subscribed only after outer complete, not when they arrived. Active set size equals buf.length, which is unbounded, so the machine stays extended/symbolic. No concurrent parameter | T-ZA-07 |
| ZA-08 | collecting | outerComplete / source | joinFn or an innerFrom inside the join throws while subscribing the collected inputs (invalid ObservableInput) | error(e) | inners already subscribed in the loop are unsubscribed by the error teardown; later inputs are not subscribed | terminal_error | outer completed with a bad collected input | terminal. This is a subscribe-time failure of the join, not an outerError | T-ZA-08 |
| ZA-09 | joining | innerNext(id, x) / inner id | after push, some inner buffer is still empty | eps | buffers[id].push(x). No tuple yet | joining | joining | x is held until every index has a buffered value | T-ZA-09 |
| ZA-10 | joining | innerNext(id, x) / inner id | this push makes every buffer nonempty. project absent or returns | next(array of shifted heads) or next(project(...heads)) | shift one value from each buffer in index order; if some buffer is now empty AND that source has completed, also complete | joining or terminal_complete if the complete-side guard fires in the same next | a full index-aligned tuple became available | leftover buffers stay for the next tuple. project is the post-map, not zip's own resultSelector (joinAllInternals calls zip(sources) with no selector) | T-ZA-10 |
| ZA-11 | joining | innerNext(id, x) / inner id | project throws on the emitted tuple | error(e) projectThrow | unsubscribe all inners | terminal_error | tuple ready | terminal | T-ZA-11 |
| ZA-12 | joining | innerComplete(id) / inner id | buffers[id] is empty | complete | cannot form another tuple; other inners unsubscribed by the downstream complete; their buffered leftovers are dropped and not emitted | terminal_complete | a source completed with nothing left to pair | terminal complete. An empty inner therefore yields complete and no next | T-ZA-12 |
| ZA-13 | joining | innerComplete(id) / inner id | buffers[id] is still nonempty | eps | mark that source completed; keep pairing until a shift empties it | joining | source completed ahead of its buffer | further tuples can still be emitted from the leftover | T-ZA-13 |
| ZA-14 | joining | innerError(id, e) / inner id | any collected inner errors. No catch inside combineLatest, zip, or the mergeMap that hosts them | error(e) | unsubscribe every other inner and the outer join immediately | terminal_error | joining | terminal; no complete | T-ZA-14 |
| ZA-15 | joining | outerNext / outerError / outerComplete | the source already completed into toArray before joining. Further outer notifications are not enabled | eps | none | joining | outerComplete already consumed | not enabled | T-ZA-15 |
| ZA-16 | joining | cancel / consumer | consumer unsubscribes while the join is live | eps | unsubscribe every inner; no complete | terminal_cancelled | joining | terminal silent | T-ZA-16 |
| ZA-17 | collecting | outerComplete with synchronous inners | after subscribe-all, synchronous innerNext/innerComplete are separate Sigma events before the join subscribe call returns. Included. A downstream subscriber calling back into the source during a next is excluded | per those events | zip's for-loop stops subscribing later sources if subscriber.closed becomes true mid-loop (zip.ts:77). Synchronous inner notifications are separate Sigma events | as those events specify | outerComplete of a non-empty buf | synchronous inner behavior is in the model | T-ZA-17 |
| ZA-18 | terminal (complete, error, or cancelled) | any of the 8 categories | location is already terminal; Subscriber.isStopped | eps | none; stopped next/complete are ignored; stopped error is not forwarded by this operator | same terminal | a word that already took a terminal transition | no further Gamma; no revival | T-ZA-18 |

zip's resultSelector pop is not used, because the helper calls zip(sources) with the array as the only argument (popResultSelector sees an array, not a function). User project is mapOneOrManyArgs after the array is emitted.

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
| I9 | joinFn is zip | zipAll.ts:19 |
| I10 | Tuples are index-aligned shifts, not latest-value snapshots | zip.ts:81-90 |
| I11 | The output length in tuples is the minimum inner length. Leftovers are dropped on complete | zip.ts:93-105 |
| I12 | No inner subscription before outer complete | joinAllInternals.ts:21-25 |
| I13 | project is optional, applied outside zip, and is not deprecated in zipAll.ts | zipAll.ts:15-19; joinAllInternals.ts:27 |
| I14 | There is no concurrent parameter | zipAll.ts:18-20 |

## E. Scenario specification

Each scenario uses the same field template. Oracle is either the documented contract or a source characterization where the implementation is more specific than the prose docs. No scenario was executed.

### E-ZA-1 zipAll: tuples by index after the source completes

| Field | Value |
| --- | --- |
| Scenario ID | E-ZA-1 |
| Title | zipAll: tuples by index after the source completes |
| Parameters | no project |
| Start state | s0 |
| Prefix | epsilon |
| Input word | subscribe, outerNext(in1), outerNext(in2), outerComplete, innerNext(id1, a1), innerNext(id1, a2), innerNext(id2, b1) |
| Transition IDs | ZA collect, ZA outerComplete, ZA innerNext held, ZA innerNext tuple |
| Guards | no subscription before outerComplete. The tuple waits until id2 has a value even though id1 already buffered two |
| Notifications (Gamma) | next([a1, b1]). a2 stays buffered |
| Lifecycle | both subscribed after outer complete |
| Suffix | joining; one value still buffered on id1 |
| End state | joining |
| Oracle | contract zipAll.ts:6-8 and zip.ts:86-90 |
| Source characterization | zipAll.ts:18-20; zip.ts:81-90 |

### E-ZA-2 zipAll: shortest inner completes the output and drops leftovers

| Field | Value |
| --- | --- |
| Scenario ID | E-ZA-2 |
| Title | zipAll: shortest inner completes the output and drops leftovers |
| Parameters | no project |
| Start state | joining |
| Prefix | id1 buffer holds a2; a tuple was already emitted |
| Input word | innerComplete(id2) while id2's buffer is empty |
| Transition IDs | ZA innerComplete with empty buffer |
| Guards | zip.ts:105 |
| Notifications (Gamma) | complete. a2 is not emitted |
| Lifecycle | id1 unsubscribed by the complete teardown |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization: zip completes when a source cannot contribute another value, and does not pad |
| Source characterization | zip.ts:98-105 |

### E-ZA-3 zipAll: source error never subscribes; empty source completes with no next

| Field | Value |
| --- | --- |
| Scenario ID | E-ZA-3 |
| Title | zipAll: source error never subscribes; empty source completes with no next |
| Parameters | no project |
| Start state | collecting or s0 |
| Prefix | either some collected values, or none |
| Input word | outerError(e); separately subscribe, outerComplete on an empty source |
| Transition IDs | ZA outerError; ZA empty outerComplete |
| Guards | toArray suppresses the array on error. zip([]) is EMPTY |
| Notifications (Gamma) | error(e); complete |
| Lifecycle | no inners in either word |
| Suffix | terminal |
| End state | terminal |
| Oracle | source characterization of the collector plus EMPTY |
| Source characterization | toArray.ts:14-16; zip.ts:116 |

### E-ZA-4 zipAll: inner error, project throw, cancel

| Field | Value |
| --- | --- |
| Scenario ID | E-ZA-4 |
| Title | zipAll: inner error, project throw, cancel |
| Parameters | project on the throw word |
| Start state | joining or collecting |
| Prefix | as required |
| Input word | innerError(id, e); a tuple whose project throws; cancel while collecting |
| Transition IDs | ZA innerError; ZA projectThrow; ZA cancel |
| Guards | no catch in zip. project is post-map |
| Notifications (Gamma) | error(e); error(e); eps |
| Lifecycle | unsubscribe all inners on error. cancel silent |
| Suffix | terminal |
| End state | terminal |
| Oracle | source characterization: inner error fails the outer. projectThrow is its own outcome and is not a deprecated resultSelector. Cancel is not complete |
| Source characterization | zip.ts:78-90; joinAllInternals.ts:27; Subscriber.ts:104-121 |

### E-ZA-5 zipAll: synchronous empty inner during subscribe completes before later inners subscribe

| Field | Value |
| --- | --- |
| Scenario ID | E-ZA-5 |
| Title | zipAll: synchronous empty inner during subscribe completes before later inners subscribe |
| Parameters | no project; first collected input is EMPTY |
| Start state | collecting |
| Prefix | outerNext(EMPTY), outerNext(in2), ... |
| Input word | outerComplete |
| Transition IDs | ZA outerComplete then synchronous innerComplete of the empty source |
| Guards | zip's loop checks subscriber.closed (zip.ts:77). EMPTY completes sync with an empty buffer, which completes the subscriber |
| Notifications (Gamma) | complete. in2 is not subscribed |
| Lifecycle | subscribe index 0; complete; skip the rest |
| Suffix | terminal_complete |
| End state | terminal_complete |
| Oracle | source characterization of synchronous inner notifications as ordered events, which this operator must include |
| Source characterization | zip.ts:77-78 and 102-105; empty.ts EMPTY completes immediately |

## F. Coverage and evidence

Denominator is the number of rows in section C: **18**. Numerator is the number of those rows executed against a runtime: **0**. Ratio: **0/18**. Tests were not executed. No mutations were applied.

| Transition ID | Executed | Notes |
| --- | --- | --- |
| ZA-01 | not executed | static reading only; no runner |
| ZA-02 | not executed | static reading only; no runner |
| ZA-03 | not executed | static reading only; no runner |
| ZA-04 | not executed | static reading only; no runner |
| ZA-05 | not executed | static reading only; no runner |
| ZA-06 | not executed | static reading only; no runner |
| ZA-07 | not executed | static reading only; no runner |
| ZA-08 | not executed | static reading only; no runner |
| ZA-09 | not executed | static reading only; no runner |
| ZA-10 | not executed | static reading only; no runner |
| ZA-11 | not executed | static reading only; no runner |
| ZA-12 | not executed | static reading only; no runner |
| ZA-13 | not executed | static reading only; no runner |
| ZA-14 | not executed | static reading only; no runner |
| ZA-15 | not executed | static reading only; no runner |
| ZA-16 | not executed | static reading only; no runner |
| ZA-17 | not executed | static reading only; no runner |
| ZA-18 | not executed | static reading only; no runner |

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
| Limits | Collect-then-zip. No concurrent cap. Tuples by index. Shortest inner wins. Leftovers dropped. project is live. Not combineLatest. |

Documented limits:

- Body is `joinAllInternals(zip, project)`.
- Inners subscribe only after the outer source completes.
- No concurrent parameter. Not mergeAll's queue and not exhaustAll's drop.
- Zip rule: one value from each inner per tuple, in collection order. Output completes when any inner completes with nothing left to pair. Leftovers are dropped.
- Empty collection completes with no `next`.
- `project` is optional, applied after `zip` emits arrays, and is not deprecated in this file.
- No tests were executed.

