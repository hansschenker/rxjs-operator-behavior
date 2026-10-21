# `toArray`

`toArray` collects every source value into a fresh array and emits that array once, when the source completes, then completes. An empty source emits `next([])` and completes. A source error forwards the error and emits no array. Unsubscribe drops the partial array and does not complete. The array is the same mutable object the reducer pushes into; it is not copied at emission. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/toArray.ts` lines 37–44 allocate `[]` inside `operate` and subscribe the destination to `reduce(arrReducer, thatArray)(source)`. Not deprecated. `arrReducer` is `(arr, value) => (arr.push(value), arr)` (line 4).

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `toArray()`. `OperatorFunction<T, T[]>`. Lines 37–44. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | Per subscription, create a new array, push each source value in order, and on source complete emit that array (the seed of `reduce`) and complete. The seed is always passed, so an empty source still flushes `[]`. |
| Model kind | Symbolic. The array contents are an uninterpreted sequence. |
| Parameter domain | No user parameters. |
| Payload/error domain | Successful payload is `T[]`. Errors are source errors only, for ordinary arrays. |
| Subscription boundary | `operate` runs per subscription, so each subscriber gets its own array (comment at lines 38–40). The inner `reduce(...)(source).subscribe(subscriber)` passes the destination `Subscriber` through (`Observable.subscribe` uses an existing `Subscriber` directly). One upstream subscription via `reduce`. No further inner observable. |
| Scheduler and tie ordering | No scheduler. Push order is source order. |
| Callback assumptions | No user callback. `arrReducer` calls `Array.prototype.push` on a plain array created at line 42. |
| Cleanup assumptions | `reduce` flushes on complete and unsubscribes. The inner `subscribe` return value is discarded (line 42); teardown still works because the `OperatorSubscriber` inside `reduce` is a child of the destination. |
| Explicit exclusions | Ordinary model, no reentrancy. A destination `next` handler that mutates the emitted array is downstream. A throwing `push` (revoked proxy, frozen array) is excluded because the seed is a fresh ordinary array. Terminal late events are silent by convention. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator function not yet subscribed. | none | empty | `subscribe` allocates a new array |
| `active(buf)` | Collecting. | array `buf` | `subscribe` and the values already pushed | complete emits this same `buf` reference |
| `completed` | Array was emitted and destination completed. | none | source `complete` | silence |
| `errored(e)` | Source errored. | `e` | source `error` | `buf` was not emitted |
| `cancelled` | Unsubscribed. | none | `cancel` | `buf` was not emitted |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 41–43. Allocates `[]` and subscribes. |
| Source next | yes | `push`, no emission. |
| Source error | yes | `reduce` forwards it. No array. |
| Source completion | yes | `reduce` emits the seed array, then completes. |
| Cancellation `cancel` | yes | Drops `buf`. |
| Inner notifications | no | The `reduce` observable is an operator lift of the same source, not a second user-facing inner producer. |
| Time | no | No clock. |
| User callback outcomes | no | No user function. |

### Γ

```text
record {
  trace: ordered list of next(array) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Source complete emits ordered `next(buf)` then `complete`. The identity of `buf` is part of the payload. Other inputs emit at most one notification.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | allocate `buf = []`; `subscribe(source)` through `reduce` | `active([])` | empty | a second subscriber of the same result gets a different array | S01 |
| T02 | `active(buf)` | source `next(v)` | `push` returns normally | none | `buf` is mutated by `push(v)`; same reference | `active(buf)` | T01 and the prior pushes | complete emits that reference, length increased by 1 | S02 |
| T03 | `active(buf)` | source `error(e)` | any | `error(e)`; no `next` | unsubscribe | `errored(e)` | T01, optional T02 | silence | S03 |
| T04 | `active(buf)` | source `complete` | any length, including 0 | ordered `next(buf)`, `complete` | unsubscribe | `completed` | T01 plus T02s | silence; `buf` contains every value in order | S01, S02 |
| T05 | `active(buf)` | `cancel` | open | none | unsubscribe | `cancelled` | T01, optional T02 | no array | S04 |
| T06 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S03 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | `push` order is source order (`toArray.ts` line 4). One array emission. |
| one terminal | yes | T03 or T04. |
| silence after terminal | yes | T06. |
| cancel does not complete | yes | T05. |
| upstream/inner lifetime | yes | One source subscription, established by the inner `reduce` subscribe, released on terminal or cancel. |
| cleanup once | yes | Destination unsubscribe tears down the child `OperatorSubscriber` once. |
| per-subscription state | yes | `[]` is created inside `operate` (lines 41–42), not at `toArray()` call time. |
| empty/error/silence | yes | Empty: T04 emits `[]` (S01). Source error: T03, no array. Never completes: stays `active`, no emission. |
| pending buffer on terminal | yes | `buf` is pending until T04. T03 and T05 drop it without emitting. |
| callback throw/reenter/cancel | no user callback | Reentrancy excluded. `push` on a fresh array does not call user code. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty source emits a fresh empty array

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T04 |
| Starting state | `idle` |
| Reset/fixture | `toArray()`, source completes with no values. Two subscribers. |
| State-reaching prefix | empty |
| Target event | each `subscribe` and the empty complete |
| Expected notifications | `next([])`, `complete` on each subscriber |
| Expected lifecycle observations | the two emitted arrays are not the same reference; each source subscription is independent |
| Distinguishing suffix | silence |
| Expected final state | `completed` per subscription |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload deep-equals `[]` and reference inequality across subscribers |
| Oracle source | `source characterization` |

### S02 Values in order, one array

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T04 |
| Starting state | `active([])` |
| Reset/fixture | source emits `a`, `b`, `undefined`, then completes |
| State-reaching prefix | `subscribe` |
| Target event | those nexts and complete |
| Expected notifications | no `next` until complete; then `next([a, b, undefined])`, `complete` |
| Expected lifecycle observations | the emitted array is the array that was pushed into (same reference the reducer returned) |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | order, including an `undefined` element, and a single data notification |
| Oracle source | `contract` |

### S03 Source error emits no array

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T06 |
| Starting state | `active([a])` |
| Reset/fixture | one value, then source `error(e)` |
| State-reaching prefix | `subscribe` and one next |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S04 Cancel drops the buffer

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active([a, b])` |
| Reset/fixture | two values, source still open |
| State-reaching prefix | `subscribe` and two nexts |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no array notification |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 6 section C rows (T01–T06).

Section E references every row. Specified coverage = 6/6.

Execution: not executed.

Evidence: `src/internal/operators/toArray.ts` lines 4 and 37–44, plus seeded `reduce` flush (`scanInternals.ts` lines 54–58). No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the operator is a per-subscription seeded `reduce` whose seed is a new array and whose reducer is `push`.

Known limitations: the emitted array remains mutable. The inner `subscribe(subscriber)` shares the destination subscriber with the outer `operate` subscription; that is intentional and is why no second observer is allocated. Reentrancy is excluded. The discarded subscribe return value is not a leak because of the child-subscription link.

Contract vs version characterization: JSDoc (lines 8–16) matches “one array on complete, nothing on error”. Emitting `[]` for an empty source and allocating per subscription are source characterization (lines 38–42).

Tests still required: S01–S04, including two subscribers and a value of `undefined`.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
