# combineLatest

Deprecated operator (JSDoc: use `combineLatestWith`, removed in v8). `operators/combineLatest.ts` 27–33 pops an optional trailing project function (`popResultSelector`). If one is present it re-enters `combineLatest` without that function and pipes `mapOneOrManyArgs(project)` (`util/mapOneOrManyArgs.ts` 14–16), which spreads an emitted array into the project. Otherwise `operate` calls `combineLatestInit([source, ...argsOrArgArray(args)])(subscriber)` with no scheduler and the default `identity` transform (`operators/combineLatest.ts` 31–32, `observable/combineLatest.ts` 225–288). `argsOrArgArray` unwraps a single array argument (`util/argsOrArgArray.ts` 7–9). Indices: `0` is the upstream, then each other input. This is not the static function’s empty-list `from([])` path and not its scheduler path; `combineLatestInit` supports a scheduler (`observable/combineLatest.ts` 232–248, 290–299) but the operator never passes one.

Static JSDoc (`observable/combineLatest.ts` 96–98) says a source that completes without a value completes the result “at the same moment”. The initializer does not do that. The complete handler only completes when `active` reaches `0` (`observable/combineLatest.ts` 271–277). There is no `EmptyError`.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| ready \| completed \| errored \| cancelled` | `idle` | `waiting` means `remainingFirstValues > 0`. `ready` means every index has produced at least one value and the output is still open. |
| `n` | integer | length of `[source, ...others]` | `n ≥ 1`. |
| `values[i]` | latest value or empty | empty array of length `n` | Slot `i` written on `sourceNext(i, _)`. |
| `hasFirst[i]` | boolean | `false` | Local `hasFirstValue` in the per-index closure (`observable/combineLatest.ts` 253–264). |
| `remainingFirstValues` | integer | `n` | Hits `0` only when every index has had a first next. |
| `active` | integer | `n` | Decremented on each `sourceComplete(i)`. Starts at `n` because every index is subscribed immediately. |
| `project` | function or absent | popped function, if any | Applied by `map` to the array, not inside `combineLatestInit`. |

`emitting` is any transition whose output is `outNext`.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. Symbolic state is A.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | All inputs subscribed; at least one index has never emitted; no `outNext` yet. |
| `ready` | Every index has a latest value; further nexts emit. |
| `completed` | `active` hit `0` without an error. |
| `errored` | Some input or the project errored. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Subscribes every index in order. |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Source next, index 0 | `sourceNext(0, v)` | Upstream. Same handler as every other index. |
| 4 | Source error, index 0 | `sourceError(0, e)` | Default `OperatorSubscriber` error forward. |
| 5 | Source complete, index 0 | `sourceComplete(0)` | Decrements `active` only. |
| 6 | Other next | `sourceNext(i, v)` for `i ≥ 1` | Writes `values[i]`. |
| 7 | Other terminal | `sourceError(i, e)`, `sourceComplete(i)` for `i ≥ 1` | Error forwards; complete only decrements `active`. |
| 8 | Project | `projectThrow(e)` | Only if a result selector was popped. A scheduler symbol is not in this operator. |

### Γ

| Symbol | Meaning |
| --- | --- |
| `ε` | No downstream notification. |
| `sub(i)` | `from(observables[i]).subscribe` with no scheduler (`observable/combineLatest.ts` 252–254). |
| `unsub(*)` | Destination teardown unsubscribes every still-active child. |
| `outNext(arr)` | `subscriber.next(values.slice())` (`observable/combineLatest.ts` 268). Fresh array. |
| `outNext(project(...arr))` | Same array passed through `mapOneOrManyArgs`. |
| `outError(e)` | Input error, project throw, or `next`-handler throw. |
| `outComplete` | Last remaining input completed (`active` from `1` to `0`). |

## C. Transition obligations

All indices are subscribed in a synchronous loop (`observable/combineLatest.ts` 248–283) unless a synchronous error or completion stops the destination first. `maybeSchedule` without a scheduler just calls the closure.

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | no input synchronously terminates the destination | `waiting` if `remainingFirstValues > 0`, else `ready` | `sub(i)` for each `i` in order |
| T02 | waiting | `waiting` | `sourceNext(i, v)` | `hasFirst[i] = false` and this next makes `remainingFirstValues = 0` | `ready` | `values[i] := v`; `outNext(snapshot)` where `snapshot` is `values.slice()` after the write |
| T03 | waiting | `waiting` | `sourceNext(i, v)` | after the write, `remainingFirstValues > 0` | `waiting` | `ε`; `values[i] := v`; if this was the first from `i`, decrement `remainingFirstValues` and set `hasFirst[i]` |
| T04 | emitting | `ready` | `sourceNext(i, v)` | output still open | `ready` | `values[i] := v`; `outNext(snapshot)` |
| T05 | per-source complete | `waiting` or `ready` | `sourceComplete(i)` | `active > 1` before the decrement | same phase | `ε`; `active := active-1`. Phase does not become `ready`. No emission. |
| T06 | terminal | `waiting` or `ready` | `sourceComplete(i)` | `active = 1` before the decrement | `completed` | `outComplete`. If phase was `waiting`, this complete has no preceding `outNext`. |
| T07 | per-source error | `waiting` or `ready` | `sourceError(i, e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T08 | emitting | `ready` | `sourceNext(i, v)` | `project` present and project returns | `ready` | `outNext(project(...snapshot))` |
| T09 | per-source error | `ready` | `sourceNext(i, v)` | `project` throws `e` | `errored` | `outError(e)`, `unsub(*)` |
| T10 | cancel | `waiting` or `ready` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T11 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

T02 is also the emitting step for the first full tuple. A source that already has `hasFirst` stays on T03 until the global counter hits zero; only the next that drives the counter to zero emits. Later duplicates of an early source overwrite `values[i]` and are not queued.

## D. Contract invariants

1. No `outNext` while `remainingFirstValues > 0`. The first `outNext` occurs on the next that makes the counter `0`, and the array contains the latest value of every index (`observable/combineLatest.ts` 260–269).
2. After that, every `sourceNext(i, v)` produces exactly one `outNext`, including a repeat from an index that already contributed.
3. Each emitted array is a shallow copy (`values.slice()`). Later writes do not mutate arrays already emitted.
4. `sourceComplete(i)` never emits by itself and never raises `EmptyError`. It completes the output only when it is the last active input (T06).
5. If any index completes without ever taking a `sourceNext`, `remainingFirstValues` stays positive forever. Subsequent nexts from siblings take T03 (`ε`). The output completes with no `outNext` only when `active` later hits `0` (T06 from `waiting`). It does not complete at the instant of that early complete unless every other index is already inactive.
6. Any `sourceError` completes the race immediately: one error, siblings unsubscribed, no `outComplete`.
7. A completed index contributes its last value to later snapshots and cannot emit again. The output can still emit when another index nexts, as long as phase is `ready`.
8. The operator does not pass `scheduler` into `combineLatestInit`. Object-dictionary combine (static `keys` / `createObject`) is not used; the operator always builds an array whose index `0` is the upstream.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Both sides emit, then one updates

Index `0` emits `a1`. T03, no output (`remainingFirstValues = 1`). Index `1` emits `b1`. T02 `outNext([a1, b1])`, phase `ready`. Index `0` emits `a2`. T04 `outNext([a2, b1])`. Index `1` emits `b2`. T04 `outNext([a2, b2])`. Both complete: the first complete is T05; the second is T06 `outComplete`.

### E2. Early values collapse to the latest

Index `0` emits `a1` then `a2` before index `1` emits. Both are T03. `values[0]` ends as `a2`. Index `1` emits `b1`. T02 `outNext([a2, b1])`. `a1` is never in an output array.

### E3. One source completes with no value

Index `1` completes before any value. T05 if index `0` is still active: no `outComplete` yet, no `outError`, no `EmptyError`. Index `0` then emits `a1`. T03 because `remainingFirstValues` is still `1`. `ε`. Index `0` completes. T06 `outComplete`. Trace: complete, and nothing else. This is the code path, not the static JSDoc sentence that says the result completes “at the same moment” as the empty completion (`observable/combineLatest.ts` 96–98 versus 271–277).

### E4. Error before the first full tuple

Index `0` has emitted `a1` (still `waiting`). Index `1` errors `e`. T07 `outError(e)`, index `0` unsubscribed. No array is emitted.

### E5. Project

`combineLatest(other$, (a, b) => a + b)`. After both have values `2` and `3`, T08 `outNext(5)`. If the project throws, T09 `outError` and both inputs are unsubscribed. The project is not called on the partial tuples of T03.

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
- synchronous multi-source emissions in listed order: in-model
- limits: `innerFrom`/`from` interop is not expanded. The static scheduler and dictionary forms inside `combineLatest()` the creation function are not taken by this operator. A synchronous error in the middle of the subscribe loop skips later `sub(i)` because the destination is already stopped. JSDoc/code disagreement on the timing of completion when a source never emits is resolved in favor of `combineLatestInit` (D5).
