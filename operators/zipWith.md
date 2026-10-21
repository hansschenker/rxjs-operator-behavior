# zipWith

`zipWith(...otherInputs)` returns `zip(...otherInputs)` (`operators/zipWith.ts` 27–29). That is the deprecated operator, which subscribes `zipStatic(source, ...otherInputs)` (`operators/zip.ts` 22–25, `observable/zip.ts` 53–117). The documented `zipWith` signature has no project and no scheduler. Pairing, completion, and dropped leftovers are entirely static `zip`: one FIFO per index, emit one index-aligned tuple when every FIFO is non-empty, complete when some index is completed and its FIFO is empty so no further pair exists. JSDoc (`zipWith.ts` 5–14) matches that rule, including the sentence that the result completes once it can no longer combine the same index.

A trailing function argument is still removed by static `zip`’s `popResultSelector`. That runtime path is not part of the `zipWith` contract. This model emits arrays only. The project path is recorded as a limit and specified on `zip.md`.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| waiting \| completed \| errored \| cancelled` | `idle` | — |
| `n` | integer ≥ 1 | `1 + otherInputs.length` | Index `0` is the upstream. |
| `buffers[i]` | FIFO of values | empty | `observable/zip.ts` 62. |
| `completed[i]` | boolean | `false` | `observable/zip.ts` 67. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `waiting` | Subscribed; pairing. |
| `completed` | No further pair is possible. |
| `errored` | An input errored. |
| `cancelled` | Downstream unsubscribed; buffers released. |

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
| 8 | Scheduler / project | — | No scheduler. Project excluded from this contract. |

### Γ

`ε`, `sub(i)`, `unsub(*)`, `outNext([v0, v1, ...])`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | — | `waiting` | `sub(i)` for each index until the subscriber closes |
| T02 | waiting | `waiting` | `sourceNext(i, v)` | some buffer remains empty after the push | `waiting` | `ε`; append `v` to `buffers[i]` |
| T03 | emitting | `waiting` | `sourceNext(i, v)` | every buffer non-empty after the push, and after one shift no empty buffer belongs to a completed index | `waiting` | `outNext` of the shifted heads in index order |
| T04 | terminal | `waiting` | `sourceNext(i, v)` | the shift of T03 leaves some `buffers[k]` empty and `completed[k]` | `completed` | that `outNext`, then `outComplete` |
| T05 | per-source complete | `waiting` | `sourceComplete(i)` | `buffers[i]` empty | `completed` | `outComplete`; other buffers dropped, not emitted |
| T06 | per-source complete | `waiting` | `sourceComplete(i)` | `buffers[i]` non-empty | `waiting` | `ε`; `completed[i] := true` |
| T07 | per-source error | `waiting` | `sourceError(i, e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T08 | cancel | `waiting` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T09 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |

The `k`-th successful T03/T04 consumes the `k`-th value of every index. It does not wait for clocks and it does not use “latest”.

## D. Contract invariants

1. Output tuples are index-aligned. The upstream is always component `0` (JSDoc `zipWith.ts` 7–9, 22–25).
2. A value is emitted at most once. It leaves its FIFO on the shift and is not reused the way `combineLatest` reuses a latest value.
3. When one source completes and its FIFO cannot supply another pair, the output completes. Longer sources’ leftovers are dropped (JSDoc `zipWith.ts` 13–14; `observable/zip.ts` 90–105).
4. A source that completes with a non-empty FIFO does not complete the output yet. Those stored values remain eligible.
5. Any input error fails the output and unsubscribes the others. No partial tuple is emitted for the failed attempt.
6. Memory can grow without bound if one index emits many values before another emits the matching index (JSDoc `zipWith.ts` 16–18). The model does not cap the FIFOs.
7. `zipWith()` with no others still wraps each upstream value as a one-element array, because static `zip` is not `EMPTY` when the upstream is passed.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Classic pair

Upstream `10`, then `20`. Other `'x'`, then `'y'`. If both of the upstream values arrive first, they sit in `buffers[0]`. `'x'` triggers T03 `outNext([10, 'x'])`. `'y'` triggers T03 `outNext([20, 'y'])`. The next complete on an empty buffer is T05 `outComplete`.

### E2. Leftover dropped

Upstream emits `1, 2, 3` then completes (T06 while its buffer still holds the unpaired tail, or T02/T03 mixed with the other). Other emits only `a` then completes. The only pair is `outNext([1, a])`. Other’s complete sees an empty buffer: T05. `2` and `3` are not emitted.

### E3. Other completes immediately

Other completes with no value during T01. T05 `outComplete`. If the upstream already pushed synchronous values, they are dropped with the buffers. Trace: `complete`.

### E4. Error after one pair

One pair `[1, 'a']` has been emitted. Upstream then errors `e` while the other is still active. T07 `outError(e)`, other unsubscribed. No second tuple and no `outComplete`.

### E5. Uneven arrival that still pairs

Other emits `'a'` then `'b'` first (both buffered, T02). Upstream emits `1`. T03 `outNext([1, 'a'])`, `buffers[1]` still holds `'b'`. Upstream emits `2`. T03 `outNext([2, 'b'])`. No values lost, because each index had a partner. This is the difference from E2.

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
- limits: A trailing function is a static-`zip` project at runtime and is specified only in `zip.md`. `innerFrom` interop is not expanded. Buffer growth is unbounded.
