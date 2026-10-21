# bufferCount

`bufferCount(bufferSize, startBufferEvery = null)` emits arrays of source values (`bufferCount.ts` 57–119). If `startBufferEvery` is `null`, it is set to `bufferSize` (line 60). A new buffer opens on the first value and every `startBufferEvery` values after that (`count % startBufferEvery === 0`, lines 75–77). Every open buffer receives the value. A buffer is emitted when its length reaches `bufferSize`, then removed. Source `complete` emits every still-open buffer, which is partial and non-empty if any values were seen, and emits nothing if no buffer was opened. Source `error` does not emit partials. `cancel` emits nothing. Overlap exists when `startBufferEvery < bufferSize`. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/bufferCount.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `bufferCount<T>(bufferSize: number, startBufferEvery: number | null = null): OperatorFunction<T, T[]>` (`bufferCount.ts` 57).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 15–19. Buffers are not opened at subscribe; they open when a value arrives and the count test passes. Contrast `windowCount`, which emits a window immediately.
- Model kind: extended, not finite. The list of open buffers and `count` are unbounded in time.
- Parameter domain: documented positive integers. `startBufferEvery == null` becomes `bufferSize` (line 60). `startBufferEvery === 0` makes `count % 0` `NaN`, and `NaN === 0` is false, so no buffer ever opens; values are dropped. That is excluded from the ordinary model and recorded as T12. `bufferSize <= 0` with a positive start emits as soon as a buffer’s length is `>= bufferSize`, which is on the same value that opened it if `bufferSize <= 1` after the push. Non-positive sizes are excluded from the ordinary rows except that note.
- Payload/error domain: `T[]`. Source error forwarded as-is (error handler `undefined`, line 112).
- Subscription boundary: one source subscriber (66–118). No inner observable.
- Scheduler and tie ordering: none. No micro-trace against a clock. Complete versus error is still two different rows.
- Callback assumptions: no selector. Emit happens after the value is pushed and after the `toEmit` list is built, so the `buffers` array is not mutated while it is being iterated (84–86, 93–100). Ordinary model: no reentrancy.
- Cleanup assumptions: finalize nulls `buffers` (113–116) and does not emit. `cancel` does not complete.
- Explicit exclusions: reentrancy; `startBufferEvery === 0`; non-positive `bufferSize` as a supported API; comparing to `windowCount`’s eager open except as a contrast.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Collecting(buffers = [], count = 0)
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Collecting` | list of open `T[]`, integer `count` of values seen | `count` is the number of values already processed. |
| `Stopped` | `buffers` nulled | Terminal. |

No buffer exists in `s₀` until the first opening value. Every opened buffer receives at least the value that opened it before any emit check (80–81), so ordinary open buffers are never empty while stored.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Does not emit. |
| `sourceNext(v)` | yes | source | Lines 69–101. |
| `sourceError(e)` | yes | source | No partial emit (line 112). |
| `sourceComplete` | yes | source | Emit each remaining buffer, then `complete` (103–109). |
| `cancel` | yes | unsubscribe | No emit, no `complete`. |
| inner / timer | no | — | None. |
| user callback | no | — | None. |

### Γ

`none` | `next(T[])` (possibly several from one `sourceNext` or from complete) | `error(e)` | `complete`. One `sourceNext` can emit zero or more buffers; the ordered list of those `next`s is the micro-trace for overlap.

## C. Transition obligations

Ordinary domain: `bufferSize >= 1`, `startEvery >= 1`, `startEvery = startBufferEvery ?? bufferSize`.

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | `buffers=[]`, `count=0` (63–64) | `Collecting` | ε | values | S01 |
| T02 | `Collecting` | `sourceNext(v)` | `count % startEvery === 0` before increment | `none` unless T04 | push a new `[]`, then push `v` into every open buffer (75–81) | buffers updated; `count` incremented | T01 | — | S01 |
| T03 | `Collecting` | `sourceNext(v)` | open condition false | `none` unless some buffer hits size | push `v` into existing buffers only | same | T02 | — | S01 |
| T04 | during T02/T03 | length test | `bufferSize <= buffer.length` | `next(buffer)` for each full buffer, after the loop (93–100) | `arrRemove` those buffers | those buffers gone | T02 | not re-emitted on complete | S01 |
| T05 | `Collecting` with open partials | `sourceComplete` | `buffers` non-empty | `next` for each remaining buffer, in list order, then `complete` (103–109) | includes buffers shorter than `bufferSize` | `Stopped` | T02 | none | S02 |
| T06 | `Collecting` with `buffers=[]` | `sourceComplete` | no values, or all buffers already emitted | `complete` only | loop emits nothing | `Stopped` | T01 or exact multiple | none | S03 |
| T07 | `Collecting` | `sourceError(e)` | partials may exist | `error(e)`; no `next` of partials | finalize nulls `buffers` (113–116) | `Stopped` | T02 | none | S04 |
| T08 | `Collecting` | `cancel` | — | `none` | finalize; no `complete` | `Stopped` | T02 | none | S05 |
| T09 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T10 | overlap | `sourceNext` | `startEvery < bufferSize` | one `next` per buffer that reaches `bufferSize` on this value | several buffers contain the same `v` | still `Collecting` | T02 | — | S06 |
| T11 | gap | `sourceNext` | `startEvery > bufferSize` | values that arrive while no buffer is open are not stored | a buffer emits and is removed before the next open count | values in the gap produce `none` | T04 | — | S06 |
| T12 | `startEvery === 0` | `sourceNext` | `n % 0` is `NaN` | `none` forever from values | no buffer created | `Collecting([])` | T01 | complete is T06 | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | No array is emitted at subscribe. An empty source completes with no `next` (T06). |
| I02 | A buffer opens only on a value whose arrival index satisfies `count % startEvery === 0`, and that value is pushed into it immediately. |
| I03 | Emission of a full buffer happens when its length reaches `bufferSize`, not later, and it is removed so complete will not emit it again. |
| I04 | On source complete, every still-open buffer is emitted once, even if shorter than `bufferSize`. Those buffers have length ≥ 1 in the ordinary domain. |
| I05 | On source error, no partial is emitted. |
| I06 | `cancel` emits nothing and does not complete. |
| I07 | If `startEvery < bufferSize`, buffers overlap. If `startEvery > bufferSize`, some values fall in a gap and appear in no array (T11). |
| I08 | `startBufferEvery == null` means `startEvery = bufferSize` (line 60), non-overlapping. |

## E. Scenario specification

### S01 Non-overlapping full buffers

- Test ID: S01
- Covered row IDs: T01, T02, T03, T04
- Starting state: unsubscribed
- Reset/fixture: `bufferCount(2)` so `startEvery = 2`
- prefix: `subscribe`
- target event: `sourceNext(a)`, `sourceNext(b)`
- expected notifications: `none` for `a`; `next([a, b])` for `b`
- lifecycle: buffer removed after emit; `buffers` empty
- suffix: next pair starts a new buffer
- final state: `Collecting([])`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`bufferCount.ts` 60, 75–100)

### S02 Complete emits a partial

- Test ID: S02
- Covered row IDs: T05
- Starting state: `Collecting([[a]])` for `bufferCount(3)`
- Reset/fixture: one value seen
- prefix: `sourceNext(a)`
- target event: `sourceComplete`
- expected notifications: `next([a])`, `complete`
- lifecycle: no further buffer
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (103–109)

### S03 Complete with nothing open

- Test ID: S03
- Covered row IDs: T06
- Starting state: `Collecting([])`
- Reset/fixture: either no values, or `bufferCount(2)` after exactly `[a,b]` was already emitted
- prefix: `subscribe` or S01
- target event: `sourceComplete`
- expected notifications: `complete` only
- lifecycle: none
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S04 Error drops partials

- Test ID: S04
- Covered row IDs: T07
- Starting state: `Collecting([[a]])`
- Reset/fixture: `bufferCount(3)`
- prefix: `sourceNext(a)`
- target event: `sourceError(e)`
- expected notifications: `error(e)`, not `next([a])`
- lifecycle: finalize nulls `buffers`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (line 112)

### S05 Cancel

- Test ID: S05
- Covered row IDs: T08
- Starting state: `Collecting([[a]])`
- Reset/fixture: partial buffer
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: finalize; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (113–116)

### S06 Overlap and gap

- Test ID: S06
- Covered row IDs: T10, T11
- Starting state: `Collecting`
- Reset/fixture: `bufferCount(3, 1)` and a separate `bufferCount(2, 3)`
- prefix: `subscribe`
- target event: three source values
- expected notifications: for `(3, 1)`, overlapping arrays that share values, first full emit on the third value (`[v0,v1,v2]`) while newer buffers stay open; for `(2, 3)`, `[v0,v1]` emitted on the second value and `v2` in no buffer
- lifecycle: `arrRemove` only the full buffers
- suffix: `Collecting` with the still-open buffers
- final state: `Collecting`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (75–100). The gap matches the shape of the `windowCount(2, 3)` example, but buffers are not opened until the opening value arrives.

## F. Coverage and evidence

Denominator = 12 (T01–T12). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S01 | not executed |
| T04 | S01 | not executed |
| T05 | S02 | not executed |
| T06 | S03 | not executed |
| T07 | S04 | not executed |
| T08 | S05 | not executed |
| T09 | none | not executed |
| T10 | S06 | not executed |
| T11 | S06 | not executed |
| T12 | none (degenerate) | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. `startBufferEvery === 0` and non-positive `bufferSize` are degenerate JavaScript edge cases, not the documented contract. No reentrancy. No clock.
- Contract vs 7.8.2 characterization: JSDoc 15–19 matches open-on-count and emit-at-size. Complete-flush of partials is code (103–109), not a sentence in the informal description. Empty source emits no array.
- Tests still required: S01–S06, plus exact-multiple complete (no extra empty array) and source error with several overlapping partials.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
