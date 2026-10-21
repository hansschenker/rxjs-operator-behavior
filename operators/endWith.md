# endWith

`endWith(...values)` returns `(source) => concat(source, of(...values))` (`operators/endWith.ts` 66–68). It does not use `operate` / `lift`. Static `concat` (`observable/concat.ts` 113–115) is `concatAll()(from([source, of(...)]))` with `concatAll = mergeAll(1)`, so the source is subscribed first and `of` is subscribed only after the source completes. `of` (`observable/of.ts` 80–83) pops a trailing scheduler and `from`s the remaining values. Without a scheduler, `fromArrayLike` emits every suffix value synchronously and completes (`innerFrom.ts` 66–80). Those nexts therefore sit after the source’s values and before `outComplete`. JSDoc (`endWith.ts` 17–18, 62–64) states that. The scheduler overloads are deprecated (`endWith.ts` 7–12 and the NOTE at 20–21).

Unlike `startWith`, a scheduler here is inside `of(...values)`, so `scheduleArray` runs over the suffix values themselves: one value per scheduler action, then a further action to complete (`scheduleArray.ts` 9–16). `endWith(scheduler)` alone pops the scheduler and schedules an empty array, which completes on the first action with no `outNext`.

If the source errors, `mergeInternals` errors the destination and never subscribes the `of` inner. Suffix values are not emitted. If the downstream unsubscribes before source complete, the suffix is not subscribed.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| mirroring \| suffix \| completed \| errored \| cancelled` | `idle` | — |
| `suffix` | array | `of`’s args after `popScheduler` | May be empty. |
| `si` | integer | `0` | Next suffix index. |
| `scheduler` | `SchedulerLike \| absent` | last arg if `isScheduler` | Deprecated. Applies only to the suffix observable. |
| `sourceDone` | boolean | `false` | Source inner completed and the suffix inner has been started or is the next shift. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `mirroring` | Source subscribed; suffix not subscribed. |
| `suffix` | Source has completed; suffix values (if any) are being emitted. |
| `completed` | Suffix completed. |
| `errored` | Source errored. The suffix was not subscribed. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Subscribes the source only. |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Source next | `sourceNext(v)` | Forwarded unchanged. |
| 4 | Source error | `sourceError(e)` | Terminal. Skips the suffix. |
| 5 | Source complete | `sourceComplete` | Starts the suffix. Not yet `outComplete` if the suffix will emit or is scheduled. |
| 6 | Suffix value | internal array or `schedTick` payload | Caller-supplied constants, not a second upstream. |
| 7 | Suffix complete | internal | The real `outComplete`. |
| 8 | Scheduler | `schedTick` | Deprecated path only. One suffix element or the final complete per action. |

### Γ

`ε`, `subSource`, `subSuffix`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `mirroring` | `subSource`. No suffix nexts. |
| T02 | emitting | `mirroring` | `sourceNext(v)` | — | `mirroring` | `outNext(v)` |
| T03 | per-source error | `mirroring` | `sourceError(e)` | — | `errored` | `outError(e)`, `unsub(*)`. `subSuffix` does not happen. |
| T04 | per-source complete | `mirroring` | `sourceComplete` | no scheduler | `suffix` | `subSuffix` |
| T05 | emitting | `suffix` | array step | no scheduler and `si < suffix.length` | `suffix` | `outNext(suffix[si])` synchronously (`innerFrom.ts` 77–78) |
| T06 | terminal | `suffix` | suffix completes | no scheduler and `si = suffix.length` | `completed` | `outComplete` |
| T07 | per-source complete | `mirroring` | `sourceComplete` | scheduler present | `suffix` | `subSuffix`, which only arms `scheduleArray`. No suffix `outNext` yet. |
| T08 | scheduler | `suffix` | `schedTick` | `si < suffix.length` | `suffix` | `outNext(suffix[si])`; `si := si+1`; arm the next action if still open (`scheduleArray.ts` 15–22) |
| T09 | scheduler | `suffix` | `schedTick` | `si = suffix.length` | `completed` | `outComplete` |
| T10 | cancel | `mirroring` or `suffix` | `unsubscribe` | — | `cancelled` | `unsub(*)`. Remaining suffix values are not emitted. |
| T11 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

T04–T06 with a non-empty suffix run in the source-complete turn: the subscriber sees the suffix nexts before `outComplete`, and it does not see `outComplete` at the source’s complete notification itself. An empty suffix with no scheduler takes T04 then T06 with no T05, so `outComplete` is still synchronous on source complete and there is no extra `outNext`.

`endWith` returns a new `concat` observable rather than lifting (`endWith.ts` 67). A custom `Observable` subclass’s `lift` is not used.

## D. Contract invariants

1. No suffix `outNext` occurs before `sourceComplete`.
2. Every source `outNext` precedes every suffix `outNext`.
3. Without a scheduler, suffix nexts are synchronous in argument order inside the source complete, and `outComplete` follows them immediately.
4. `sourceError` emits no suffix value and no `outComplete`.
5. Unsubscribe in `mirroring` or mid-suffix drops the rest of the suffix.
6. `null` and `undefined` are suffix values if they were arguments. A trailing object with `schedule` is a scheduler, not a value (`util/isScheduler.ts` 5–7, `observable/of.ts` 81).
7. The scheduler parameter is deprecated (`endWith.ts` 7–12, 20–21) and, unlike `startWith`, it schedules each suffix value.

## E. Scenario specification

Source characterization only. Not executed.

### E1. JSDoc interval tail

Source emits `'tick'` three times and then completes because of an upstream `takeUntil`. `endWith('interval ended by click')`. Each tick is T02. Source complete is T04–T06: `outNext('interval ended by click')`, then `outComplete`. The suffix is not present on subscribe (contrast `startWith`).

### E2. Sync source

`of(1, 2).pipe(endWith(3, 4))`. Trace, all in the subscribe turn: `1`, `2`, `3`, `4`, `complete`. `3` is not emitted before `2`. `complete` is not emitted between `2` and `3`.

### E3. Source errors

Source emits `1` then errors `e`. `endWith(9)`. Trace: `outNext(1), outError(e)`. `9` is absent. Phase `errored`, not `suffix`.

### E4. Empty suffix

`src.pipe(endWith())`. `of()` is an empty array. On source complete, T04 then T06 with no extra next. Notifications match `src`, including a synchronous complete. `endWith(asyncScheduler)` is different: T07 arms a tick, and T09 delivers `outComplete` on that tick with no extra next. Completion is not synchronous.

### E5. Deprecated per-value scheduler

`endWith(1, 2, asyncScheduler)`. Source completes. T07: no suffix next yet. First tick T08 `outNext(1)`. Second tick T08 `outNext(2)`. Third tick T09 `outComplete`. The source’s own values were not scheduled. Unsubscribe after `outNext(1)` is T10: `2` and `outComplete` do not happen.

## F. Coverage and evidence

Not executed.

Denominator = 11 (T01–T11). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model for the unscheduling suffix array
- limits: Scheduler implementations are modeled only as `scheduleArray` actions. Because `endWith` does not use `operate`, interaction with a subclass `lift` is out of the machine. Suffix arguments are values, not flattened observables, except that `of` will still treat a trailing scheduler specially. See `startWith.md` for the opposite order and the different scheduler nesting.
