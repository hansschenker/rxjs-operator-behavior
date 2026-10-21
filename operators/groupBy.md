# groupBy

`groupBy(keySelector, elementOrOptions?, duration?, connector?)` (`operators/groupBy.ts` 141–277) groups source values into `GroupedObservable`s. The second argument is an element selector when it is a function or missing; when it is an object it supplies `element`, `duration`, and `connector` (lines 148–153). The positional `element` / `duration` / `connector` overloads are deprecated (JSDoc lines 34–49 and 131) but still implemented.

On each source value (lines 183–233), inside a try/catch that errors **every** group and the downstream subscriber (`handleError`, lines 165–166, 231–233):

- `key = keySelector(value)`.
- `groups.get(key)`: an existing key does not emit another `GroupedObservable`.
- A new key: `groups.set(key, connector ? connector() : new Subject())`, build `createGroupedObservable` (lines 261–274), `subscriber.next(grouped)`, then if `duration` is set subscribe `innerFrom(duration(grouped))` with the group subject as the operator-subscriber destination (lines 201–225).
- Then `group.next(element ? element(value) : value)` (line 230), including the value that created the group.

`createGroupedObservable` increments `activeGroups` on each subscribe to that group and decrements on unsubscribe. If the decrement hits `0` and `teardownAttempted` is set, it unsubscribes the source subscriber (lines 262–271). The source subscriber’s `shouldUnsubscribe` (lines 244–249) sets `teardownAttempted` and returns `activeGroups === 0`, so an outer unsubscribe does **not** disconnect the source while any group subscription is still active (`OperatorSubscriber.ts` 104–110). When the source subscriber really unsubscribes, `onFinalize` does `groups.clear()` (line 243).

Duration destination behavior (`groupBy.ts` 202–221): the first duration `next` completes that group and unsubscribes the duration subscriber. Duration `complete` uses the default handler, which completes the destination group. Duration `error` uses the default handler, which errors **that group only**, not the outer subscriber (comment at lines 217–219). Finalize always `groups.delete(key)` (line 221), so a later source value with the same key opens a new group.

Source complete: `notify` completes every group subject and the outer subscriber (lines 159–162, 236). Source error: `notify` errors every group and the outer subscriber (line 238). A `keySelector` or `element` throw takes the same `handleError` path.

Default group bus is a `Subject` (line 193): no replay. A subscriber who does not subscribe to the `GroupedObservable` synchronously inside the outer `next` misses the value that was just `group.next`’d, and misses every earlier value. A `connector` can replace that. Late subscribe after the group has completed or errored is that subject’s terminal replay (`Subject.ts` 136–144). `GroupedObservable.key` is assigned at line 273. It is not part of the notification stream.

`activeGroups` counts group subscriptions, not keys. A key that was emitted but never subscribed does not keep the source alive.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| open \| completed \| errored \| cancelled` | `idle` | `cancelled` means the source subscriber actually unsubscribed. |
| `groups` | `Map<K, SubjectLike>` | empty | Live keys (`groupBy.ts` 156). |
| `activeGroups` | integer | `0` | Subscriptions to grouped observables, not map size. |
| `teardownAttempted` | boolean | `false` | Set when an unsubscribe of the source subscriber is requested (line 246). |
| `keySelector` | `(T) => K` | argument | — |
| `element` | function or absent | — | Absent forwards the source value. |
| `duration` | function or absent | — | Per new group. |
| `connector` | factory or absent | absent means `new Subject()` | One bus per new key. |

Each map entry has the subject’s own stopped flag and buffer, which this machine treats as `open`, `completed`, or `errored(e)`.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Extended state is the map plus `activeGroups` and `teardownAttempted`. `emitting` is an outer `outNext(grouped)` or a `groupNext`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `open` | Source subscribed. Map may be partial. |
| `completed` | Source completed; every group that was in the map was completed; outer completed. |
| `errored` | Source or key/element failure; every group and the outer got the error. |
| `cancelled` | Source subscription released and `groups.clear()` has run. |

A single group can be `completed` or `errored` while `phase` stays `open` (duration). That is data, not a control location.

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Subscribes the source. |
| 2 | Downstream cancel | `unsubscribe` | Sets `teardownAttempted`. Disconnects the source only if `activeGroups = 0`. |
| 3 | Source next | `sourceNext(v)` | Key, maybe emit a group, then push the element. |
| 4 | Source error | `sourceError(e)` | Errors every open group and the outer. |
| 5 | Source complete | `sourceComplete` | Completes every open group and the outer. |
| 6 | Group subscribe / cancel | `groupSubscribe(k)`, `groupUnsubscribe(k)` | Changes `activeGroups`. |
| 7 | Duration | `durationNext(k)`, `durationError(k, e)`, `durationComplete(k)` | One duration observable per currently open key that was created while `duration` was set. |
| 8 | Projector | `keySelector` / `element` throw | Same fan-out as source error. No scheduler. |

### Γ

`ε`, `subSource`, `unsubSource`, `outNext(grouped_k)` (once per new key), `groupNext(k, value)`, `groupError(k, e)`, `groupComplete(k)`, `outError(e)`, `outComplete`, `subDuration(k)`, `unsubDuration(k)`.

`grouped_k` is an observable with `.key === k` (`groupBy.ts` 272–273, 283–287).

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `open` | `subSource` |
| T02 | emitting | `open` | `sourceNext(v)` | `keySelector(v)` is a new key; no throw; no duration | `open` | `outNext(grouped_k)`; `groupNext(k, elementOrValue)`. Both happen before the source `next` returns (lines 198–230). |
| T03 | emitting | `open` | `sourceNext(v)` | new key and `duration` is set | `open` | `outNext(grouped_k)`; `subDuration(k)` (`duration(grouped)` subscribed, lines 201–225); then `groupNext(k, elementOrValue)` |
| T04 | emitting | `open` | `sourceNext(v)` | key already in the map and that subject is not stopped | `open` | `groupNext(k, elementOrValue)` only. No second `outNext`. |
| T05 | per-source error | `open` | `sourceNext(v)` | `keySelector` or `element` throws `e`, or `duration(grouped)` throws | `errored` | `groupError` on every map entry, `outError(e)` (`handleError`, lines 165–166, 187, 231–233) |
| T06 | waiting | `open` | `groupSubscribe(k)` | — | `open` | `activeGroups++`; inner subscription to the group subject (lines 263–265). If the subject already has a value and is a plain `Subject`, that value is not replayed. |
| T07 | cancel | `open` | `groupUnsubscribe(k)` | after decrement `activeGroups > 0` or not `teardownAttempted` | `open` | `ε` on the outer. The group bus stays in the map unless a duration finalize already deleted it. |
| T08 | cancel | `open` | `groupUnsubscribe(k)` | decrement hits `0` and `teardownAttempted` | `cancelled` | `unsubSource`; `groups.clear()` (lines 270 and 243–249) |
| T09 | cancel | `open` | outer `unsubscribe` | `activeGroups > 0` | `open` | `teardownAttempted := true`; source **stays** subscribed (`OperatorSubscriber.unsubscribe` does not proceed, `OperatorSubscriber.ts` 105–106). |
| T10 | cancel | `open` | outer `unsubscribe` | `activeGroups = 0` | `cancelled` | `teardownAttempted := true`; `unsubSource`; `groups.clear()`. Subjects already handed out are not completed by `clear`. |
| T11 | per-source complete | `open` | `durationNext(k)` | — | `open` | `groupComplete(k)`; `unsubDuration(k)`; `groups.delete(k)` (lines 209–212, 221) |
| T12 | per-source complete | `open` | `durationComplete(k)` | no prior duration next | `open` | default complete completes the group (`OperatorSubscriber` default `_complete`); finalize deletes `k` |
| T13 | per-source error | `open` | `durationError(k, e)` | — | `open` | `groupError(k, e)` only. Outer stays open (lines 217–219). Key deleted on finalize. |
| T14 | terminal | `open` | `sourceComplete` | — | `completed` | `groupComplete` for each map entry, then `outComplete` (`notify`, lines 159–162, 236) |
| T15 | per-source error | `open` | `sourceError(e)` | — | `errored` | `groupError(k, e)` for each entry, then `outError(e)` (line 238) |
| T16 | emitting | `open` | `sourceNext(v)` | key was deleted by T11–T13 and appears again | `open` | a **new** `outNext(grouped_k)` and a new subject (the map miss at line 190). Same as T02/T03. |
| T17 | waiting | `open` | `groupSubscribe(k)` | subject already completed or errored | `open` | `activeGroups++`, then the subject’s `syncComplete` or `syncError`, which will unsubscribe and run T07 or T08. No replay of past elements on a default `Subject`. |
| T18 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |
| T19 | waiting | `open` | `sourceNext(v)` | key exists but that subject is already stopped and was not deleted | `open` | `Subject.next` drops the value if `isStopped` (`Subject.ts` 61–62). No outer error. A duration path deletes the key, so this row is for a `connector` subject that was stopped without going through the duration finalize, or a subject completed by a direct complete. Default duration finalize deletes first. |

T02’s `groupNext` is synchronous with `outNext`. A downstream handler that `groupSubscribe`s inside `outNext` is T06 interleaved before `groupNext`, so it **does** see the creating value. That subscription is the supported use, not excluded reentrancy. Re-entering `subscribe` on the outer grouped result is excluded.

## D. Contract invariants

1. For a given key, while its subject stays in the map, the outer emits at most one `GroupedObservable`. Later values are `groupNext` only (T04). JSDoc `groupBy.ts` 58–61.
2. The element on the group is `element(v)` if an element function was passed, otherwise `v` (line 230).
3. Default buses do not replay. Missing the synchronous `groupSubscribe` during `outNext` drops that element for that observer. A later `groupSubscribe` sees only subsequent `groupNext`s (T06).
4. `duration`’s first `next`, its `complete`, and its `error` all close that group. Error is group-local (T11–T13). After delete, the key may be reborn (T16).
5. Source complete completes the outer and every group still in the map (T14). Source error errors the outer and every such group (T15). There is no “complete the outer but leave groups open”.
6. Outer unsubscribe with `activeGroups > 0` does not unsubscribe the source (T09). The last group unsubscribe then does (T08). This is the `take(2)` comment at lines 178–180 and 247–249.
7. Outer unsubscribe with `activeGroups = 0` drops the source and clears the map without completing groups that were emitted but never subscribed (T10). Those subjects are orphaned open buses.
8. `activeGroups` is not the number of keys. Unsubscribed groups do not keep the source alive. Never-subscribed groups never incremented it.
9. Key identity is `Map` identity: primitives by value, objects by reference. The machine does not structural-compare keys.
10. Positional duration/connector still work. The options object is the non-deprecated form (lines 34–49, 148–153).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Three ids, subscribe inside the outer next

Source emits `{id:1}`, `{id:2}`, `{id:1}`. First value: T02 `outNext(group1)`, and the observer subscribes (T06) before `groupNext`, so the group observer sees the first object. Second value: new key, same pattern for `group2`. Third value: T04 `groupNext(group1, third object)` only. No third outer next. On source complete, T14 completes `group1`, `group2`, and the outer. This is the shape of the JSDoc `mergeMap` / `reduce` example (`groupBy.ts` 76–91), which subscribes each group.

### E2. Element selector

`groupBy(p => p.id, { element: p => p.name })` (JSDoc lines 105–108). The group observer sees names, not objects (T02’s element branch). The outer still sees `GroupedObservable`s. `.key` is the id.

### E3. Late group subscriber misses history

Outer receives `grouped` and does not subscribe until after two more source values for that key have already been `group.next`’d. Default `Subject`. T06 joins an empty future: those two values are gone. Only later `groupNext`s arrive. If `connector` returns a `ReplaySubject`, those values would replay; the default does not.

### E4. Duration reopens a key

`duration` returns an observable that emits once. The group’s creating value is delivered (T03). Duration next is T11: the group completes, the key is deleted. A later source value with the same key is T16: a new `outNext(grouped)` with a new subject. The old group does not also emit that value. A duration error is T13: that group errors, the outer does not, and the key can likewise reopen. A duration complete with no next is T12 and also closes the group.

### E5. `take(2)` on the outer while groups stay subscribed

Source will emit three keys. Downstream is `groupBy(...), take(2)` and each taken group is subscribed (`activeGroups` becomes 2). The second `outNext` causes `take` to unsubscribe the outer: T09, source **remains** subscribed, `teardownAttempted`. Further source values for those two keys still `groupNext` (T04). A third key would still `outNext` into a destination that `take` has already stopped, so that outer next is ignored by the stopped subscriber; the group may still be created before the stopped check depending on `Subscriber.next` (`Subscriber.ts` 67–72). Once both group subscribers unsubscribe, T08 `unsubSource`. The comment at `groupBy.ts` 180 is this keep-alive.

### E6. Source error and key throw

Source emits one group that is subscribed, then `sourceError(e)`. T15: that group gets `groupError(e)` and the outer gets `outError(e)`. No `outComplete`. Separately, if `keySelector` throws on a value, T05 has the same fan-out, including groups already open.

### E7. Never subscribing, then cancel

Two groups are emitted and the caller unsubscribes the outer without `groupSubscribe`. `activeGroups` is `0`. T10: source unsubscribed, map cleared. The two `GroupedObservable` objects, if retained, subscribe to subjects that will not complete and will not receive more values. Contrast T14, which completes groups the caller never subscribed to, but only when the **source** completes.

## F. Coverage and evidence

Not executed.

Denominator = 19 (T01–T19). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded. Synchronous `groupSubscribe` inside the outer `next` that delivers that group is in-model (it is the only way to observe the creating element on a `Subject`).
- synchronous multi-source emissions in listed order: single source; duration notifications are additional inputs and are in-model
- limits: `connector` subjects other than `Subject` are not given their own replay algebra; only the default miss-on-late-subscribe rule and the “connector may change it” fact are stated. `Map` key identity is not a structural equality. Duration observables’ internal schedulers are not modeled. `innerFrom` interop for the duration observable is not expanded. A `group.next` that itself throws is inside the source-next try/catch and is T05; a throw from a group observer’s handler is ordinary downstream reentrancy and is excluded.
