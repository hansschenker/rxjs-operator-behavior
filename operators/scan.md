# `scan`

`scan` emits the current accumulation on every source value. Without a seed, the first source value is that state and is emitted as `next` without calling `accumulator`; later values are `accumulator(state, value, index)` and are also emitted. With a seed, including an explicit `undefined` seed, the seed is not emitted at subscribe and is not emitted at all if the source completes without a value; the first source value is passed through `accumulator` together with the seed and that result is emitted. An empty source completes with no `next` in both cases. A throw from `accumulator` is a destination error and does not emit a partial result. Source errors are forwarded and do not emit the current state. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. This operator is the full public wrapper around the internal helper: `operate(scanInternals(accumulator, seed, arguments.length >= 2, true))` (`src/internal/operators/scan.ts` lines 88–95). It is not deprecated. The fifth `scanInternals` argument is omitted, so `emitBeforeComplete` is falsy and completion does not flush.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `scan(accumulator)` and `scan(accumulator, seed)` (lines 5–7 and 88–95). `OperatorFunction`. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. `hasSeed` is `arguments.length >= 2` at the call to `scan`, not at subscribe (lines 89–94), so `scan(fn, undefined)` has a seed. |
| Model kind | Symbolic. Specialization of `scanInternals` with `emitOnNext = true` and `emitBeforeComplete` falsy. |
| Parameter domain | `accumulator` is synchronous `(acc, value, index) => A`. Seed is optional. Presence, not truthiness, selects the seed overload. |
| Payload/error domain | Symbolic state and symbolic errors. |
| Subscription boundary | `scanInternals` allocates `hasState`, `state`, and `index` per subscription. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | `accumulator` is not called on the first value when no seed was passed. When it is called, `index` is 0 for the first source value if a seed exists, and 1 for the first call if the first source value was used as the seed (`scanInternals.ts` lines 38–47). |
| Cleanup assumptions | Default error and complete paths of `OperatorSubscriber` (no custom handlers, because `emitBeforeComplete` is omitted). |
| Explicit exclusions | Ordinary model, no reentrancy. Terminal late events are silent by convention. This file does not implement `reduce`’s flush-on-complete. Behavior of other flag combinations belongs to `scanInternals.md`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | `scan(...)` returned; not subscribed. | `accumulator`, `hasSeed`, `seed` | the call | `subscribe` does not emit |
| `active(hasState, state, index)` | Subscribed. | triple from `scanInternals` | `subscribe` | the next source value emits exactly one `next` if `accumulator` returns |
| `completed` | Completed with no extra flush. | none | source `complete` | silence |
| `errored(e)` | Source error or accumulator throw. | `e` | T04 or T05 | state is not emitted after the error |
| `cancelled` | Unsubscribed. | none | `cancel` | no `complete` and no flush |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `operate` runs `scanInternals` (scan.ts line 94). |
| Source next | yes | `emitOnNext` is true. |
| Source error | yes | Default forward. No flush. |
| Source completion | yes | Default forward. No flush. |
| Cancellation `cancel` | yes | Child teardown. No flush. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | yes | `accumulator` returns or throws, but only once `hasState` is already true. |

### Γ

```text
record {
  trace: ordered list of next(state) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Each input produces at most one notification, so a one-notification record is enough. `scan` never emits `next` and `complete` as the output of a single input (completion does not flush).

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | `hasSeed` true or false | none | `subscribe(source)`; `hasState = hasSeed`; `state = seed`; `index = 0` | `active(hasSeed, seed, 0)` | `scan(...)` | empty complete emits no seed | S01, S04 |
| T02 | `active(false, _, 0)` | source `next(v)` | no seed was passed | `next(v)` | `accumulator` not called | `active(true, v, 1)` | T01 with `arguments.length < 2` | the following value is accumulated with index 1 | S02 |
| T03 | `active(true, s, i)` | source `next(v)` | `accumulator(s, v, i)` returns `a` | `next(a)` | stay subscribed | `active(true, a, i+1)` | seed path after T01, or any state after T02 | index increases by 1 | S03 |
| T04 | `active(true, s, i)` | source `next(v)` | `accumulator` throws `e` | `error(e)`; no `next` | unsubscribe | `errored(e)` | state already true | silence | S05 |
| T05 | `active(_, _, _)` | source `error(e)` | any | `error(e)`; no `next(state)` | unsubscribe | `errored(e)` | T01, optional T02/T03 | silence | S06 |
| T06 | `active(_, _, _)` | source `complete` | any, including no values, with or without seed | `complete` only | unsubscribe | `completed` | T01, optional updates | seed was not emitted solely because the source ended | S01, S04 |
| T07 | `active` | `cancel` | open | none | unsubscribe; state dropped | `cancelled` | T01 | no `complete` | S07 |
| T08 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S05 |

T02 is unreachable when `hasSeed` is true. T04 is unreachable on the single first value of a no-seed scan, because T02 does not call `accumulator`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | T02, T03. One `next` per source `next` after a successful step, in order. JSDoc lines 21–29 match the helper when `emitOnNext` is true. |
| one terminal | yes | T04, T05, or T06. |
| silence after terminal | yes | T08. |
| cancel does not complete | yes | T07. |
| upstream/inner lifetime | yes | One source subscription. No inners. |
| cleanup once | yes | Default `OperatorSubscriber` / `Subscription` unsubscribe. |
| per-subscription state | yes | Cells live inside `scanInternals`’s subscriber function. |
| empty/error/silence | yes | Empty source, with or without seed: T01 then T06, no `next` (S01, S04). Source error: no emission of the current state (T05). Non-terminating source: one `next` per source `next` and no terminal. |
| pending buffer on terminal | no | Because `emitOnNext` is true, state is emitted at the update. Complete and error do not emit a held seed. The no-seed “pending” first value does not exist across a complete that never saw a value. |
| callback throw/reenter/cancel | yes | T04. The no-seed first value cannot throw from `accumulator` (T02). Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty source with a seed

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T06 |
| Starting state | `idle` |
| Reset/fixture | `scan(acc, seed)`, source completes with no next |
| State-reaching prefix | call `scan` |
| Target event | `subscribe` and the empty complete |
| Expected notifications | `complete` |
| Expected lifecycle observations | source subscribed then unsubscribed; `acc` not called |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next(seed)` |
| Oracle source | `source characterization` |

### S02 No seed, first value emitted raw

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02 |
| Starting state | `active(false, _, 0)` |
| Reset/fixture | `scan(acc)` with `acc` recording its index; source values `v` then `w` |
| State-reaching prefix | `subscribe` |
| Target event | first `next(v)` |
| Expected notifications | `next(v)` |
| Expected lifecycle observations | `acc` not called |
| Distinguishing suffix | second next emits `acc(v, w, 1)` |
| Expected final state | `active(true, v, 1)` after the target event |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload identity and index of the following call |
| Oracle source | `source characterization` |

### S03 Seed is combined, not emitted raw

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | `scan((s, v, i) => [s, v, i], seed)`, one value `v` |
| State-reaching prefix | `subscribe` |
| Target event | source `next(v)` |
| Expected notifications | `next([seed, v, 0])` |
| Expected lifecycle observations | still subscribed |
| Distinguishing suffix | source `complete` adds only `complete` (no second emission of the state) |
| Expected final state | `active(true, [seed, v, 0], 1)` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | index 0 and seed included once |
| Oracle source | `source characterization` |

### S04 Empty source without a seed

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T01, T06 |
| Starting state | `idle` |
| Reset/fixture | `scan(acc)`, empty source |
| State-reaching prefix | call `scan` |
| Target event | `subscribe` and complete |
| Expected notifications | `complete` |
| Expected lifecycle observations | `acc` not called |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` and of `error` |
| Oracle source | `source characterization` |

### S05 Accumulator throw

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T04, T08 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | `accumulator` throws `e` on the first value |
| State-reaching prefix | `subscribe` of `scan(acc, seed)` |
| Target event | source `next(v)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source unsubscribed; no `next` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error versus next |
| Oracle source | `source characterization` |

### S06 Source error

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T05 |
| Starting state | `active(true, s, 1)` |
| Reset/fixture | one successful emission, then source `error(e)` |
| State-reaching prefix | `subscribe` and one successful next |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` and no further `next` |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | no flush on error |
| Oracle source | `contract` |

### S07 Cancel

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T07 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | subscribed, no values yet |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no `next(seed)` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 8 section C rows (T01–T08).

Section E references T01, T02, T03, T04, T05, T06, T07, T08. Specified coverage = 8/8.

Execution: not executed.

Evidence: `src/internal/operators/scan.ts` lines 88–95 and `src/internal/operators/scanInternals.ts` lines 21–60. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: `scan` only chooses flags and the `arguments.length` seed test. The emission rules are the `emitOnNext` half of `scanInternals`, checked against this caller.

Known limitations: a seed of `undefined` is a real seed only because `arguments.length` is captured in `scan.ts` before `scanInternals` runs. Passing `undefined` through a wrapper that drops the argument would change the overload. Reentrancy is excluded. The public JSDoc (lines 21–29) matches this specialization; it does not describe `reduce`.

Contract vs version characterization: “emit after each update” and “first value is the seed when omitted” are the JSDoc contract. “Empty source emits nothing even if a seed was given” and “first accumulator index is 1 when the seed is omitted” are source characterization of the helper as called here.

Tests still required: S01–S07, plus `scan(fn, undefined)` on a non-empty source (accumulator must see `undefined` as `acc`) and two concurrent subscribers.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
