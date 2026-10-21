# bufferTime

`bufferTime` collects source values into time-bounded arrays (`bufferTime.ts` 75–164). The fully tabulated machine is the span-only call: one buffer opens at subscribe, is emitted even if empty when `bufferTimeSpan` elapses, and another opens immediately (`restartOnEmit`). `maxBufferSize` can close a buffer early. Source `complete` emits every open buffer, including empty ones, then completes. Source `error` does not emit partials. `cancel` clears timers and does not emit. The creation-interval overload is a second table: buffers open on a repeating schedule and do not restart on emit, so a gap drops values when the creation interval is longer than the span. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/bufferTime.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: three signatures (lines 10–21), implemented by `popScheduler` plus optional `bufferCreationInterval` and `maxBufferSize` (75–78).
  - `bufferTime(span, scheduler?)`
  - `bufferTime(span, creationInterval, scheduler?)`
  - `bufferTime(span, creationInterval, maxBufferSize, scheduler?)`
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 31–38. Span-only emits every `bufferTimeSpan`. With a creation interval, a new buffer starts every interval and closes `bufferTimeSpan` after it opened. `maxBufferSize` closes a buffer that reaches that many elements.
- Model kind: timed and extended, not finite. Several buffers may be open. Record list is unbounded over time.
- Parameter domain: `scheduler = popScheduler(otherArgs) ?? asyncScheduler` (76). `bufferCreationInterval = otherArgs[0] ?? null` (77). `maxBufferSize = otherArgs[1] || Infinity` (78), so `0` is treated as `Infinity` because `0` is falsy. A creation interval that is `null` or `< 0` selects span-only (`restartOnEmit = true`, lines 120–127). A creation interval `>= 0` selects the repeating schedule (120–124). Negative span is scheduler-defined and excluded.
- Payload/error domain: `T[]`, possibly empty. Source error forwarded (error handler `undefined`, line 158). No selector throw in this file.
- Subscription boundary: source subscriber is created before `source.subscribe` (131–163). Timers are `executeSchedule` on either the destination (creation interval, repeating) or a per-buffer `Subscription` added to the destination (116).
- Scheduler and tie ordering: assumption, not a proof: same-virtual-time actions run in schedule order. `startBuffer` is called synchronously at subscribe (129) and, in interval mode, first again after one creation interval (124). Micro-trace required when a tick, a max-size emit, and source complete can meet. Ordinary model: no reentrancy (the source copies records and removes them before `next` to tolerate it, lines 89–97 and 138–139, but this model does not rely on reentry).
- Callback assumptions: no user callback besides the downstream observer. `emit` unsubscribes the record’s timer before `subscriber.next` (93–97).
- Cleanup assumptions: destination unsubscribe clears per-buffer subs and the repeating schedule because they were `add`ed. Finalize sets `bufferRecords = null` (160) so a late `startBuffer` no-ops (107). `cancel` does not emit and does not complete. Source complete emits buffers, then unsubscribes the operator subscriber, completes, and unsubscribes the destination (147–156), which clears timers.
- Explicit exclusions: reentrancy; `maxBufferSize === 0` as a real cap (coerced to `Infinity`); negative creation interval (falls through to span-only); proving `asyncScheduler`.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Open(records = [empty buffer just started])
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Open` | `bufferRecords`: list of `{ buffer, subs }`, flag `restartOnEmit` | Span-only: `restartOnEmit = true` and normally one record. Interval mode: `restartOnEmit = false` and zero or more records. |
| `Stopped` | `bufferRecords = null` | Terminal. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | `startBuffer()` immediately (129). |
| `sourceNext(v)` | yes | source | Push into every current record; maybe `emit` on max size (133–145). |
| `sourceError(e)` | yes | source | No partial `next` (line 158). |
| `sourceComplete` | yes | source | `next` every remaining buffer, including empty, then `complete` (147–156). |
| `cancel` | yes | unsubscribe | No `next`, no `complete`. |
| `spanFired(record)` | yes | per-buffer `executeSchedule` (116) | `emit(record)`. |
| `creationFired` | yes, interval mode | repeating schedule (124) | `startBuffer`. |
| user callback | no | — | None. |
| inner error | no | timers do not error | Inapplicable. |

### Γ

`none` | `next(T[])` | `error(e)` | `complete`. Micro-trace required at span boundaries and on complete.

## C. Transition obligations

### Span-only (`creationInterval == null` or `< 0`), fully specified

`restartOnEmit = true`. `maxBufferSize` defaults to `Infinity`.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | span-only | `none` | one record with `[]`; timer due at `span` (106–117, 129) | `Open([empty])` | ε | values or span | S01 |
| T02 | `Open` | `sourceNext(v)` | length stays `< maxBufferSize` | `none` | push into each record (142–143) | same records | T01 | — | S01 |
| T03 | `Open([buf])` | `spanFired` | — | `next(buf)` even if empty | unsubscribe record subs, `arrRemove`, then `next` (93–97); `restartOnEmit` calls `startBuffer` (98) | `Open([fresh empty])` | T01 or T02 | next span | S01 |
| T04 | `Open` | `sourceNext(v)` | `maxBufferSize <= length` after push | `next(buf)` | `emit` cancels that record’s timer and, if `restartOnEmit`, starts a new buffer (144, 93–98) | `Open` with the new buffer, which does not contain `v` | T02 | — | S02 |
| T05 | `Open` with records | `sourceComplete` | — | `next` for each record in order, including empty, then `complete` | loop 150–152; then unsubscribe subscriber (153–156). Timers cleared by that unsubscribe, not before the `next`s | `Stopped` | T01 or T02 | span must not double-emit | S03 |
| T06 | `Open` with partial or empty | `sourceError(e)` | — | `error(e)`; no `next` | default error; finalize nulls records (158–160); timers cleared | `Stopped` | T02 | none | S04 |
| T07 | `Open` | `cancel` | — | `none` | timers unsubscribed; records nulled on finalize; no `complete` | `Stopped` | T02 | span must not emit | S05 |
| T08 | `Stopped` | `spanFired` | records null or subs dead | `none` | `startBuffer` no-ops if `bufferRecords` is null (107) | `Stopped` | T05–T07 | none | — |

### Creation-interval overload (`creationInterval >= 0`)

`restartOnEmit = false`. Repeating `startBuffer` every `creationInterval`, plus the synchronous first buffer.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T20 | ∅ | `subscribe` | interval `>= 0` | `none` | immediate `startBuffer`; repeating schedule due after one interval (120–129) | `Open([buf0])` | ε | — | S06 |
| T21 | `Open` | `creationFired` | `bufferRecords != null` | `none` (the new window observable is not a buffer `next`; the buffer starts empty) | another record appended; its own span timer (106–117) | more records | T20 | — | S06 |
| T22 | `Open` | `spanFired(record)` | `restartOnEmit` false | `next(that buffer)` only | record removed; no automatic replacement (98) | records without it | T20 | gap if no other record is open | S06 |
| T23 | `Open` | `sourceNext(v)` | some records open | `none` or max-size emits | `v` pushed into every open record only (138–145). Values while the list is empty are dropped | same | T22 if a gap | — | S06 |
| T24 | `Open` | `sourceComplete` | — | every still-open buffer, including empty, then `complete` | same loop as T05; repeating schedule cleared by `subscriber.unsubscribe()` | `Stopped` | T20 | none | S06 |
| T25 | `Open` | `sourceError` / `cancel` | — | error: `error(e)` and no buffers; cancel: `none` | timers and repeating schedule cleared | `Stopped` | T20 | none | S04 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Span-only opens a buffer during subscribe, before any source value (129). |
| I02 | A span fire emits the buffer even if no values arrived, then span-only opens another (T03). |
| I03 | Source complete emits all open buffers, including empty ones, then completes (150–155). |
| I04 | Source error does not emit open buffers (158). |
| I05 | `cancel` emits nothing and does not complete. |
| I06 | `maxBufferSize` counts elements after the push. The closing value is inside the emitted array. The restarted span-only buffer does not contain it. |
| I07 | `maxBufferSize` of `0` is stored as `Infinity` (`\|\|` at line 78). |
| I08 | In creation-interval mode, closing a buffer does not open the next one; the repeating schedule does. If `creationInterval > span`, there are gaps and values in the gaps are dropped. |
| I09 | The first creation-interval buffer exists at t=0, not after the first interval (129 plus 124). |

## E. Scenario specification

### S01 Span emits empty and non-empty buffers

- Test ID: S01
- Covered row IDs: T01, T02, T03
- Starting state: unsubscribed
- Reset/fixture: `bufferTime(10)`, virtual scheduler, no max size
- prefix: `subscribe` at t=0
- target event: span at t=10 with no values, then `sourceNext(a)` at t=12, then span at t=20
- expected notifications: `next([])` at t=10; `next([a])` at t=20
- lifecycle: each emit unsubscribes that record and starts the next
- suffix: `Open` with a fresh empty buffer due at t=30
- final state: `Open`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (`bufferTime.ts` 93–98, 120–129, 133–145)

### S02 maxBufferSize closes early

- Test ID: S02
- Covered row IDs: T04
- Starting state: `Open` span-only, `maxBufferSize = 2`, span 100
- Reset/fixture: `bufferTime(100, null, 2)` so creation interval is null and the third numeric is max size. Note `popScheduler` only if a scheduler is last.
- prefix: `subscribe`
- target event: `sourceNext(a)`, `sourceNext(b)`
- expected notifications: `next([a, b])` on the second value; span timer for that record cancelled
- lifecycle: `restartOnEmit` starts a new buffer immediately
- suffix: `Open` with `[]` not containing `a` or `b`
- final state: `Open`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (lines 78, 142–144, 93–98)

### S03 Complete flushes the open buffer

- Test ID: S03
- Covered row IDs: T05
- Starting state: `Open([[a]])` or `Open([[]])`
- Reset/fixture: span not yet fired
- prefix: `subscribe` and optional value
- target event: `sourceComplete`
- expected notifications: `next([a])` or `next([])`, then `complete`
- lifecycle: destination unsubscribe after complete cancels the span timer so it cannot emit again
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (147–156)

### S04 Error and cancel drop the open buffer

- Test ID: S04
- Covered row IDs: T06, T25
- Starting state: `Open([[a]])`
- Reset/fixture: span-only and, separately, creation-interval
- prefix: `sourceNext(a)`
- target event: `sourceError(e)` or, for cancel, see S05
- expected notifications: `error(e)`, not `next([a])`
- lifecycle: timers cleared; `bufferRecords = null`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (line 158)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T07
- Starting state: `Open([[a]])`
- Reset/fixture: span armed
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: record subscription unsubscribed; no `complete`
- suffix: span time must not `next`
- final state: `Stopped`
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (109, 116, 160)

### S06 Creation interval can overlap or leave a gap

- Test ID: S06
- Covered row IDs: T20, T21, T22, T23, T24
- Starting state: unsubscribed
- Reset/fixture: `bufferTime(10, 10)` (adjacent) and a separate `bufferTime(5, 10)` (gap)
- prefix: `subscribe` at t=0
- target event: creation ticks and span ticks; a value during a gap for the second fixture
- expected notifications: buffers close on their own span; a value while no record is open is absent from every array; source complete emits whatever is still open, including `[]`
- lifecycle: `restartOnEmit` is false, so span fire does not call `startBuffer`
- suffix: `Stopped` if complete is included, else `Open`
- final state: as suffix
- version and scheduler: 7.8.2, virtual scheduler
- assertion type: source characterization
- oracle source: source characterization (120–129, 93–98)

## F. Coverage and evidence

Denominator = 14 (T01–T08 and T20–T25). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S05 | not executed |
| T08 | none | not executed |
| T20 | S06 | not executed |
| T21 | S06 | not executed |
| T22 | S06 | not executed |
| T23 | S06 | not executed |
| T24 | S06 | not executed |
| T25 | S04 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Tie order between a span action and source complete is assumed; the complete handler emits buffers and only then unsubscribes, so a reentrant scheduler could double-emit. That reentrancy is excluded. `maxBufferSize || Infinity` makes `0` mean unlimited. Negative creation intervals silently select span-only.
- Contract vs 7.8.2 characterization: JSDoc 31–38 matches both overloads. Empty emits on span and on complete are visible in the code (the buffer starts as `[]` and is passed to `next` unconditionally) more than in the informal text.
- Tests still required: S01–S06 on `TestScheduler`, including complete of an empty span buffer, error versus complete, `maxBufferSize`, and `bufferTime(span, creationInterval)` with `creationInterval > span`.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
