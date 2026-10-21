# `reduce`

`reduce` folds the source with `accumulator` and emits a single result when the source completes. It does not emit on source `next`. With a seed, including an explicit `undefined` seed, that seed is the initial state and is emitted on complete if the source was empty. Without a seed, the first source value becomes the state and is not a separate emission; `accumulator` runs only from the second value, and the index of that first call is `1`. If the source completes with no value and no seed, the destination completes and nothing is emitted: this 7.8.2 implementation does not raise `EmptyError`. A source error or an `accumulator` throw forwards an error and does not emit a partial aggregate. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Implementation: `operate(scanInternals(accumulator, seed, arguments.length >= 2, false, true))` (`src/internal/operators/reduce.ts` lines 59–61). Not deprecated. `emitOnNext` is false and `emitBeforeComplete` is true.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `reduce(accumulator)` and `reduce(accumulator, seed)` (lines 5–7 and 59–61). |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. `hasSeed = arguments.length >= 2` is captured at the call to `reduce` (line 60), for the same `undefined` reason as `scan` (`scan.ts` lines 89–93). |
| Model kind | Symbolic. Specialization of `scanInternals` with flush-on-complete and no per-value emission. |
| Parameter domain | Synchronous `accumulator`. Seed optional. Presence of the argument, not a nullish check, selects the seed. |
| Payload/error domain | Symbolic state and errors. |
| Subscription boundary | One `scanInternals` state triple per subscription. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | `accumulator` is skipped for the seed-installing first value when `hasSeed` is false. Throws become `destination.error` via `OperatorSubscriber._next` (`OperatorSubscriber.ts` lines 67–74). |
| Cleanup assumptions | The complete path is the custom handler in `scanInternals.ts` lines 54–58: `hasState && subscriber.next(state); subscriber.complete()`. That handler’s `finally` unsubscribes. |
| Explicit exclusions | Ordinary model, no reentrancy. Terminal late events are silent by convention. `EmptyError` is not produced by this operator in this version; `src/internal/util/EmptyError.ts` is not referenced from `reduce.ts` or `scanInternals.ts`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator created. | `accumulator`, `hasSeed`, `seed` | the call | `subscribe` emits nothing |
| `active(hasState, state, index)` | Folding, nothing emitted yet. | triple | `subscribe` plus zero or more source values | complete either flushes one `next` or completes empty |
| `completed` | Completed, with or without a prior flush `next`. | none | source `complete` | silence |
| `errored(e)` | Failed. | `e` | source error or accumulator throw | the aggregate was not emitted |
| `cancelled` | Unsubscribed before complete. | none | `cancel` | the aggregate is dropped |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `operate` / `scanInternals`. No emission. |
| Source next | yes | Updates state only (`emitOnNext` false). |
| Source error | yes | Forwarded, no flush. |
| Source completion | yes | Flush iff `hasState`, then `complete`. |
| Cancellation `cancel` | yes | Drops state. No `complete`. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | yes | `accumulator` returns or throws after state exists. It is not invoked while `hasState` is false. |

### Γ

```text
record {
  trace: ordered list of next(state) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Source `next`, source `error`, and cancel emit at most one notification. Source `complete` when `hasState` is true emits the ordered pair `next(state)` then `complete` (`scanInternals.ts` lines 56–57). An unordered record is not enough for that input.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)`; `hasState = hasSeed`; `state = seed`; `index = 0` | `active(hasSeed, seed, 0)` | `reduce(...)` | an immediate complete distinguishes seed from no seed | S01, S02 |
| T02 | `active(false, _, 0)` | source `next(v)` | no seed argument | none | `accumulator` not called | `active(true, v, 1)` | T01 with `arguments.length < 2` | a second value calls `accumulator(_, _, 1)` | S03 |
| T03 | `active(true, s, i)` | source `next(v)` | `accumulator(s, v, i)` returns `a` | none | stay subscribed | `active(true, a, i+1)` | seed already present, or after T02 | complete emits `a` once | S03, S04 |
| T04 | `active(true, s, i)` | source `next(v)` | `accumulator` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | `hasState` already true | silence | S05 |
| T05 | `active(_, _, _)` | source `error(e)` | any | `error(e)`; no flush | unsubscribe | `errored(e)` | T01, optional updates | silence | S06 |
| T06 | `active(true, s, _)` | source `complete` | seed was provided, or at least one value was seen | ordered `next(s)`, `complete` | custom complete unsubscribes | `completed` | T01 with seed, or T02/T03 | silence | S01, S03, S04 |
| T07 | `active(false, _, 0)` | source `complete` | no seed and no value | `complete` only. Not `error`, not `EmptyError`. | custom complete unsubscribes | `completed` | T01 with `hasSeed` false | silence | S02 |
| T08 | `active` | `cancel` | open | none | unsubscribe; state dropped | `cancelled` | T01, optional updates | no flush | S07 |
| T09 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S05 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Values are folded in source order. One data `next` at most, and only on complete (T06). Index rules are those of `scanInternals`. |
| one terminal | yes | T04, T05, T06, T07. The `next` in T06 is not a second terminal. |
| silence after terminal | yes | T09. |
| cancel does not complete | yes | T08. |
| upstream/inner lifetime | yes | One source subscription from T01 until terminal or cancel. No inners. |
| cleanup once | yes | Custom complete `finally` plus idempotent unsubscribe. |
| per-subscription state | yes | Locals in `scanInternals.ts` lines 25–31. |
| empty/error/silence | yes | Empty with seed: T06 emits the seed (S01). Empty without seed: T07 completes with no value and no `EmptyError` (S02). Source error: T05, no aggregate. Never-completing source: silence in `active` (no emission). |
| pending buffer on terminal | yes | `state` is pending whenever `hasState` is true. T06 emits it. T05 and T08 drop it. T07 has nothing pending. |
| callback throw/reenter/cancel | yes | T04. Unreachable on the first value when there is no seed (T02 does not call `accumulator`). Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty source emits the seed

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T06 |
| Starting state | `idle` |
| Reset/fixture | `reduce(acc, seed)` and `seed` may be `undefined`; empty source |
| State-reaching prefix | call `reduce` with two arguments |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `next(seed)`, `complete` |
| Expected lifecycle observations | `acc` not called; unsubscribed after complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered flush of the seed, including `undefined` |
| Oracle source | `source characterization` |

### S02 Empty source without seed completes

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T01, T07 |
| Starting state | `idle` |
| Reset/fixture | `reduce(acc)`, empty source |
| State-reaching prefix | call `reduce` with one argument |
| Target event | `subscribe` and source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | `acc` not called; no `EmptyError` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `complete` rather than `error` |
| Oracle source | `source characterization` |

### S03 No seed, first value is not a separate emission

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T02, T03, T06 |
| Starting state | `active(false, _, 0)` |
| Reset/fixture | `reduce((s, v, i) => [s, v, i])`, values `v` then `w`, then complete |
| State-reaching prefix | `subscribe` |
| Target event | both nexts and complete |
| Expected notifications | `next([v, w, 1])`, `complete`. No `next` before complete. |
| Expected lifecycle observations | `accumulator` called once |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | single emission and index 1 |
| Oracle source | `source characterization` |

### S04 Seed and several values, one emission

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T03, T06 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | `reduce((s, v, i) => ({s, v, i}), seed)`, values `a` then `b`, then complete |
| State-reaching prefix | `subscribe` |
| Target event | two nexts and complete |
| Expected notifications | one `next` of the nested fold, then `complete`. The inner index of the first step is 0. |
| Expected lifecycle observations | no `next` until complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | emission count is 1 |
| Oracle source | `contract` |

### S05 Accumulator throw

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T04, T09 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | `accumulator` throws `e` |
| State-reaching prefix | `subscribe` of a seeded `reduce` |
| Target event | first source `next` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed; no aggregate `next` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error, not a partial next |
| Oracle source | `source characterization` |

### S06 Source error

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T05 |
| Starting state | `active(true, s, i)` |
| Reset/fixture | at least the seed, then source `error(e)` |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | unsubscribed without a data `next` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | no flush |
| Oracle source | `contract` |

### S07 Cancel drops the aggregate

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T08 |
| Starting state | `active(true, s, i)` |
| Reset/fixture | seeded, one value already folded, source not complete |
| State-reaching prefix | `subscribe` and one next |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no late `next` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 9 section C rows (T01–T09).

Section E references every row. Specified coverage = 9/9.

Execution: not executed.

Evidence: `src/internal/operators/reduce.ts` lines 59–61 and `src/internal/operators/scanInternals.ts` lines 37–58. No `EmptyError` import exists in either file. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `reduce` is the flush-on-complete specialization of `scanInternals`. The empty-without-seed path is the `hasState && subscriber.next(state)` short-circuit, which completes either way.

Known limitations: public prose that still says `reduce` is `scan` followed by `last` (`reduce.ts` lines 24–25) is not accurate for the empty-without-seed case, because `last` raises `EmptyError` and this operator does not. Reentrancy is excluded. `arguments.length` must be observed at the `reduce` call itself.

Contract vs version characterization: “one value, only when the source completes” matches the JSDoc for sources that do produce a state. “Empty without seed completes silently” and “empty with seed emits the seed” are source characterization of 7.8.2, including the absence of `EmptyError`.

Tests still required: S01–S07, especially S01 with seed `undefined` and S02 as a negative `EmptyError` test.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
