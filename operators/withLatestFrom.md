# withLatestFrom

`operators/withLatestFrom.ts` 59–110 pops an optional trailing project (`popResultSelector`). On subscribe it records `otherValues` and `hasValue` for each other input, then subscribes every other via `innerFrom` **before** subscribing the source (`withLatestFrom.ts` 77–109). The comment at 73–76 says those subscriptions are intentional side effects even if nothing can be emitted. An other `next` stores the latest value and, on that other’s first value, sets `hasValue[i]`. When every flag is true, `ready` becomes true and `hasValue` is dropped (`withLatestFrom.ts` 81–91). The source `next` emits only if `ready`, as `[sourceValue, ...otherValues]` or `project(...)` (`withLatestFrom.ts` 102–107). Source values that arrive while `ready` is false are dropped, not queued.

The other `complete` handler is `noop` (`withLatestFrom.ts` 93–96). An other completing does not complete the result and does not raise `EmptyError`. An other error uses the default `OperatorSubscriber` error path and is forwarded. Source error and source complete also use the defaults, so they terminate the output even if `ready` was never set.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| collecting \| ready \| completed \| errored \| cancelled` | `idle` | `collecting` means `ready = false`. |
| `m` | integer | `inputs.length` after the project pop | Number of others. The source is not one of them. |
| `otherValues[i]` | latest value or empty | length `m` | Slot written on every other next, including after `ready`. |
| `hasValue[i]` | boolean or released | `false` | Nulled as an array once `ready` becomes true (`withLatestFrom.ts` 90). |
| `ready` | boolean | `false` | Sticky true once every other has emitted at least once. |
| `project` | function or absent | popped | — |

If `m = 0`, the loop does not run and nothing ever assigns `ready = true`.

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. The source and the others are different alphabets. This is not a symmetric multi-source combine.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `collecting` | Source and others are subscribed; source nexts are dropped. |
| `ready` | Every other has produced one value; source nexts emit. |
| `completed` | Source completed. |
| `errored` | Source or an other (or the project) errored. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | Subscribes others in order, then the source. |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Source next | `sourceNext(v)` | Not indexed. The source is not `i = 0` of the others. |
| 4 | Source error | `sourceError(e)` | Forwarded. |
| 5 | Source complete | `sourceComplete` | Forwarded even if `ready` is false. |
| 6 | Other next | `otherNext(i, v)` | Updates latest. Does not itself emit. |
| 7 | Other terminal | `otherError(i, e)`, `otherComplete(i)` | Error forwards. Complete is `noop` plus inner teardown. |
| 8 | Project | inside the ready source-next | No scheduler. |

### Γ

`ε`, `subOther(i)`, `subSource`, `unsub(*)`, `outNext([v, ...latest])`, `outNext(project(v, ...latest))`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | `m ≥ 1` and no other synchronously errors | `collecting` | `subOther(i)` for `i = 0 .. m-1`, then `subSource` |
| T02 | waiting | `collecting` | `otherNext(i, v)` | this is the first value from `i`, and some other is still false | `collecting` | `ε`; `otherValues[i] := v`; `hasValue[i] := true` |
| T03 | waiting | `collecting` | `otherNext(i, v)` | this first value makes every `hasValue` true | `ready` | `ε`; store `v`; `ready := true`; release `hasValue` (`withLatestFrom.ts` 83–90). No `outNext`. |
| T04 | waiting | `collecting` or `ready` | `otherNext(i, v)` | `i` already had a value, or phase is already `ready` | same | `ε`; `otherValues[i] := v` |
| T05 | waiting | `collecting` | `sourceNext(v)` | `ready = false` | `collecting` | `ε`. `v` is not queued. |
| T06 | emitting | `ready` | `sourceNext(v)` | no project | `ready` | `outNext([v, ...otherValues])` using the latest slots (`withLatestFrom.ts` 103–106) |
| T07 | emitting | `ready` | `sourceNext(v)` | project returns | `ready` | `outNext(project(v, ...otherValues))` |
| T08 | per-source error | `ready` | `sourceNext(v)` | project throws `e` | `errored` | `outError(e)` |
| T09 | per-source complete | `collecting` or `ready` | `otherComplete(i)` | — | same | `ε`. Latest slot retained. `ready` unchanged (`noop`, line 96). |
| T10 | per-source error | `collecting` or `ready` | `otherError(i, e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T11 | per-source error | `collecting` or `ready` | `sourceError(e)` | — | `errored` | `outError(e)`, `unsub(*)` |
| T12 | terminal | `collecting` or `ready` | `sourceComplete` | — | `completed` | `outComplete`. Legal from `collecting` (no emission ever). |
| T13 | cancel | `collecting` or `ready` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T14 | terminal | terminal phases | any | — | same | `ε` |
| T15 | waiting | `idle` | `subscribe` | `m = 0` | `collecting` | `subSource` only. `ready` stays false. |

T03 does not emit. Only a later T06/T07 emits. Other nexts never take an emitting transition.

If `otherError` is synchronous during T01, the destination closes. Later `subOther` / `subSource` are added to a closed destination and are torn down immediately (`Subscription.add`, `Subscription.ts` 120–123). Those extra attempts are not separate outputs.

## D. Contract invariants

1. `outNext` happens only on a source next, and only after every other has emitted at least one value (JSDoc `withLatestFrom.ts` 26–30).
2. Source nexts before that condition are discarded. They are not replayed once `ready` flips.
3. Each other slot keeps a single latest value. Two `otherNext`s from the same `i` without a source next between them leave only the second value.
4. `otherComplete(i)` does not complete the output, does not error, and does not clear the slot. If `i` completes without a value, `ready` stays false unless every other (including `i`) has already emitted. There is no `EmptyError`.
5. `otherError(i, e)` is `outError(e)`. It is not ignored.
6. `sourceComplete` is `outComplete` whether or not any `outNext` happened. `sourceError` is `outError`.
7. The array form is `[sourceValue, other0, other1, ...]`. The project receives those as separate arguments.
8. `m = 0` never becomes `ready` (`withLatestFrom.ts` 69–71 and 77). Every source value is dropped. Source terminal notifications still pass.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Click with a timer (JSDoc shape)

Source is clicks, the other is a timer. A click before the timer’s first tick is T05: no output. The timer’s first tick is T03 (or T02 if more others exist): still no output. The next click is T06 `outNext([click, latestTick])`. A later tick updates the slot (T04) and does not emit. The following click emits the new pair.

### E2. Several early source values

Other has not emitted. Source emits `a` then `b`. Both T05. Other emits `1` (T03, `ε`). Source emits `c`. T06 `outNext([c, 1])`. `a` and `b` never appear.

### E3. Other completes after a value

Other emits `1` then completes. T03 then T09. Phase stays `ready` if that was the only other. Source later emits `a` then completes. Trace: `outNext([a, 1])`, `outComplete`. The other’s completion produced nothing.

### E4. Other completes with no value, then the source completes

T09 leaves `collecting`. Source emits `a` (T05, dropped) and completes (T12). Trace: `complete`. No `EmptyError`, no `outNext`.

### E5. Other errors

Source has not emitted. Other errors `e`. T10 `outError(e)`, source unsubscribed. No `outNext`.

### E6. Project and a second other

Others emit `1` and `'x'` (the second of those nexts is T03). Source emits `9`. Project `(s, a, b) => s + a` yields T07 `outNext(10)`. `'x'` is passed into the project and ignored by this function. If the project throws, T08.

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
- limits: `m = 0` never emits (D8); the type overloads always show at least the other-tuple, but the runtime allows an empty rest. Synchronous `otherError` during the subscribe loop can still construct later subscriptions onto an already closed destination; they are torn down and are not given outputs. `innerFrom` interop is not expanded. No `EmptyError` exists on this path.
