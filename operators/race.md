# race

Deprecated operator (JSDoc `operators/race.ts` 5–17: replaced by `raceWith`, removed in v8). The body is `raceWith(...argsOrArgArray(args))` (`operators/race.ts` 18–20, `util/argsOrArgArray.ts` 7–9). A single array argument is unwrapped; otherwise the arguments are the other sources. All winning rules are `raceWith`’s: zero others yields `identity` (`operators/raceWith.ts` 35–36); otherwise `raceInit([source, ...otherSources])` (`operators/raceWith.ts` 37–39, `observable/race.ts` 62–88). This file does not add a scheduler or a project.

`raceInit` subscribes in index order and stops the loop when `subscriptions` has been nulled or the subscriber is closed. The `next` handler, if still racing, unsubscribes every other already-created subscription and then forwards the value. Error and complete are not given custom handlers, so `OperatorSubscriber`’s defaults forward them to the destination (`OperatorSubscriber.ts` 76–101, `Subscriber.ts` 112–129), which unsubscribes sibling children. The first next, the first error, or the first complete therefore wins. It is not “wait until every source completes”.

## A. Identity, contract, and scope

| Field | Domain | Initial | Role |
| --- | --- | --- | --- |
| `phase` | `idle \| racing \| mirroring \| completed \| errored \| cancelled` | `idle` | `mirroring` means a winner index has been chosen by a next and is still open. |
| `inputs` | `ObservableInput[]` | `[source, ...unwrapped others]` | Index `0` is the upstream. If there are no others, there is no race state; the operator is `identity`. |
| `winner` | index or empty | empty | Set when the first next wins. Error/complete winners go straight to a terminal phase and need no winner slot. |
| `subscriptions` | array or `null` | `[]` while racing | Nulled by the winning `next` (`observable/race.ts` 74–81). |
| `nextToSub` | integer | `0` | Loop index. Sources at or past this index are unsubscribed-from by never having been subscribed when the race ends synchronously. |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`, `s₀ = idle`. For the zero-other case the machine is the identity mirror in T10–T12 and the fields above are unused.

### S

| Location | Meaning |
| --- | --- |
| `idle` | Not subscribed. |
| `racing` | More than one input may still be subscribed. No next has won. |
| `mirroring` | One winner is subscribed. The others have been unsubscribed or were never subscribed. |
| `completed` | Winner completed, or the first notification was a complete. |
| `errored` | Winner errored, or the first notification was an error. |
| `cancelled` | Downstream unsubscribed. |

### Σ (eight categories)

| # | Category | Symbols | In this operator |
| --- | --- | --- | --- |
| 1 | Downstream subscribe | `subscribe` | — |
| 2 | Downstream cancel | `unsubscribe` | — |
| 3 | Upstream next | `sourceNext(0, v)` | Can win or, after a loss, is not delivered. |
| 4 | Upstream error | `sourceError(0, e)` | Wins if still `racing`. |
| 5 | Upstream complete | `sourceComplete(0)` | Wins if still `racing`. |
| 6 | Other next | `sourceNext(i, v)`, `i ≥ 1` | Same win rule. |
| 7 | Other terminal | `sourceError(i, e)`, `sourceComplete(i)`, `i ≥ 1` | Same win rule. |
| 8 | Scheduler / project | — | None. `identity` (no others) has no extra symbol. |

### Γ

`ε`, `sub(i)`, `unsub(j)` for each loser `j`, `unsub(*)`, `outNext(v)`, `outError(e)`, `outComplete`.

## C. Transition obligations

`subscriptions` in the source is the list of inner subscriptions already pushed. The closure compares `s !== i` using the loop index captured for that source (`observable/race.ts` 70–84).

| ID | Phase | From | Input | Guard | To | Output |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | init | `idle` | `subscribe` | `inputs.length ≥ 2` | `racing` | `sub(i)` for each `i` reached before a sync win or a closed subscriber (`observable/race.ts` 70) |
| T02 | emitting | `racing` | `sourceNext(i, v)` | still racing | `mirroring` | `unsub(j)` for every subscribed `j ≠ i`; `subscriptions := null`; `winner := i`; `outNext(v)` |
| T03 | emitting | `mirroring` | `sourceNext(winner, v)` | — | `mirroring` | `outNext(v)`. The `subscriptions` null check skips a second unsubscribe (`observable/race.ts` 74). |
| T04 | per-source error | `racing` | `sourceError(i, e)` | still racing | `errored` | `outError(e)`, `unsub(*)` via destination teardown. Later indices in the sync loop are not subscribed. |
| T05 | per-source complete | `racing` | `sourceComplete(i)` | still racing; this complete is the first notification from any input | `completed` | `outComplete`, `unsub(*)`. No `outNext`. |
| T06 | per-source error | `mirroring` | `sourceError(winner, e)` | — | `errored` | `outError(e)` |
| T07 | terminal | `mirroring` | `sourceComplete(winner)` | — | `completed` | `outComplete` |
| T08 | cancel | `racing` or `mirroring` | `unsubscribe` | — | `cancelled` | `unsub(*)` |
| T09 | terminal | `completed`, `errored`, `cancelled` | any | — | same | `ε` |
| T10 | init | `idle` | `subscribe` | no other sources (`identity`) | `mirroring` | `sub(0)` only, as a plain lift of the source |
| T11 | emitting | `mirroring` | `sourceNext(0, v)` | identity case | `mirroring` | `outNext(v)` |
| T12 | terminal | `mirroring` | `sourceError(0, e)` or `sourceComplete(0)` | identity case | `errored` or `completed` | `outError(e)` or `outComplete` |

T05 is the “everyone would have completed” situation reduced to one winner: the first complete ends the race. Outputs that only complete are observationally the same as “all completed with no next”, but losers are not observed.

A next that wins unsubscribes losers before `subscriber.next` (`observable/race.ts` 77–83), so a synchronous loser notification during unsubscribe is not given its own row; unsubscribe is assumed to stop that source. A next that arrived without unsubscribe having taken effect would still be forwarded, because the handler does not re-check the winner. That failure mode is excluded.

## D. Contract invariants

1. At most one index is mirrored after the first notification of any kind.
2. The winner of a next is the least index that emits `sourceNext` in subscription/emission order, not a priority among sources.
3. An error that happens while `racing` beats every not-yet-emitted next, including a source that “would have won” later (`observable/race.ts` 22–24, and the default error forward used by `raceInit`).
4. A complete while `racing` completes the output with no value and drops the other racers. The implementation does not wait for the remaining sources.
5. After T02, only the winner’s later next, error, and complete are outputs.
6. `race()` and `race([])` go through `raceWith()` and are `identity` on the upstream. They do not complete immediately.
7. `race([a$, b$])` and `race(a$, b$)` are the same other-source list because of `argsOrArgArray`.

## E. Scenario specification

Source characterization only. Not executed.

### E1. Faster other emits first

Upstream is slow. Other index `1` emits `fast` first. T01 subscribed both. T02 unsubscribes `0`, `outNext(fast)`. Later values from `1` are T03. A later upstream value is not subscribed anymore. Matches the `raceWith` JSDoc example’s “first to emit” rule (`operators/raceWith.ts` 7–9), which this operator delegates to.

### E2. Error before any next

Index `0` errors `e` synchronously before index `1` is subscribed. T04: `outError(e)`. The loop condition `!subscriber.closed` fails (`observable/race.ts` 70), so index `1` is not subscribed. No `outNext`.

### E3. First notification is a complete

Index `1` completes with no value while index `0` is still silent and already subscribed. T05: `outComplete`, index `0` unsubscribed. Index `0` does not get to emit later. Trace: `complete`.

### E4. All would complete with no value

Every input’s first notification is `complete`. The one that is delivered first (lowest index if they are synchronous, because the loop subscribes in order and a sync complete closes the subscriber) takes T05. The output completes and the rest are not left running. No `EmptyError`, no `outNext`.

### E5. No other sources

`source.pipe(race())` is `identity` (T10). Upstream `1`, then `2`, then complete. Trace: `outNext(1), outNext(2), outComplete`. No second subscription.

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
- limits: Loser notifications after a successful synchronous `unsubscribe` are excluded. `innerFrom` interop is not expanded. Static `race` of a single source returns `innerFrom` of that source (`observable/race.ts` 51–54); this operator always goes through `raceWith`, so a single other source still uses `raceInit` on a two-element list. Detail shared with `raceWith.md`.
