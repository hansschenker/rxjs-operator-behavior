# bufferWhen

`bufferWhen(closingSelector)` opens one buffer immediately, emits it when the current closing observable emits `next`, and then opens another by calling `closingSelector` again (`bufferWhen.ts` 46–93). Closing `complete` is `noop`: the same buffer stays open and the selector is not called again. Source `complete` emits the current buffer if it is non-null, and an empty array is non-null, so an empty open buffer is emitted, then the output completes. Source `error` does not emit the partial. A throw from `closingSelector` on a later close happens after the previous buffer was already emitted. A throw from the initial call happens after the array is created but before any emit, and `operate` turns it into `subscriber.error` (`lift.ts` 23–26). `cancel` emits nothing. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/bufferWhen.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `bufferWhen<T>(closingSelector: () => ObservableInput<any>): OperatorFunction<T, T[]>` (`bufferWhen.ts` 46).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 18–20. One buffer at a time. Contrast `windowWhen`, whose closing notifier resubscribes on both `next` and `complete` (`windowWhen.ts` 99). This operator resubscribes only from `openBuffer`, which is the closing `next` handler (line 69). Complete is `noop`.
- Model kind: extended/timed, not finite. One array plus one closing subscription.
- Parameter domain: `closingSelector` is nullary and is called once per open, including the initial open (59–73).
- Payload/error domain: `T[]`, possibly empty. Closing `error` is default → output `error`, partial not emitted. Selector throw ≠ source error, but it becomes output `error`.
- Subscription boundary: `openBuffer()` runs before `source.subscribe` (72–76). The closing subscriber is an `OperatorSubscriber` parented to the destination. Source error handler is omitted (line 88).
- Scheduler and tie ordering: no scheduler in this file. If the closer is timed, same-virtual-time order is an assumption, not a proof. Micro-trace required when `openBuffer` both emits and subscribes to a synchronous closer. A synchronous closing `next` recurses into `openBuffer`. An infinite synchronous closer is excluded.
- Callback assumptions: initial `closingSelector` throw is inside `operate`’s try (`lift.ts` 22–26), which calls `this.error(err)`. Later throws are inside the closing `onNext` try/catch. Order on a later open: unsubscribe previous closer, swap in a new `[]`, emit the old buffer, then call the selector (59–69). Ordinary model: no reentrancy from the consumer.
- Cleanup assumptions: finalize nulls `buffer` and `closingSubscriber` (89–91) and does not emit. `cancel` unsubscribes the closing child and does not complete.
- Explicit exclusions: reentrancy; infinite synchronous closing sequences; modeling `windowWhen`’s complete-reopens behavior as if it applied here.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open([]) after a successful initial openBuffer
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(buf)` | one array, one closing subscription | Collecting. |
| `Stopped` | refs nulled | Terminal. |

If the initial selector throws, the machine goes to `Stopped` without an output `next`.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Calls `openBuffer` (73). |
| `sourceNext(v)` | yes | source | `buffer?.push(v)` (80). |
| `sourceError(e)` | yes | source | No flush (line 88). |
| `sourceComplete` | yes | source | `buffer && subscriber.next(buffer)` then `complete` (83–86). `[]` is truthy. |
| `cancel` | yes | unsubscribe | No flush, no `complete`. |
| `closingNext` | yes | current closer | `openBuffer` (69): emit old, start new, resubscribe. |
| `closingComplete` | yes | current closer | `noop` (69). No emit, no resubscribe. |
| `closingError(e)` | yes | closer | Output `error`; no emit. |
| `selectorThrow(e)` | yes | user callback | See T08 and T09. |
| `timerFired` | no | — | Not in this file. |

### Γ

`none` | `next(T[])` | `error(e)` | `complete`. Micro-trace required across emit-then-resubscribe.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | selector returns | `none` | `buffer` was null, so no emit; `buffer=[]`; subscribe closer (59–69, 73) | `Open([])` | ε | source subscribed after this (76) | S01 |
| T02 | `Open(buf)` | `sourceNext(v)` | `buffer` non-null | `none` | push (80) | `Open(buf++v)` | T01 | — | S01 |
| T03 | `Open(buf)` | `closingNext` | selector returns | `next(buf)` even if empty | unsubscribe old closer; `buffer=[]`; emit old; subscribe new closer (59–69) | `Open([])` | T01 or T02 | new closer | S01 |
| T04 | `Open(buf)` | `closingComplete` | — | `none` | closing subscriber ends; `buffer` unchanged; selector not called | `Open(buf)` | T02 | values still accumulate | S02 |
| T05 | `Open(buf)` | `sourceComplete` | `buffer` non-null | `next(buf)` then `complete`, `buf` may be `[]` | lines 83–86 | `Stopped` | T01 or T04 | none | S03 |
| T06 | `Open(buf)` | `sourceError(e)` | — | `error(e)`; no `next(buf)` | default error; finalize nulls refs (88–91) | `Stopped` | T02 | none | S04 |
| T07 | `Open` | `closingError(e)` | — | `error(e)`; no `next` | default error on the closing subscriber | `Stopped` | T01 | none | S04 |
| T08 | initial `openBuffer` | `selectorThrow(e)` | before source subscribe | `error(e)`; no `next` | `buffer` already set to `[]` (65) then throw; `operate` catch (`lift.ts` 23–26) | `Stopped` | ε | source not subscribed if throw aborts `init` before line 76 | S05 |
| T09 | `Open(buf)` | `closingNext` then selector throws | old buffer already emitted | `next(buf)` then `error(e)` | lines 62–69: emit happens before `closingSelector()` | `Stopped` | T02 | new `[]` not emitted | S05 |
| T10 | `Open` | `cancel` | — | `none` | closing unsubscribed; finalize nulls refs; no `complete` | `Stopped` | T02 | none | S06 |
| T11 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T12 | `Open` | `closingComplete` then more source values | buffer still there | `none` until source complete | T04 does not clear `buffer` | `Open` grows | T04 | T05 flushes the whole accumulation | S02 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | A buffer is opened during subscribe, before the source is subscribed (72–76). |
| I02 | The initial open does not emit. The first `next(array)` is a closing `next` or source `complete`. |
| I03 | Closing `next` emits the current array (possibly empty), then subscribes to a new selector result. |
| I04 | Closing `complete` does not emit and does not call `closingSelector` again. |
| I05 | Source `complete` emits the open array, and `[]` is emitted because it is truthy (84). |
| I06 | Source `error` and closing `error` do not emit the partial array. |
| I07 | A selector throw on a subsequent close emits the buffer that just closed, then errors (T09). A selector throw on the first open errors without a buffer `next` (T08). |
| I08 | `cancel` does not emit and does not complete. |

## E. Scenario specification

### S01 Close emits and reopens

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: first closer emits once; selector is called again
- prefix: `subscribe`, `sourceNext(a)`
- target event: `closingNext`
- expected notifications: `next([a])`; no emission at subscribe
- lifecycle: first closer unsubscribed; second closer subscribed; active buffer is `[]`
- suffix: `Open([])`
- final state: `Open([])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`bufferWhen.ts` 59–73, 80)

### S02 Closing complete does not reopen

- Test ID: S02
- Covered row IDs: T04, T12
- Starting state: `Open([])`
- Reset/fixture: closer completes without `next`
- prefix: `subscribe`
- target event: `closingComplete`, then `sourceNext(a)`, `sourceNext(b)`
- expected notifications: none
- lifecycle: selector not called again; both values sit in the original array
- suffix: `Open([a, b])` until source complete, which would `next([a, b])`
- final state: `Open([a, b])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 69 `noop`). Contrast `windowWhen.ts` 99.

### S03 Source complete flushes an empty buffer

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Open([])`
- Reset/fixture: no source values
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `next([])`, `complete`
- lifecycle: closer unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (83–86)

### S04 Error drops the partial

- Test ID: S04
- Covered row IDs: T06, T07
- Starting state: `Open([a])`
- Reset/fixture: separate source-error and closing-error runs
- prefix: `sourceNext(a)`
- target event: `sourceError(e)` or `closingError(e)`
- expected notifications: `error(e)`, not `next([a])`
- lifecycle: finalize nulls `buffer`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 69 and 88)

### S05 Selector throw before versus after an emit

- Test ID: S05
- Covered row IDs: T08, T09
- Starting state: unsubscribed, and a second run already `Open([a])`
- Reset/fixture: selector throws `e`
- prefix: none, or `sourceNext(a)` plus a closing `next`
- target event: initial subscribe, or the closing `next` that calls the throwing selector
- expected notifications: initial: `error(e)` only; subsequent: `next([a])` then `error(e)`
- lifecycle: initial throw is in `operate`’s init try; later throw is in the closing `onNext` try, after line 66
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`bufferWhen.ts` 59–69, `lift.ts` 22–26)

### S06 Cancel

- Test ID: S06
- Covered row IDs: T10
- Starting state: `Open([a])`
- Reset/fixture: closer live
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: closer unsubscribed; finalize nulls refs; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (89–91)

## F. Coverage and evidence

Denominator = 12 (T01–T12). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | S05 | not executed |
| T10 | S06 | not executed |
| T11 | none | not executed |
| T12 | S02 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Synchronous closing observables that `next` forever are excluded. Closing `complete` leaving the buffer open is easy to confuse with `windowWhen`. Reentrancy from consumer `next` is excluded.
- Contract vs 7.8.2 characterization: JSDoc 18–20 matches “close when the closing observable emits” as `next`. It does not say that closing `complete` is ignored. Empty flush on source complete follows from `buffer && subscriber.next(buffer)` and `buffer = []`.
- Tests still required: S01–S06, including `EMPTY` as the first closer, source error with a non-empty buffer, and a selector that throws only on the second call.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
