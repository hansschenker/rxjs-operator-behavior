# merge

Operator `merge` (deprecated; JSDoc: replaced by `mergeWith`, removed in v8) builds one higher-order sequence and flattens it. At subscribe time it pops a trailing `SchedulerLike` (`popScheduler`) and then a trailing concurrency number (`popNumber`, default `Infinity`), then runs `mergeAll(concurrent)(from([source, ...remainingArgs], scheduler))` (`operators/merge.ts` 22–28). `mergeAll(n)` is `mergeMap(identity, n)` (`operators/mergeAll.ts` 64–66), and `mergeMap` calls `mergeInternals` (`operators/mergeMap.ts` 82–93, `operators/mergeInternals.ts` 21–149). `from` with a scheduler is `scheduled`, otherwise `innerFrom` (`observable/from.ts` 102–104). This is not the static `merge` in `observable/merge.ts` (that function is a sibling creation API with the same flatten strategy). Inputs are multi-source: index `0` is the upstream, indices `1..n-1` are the arguments left after the pops. Each input is an `ObservableInput` coerced by `innerFrom` only when that slot is actually subscribed.

## A. Identity, contract, and scope

| Field | Domain | Initial on `subscribe` | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| init \| waiting \| completed \| errored \| cancelled` | `idle` | Control location. Emission is an output, not a resting phase. |
| `concurrent` | positive integer or `Infinity` (runtime also accepts `0`) | `popNumber(args, Infinity)` | Max simultaneously subscribed inputs. |
| `scheduler` | `SchedulerLike \| absent` | `popScheduler(args)` | If present, gates delivery of the input list, not each inner `next`. |
| `inputs` | `ObservableInput[]` | `[source, ...args]` | Indexed sources. Length `n ≥ 1` (upstream is always included). |
| `hoIndex` | integer | `0` | Next input index the higher-order list will hand to `mergeInternals`. |
| `buffer` | queue of inputs | `[]` | Inputs seen while `active >= concurrent` (`mergeInternals.ts` 32, 52). |
| `active` | integer | `0` | Subscribed inners not yet completed (`mergeInternals.ts` 34, 62). |
| `outerDone` | boolean | `false` | Higher-order list has completed (`mergeInternals.ts` 37, 139). |
| `seen` | per index `pending \| active \| done \| dropped` | all `pending` | Whether that source was subscribed. |

`emitting` is the set of transitions whose output contains `outNext`. There is no separate data field for it.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)` with `s₀ = (phase=idle, empty buffer, active=0, outerDone=false)`. `S` is the control location times the fields in A (extended/symbolic). `δ` and `λ` are the transition rows in C; a row is one pair `(δ, λ)`.

### S (control locations)

| Location | Meaning |
| --- | --- |
| `idle` | Operator not subscribed. |
| `init` | Higher-order list is being opened (sync `innerFrom` or first scheduler action). |
| `waiting` | At least the setup has run; zero or more inners are active; output is open. |
| `completed` | `outComplete` has been produced. |
| `errored` | `outError` has been produced. |
| `cancelled` | Downstream unsubscribed before a terminal notification. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Starts the machine. |
| 2 | Downstream cancel | `unsubscribe` | Tears down every active inner and the higher-order subscription. |
| 3 | Primary-list next | `hoNext(i)` | Higher-order emits input `i` (the `ObservableInput` object, not a value). |
| 4 | Primary-list error | `hoError(e)` | Only if `from` / `scheduled` fails. The input list itself does not error in normal use. |
| 5 | Primary-list complete | `hoComplete` | List of inputs exhausted. |
| 6 | Inner next | `sourceNext(i, v)` | Value from subscribed input `i`. |
| 7 | Inner terminal | `sourceError(i, e)`, `sourceComplete(i)` | Per subscribed input. Unsubscribed or not-yet-subscribed indices do not emit these. |
| 8 | Scheduler | `schedTick` | Present only when `scheduler` was popped. One `scheduleArray` action emits one list element (`scheduled/scheduleArray.ts` 4–25). Absent otherwise. |

### Γ

| Symbol | Meaning |
| --- | --- |
| `ε` | No downstream notification. |
| `sub(i)` | `innerFrom(inputs[i]).subscribe` (`mergeInternals.ts` 71). |
| `unsub(*)` | Destination unsubscribe; active inners and the higher-order subscription are children and drop. `buffer` discarded. |
| `outNext(v)` | Forward inner value (`mergeInternals.ts` 85). No projection. |
| `outError(e)` | First inner error, or a projection/`innerFrom` throw caught by `OperatorSubscriber` / the inner finalizer (`OperatorSubscriber.ts` 67–74, `mergeInternals.ts` 126–128). |
| `outComplete` | `outerDone && buffer empty && active = 0` (`mergeInternals.ts` 43–48). |

## C. Transition obligations

Synchronous list order is in-model: without a scheduler, `innerFrom` on the array emits every `hoNext(i)` and `hoComplete` in index order before `subscribe` returns (`innerFrom.ts` `fromArrayLike`, 66–80), interleaved with any synchronous inner notifications those subscriptions produce. Ordinary downstream reentrancy (a handler that re-enters `subscribe` on this same result) is excluded.

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | `scheduler` absent | `init` | `ε` (array `from` begins sync) |
| T02 | init | `idle` | `subscribe` | `scheduler` present | `init` | `ε` (`scheduleArray` arms one action) |
| T03 | init | `init` | `hoNext(i)` | `active < concurrent` | `waiting` | `sub(i)`; `active := active+1`; slot `active` |
| T04 | waiting | `waiting` | `hoNext(i)` | `active >= concurrent` | `waiting` | `ε`; `buffer` appends `i` |
| T05 | waiting | `waiting` | `hoComplete` | `active = 0` and `buffer` empty | `completed` | `outComplete` |
| T06 | waiting | `waiting` | `hoComplete` | `active > 0` or `buffer` nonempty | `waiting` | `ε`; `outerDone := true` |
| T07 | emitting | `waiting` | `sourceNext(i, v)` | slot `i` is `active`; output not stopped | `waiting` | `outNext(v)` |
| T08 | per-source error | `waiting` | `sourceError(i, e)` | slot `i` is `active` | `errored` | `outError(e)`, `unsub(*)`; pending buffer dropped |
| T09 | per-source complete | `waiting` | `sourceComplete(i)` | after decrement, `buffer` nonempty and `active < concurrent` | `waiting` | `ε` then `sub(j)` for each shifted `j` while `active < concurrent` (`mergeInternals.ts` 99–122) |
| T10 | per-source complete | `waiting` | `sourceComplete(i)` | `outerDone` and `buffer` empty and `active = 0` after decrement | `completed` | `outComplete` |
| T11 | per-source complete | `waiting` | `sourceComplete(i)` | not T09 and not T10 | `waiting` | `ε`; `active := active-1`; slot `done` |
| T12 | cancel | `init` or `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T13 | terminal | `completed`, `errored`, or `cancelled` | any | — | same | `ε` |
| T14 | scheduler | `init` or `waiting` | `schedTick` | `scheduler` present and list not exhausted | `init` or `waiting` | same as T03 or T04 for the next index; a further tick is armed if the subscriber is still open (`scheduleArray.ts` 18–22) |
| T15 | per-source error | `init` or `waiting` | `innerFrom` or subscriber callback throws while starting `i` | during T03/T09 | `errored` | `outError(e)`, `unsub(*)` |

T09’s `sub(j)` is synchronous when `innerSubScheduler` is absent (it is absent on this path; that hook is for `expand`). A synchronous `sourceComplete` that happens inside `sub(j)` chains another T09/T10 before the outer notification returns.

## D. Contract invariants

1. Index `0` is always the upstream. `merge(a$, b$, 2)` means inputs `(source, a$, b$)` and `concurrent = 2` (`popScheduler` runs before `popNumber`, `util/args.ts` 9–18).
2. Every `outNext(v)` is some `sourceNext(i, v)` with the input order preserved per index and no cross-index reordering beyond interleaving of concurrently subscribed sources.
3. No input with `seen = pending` inside `buffer`, and no input past the concurrency cap, has been subscribed. `mergeWith`’s default `Infinity` subscribes every input during the synchronous list flush.
4. `outComplete` happens only after every input has completed, which implies `outerDone`, an empty `buffer`, and `active = 0`. A still-active sibling keeps the output open after another index completes.
5. The first `sourceError(i, e)` is the output error. Later indices are not subscribed if the error is synchronous during the list flush (`Subscriber` is stopped). Already active siblings are unsubscribed. There is no resume.
6. Values are not buffered. Only not-yet-subscribed `ObservableInput`s sit in `buffer`.
7. With a scheduler, `scheduleArray` emits one input object per action. It does not wrap those observables in `scheduleObservable`, so once `sub(i)` runs, that source’s own `next`s are not scheduler-shifted.
8. `concurrent <= 0` never enters T03, so every input stays buffered, `active` stays `0`, and T05/T10 cannot fire if `n ≥ 1`. The output neither emits nor completes. Not a supported call shape (`Infinity` is the default).

## E. Scenario specification

Source characterization only. Not executed.

### E1. Unlimited concurrency, sync values

`of(1, 2).pipe(merge(of(3)))`, no scheduler, `concurrent = Infinity`. Inputs: `0 = of(1, 2)`, `1 = of(3)`.

1. `subscribe` → T01. `hoNext(0)` → T03 `sub(0)`. `of(1, 2)` sync: T07 `outNext(1)`, T07 `outNext(2)`, T09/T11 `active` returns to `0` before `hoNext(1)` (buffer still empty).
2. `hoNext(1)` → T03 `sub(1)` → T07 `outNext(3)` → inner complete, `active = 0`.
3. `hoComplete` → T05 `outComplete`.

Observed sequence: `1, 2, 3, complete`.

### E2. Finite concurrency defers subscribe

Inputs `A`, `B`, `C`, `concurrent = 1` (the `concat` shape, but via this operator). `A` emits `a` then completes later; `B` and `C` are cold.

1. T03 `sub(A)`; T04 buffers `B`; T04 buffers `C`; T06 `outerDone`.
2. T07 `outNext(a)`; T09 on `A` complete: `sub(B)`.
3. On `B` complete, T09 `sub(C)`. On `C` complete, T10 `outComplete`.

`B` is not subscribed until `A` completes. Same nesting is `concat` / `concatAll` (`operators/concatAll.ts` 60–62).

### E3. Error wins and drops the tail

`concurrent = Infinity`. Input `0` errors `e` synchronously before `hoNext(1)`.

1. T03 `sub(0)` → T08 `outError(e)`, `unsub(*)`.
2. Further `hoNext` notifications hit a stopped subscriber and do not subscribe input `1` (T13).

No `outComplete`. Input `1` side effects do not run.

### E4. Scheduler only sequences the list

`merge(other$, asyncScheduler)` (scheduler overload is part of the deprecated signature). No `schedTick` yet: no `sub`. First tick: T14/T03 `sub(0)` (upstream). A later tick: T03 `sub(1)`. Upstream values that arrive between ticks are delivered immediately (T07); they are not queued onto the scheduler. After both complete and `hoComplete` has been delivered by the last tick, T10 `outComplete`.

### E5. One fast source, one quiet source

Input `0` completes with no value while input `1` is still active (`concurrent = Infinity`, both already subscribed). T11: `active` goes `1 → 0` is wrong here — input `1` is still active, so `active` goes `2 → 1`, T11, no `outComplete`. Output stays `waiting` until input `1` completes (T10) or errors (T08). Silence from `0` does not invent a value.

## F. Coverage and evidence

Not executed.

Denominator = 15 (T01–T15). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: `ObservableInput` interop (promise, iterable, readable stream) is whatever `innerFrom` does at `sub(i)` and is not expanded. `concurrent <= 0` is the hang in D8. Stopped-subscriber notifications after T08/T12 are dropped by `Subscriber`, not separate outputs. The static `observable/merge.ts` early-returns (`EMPTY`, single-source `innerFrom`) are not taken by this operator, because the array always contains the upstream.
