# sample

`sample(notifier)` stores the latest source value and, on each notifier `next`, emits that value once if at least one source value arrived since the previous sample. The stored value is then cleared, so a notifier `next` with no new source value emits nothing. Notifier `complete` is `noop`: it does not sample and does not complete the output. Notifier `error` becomes output `error`. Source `complete` completes the output immediately and does not flush an unsampled value. Source `error` is immediate and drops the sample. `cancel` unsubscribes both upstreams and does not complete. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/sample.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `sample<T>(notifier: ObservableInput<any>): MonoTypeOperatorFunction<T>` (`sample.ts` 47).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: lines 16–20 match the code. The `@return` text (lines 43–45) says the notifier “emits value or completes.” The complete handler is `noop` (line 68). Code wins: notifier completion does not sample and does not complete the output.
- Model kind: extended, not finite. The notifier is an arbitrary input. There is no internal clock in this file.
- Parameter domain: `notifier` is converted with `innerFrom` at subscribe time (line 57), not per sample. It is subscribed once for the life of the output.
- Payload/error domain: one-slot cache (`hasValue`, `lastValue`). `T` may be nullish. Notifier payloads are ignored. Notifier errors are forwarded by the default `onError`.
- Subscription boundary: source is subscribed first (lines 51–56), then the notifier (57–70). Both `OperatorSubscriber`s are children of the destination (`Subscriber.ts` 47–55). Source error and complete use default handlers, so they forward to the destination and drop the cache. Source complete does not read `hasValue`.
- Scheduler and tie ordering: none here. If both upstreams schedule at the same virtual time, delivery order is the producers’ schedule order — assumption, not a proof. Subscription order means a synchronous notifier emission happens after the source subscription is installed, so synchronous source values from `subscribe` are already cached. Micro-trace required when both can emit in one turn.
- Callback assumptions: no user selector. Downstream throw from `subscriber.next` (lines 61–65) is caught on the notifier subscriber. Ordinary model: no reentrancy.
- Cleanup assumptions: `cancel` unsubscribes destination children (source and notifier). No `complete`. There is no finalize that nulls `lastValue`; the cache simply becomes unreachable.
- Explicit exclusions: reentrancy; treating JSDoc line 45 as normative; multi-value sampling buffers (only the latest value is kept).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Empty
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Empty` | `hasValue = false` | Nothing new since the last sample or since subscribe. |
| `Held(v)` | `hasValue = true`, `lastValue = v` | `v` will be emitted on the next notifier `next`, then cleared. |
| `Stopped` | terminal | Output error, output complete, or cancel. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Subscribe source, then notifier. |
| `sourceNext(v)` | yes | source | Sets the slot (lines 53–54). |
| `sourceError(e)` | yes | source | Immediate `error(e)`; slot dropped. |
| `sourceComplete` | yes | source | Immediate `complete`; slot dropped, not emitted. |
| `cancel` | yes | unsubscribe | Both upstreams released; no `complete`. |
| `notifierNext` | yes | notifier | Emit slot if `hasValue`, then clear (60–66). |
| `notifierComplete` | yes | notifier | `noop` (68) then the notifier subscriber unsubscribes itself. Output stays open. No sample. |
| `notifierError(e)` | yes | notifier | Default error → `outError(e)`. |
| `timerFired` | no | — | Not in this file. |
| user callback | no selector | downstream `next` throw only | Fault → `error`. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required for same-turn source and notifier signals, including sync notifier on subscribe.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | source subscriber then notifier subscriber (`sample.ts` 51–70) | `Empty` | ε | either upstream | S01 |
| T02 | `Empty` or `Held(*)` | `sourceNext(v)` | — | `none` | `hasValue=true`, `lastValue=v` | `Held(v)` | T01 | notifier may sample | S01 |
| T03 | `Held(v)` | `notifierNext` | `hasValue` | `next(v)` | clear `hasValue` and `lastValue` before `next` (61–65) | `Empty` | T02 | a second notifier `next` emits nothing until a new source value | S01 |
| T04 | `Empty` | `notifierNext` | `!hasValue` | `none` | no write | `Empty` | T01 or T03 | — | S02 |
| T05 | `Held(v)` or `Empty` | `notifierComplete` | — | `none` | notifier subscriber finalized; source remains; slot unchanged | same location | T02 | later `sourceComplete` still completes; no retroactive sample | S03 |
| T06 | `Held(v)` | `notifierError(e)` | — | `error(e)`; `v` not emitted | destination teardown unsubscribes source | `Stopped` | T02 | none | S04 |
| T07 | `Held(v)` | `sourceComplete` | — | `complete`; `v` not emitted | default complete (`sample.ts` 51–56 has no complete handler) | `Stopped` | T02 | none | S05 |
| T08 | `Empty` | `sourceComplete` | — | `complete` | — | `Stopped` | T01 or T03 | none | S02 |
| T09 | `Held` or `Empty` | `sourceError(e)` | — | `error(e)`; slot dropped | default error | `Stopped` | T02 | none | S04 |
| T10 | any non-terminal | `cancel` | — | `none` | both children unsubscribed; no `complete` | `Stopped` | T02 | notifier must not `next` | S06 |
| T11 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T12 | any | `timerFired` | — | — | inapplicable in this file | — | — | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | At most one unsampled value is stored. A newer `sourceNext` overwrites it without emitting. |
| I02 | Notifier `next` emits the slot at most once and clears it before `subscriber.next`. |
| I03 | Notifier `next` with an empty slot emits nothing. |
| I04 | Notifier `complete` does not emit, does not clear the slot, and does not complete the output (`sample.ts` 68). |
| I05 | Source `complete` and source `error` do not emit the unsampled slot. |
| I06 | Notifier `error` is output `error` and drops the slot. |
| I07 | `cancel` emits neither `next` nor `complete`. |
| I08 | The notifier is subscribed for the output’s lifetime, not once per value. |

## E. Scenario specification

### S01 Sample the latest value once

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: cold source and notifier
- prefix: `subscribe`, `sourceNext(a)`, `sourceNext(b)`
- target event: `notifierNext`
- expected notifications: `next(b)` only
- lifecycle: slot cleared; both subscriptions remain
- suffix: another `notifierNext` without a new source value follows T04 (`none`)
- final state: `Empty`
- version and scheduler: 7.8.2; producers’ schedulers if any
- assertion type: source characterization
- oracle source: source characterization (`sample.ts` 51–66)

### S02 Sample with an empty slot, then idle complete

- Test ID: S02
- Covered row IDs: T04, T08
- Starting state: `Empty`
- Reset/fixture: notifier emits before any source value, or after a prior sample
- prefix: `subscribe`
- target event: `notifierNext`, later `sourceComplete`
- expected notifications: `none` then `complete`
- lifecycle: no timer
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 Notifier complete is ignored

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Held(a)`
- Reset/fixture: notifier completes without a further `next`
- prefix: `sourceNext(a)`
- target event: `notifierComplete`
- expected notifications: none (not `next(a)`, not `complete`)
- lifecycle: notifier subscriber unsubscribes; source still subscribed; `hasValue` remains true
- suffix: a later `sourceNext` is impossible if we instead complete the source: `sourceComplete` yields `complete` without `next(a)` (T07). If the notifier is replaced, it is not; this operator does not resubscribe.
- final state: `Held(a)` until source termination or cancel
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 68 versus JSDoc lines 43–45)

### S04 Notifier error and source error drop the slot

- Test ID: S04
- Covered row IDs: T06, T09
- Starting state: `Held(a)`
- Reset/fixture: two runs
- prefix: `sourceNext(a)`
- target event: `notifierError(e)` or `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: the other upstream is unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Source complete drops an unsampled value

- Test ID: S05
- Covered row IDs: T07
- Starting state: `Held(a)`
- Reset/fixture: notifier still silent
- prefix: `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `complete`, not `next(a)`
- lifecycle: notifier unsubscribed because destination complete tears down children
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (source subscriber has no complete handler, lines 51–56)

### S06 Cancel

- Test ID: S06
- Covered row IDs: T10
- Starting state: `Held(a)`
- Reset/fixture: both upstreams live
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: source and notifier unsubscribed; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

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
| T07 | S05 | not executed |
| T08 | S02 | not executed |
| T09 | S04 | not executed |
| T10 | S06 | not executed |
| T11 | none | not executed |
| T12 | none (inapplicable) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Same-turn ordering of source and notifier is a producer/scheduler assumption. The output can remain open forever after notifier `complete` if the source does not terminate; that is the code, not a liveness proof.
- Contract vs 7.8.2 characterization: body JSDoc matches the code. The `@return` clause that mentions notifier completion does not. Notifier `complete` is not a sample and not an output `complete`.
- Tests still required: S01–S06, plus a synchronous notifier that emits during subscribe after a synchronous source, and unsubscribe while `Held`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
