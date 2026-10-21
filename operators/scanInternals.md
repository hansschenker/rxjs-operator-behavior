# `scanInternals`

Internal helper, not a public operator. `scanInternals` is the shared accumulator protocol used by `scan` and `reduce`. It is not `scan` and it is not `reduce`: those callers fix the flags, while this function implements every flag combination. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. The only imports of `scanInternals` under `src/` are `src/internal/operators/scan.ts` line 94 (`emitOnNext = true`, `emitBeforeComplete` omitted) and `src/internal/operators/reduce.ts` line 60 (`emitOnNext = false`, `emitBeforeComplete = true`). Both pass `hasSeed = arguments.length >= 2` so that an explicit `undefined` seed still counts as a seed.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | Not exported as an operator. `scanInternals(accumulator, seed, hasSeed, emitOnNext, emitBeforeComplete?)` returns `(source, subscriber) => void` (`src/internal/operators/scanInternals.ts` lines 14–62). |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | Keep `hasState`, `state`, and `index`. On a source value, if `hasState` is already true, set `state = accumulator(state, value, index)` and then increment the index that was passed; if `hasState` is false, do not call `accumulator`, set `state` to the raw value, and set `hasState` true. If `emitOnNext`, emit `state` after that update. On source complete, if `emitBeforeComplete` is truthy and `hasState`, emit `state` and then `complete`; if `emitBeforeComplete` is truthy and `hasState` is false, `complete` with no `next` and no `EmptyError`; if `emitBeforeComplete` is falsy, forward `complete` with no extra `next`. Source errors are forwarded and do not flush `state`. |
| Model kind | Symbolic. Flags are finite parameters. `state` and errors are uninterpreted. |
| Parameter domain | `accumulator` is synchronous. `hasSeed`, `emitOnNext`, and `emitBeforeComplete` are booleans in practice (`emitBeforeComplete` may be `undefined`). `seed` is stored even when it is `undefined`. |
| Payload/error domain | Symbolic accumulator results and symbolic errors. |
| Subscription boundary | The returned function closes over the flags. `hasState`, `state`, and `index` are created when that function runs (one destination subscription). One source subscription. No inner observable. |
| Scheduler and tie ordering | No scheduler. Source order is the only order. |
| Callback assumptions | `accumulator` runs synchronously inside `onNext`. It is not called for the value that first establishes state when `hasSeed` is false. The index passed on that skipped call is consumed: the next real accumulator call receives `1`, not `0` (`scanInternals.ts` lines 38–47). |
| Cleanup assumptions | `createOperatorSubscriber` without a custom `onError`. Complete is custom only when `emitBeforeComplete` is truthy (lines 52–58). Throws from `accumulator` use `OperatorSubscriber._next`’s catch (`OperatorSubscriber.ts` lines 67–74). |
| Explicit exclusions | Ordinary model: each input to quiescence; no reentrancy from `accumulator` or from a downstream handler. No caller in this tree sets both `emitOnNext` and `emitBeforeComplete`; those rows are still part of the helper. Terminal late events are silent by convention. `useDeprecatedSynchronousErrorHandling` is off. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

Parameters `P = (accumulator, seed, hasSeed, emitOnNext, emitBeforeComplete)` are fixed before `s₀` and are not part of the subscription alphabet.

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Flags chosen; subscriber function not yet invoked. | `P` | empty | running the subscriber function takes `active` |
| `active(hasState, state, index)` | Accumulating. | the triple | subscriber function ran; zero or more nexts | `emitOnNext` decides whether the next value is visible now or only stored; `hasState` decides whether `accumulator` runs |
| `completed` | Destination completed. | none | source `complete` under the flag rules below | silence |
| `errored(e)` | Destination errored. | `e` | source error, or accumulator throw | state was not flushed |
| `cancelled` | Unsubscribed with no terminal from this helper. | none | `cancel` | stored state is dropped |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | The function at lines 21–61 is the subscription initializer. It does not emit the seed. |
| Source next | yes | Lines 37–50. |
| Source error | yes | No custom `onError` (line 34 comment: errors are passed through). |
| Source completion | yes | Either the default complete or the handler at lines 54–58. |
| Cancellation `cancel` | yes | Child unsubscribe of the operator subscriber. |
| Inner notifications | no | No inner subscribe. |
| Time | no | No clock. |
| User callback outcomes | yes | `accumulator` may return or throw, and only when `hasState` is already true at the start of the next. |

### Γ

```text
record {
  trace: ordered list of next(state) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

A one-notification record is enough except when `emitBeforeComplete` and `hasState` both hold: that input’s output is the ordered pair `next(state)` then `complete`. A bag of notifications would lose that order, so an ordered trace is required for T09.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | run `(source, subscriber)` | any flags | none, including when `hasSeed` (seed is stored, not emitted) | `hasState = hasSeed`, `state = seed`, `index = 0`; `subscribe(source)` (lines 25–34) | `active(hasSeed, seed, 0)` | flags fixed | the first source next either seeds or reduces | S01 |
| T02 | `active(true, s, i)` | source `next(v)` | `accumulator(s, v, i)` returns `a`; `emitOnNext` true | `next(a)` | stay subscribed | `active(true, a, i+1)` | T01 and enough nexts to have state | another next uses index `i+1` | S02 |
| T03 | `active(true, s, i)` | source `next(v)` | accumulator returns `a`; `emitOnNext` false | none | stay subscribed | `active(true, a, i+1)` | T01 with a seed, or a prior seed-install | complete flushes `a` only if T09 | S03 |
| T04 | `active(false, _, i)` | source `next(v)` | `emitOnNext` true | `next(v)` | `accumulator` not called | `active(true, v, i+1)` | T01 with `hasSeed` false (so `i` is 0) | the next source value does call `accumulator` with index `i+1` | S04 |
| T05 | `active(false, _, i)` | source `next(v)` | `emitOnNext` false | none | `accumulator` not called | `active(true, v, i+1)` | T01 with `hasSeed` false | complete flushes `v` via T09; no emission yet | S05 |
| T06 | `active(true, s, i)` | source `next(v)` | `accumulator` throws `e` | `error(e)`; no `next` | index expression `index++` already ran (line 39); assignment to `state` did not; unsubscribe | `errored(e)` | state already established | silence; `s` is not emitted | S06 |
| T07 | `active(_, _, _)` | source `error(e)` | any flags | `error(e)`; no flush `next` | default `_error` unsubscribes | `errored(e)` | T01, optional updates | silence | S07 |
| T08 | `active(_, _, _)` | source `complete` | `emitBeforeComplete` falsy | `complete` only | default `_complete` | `completed` | T01, optional updates | seed is not emitted on an empty source | S08 |
| T09 | `active(true, s, _)` | source `complete` | `emitBeforeComplete` truthy | ordered `next(s)`, `complete` (lines 56–57) | custom complete unsubscribes in its `finally` (`OperatorSubscriber.ts` lines 89–100) | `completed` | a seed, or at least one T04/T05 | silence | S03, S05 |
| T10 | `active(false, _, _)` | source `complete` | `emitBeforeComplete` truthy | `complete` only. No `next`. No `EmptyError`. | custom complete still calls `subscriber.complete()` (line 57) | `completed` | T01 with `hasSeed` false and no next | silence | S09 |
| T11 | `active(_, _, _)` | `cancel` | open | none | unsubscribe source; state dropped | `cancelled` | T01 | no flush | S10 |
| T12 | terminal | late source events | stopped subscriber | none | none | same | T06–T11 | convention, not a legal trace | S06 |

`hasState` is false only in the initial state when `hasSeed` is false, so T04, T05, and T10 are unreachable once any source value has been seen. No `src/` caller passes `emitOnNext && emitBeforeComplete`. T02 with a later T08 is `scan`. T03/T05 with T09/T10 is `reduce`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Updates follow source order. Index is the pre-increment value (lines 38–43). Without a seed, the first accumulator index is 1. |
| one terminal | yes | T06, T07, T08, T09, T10 each produce one terminal. T09’s `next` is not a terminal. |
| silence after terminal | yes | T12. |
| cancel does not complete | yes | T11. Cancel does not flush. |
| upstream/inner lifetime | yes | One source subscription from T01 until a terminal or cancel. No inners. |
| cleanup once | yes | `OperatorSubscriber` unsubscribe is idempotent. The custom complete handler’s `finally` unsubscribes even if `subscriber.complete()` already did. |
| per-subscription state | yes | `hasState`, `state`, and `index` are locals of the function at line 21, so they are per destination subscription. |
| empty/error/silence | yes | Empty source and `emitOnNext`: T08, no `next`, even if a seed exists (the seed is not flushed). Empty source, no seed, `emitBeforeComplete`: T10, `complete` only, no `EmptyError`. Empty source with seed and `emitBeforeComplete`: T09 emits the seed. Source error never flushes (T07). A source that never completes stays `active` (silence). |
| pending buffer on terminal | yes | The single `state` cell is pending output when `emitOnNext` is false. T09 flushes it if `hasState`. T07, T10, T11 drop it. When `emitOnNext` is true the cell has already been emitted on each update, and T08 does not emit it again. |
| callback throw/reenter/cancel | yes | T06 only if `hasState` was already true. The seed-install next (T04, T05) cannot throw from `accumulator` because it is not called. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Seed is not emitted at subscribe

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01 |
| Starting state | `idle` |
| Reset/fixture | `hasSeed` true, `seed = S0`, either `emitOnNext` setting |
| State-reaching prefix | flags fixed |
| Target event | invoke the subscriber function on a silent source |
| Expected notifications | none |
| Expected lifecycle observations | source subscribed; `state === S0`; `index === 0`; `hasState === true` |
| Distinguishing suffix | source `complete` with `emitBeforeComplete` emits `S0` (T09); with `emitBeforeComplete` falsy it emits only `complete` (T08) |
| Expected final state | still `active` if the suffix is not taken |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` at subscribe |
| Oracle source | `source characterization` |

### S02 emitOnNext with seed

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02 |
| Starting state | `active(true, S0, 0)` |
| Reset/fixture | `emitOnNext` true; `accumulator(s, v, i) = (s, v, i)` |
| State-reaching prefix | T01 with `hasSeed` |
| Target event | source `next(v)` |
| Expected notifications | `next((S0, v, 0))` |
| Expected lifecycle observations | still subscribed; index is 1 |
| Distinguishing suffix | a second next receives index 1 |
| Expected final state | `active(true, (S0, v, 0), 1)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload includes index 0 |
| Oracle source | `source characterization` |

### S03 No emit until complete, with seed

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T09 |
| Starting state | `active(true, S0, 0)` |
| Reset/fixture | `emitOnNext` false, `emitBeforeComplete` true, one source value then complete |
| State-reaching prefix | T01 with seed |
| Target event | source `next(v)` then source `complete` |
| Expected notifications | no `next` on the value; then `next(accumulator(S0, v, 0))`, `complete` |
| Expected lifecycle observations | unsubscribed on complete |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered flush |
| Oracle source | `source characterization` |

### S04 First value is the seed and is emitted

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04 |
| Starting state | `active(false, seedIgnored, 0)` |
| Reset/fixture | `hasSeed` false, `emitOnNext` true, `accumulator` throws if called |
| State-reaching prefix | T01 |
| Target event | first source `next(v)` |
| Expected notifications | `next(v)` |
| Expected lifecycle observations | `accumulator` call count is 0; `hasState` true; index 1 |
| Distinguishing suffix | second source `next(w)` calls `accumulator(v, w, 1)` and emits that result |
| Expected final state | `active(true, v, 1)` after the first next |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | accumulator not called; index of the later call is 1 |
| Oracle source | `source characterization` |

### S05 First value stored, not emitted

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T05, T09 |
| Starting state | `active(false, _, 0)` |
| Reset/fixture | `hasSeed` false, `emitOnNext` false, `emitBeforeComplete` true, values `v` then `w`, then complete |
| State-reaching prefix | T01 |
| Target event | two nexts and complete |
| Expected notifications | one `next(accumulator(v, w, 1))` then `complete` |
| Expected lifecycle observations | `accumulator` called once, with index 1 |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | single flush and index |
| Oracle source | `source characterization` |

### S06 Accumulator throw

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T06, T12 |
| Starting state | `active(true, s, i)` |
| Reset/fixture | `accumulator` throws `e` |
| State-reaching prefix | state already established |
| Target event | source `next(v)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source unsubscribed; `s` not emitted |
| Distinguishing suffix | late complete is silent |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error, not flush |
| Oracle source | `source characterization` |

### S07 Source error does not flush

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T07 |
| Starting state | `active(true, s, i)` |
| Reset/fixture | any flags |
| State-reaching prefix | T01 and an update that stored `s` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` only |
| Expected lifecycle observations | unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next(s)` |
| Oracle source | `source characterization` |

### S08 emitOnNext false-complete does not flush

| Field | Content |
| --- | --- |
| Test ID | S08 |
| Covered row IDs | T08 |
| Starting state | `active(true, seed, 0)` |
| Reset/fixture | `hasSeed` true, `emitOnNext` true, `emitBeforeComplete` undefined, no source values |
| State-reaching prefix | T01 |
| Target event | source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | unsubscribed; seed was never a `next` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `source characterization` |

### S09 Empty, no seed, flush flag

| Field | Content |
| --- | --- |
| Test ID | S09 |
| Covered row IDs | T10 |
| Starting state | `active(false, _, 0)` |
| Reset/fixture | `hasSeed` false, `emitBeforeComplete` true, empty source |
| State-reaching prefix | T01 |
| Target event | source `complete` |
| Expected notifications | `complete` only |
| Expected lifecycle observations | unsubscribed; no `EmptyError` |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `complete` versus `error` |
| Oracle source | `source characterization` |

### S10 Cancel drops state

| Field | Content |
| --- | --- |
| Test ID | S10 |
| Covered row IDs | T11 |
| Starting state | `active(true, s, i)` |
| Reset/fixture | `emitBeforeComplete` true so a complete would have flushed |
| State-reaching prefix | T01 and an update |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no late flush |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 12 section C rows (T01–T12).

Section E references every row T01–T12. Specified coverage = 12/12.

Execution: not executed.

Evidence: `src/internal/operators/scanInternals.ts` lines 14–62, call sites `scan.ts` line 94 and `reduce.ts` line 60, and `OperatorSubscriber.ts` lines 67–100. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the helper is a straight-line closure with three cells and two booleans. Flag combinations that no current caller uses are still specified, and marked as such, because this document is about the helper rather than about `scan`.

Known limitations: `emitBeforeComplete && handler` uses JavaScript truthiness (line 54). A non-boolean truthy fifth argument would install the flush handler. `hasSeed` is an independent boolean; this helper does not itself inspect `arguments.length`. Reentrancy from the accumulator is excluded. There is no `EmptyError` branch in this file.

Contract vs version characterization: there is no public contract. All obligations are source characterization of 7.8.2. Older RxJS versions that raised `EmptyError` from `reduce` on an empty source are not this helper.

Tests still required: S01–S10, including the unused flag pair `emitOnNext && emitBeforeComplete` if the helper is tested directly, and an explicit `undefined` seed (`hasSeed` true) versus an omitted seed.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
