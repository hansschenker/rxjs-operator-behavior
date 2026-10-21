# startWith

`startWith(...values)` pops a trailing scheduler (`operators/startWith.ts` 59–66). It then subscribes the downstream to static `concat(values, source)` or, if a scheduler was popped, `concat(values, source, scheduler)`. The `values` identifier here is the **array** left after `popScheduler`, passed as one argument, not spread. Static `concat` (`observable/concat.ts` 113–115) pops that scheduler again and returns `concatAll()(from(args, scheduler))`, with `concatAll = mergeAll(1)` (`operators/concatAll.ts` 60–62). So the higher-order sequence has two items: the prefix array, then the source.

Without a scheduler, `from` emits both items synchronously. `mergeInternals` with `concurrent = 1` subscribes the prefix array first. `innerFrom` on an array emits each element synchronously and completes (`innerFrom.ts` 66–80). Only then is the source subscribed. That is the JSDoc rule (`startWith.ts` 21–23, 52–53): synchronous prefix nexts, then the source.

With a scheduler, `from([prefixArray, source], scheduler)` is `scheduleArray` (`scheduled/scheduled.ts` 28–35, `scheduleArray.ts` 4–25): one scheduler action delivers the prefix **array object**, and a later action delivers the source. Flattening that array is still a synchronous `innerFrom` inside the first action. Individual prefix values are not each scheduled. The scheduler overload is deprecated (`startWith.ts` 14–16, and the note at 62–64). `null` and `undefined` are ordinary prefix values (`startWith.ts` 11–12); `isScheduler` requires a `schedule` function (`util/isScheduler.ts` 5–7).

The source’s own error and complete are mirrored after the prefix. A source error does not emit further prefix values (the prefix has already completed). Unsubscribing during the prefix, or before a scheduled action runs, skips the source.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| prefix \| mirroring \| completed \| errored \| cancelled` | `idle` | — |
| `prefix` | array | arguments after `popScheduler` | May be empty. |
| `pi` | integer | `0` | Next prefix index. |
| `scheduler` | `SchedulerLike \| absent` | popped or absent | Gates the higher-order pair only. |
| `hoStep` | `0 \| 1 \| 2` | `0` | `0` nothing delivered, `1` prefix array delivered, `2` source delivered or list complete. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. One upstream source, plus an internal prefix sequence. Not a multi-source race or combine.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `prefix` | Emitting prefix values; source not subscribed. |
| `mirroring` | Prefix finished; source subscribed. |
| `completed` | Source completed (prefix already finished). |
| `errored` | Source errored. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Source next | `sourceNext(v)` | Only in `mirroring`. |
| 4 | Source error | `sourceError(e)` | Forwarded. Prefix is not repeated. |
| 5 | Source complete | `sourceComplete` | Forwarded. No extra suffix. |
| 6 | Prefix value | internal, modeled as the array walk | Not a second observable the caller subscribes. |
| 7 | Prefix complete | internal | The signal that allows `sub(source)`. |
| 8 | Scheduler | `schedTick` | Only on the deprecated overload. Each tick delivers one higher-order item (`scheduleArray.ts` 9–23). |

### Γ

`ε`, `outNext(prefix[k])`, `subSource`, `unsub(*)`, `outNext(v)` for source values, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | no scheduler, `prefix` nonempty | `prefix` | no `subSource` yet |
| T02 | emitting | `prefix` | array step | `pi < prefix.length` and subscriber open | `prefix` | `outNext(prefix[pi])`; `pi := pi+1`. Synchronous, in order (`innerFrom.ts` 77–78). |
| T03 | init | `prefix` | prefix array completes | `pi = prefix.length` | `mirroring` | `subSource` (`mergeInternals.ts` 107–122 with the source waiting as the next inner, or T07 if the source was not yet delivered) |
| T04 | emitting | `mirroring` | `sourceNext(v)` | — | `mirroring` | `outNext(v)` |
| T05 | per-source error | `mirroring` | `sourceError(e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T06 | terminal | `mirroring` | `sourceComplete` | — | `completed` | `outComplete` |
| T07 | waiting | `prefix` | higher-order has not yet emitted the source | scheduler present and prefix inner already completed inside an earlier tick | `prefix` | `ε`; `active = 0` until the next tick |
| T08 | scheduler | `idle` or `prefix` | `schedTick` | next higher-order item is the prefix array | `prefix` | then T02 for every element, synchronously, then T03 or T07 |
| T09 | scheduler | `prefix` or `mirroring` | `schedTick` | next higher-order item is the source and prefix is done | `mirroring` | `subSource` |
| T10 | terminal | `prefix` | `schedTick` or sync `hoComplete` | prefix empty and source already completed, or empty prefix and the source item completes the chain | `completed` | `outComplete` when the source inner completes |
| T11 | cancel | `prefix` or `mirroring` | `unsubscribe` | — | `cancelled` | `unsub(*)`. If still in `prefix`, `subSource` does not happen. |
| T12 | init | `idle` | `subscribe` | no scheduler, `prefix` empty | `mirroring` | the empty array completes with no `outNext`, then `subSource` in the same turn |
| T13 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

No-scheduler order inside one `subscribe` turn: T01, T02 repeated, T03 `subSource`, then any synchronous source notifications (T04/T05/T06), then the higher-order complete. The source is not subscribed before the prefix `outNext`s. That is the opposite of `endWith`.

Empty prefix (T12) still builds `concat([], source)`. There is a synchronous empty inner subscription, then the source. Observable notifications match the source.

Deprecated scheduler order: first `schedTick` runs T08 and emits the whole prefix synchronously inside that action; `subSource` waits for a later tick (T09). `queueScheduler` may drain both actions before `subscribe` returns to user code, but the source subscription is still ordered after the prefix emissions.

## D. Contract invariants

1. Every prefix value is an `outNext` strictly before `subSource`, unless the downstream unsubscribes during the prefix (the array loop stops when `subscriber.closed`, `innerFrom.ts` 77).
2. Prefix values are emitted in argument order, including `null` and `undefined`.
3. After `subSource`, notifications are exactly the source’s. There is no second copy of the prefix on `sourceComplete`.
4. `sourceError` does not become `outComplete` and does not append values.
5. Without a scheduler, the prefix is synchronous on the subscribing stack.
6. With a scheduler, prefix elements are not one-per-tick. The tick boundary sits between the prefix array and the source (`startWith.ts` 65 versus `scheduleArray.ts`).
7. The scheduler parameter is deprecated (`startWith.ts` 14–16).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Timer story from the JSDoc

`timer(1000).pipe(map(() => 'timer emit'), startWith('timer start'))`. On subscribe, T02 `outNext('timer start')` before `subSource` (T03). Later the source next is T04 `outNext('timer emit')` and T06 `outComplete`. Trace: `'timer start'`, `'timer emit'`, `complete`.

### E2. Several sync prefix values

`src.pipe(startWith(1, 2, 3))` and `src` synchronously emits `'a'` then completes. During `subscribe`: `outNext(1), outNext(2), outNext(3)`, then `subSource`, then `outNext('a'), outComplete`. The source factory does not run before `3`.

### E3. Empty prefix

`src.pipe(startWith())`. T12 `subSource` with no leading `outNext`. `src`’s notifications are unchanged.

### E4. Unsubscribe during the prefix

Prefix `(1, 2, 3)`. The downstream unsubscribes inside the handler for `1`. The array loop stops (`innerFrom.ts` 77). T11. `2` and `3` are not emitted. `subSource` does not run.

### E5. Deprecated scheduler

`startWith(1, 2, asyncScheduler)`. T01 is replaced by waiting for ticks. Before any tick, no `outNext` and no `subSource`. First tick: `outNext(1), outNext(2)` synchronously inside that action, still no `subSource` (T07). Next tick: T09 `subSource`. Source values are not delayed by further prefix ticks. This is not “one scheduled action per prefix value”.

## F. Coverage and evidence

Not executed.

Denominator = 13 (T01–T13). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model for the prefix array, which is synchronous
- limits: Concrete `SchedulerLike` implementations are not modeled past `scheduleArray`’s one-item-per-action contract. `queueScheduler` draining is mentioned only as an ordering note. Prefix values are not re-interpreted as observables; they are array elements. A prefix value that is itself an observable is still emitted as a single next, because the prefix is flattened only one level by `innerFrom` on the array.
