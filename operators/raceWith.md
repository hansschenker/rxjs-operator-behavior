# raceWith

`raceWith(...otherSources)` returns `identity` when `otherSources.length` is `0`. Otherwise it `operate`s `raceInit([source, ...otherSources])` (`operators/raceWith.ts` 32–39). `raceInit` (`observable/race.ts` 62–88) subscribes to each input while `subscriptions` is still a live array and the subscriber is open. On the first `next`, it unsubscribes every other subscription already stored, nulls that array, and forwards the value. Further nexts from the winner are forwarded. `createOperatorSubscriber` is called with only a `next` handler, so error and complete use `Subscriber`’s defaults (`OperatorSubscriber.ts` 76–101, `Subscriber.ts` 116–129) and close the destination, which unsubscribes the other children. JSDoc (`raceWith.ts` 7–9) names the winning notification as the first next, error, or complete. That matches the code. It does not match a reading where complete is ignored until every racer completes.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| racing \| mirroring \| completed \| errored \| cancelled` | `idle` | — |
| `n` | integer | `1 + otherSources.length` | `n = 1` selects the identity machine. |
| `winner` | index or empty | empty | Set only by a winning next. |
| `armed` | boolean | `true` while `n ≥ 2` and no notification has won | Mirrors `subscriptions !== null`. |
| `subscribedThrough` | integer | `0` | How far the subscribe loop got. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `racing` | `n ≥ 2`, no notification yet. |
| `mirroring` | Either `n = 1` (identity) or a next-winner is the only remaining subscription. |
| `completed` | Terminal complete. |
| `errored` | Terminal error. |
| `cancelled` | Downstream unsubscribed before terminal. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Upstream next | `sourceNext(0, v)` | — |
| 4 | Upstream error | `sourceError(0, e)` | — |
| 5 | Upstream complete | `sourceComplete(0)` | — |
| 6 | Other next | `sourceNext(i, v)`, `i ≥ 1` | Absent when `n = 1`. |
| 7 | Other terminal | `sourceError(i, e)`, `sourceComplete(i)`, `i ≥ 1` | Absent when `n = 1`. |
| 8 | Scheduler / project | — | None. |

### Γ

`ε`, `sub(i)`, `unsub(losers)`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`.

## C. Transition obligations

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | `n ≥ 2` | `racing` | `sub(i)` in order `0 .. n-1` until a sync notification closes the subscriber or nulls `armed` |
| T02 | emitting | `racing` | `sourceNext(i, v)` | `armed` | `mirroring` | `unsub` every subscribed `j ≠ i`; `armed := false`; `winner := i`; `outNext(v)` |
| T03 | emitting | `mirroring` | `sourceNext(winner, v)` | `n ≥ 2` | `mirroring` | `outNext(v)` |
| T04 | per-source error | `racing` | `sourceError(i, e)` | `armed` | `errored` | `outError(e)`, `unsub(*)` |
| T05 | per-source complete | `racing` | `sourceComplete(i)` | `armed` | `completed` | `outComplete`, `unsub(*)` |
| T06 | per-source error | `mirroring` | `sourceError(winner, e)` | — | `errored` | `outError(e)` |
| T07 | terminal | `mirroring` | `sourceComplete(winner)` | `n ≥ 2` | `completed` | `outComplete` |
| T08 | cancel | `racing` or `mirroring` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T09 | terminal | terminal phases | any | — | same | `ε` |
| T10 | init | `idle` | `subscribe` | `n = 1` | `mirroring` | identity: subscribe upstream only (`util/identity.ts` 43–45) |
| T11 | emitting | `mirroring` | `sourceNext(0, v)` | `n = 1` | `mirroring` | `outNext(v)` |
| T12 | terminal | `mirroring` | `sourceError(0, e)` or `sourceComplete(0)` | `n = 1` | `errored` or `completed` | the same notification |

The subscribe loop and the winning `next` both consult the live subscription list (`observable/race.ts` 66–84). A synchronous winner prevents `sub` of later indices. Complete and error do not null that list themselves; they close the subscriber, and the loop condition `!subscriber.closed` stops further `sub`.

## D. Contract invariants

1. With `n ≥ 2`, the output mirrors exactly one input: the input that produces the first notification in subscription order.
2. A winning next unsubscribes the other already-subscribed racers before the value is forwarded, so those racers’ handlers do not run as part of that `outNext`.
3. A winning error or complete is forwarded by the default subscriber path and tears down siblings as destination children. There is no separate “ignore completes until all racers complete” counter.
4. If every racer’s first signal is `complete`, the output is `outComplete` and nothing else (T05 on whichever complete is first). That is the observable content of “all completed with no next”.
5. If every racer’s first signal is an error, the first error is the output error (T04).
6. After a next-win, the winner’s subsequent error and complete are ordinary mirror terminals (T06, T07).
7. `raceWith()` does not allocate `raceInit` and does not change notifications.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Other wins on next

`slow$.pipe(raceWith(fast$))`. Both subscribed (T01). `fast$` emits `'fast'` first. T02 unsubscribes `slow$`, `outNext('fast')`. Further `fast$` values are T03 until `fast$` completes (T07). `slow$` emits nothing downstream.

### E2. Upstream wins on next

Upstream emits `0` synchronously, other has not emitted. If the sync next happens inside `sub(0)` before `sub(1)`, T02 sets `winner = 0` and the loop stops, so the other is never subscribed (`observable/race.ts` 70, `subscriptions` already null). Trace starts with `outNext(0)` and continues as a mirror of the upstream.

### E3. Error wins

Neither has nexted. Other errors `e`. T04 `outError(e)`, upstream unsubscribed. A later upstream next is not observed.

### E4. Complete with no next wins

Other completes while upstream is open and silent. T05 `outComplete`. Upstream is unsubscribed. Trace: `complete`. No error object.

### E5. Identity

`src.pipe(raceWith())`. T10–T12. `src` emits `1` then errors `e`. Trace: `outNext(1), outError(e)`. No extra complete.

## F. Coverage and evidence

Not executed.

Denominator = 12 (T01–T12). Tests run: 0. Numerator = 0.

## G. Review decision

- decision: accept with documented limits
- reviewer: source-derived analysis (Grok)
- date: 2026-10-21
- pin: RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- mutations: none performed
- tests: not executed
- ordinary downstream reentrancy: excluded
- synchronous multi-source emissions in listed order: in-model
- limits: A loser that still delivered a notification after `unsubscribe` returned is excluded; the `next` handler would forward it because it does not test `winner`. `innerFrom` kinds are not expanded. Deprecated `race` is a thin wrapper and is specified in `race.md`.
