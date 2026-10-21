# buffer

`buffer(closingNotifier)` collects source values into an array and emits that array on every notifier `next`, then starts a fresh array (`buffer.ts` 45–80). The array is emitted even when it is empty. Notifier `complete` is `noop`: it does not emit the buffer and does not complete the output. Source `complete` emits the current buffer (including `[]`) and then completes. Source `error` uses the default handler, so the partial buffer is not emitted. Notifier `error` is output `error` and also drops the partial. `cancel` drops the buffer and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/buffer.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `buffer<T>(closingNotifier: ObservableInput<any>): OperatorFunction<T, T[]>` (`buffer.ts` 45).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 15–19. One open buffer for the whole subscription. Notifier `next` emits a copy of the reference that was current and replaces it with a new array (66–70). The emitted array is the same object that was filled, not a shallow copy; callers must not assume a defensive copy beyond the swap.
- Model kind: extended, not finite. Buffer length is unbounded.
- Parameter domain: one `closingNotifier`, subscribed once at output subscribe (63–74), after the source subscription (51–60).
- Payload/error domain: output items are `T[]`. Source errors and notifier errors are forwarded as-is. No selector callback.
- Subscription boundary: both subscribers are children of the destination. Source complete is custom (55–58). Source error is default. Notifier complete is `noop` (72). Notifier error is default.
- Scheduler and tie ordering: no scheduler in this file. If both upstreams schedule at the same virtual time, delivery order is theirs — assumption, not a proof. Subscription order is source then notifier, so a synchronous notifier emission during subscribe sees whatever the source already pushed synchronously. Micro-trace required for same-turn source and notifier signals.
- Callback assumptions: no user selector. Downstream throw on `subscriber.next(buffer)` is caught by the notifying subscriber. Ordinary model: no reentrancy. The code swaps the array before `next` (68–70), so a reentrant source `next` would land in the new array; excluded.
- Cleanup assumptions: `operate` returns a teardown that nulls `currentBuffer` (76–79) and does not emit. `cancel` unsubscribes both upstreams. No `complete`.
- Explicit exclusions: reentrancy; copying buffer contents; windows (this operator emits arrays, not inners).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open([])
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open(buf)` | `currentBuffer = buf` | Collecting. |
| `Stopped` | `currentBuffer` nulled | Terminal. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | `buf = []`; subscribe source then notifier. |
| `sourceNext(v)` | yes | source | `buf.push(v)` (line 54). |
| `sourceError(e)` | yes | source | `error(e)`; no `next(buf)`. |
| `sourceComplete` | yes | source | `next(buf)` then `complete`, even if `buf` is empty (55–58). |
| `cancel` | yes | unsubscribe | No emit; teardown nulls the array (76–78). |
| `notifierNext` | yes | closing notifier | Emit current array, replace with `[]` (66–70). |
| `notifierComplete` | yes | notifier | `noop` (72). Output stays `Open`. No emit. |
| `notifierError(e)` | yes | notifier | `error(e)`; buffer dropped. |
| `timerFired` | no | — | Not in this file. |
| user callback | no | — | No selector. |

### Γ

`none` | `next(T[])` | `error(e)` | `complete`. Micro-trace required when source complete and notifier `next` can meet.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `currentBuffer=[]` (48); both subscribed (51–74) | `Open([])` | ε | source or notifier | S01 |
| T02 | `Open(buf)` | `sourceNext(v)` | — | `none` | push (54) | `Open(buf++v)` | T01 | — | S01 |
| T03 | `Open(buf)` | `notifierNext` | any length, including 0 | `next(buf)` | replace with a new `[]` before `next` (68–70) | `Open([])` | T01 or T02 | another notifier emits `[]` if no new values | S01 |
| T04 | `Open(buf)` | `notifierComplete` | — | `none` | notifier subscriber ends; source stays; buffer kept | `Open(buf)` | T02 | source complete still emits `buf` | S02 |
| T05 | `Open(buf)` | `notifierError(e)` | — | `error(e)`; no `next(buf)` | destination teardown | `Stopped` | T02 | none | S03 |
| T06 | `Open(buf)` | `sourceComplete` | including empty `buf` | `next(buf)` then `complete` | lines 55–58 | `Stopped` | T01 or T02 | none | S04 |
| T07 | `Open(buf)` | `sourceError(e)` | — | `error(e)`; no `next(buf)` | default error; teardown nulls buffer (76–78) | `Stopped` | T02 | none | S03 |
| T08 | `Open` | `cancel` | — | `none` | both upstreams unsubscribed; buffer nulled; no `complete` | `Stopped` | T02 | none | S05 |
| T09 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T10 | `Open` | `timerFired` | — | — | inapplicable | `Open` | — | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | There is exactly one active array between subscribe and stop. |
| I02 | Notifier `next` emits the current array even if its length is 0, then the active array is a different object. |
| I03 | Values are not copied into a second array at emit time; the emitted object is the one that was pushed into. |
| I04 | Notifier `complete` does not emit and does not complete the output. |
| I05 | Source `complete` emits the remainder once, even if it is `[]`, then `complete`. |
| I06 | Source `error` and notifier `error` do not emit the partial array. |
| I07 | `cancel` does not emit and does not complete. |

## E. Scenario specification

### S01 Notifier emits the collected values and resets

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: cold source and notifier
- prefix: `subscribe`, `sourceNext(a)`, `sourceNext(b)`
- target event: `notifierNext`, then another `notifierNext` with no new source values
- expected notifications: `next([a, b])`, then `next([])`
- lifecycle: array identity changes at each notifier `next`
- suffix: `Open([])`
- final state: `Open([])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`buffer.ts` 54, 66–70)

### S02 Notifier complete does not flush

- Test ID: S02
- Covered row IDs: T04
- Starting state: `Open([a])`
- Reset/fixture: notifier completes
- prefix: `sourceNext(a)`
- target event: `notifierComplete`
- expected notifications: none
- lifecycle: notifier subscriber unsubscribed; source remains
- suffix: later `sourceComplete` emits `next([a])` then `complete` (T06)
- final state: `Open([a])` until source termination
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 72)

### S03 Errors drop the partial

- Test ID: S03
- Covered row IDs: T05, T07
- Starting state: `Open([a])`
- Reset/fixture: separate source-error and notifier-error runs
- prefix: `sourceNext(a)`
- target event: `sourceError(e)` or `notifierError(e)`
- expected notifications: `error(e)`, not `next([a])`
- lifecycle: teardown nulls `currentBuffer`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (no error handler on either subscriber except default)

### S04 Source complete flushes empty and non-empty

- Test ID: S04
- Covered row IDs: T06
- Starting state: `Open([])` or `Open([a])`
- Reset/fixture: two runs, zero values and one value
- prefix: `subscribe` and optional `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `next([])` or `next([a])`, then `complete`
- lifecycle: notifier unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 55–58)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T08
- Starting state: `Open([a])`
- Reset/fixture: both upstreams live
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: teardown at 76–78; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 10 (T01–T10). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S03 | not executed |
| T08 | S05 | not executed |
| T09 | none | not executed |
| T10 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Same-turn source/notifier order is a producer assumption. The emitted array is aliased with the internal buffer until the swap; after the swap it is stable only if the consumer does not mutate it. Reentrancy excluded.
- Contract vs 7.8.2 characterization: JSDoc describes emit-on-notifier-next. Empty flush on source complete, drop on error, and ignore of notifier complete are source characterization.
- Tests still required: S01–S05, including an empty buffer on notifier `next`, notifier complete while values are buffered, and source error versus source complete.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
