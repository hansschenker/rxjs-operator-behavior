# combineLatestWith

`combineLatestWith(...otherSources)` returns `combineLatest(...otherSources)` (`operators/combineLatestWith.ts` 44–48). That is the deprecated operator, which calls `combineLatestInit([source, ...argsOrArgArray(otherSources)])` with no scheduler and no project (`operators/combineLatest.ts` 27–33, `observable/combineLatest.ts` 225–288). The output element is an array `[upstream, ...others]` of latest values. JSDoc (`combineLatestWith.ts` 8–11) states the emission rule correctly: nothing until every source has emitted once, then an array on every later next. It does not mention the no-value completion case. The initializer never throws `EmptyError`. A source that completes without a value does not by itself complete the result unless it was the last active source; see D4. The static JSDoc sentence “complete at the same moment” (`observable/combineLatest.ts` 96–98) is not what `combineLatestInit` does (`271–277`).

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| ready \| completed \| errored \| cancelled` | `idle` | `waiting`: some index has never emitted. `ready`: all have. |
| `n` | integer ≥ 1 | `1 + otherSources.length` | Index `0` is the upstream. `combineLatestWith()` with no arguments is a 1-slot combine. |
| `values[i]` | latest or empty | length `n` | — |
| `hasFirst[i]` | boolean | `false` | — |
| `remainingFirstValues` | integer | `n` | — |
| `active` | integer | `n` | Decremented only on complete. |

No project and no scheduler in this signature. A trailing function would be popped as a project by the callee `combineLatest`; that is outside the typed `combineLatestWith` contract and outside this model.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | Subscribed to every index; suppressing emissions. |
| `ready` | Emitting a fresh array on each next. |
| `completed` | Last active input completed. |
| `errored` | An input errored. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Upstream next | `sourceNext(0, v)` | — |
| 4 | Upstream error | `sourceError(0, e)` | — |
| 5 | Upstream complete | `sourceComplete(0)` | — |
| 6 | Other next | `sourceNext(i, v)`, `i ≥ 1` | — |
| 7 | Other terminal | `sourceError(i, e)`, `sourceComplete(i)`, `i ≥ 1` | — |
| 8 | Scheduler / project | — | Not used. `combineLatestInit`’s scheduler parameter is omitted by the operator. |

### Γ

`ε`, `sub(i)` for every index, `unsub(*)`, `outNext(values.slice())`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `waiting` if `n > 0` and not every source has already sync-emitted, else `ready` | `sub(i)` in index order (`observable/combineLatest.ts` 248–283) |
| T02 | waiting | `waiting` | `sourceNext(i, v)` | this is the first next from `i`, and some other index still has no value | `waiting` | `ε`; store `v`; `remainingFirstValues--` |
| T03 | emitting | `waiting` | `sourceNext(i, v)` | this next sets `remainingFirstValues` to `0` | `ready` | store `v`; `outNext(values.slice())` |
| T04 | emitting | `ready` | `sourceNext(i, v)` | — | `ready` | store `v`; `outNext(values.slice())` |
| T05 | per-source complete | `waiting` or `ready` | `sourceComplete(i)` | `active > 1` | same | `ε`; `active--` |
| T06 | terminal | `waiting` or `ready` | `sourceComplete(i)` | `active = 1` | `completed` | `outComplete` |
| T07 | per-source error | `waiting` or `ready` | `sourceError(i, e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T08 | cancel | `waiting` or `ready` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T09 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

If `n = 1`, the upstream’s first `sourceNext(0, v)` is T03, and the output is `outNext([v])` on every upstream next until T06.

## D. Contract invariants

1. `outNext` arrays have length `n`. Position `0` is always the upstream’s latest value (JSDoc `combineLatestWith.ts` 41–42).
2. No emission before every index has produced one next. Extra early nexts from a fast index keep only the latest.
3. After `ready`, every next from any still-active index emits. A completed index is sticky: its last value remains in the snapshot.
4. Completion-without-a-value does not raise `EmptyError`. It blocks `ready` permanently. The result completes without `outNext` only when every index has completed (`active = 0`), not necessarily on the empty index’s own complete if siblings are still active. Code wins over `observable/combineLatest.ts` 96–98.
5. The first error is the output error and unsubscribes the other indices. No later `outNext` or `outComplete`.
6. Snapshots are copies. Project functions are not applied by `combineLatestWith` itself.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Two inputs become ready on the second

Upstream emits `'L'`. No output (T02). Other emits `'R'`. T03 `outNext(['L', 'R'])`. Other emits `'R2'`. T04 `outNext(['L', 'R2'])`.

### E2. Upstream completes last, both had values

After `outNext(['L', 'R'])`, the other completes (T05, no output). Upstream emits `'L2'` (T04 `outNext(['L2', 'R'])`) then completes (T06 `outComplete`). The completed other’s value is reused.

### E3. Other completes with no value

Other completes immediately. Upstream is still active. T05, phase stays `waiting`. Upstream emits `'L'` (T02, `ε`) and later completes (T06). Trace: `complete` only. No `EmptyError`.

### E4. Other errors after one partial value

Upstream emitted `'L'` (still waiting). Other errors `e`. T07. Trace: `error e`. `'L'` is not emitted.

### E5. Single-argument absence

`source.pipe(combineLatestWith())`. `n = 1`. First upstream value `v` yields `outNext([v])` (T03). Each later upstream value yields a one-element array (T04). Upstream complete is T06. No second subscription.

## F. Coverage and evidence

Not executed.

Denominator = 9 (T01–T09). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: Trailing project functions are honored by the callee `combineLatest` via `popResultSelector` but are not part of this operator’s documented signature, so they are excluded. Scheduler support inside `combineLatestInit` is not reachable from this call. `innerFrom` interop is not expanded. Parent detail: `combineLatest.md`.
