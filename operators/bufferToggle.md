# bufferToggle

`bufferToggle(openings, closingSelector)` starts a buffer only when `openings` emits, and closes that buffer when the observable returned by `closingSelector(openValue)` emits `next` (`bufferToggle.ts` 52–101). Closing `complete` is `noop` and does not emit the buffer. Several buffers may be open; each source value is pushed into all of them. Source `complete` emits every still-open buffer, including ones that received no values, then completes. Source `error`, openings `error`, and closing `error` do not emit partials. Openings `complete` does not complete the output and does not flush. `cancel` emits nothing. A throw from `closingSelector` is a callback fault and becomes output `error` without flushing. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/bufferToggle.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `bufferToggle<T, O>(openings: ObservableInput<O>, closingSelector: (value: O) => ObservableInput<any>)` (`bufferToggle.ts` 52–55).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 19–21. Buffers are not opened at subscribe. The closing selector is per opening value. Contrast `windowToggle`, which has an explicit try/catch around the selector (`windowToggle.ts` 84–89); this file relies on `OperatorSubscriber`’s `onNext` try/catch.
- Model kind: extended, not finite. The list of open buffers is unbounded.
- Parameter domain: `openings` subscribed once (60). `closingSelector` called once per openings `next`, with that value (77).
- Payload/error domain: output `T[]`, possibly empty if an opening happened and no source value arrived before close or source complete. Errors forwarded as-is.
- Subscription boundary: openings subscriber is installed first (60–81), then source (83–99). Each closing subscription is added both to a local `closingSubscription` and, via `createOperatorSubscriber`, to the destination (77).
- Scheduler and tie ordering: no scheduler here. Same-virtual-time order of openings, closings, and source is a producer assumption, not a proof. Micro-trace required when those signals share a turn. Ordinary model: no reentrancy. `emitBuffer` removes the buffer before `next` (71–72).
- Callback assumptions: `closingSelector` throw ≠ source error. It happens after `buffers.push(buffer)` (65–77), inside the openings `onNext` catch, so the output errors and the pushed buffer is not emitted. Closing `next` emits; closing `complete` does not (77, `noop`). Closing `error` is default → output `error`.
- Cleanup assumptions: `cancel` unsubscribes destination children (openings, source, closings) and does not walk `buffers` to emit them. No `complete`. There is no finalize that nulls `buffers`.
- Explicit exclusions: reentrancy; the JSDoc example that uses `EMPTY` as a closer (`bufferToggle.ts` 32–34). `EMPTY` completes without `next`, and complete is `noop`, so that closer does not emit the buffer. Code wins over the example.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle([])
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Collecting(buffers)` | list of `{ array, closing subscription }` | Zero or more open buffers. Source subscribed. Openings subscribed until they terminate. |
| `Stopped` | terminal | — |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | No buffer yet. |
| `sourceNext(v)` | yes | source | Push into every open buffer (86–90). If none are open, `v` is dropped. |
| `sourceError(e)` | yes | source | `error(e)`; no flush (no custom error handler). |
| `sourceComplete` | yes | source | `next` each buffer then `complete` (92–97), including empty buffers. |
| `cancel` | yes | unsubscribe | No flush, no `complete`. |
| `openingsNext(o)` | yes | openings | New buffer; subscribe `closingSelector(o)`. |
| `openingsComplete` | yes | openings | `noop` (79). Existing buffers stay. Output stays open. |
| `openingsError(e)` | yes | openings | `error(e)`; buffers dropped. |
| `closingNext(i)` | yes | that buffer’s closer | `emitBuffer` (70–74). |
| `closingComplete(i)` | yes | closer | `noop` (77). Buffer stays open. |
| `closingError(e)` | yes | closer | Output `error`; no flush. |
| `selectorThrow(e)` | yes | user callback | Output `error`; the buffer just pushed is not emitted. |
| `timerFired` | no | — | Only inside user observables. |

### Γ

`none` | `next(T[])` | `error(e)` | `complete`. Micro-trace required for opening versus source versus closing in one turn.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `buffers=[]`; subscribe openings then source (57–99) | `Collecting([])` | ε | openings | S01 |
| T02 | `Collecting` | `openingsNext(o)` | selector returns | `none` | push `[]`; subscribe closer (63–77) | one more buffer | T01 | source values enter it | S01 |
| T03 | `Collecting` | `sourceNext(v)` | one or more buffers | `none` | push `v` into each (86–90) | same buffers, longer | T02 | — | S01 |
| T04 | `Collecting` | `sourceNext(v)` | no open buffer | `none` | loops over `[]` | unchanged; `v` dropped | T01 | — | S02 |
| T05 | `Collecting` | `closingNext` for buffer `b` | — | `next(b)` even if empty | `arrRemove`, `next`, unsubscribe that closer (70–73) | `b` gone | T02 or T03 | other buffers stay | S01 |
| T06 | `Collecting` | `closingComplete` | — | `none` | closer subscriber ends; buffer remains | same | T02 | source complete can still emit it | S03 |
| T07 | `Collecting` | `openingsComplete` | — | `none` | openings subscriber ends; buffers and source stay | same | T02 | — | S03 |
| T08 | `Collecting` with buffers | `sourceComplete` | — | `next` each buffer from front to back, then `complete` (92–97) | closers torn down with destination | `Stopped` | T02 | none | S04 |
| T09 | `Collecting([])` | `sourceComplete` | — | `complete` only | no array | `Stopped` | T01 | none | S02 |
| T10 | `Collecting` | `sourceError(e)` | partials may exist | `error(e)`; no `next` | default error | `Stopped` | T03 | none | S05 |
| T11 | `Collecting` | `openingsError` or `closingError` | — | `error(e)`; no flush | default error | `Stopped` | T02 | none | S05 |
| T12 | `Collecting` | `selectorThrow(e)` | during openings `next` | `error(e)`; buffer already pushed is not emitted | catch in `OperatorSubscriber.ts` 71–73 | `Stopped` | T01 | none | S06 |
| T13 | `Collecting` | `cancel` | — | `none` | openings, source, closers unsubscribed; no `complete` | `Stopped` | T03 | none | S07 |
| T14 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | No buffer exists until an openings `next`. Source values before the first opening are dropped. |
| I02 | Each openings value has its own buffer and its own closing subscription. |
| I03 | A closing `next` emits that buffer once, even if empty, and unsubscribes that closer. |
| I04 | A closing `complete` does not emit. `EMPTY` does not close a buffer. |
| I05 | Openings `complete` does not flush and does not complete the output. |
| I06 | Source `complete` emits every open buffer, including empty ones, then completes. |
| I07 | Source `error`, openings `error`, closing `error`, and `closingSelector` throw do not emit partial buffers. |
| I08 | `cancel` does not emit and does not complete. |
| I09 | A source value is copied by push into every buffer that is open at that time. |

## E. Scenario specification

### S01 Open, collect, close

- Test ID: S01
- Covered row IDs: T01, T02, T03, T05
- Starting state: unsubscribed
- Reset/fixture: one opening `o`, closer that has not signaled, source values `a`,`b`
- prefix: `subscribe`, `openingsNext(o)`, `sourceNext(a)`, `sourceNext(b)`
- target event: `closingNext`
- expected notifications: `next([a, b])`
- lifecycle: that closing subscription unsubscribed; buffer removed
- suffix: `Collecting([])` if it was the only buffer
- final state: `Collecting([])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`bufferToggle.ts` 63–77, 86–90)

### S02 Value before any opening is dropped; empty complete

- Test ID: S02
- Covered row IDs: T04, T09
- Starting state: `Collecting([])`
- Reset/fixture: no openings
- prefix: `subscribe`, `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `complete` only; `a` appears in no array
- lifecycle: none
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 Closing complete and openings complete leave the buffer

- Test ID: S03
- Covered row IDs: T06, T07
- Starting state: `Collecting([[a]])`
- Reset/fixture: closer is `EMPTY` or completes without `next`; openings then complete
- prefix: opening and `sourceNext(a)`
- target event: `closingComplete` then `openingsComplete`
- expected notifications: none
- lifecycle: those subscribers end; source still live; buffer still stored
- suffix: a later source `complete` emits `next([a])` (T08)
- final state: `Collecting([[a]])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 77 and 79). Disagrees with the `EMPTY` example at lines 32–34 if that example is read as “EMPTY closes the buffer.”

### S04 Source complete flushes open buffers

- Test ID: S04
- Covered row IDs: T08
- Starting state: two open buffers, one empty and one `[a]`
- Reset/fixture: two openings, one value after the second
- prefix: openings and the value
- target event: `sourceComplete`
- expected notifications: `next` of the first buffer, `next` of the second, then `complete`
- lifecycle: closers unsubscribed with the destination
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (92–97)

### S05 Errors drop partials

- Test ID: S05
- Covered row IDs: T10, T11
- Starting state: `Collecting([[a]])`
- Reset/fixture: three runs: source error, openings error, closing error
- prefix: buffer holds `a`
- target event: the error
- expected notifications: `error(e)`, not `next([a])`
- lifecycle: destination teardown
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Selector throw

- Test ID: S06
- Covered row IDs: T12
- Starting state: `Collecting([])`
- Reset/fixture: `closingSelector` throws `e`
- prefix: `subscribe`
- target event: `openingsNext(o)`
- expected notifications: `error(e)`; no `next([])`
- lifecycle: buffer was pushed (65) then the throw escaped before a successful closer subscribe
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`bufferToggle.ts` 63–77, `OperatorSubscriber.ts` 67–74)

### S07 Cancel

- Test ID: S07
- Covered row IDs: T13
- Starting state: `Collecting([[a]])`
- Reset/fixture: closer still open
- prefix: opening and value
- target event: `cancel`
- expected notifications: none
- lifecycle: closer, openings, and source unsubscribed; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 14 (T01–T14). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S01 | not executed |
| T06 | S03 | not executed |
| T07 | S03 | not executed |
| T08 | S04 | not executed |
| T09 | S02 | not executed |
| T10 | S05 | not executed |
| T11 | S05 | not executed |
| T12 | S06 | not executed |
| T13 | S07 | not executed |
| T14 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Producer tie order is assumed. The `EMPTY` closing example in the JSDoc is not what the `noop` complete handler does. Reentrancy excluded. No inner-subject model; outputs are arrays.
- Contract vs 7.8.2 characterization: the prose “when closingSelector emits” matches closing `next` only. Complete-flush of open buffers, including empty ones, is the source-complete handler (92–97). Error paths drop partials because no error handler emits them.
- Tests still required: S01–S07, especially `EMPTY` as a closer, openings complete with a buffer still open, and selector throw.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
