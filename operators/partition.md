# `partition`

`partition(predicate, thisArg?)` is not an `OperatorFunction`. It returns a unary function from a source observable to a pair of observables: `[filter(predicate, thisArg)(source), filter(not(predicate, thisArg))(source)]` (`src/internal/operators/partition.ts` lines 56–62). Applying it does not subscribe. Each branch subscribes to `source` on its own, with its own index, and there is no `share`. The pass branch emits a source value when `predicate.call(thisArg, value, index)` is truthy. The fail branch emits it when that call is falsy. A throw fails only the branch that evaluated it. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. The function is `@deprecated` and scheduled for removal in v8, replaced by the static `partition` creation function (line 54). `thisArg` is not separately deprecated on this function; `filter`’s `thisArg` overload is.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `partition(predicate, thisArg?)` returns `UnaryFunction<Observable<T>, [Observable<T>, Observable<T>]>`. Lines 56–62. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | Pass branch: `filter` (`src/internal/operators/filter.ts` lines 61–75) calls `predicate.call(thisArg, value, index++)` and emits the value when the result is truthy (`&&`). Fail branch: `not` (`src/internal/util/not.ts` lines 1–3) returns `(value, index) => !pred.call(thisArg, value, index)`, and `filter` is applied without a second `thisArg`. Indexes are per branch subscription, starting at 0, and increment on every source value that branch sees, including values it does not emit. |
| Model kind | Symbolic. The machine is the independent product of two `filter` machines plus a pair factory. It is not one shared subscription. |
| Parameter domain | `predicate` is a synchronous function. `thisArg` is optional. A truthy return selects the pass branch; a falsy return selects the fail branch. The TypeScript type says `boolean`; the implementation uses truthiness and `!`. |
| Payload/error domain | Emitted payloads are the source references. Errors are source errors on that branch’s subscription, or a throw from the evaluation that branch performed. |
| Subscription boundary | Zero, one, or two source subscriptions. Subscribing only one branch does not subscribe the other and does not run `predicate` for the other. A cold source subscribed twice runs twice. A hot source delivers each branch the events from that branch’s own subscription onward. |
| Scheduler and tie ordering | No scheduler. Each branch preserves its source order. The pair is not zipped. |
| Callback assumptions | On the pass branch, `this` is `thisArg`. On the fail branch, `not` applies `pred.call(thisArg, value, index)` itself, so `thisArg` is the same even though `filter`’s `thisArg` is omitted. `predicate` runs once per value per subscribed branch. Both branches subscribed means two calls per source value (and twice the cold-source side effects). |
| Cleanup assumptions | Each branch is a normal `filter`: one `OperatorSubscriber`, torn down with that branch’s destination only. |
| Explicit exclusions | Ordinary model, no reentrancy, per branch. A predicate that unsubscribes or re-enters is excluded. Terminal late events on a branch are silent by convention and do not affect the other branch. This model is not the static `partition` creation function. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = unapplied
```

A state is the factory phase plus two independent branch states. A transition touches one branch, or only the factory. There is no joint index and no joint terminal.

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `unapplied` | `partition(predicate, thisArg)` returned a function. | `predicate`, `thisArg` | the call | applying it to a source does not subscribe |
| `paired` | Two observables exist. Each branch is `idle`, `active(n)`, `completed`, `errored(e)`, or `cancelled`. | per branch: index `n` when active | `apply(source)` | subscribing the pass branch does not change the fail branch |
| branch `idle` | That observable has not been subscribed. | none | `paired` | its subscribe is still available |
| branch `active(n)` | That branch is subscribed and has seen `n` source values. | index `n` | that branch’s subscribe | the next value is tested with index `n` |
| branch `completed` | That branch completed. | none | that branch’s source `complete` | the other branch is unchanged |
| branch `errored(e)` | That branch errored. | `e` | that branch’s source error or its own predicate throw | the other branch is unchanged |
| branch `cancelled` | That branch was unsubscribed. | none | that branch’s cancel | no `complete` on that branch |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Per branch, when that branch’s observable is subscribed. Factory application is a separate input and is not a subscribe. |
| Source next | yes | Per branch subscription. The same upstream event is two inputs if both branches are subscribed to a hot source; a cold source produces two separate executions. |
| Source error | yes | Per branch subscription. Default `filter` forward. |
| Source completion | yes | Per branch. Default forward. |
| Cancellation `cancel` | yes | Per branch. Does not cancel the other. |
| Inner notifications | no | `filter` has no inner observable. The two branches are not inners of a shared parent subscription. |
| Time | no | No clock. |
| User callback outcomes | yes | Each evaluation may return truthy, return falsy, or throw. The fail branch’s throw happens inside `not`, before `!`. |

### Γ

```text
record {
  branch: pass | fail,
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source on that branch) | unsubscribe(source on that branch)
}
```

Outputs are tagged by branch. One input notifies at most one branch. A one-notification record per branch-input is enough. Collapsing the pair into one subscriber would be the wrong machine: the implementation returns two observables.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `unapplied` | `apply(source)` | any source | none | no subscribe | `paired`, both branches `idle` | `partition(predicate, thisArg)` | subscribing one branch leaves the other `idle` | S01 |
| T02 | pass `idle` | subscribe pass | any | none | `subscribe(source)` for the pass branch only; index `0` | pass `active(0)` | T01 | a truthy value is emitted only on pass | S01 |
| T03 | fail `idle` | subscribe fail | any | none | a second, independent `subscribe(source)`; index `0` | fail `active(0)` | T01 | pass, if still `idle`, stays `idle` | S02 |
| T04 | pass `active(n)` | source `next(v)` on the pass subscription | `predicate.call(thisArg, v, n)` is truthy | pass `next(v)` | pass stays subscribed | pass `active(n+1)` | T02 and `n` pass-branch values | the next pass evaluation uses index `n+1` | S01 |
| T05 | pass `active(n)` | source `next(v)` on the pass subscription | result is falsy | none on pass | index becomes `n+1` | pass `active(n+1)` | T02 | a later truthy value is still forwarded | S03 |
| T06 | pass `active(n)` | source `next(v)` on the pass subscription | `predicate` throws `e` | pass `error(e)`; no `next` | unsubscribe pass source only | pass `errored(e)` | T02 | fail branch, if subscribed, is not stopped by this throw | S04 |
| T07 | fail `active(n)` | source `next(v)` on the fail subscription | `predicate` returns falsy, so `not` returns true | fail `next(v)` | fail stays subscribed | fail `active(n+1)` | T03 | pass is not notified by this input | S02 |
| T08 | fail `active(n)` | source `next(v)` on the fail subscription | `predicate` returns truthy, so `not` returns false | none on fail | index `n+1` | fail `active(n+1)` | T03 | a later falsy value is forwarded on fail | S03 |
| T09 | fail `active(n)` | source `next(v)` on the fail subscription | `predicate` throws `e` | fail `error(e)` | unsubscribe fail source only | fail `errored(e)` | T03 | pass is unaffected | S04 |
| T10 | a branch `active(n)` | that subscription’s source `error(e)` | predicate not running | that branch `error(e)` | unsubscribe that branch only | that branch `errored(e)` | that branch subscribed | the other branch remains where it was | S05 |
| T11 | a branch `active(n)` | that subscription’s source `complete` | any | that branch `complete` | unsubscribe that branch only | that branch `completed` | that branch subscribed | the other branch is not completed by this input | S06 |
| T12 | a branch `active(n)` | cancel that branch | open | none | unsubscribe that branch only | that branch `cancelled` | that branch subscribed | no `complete` on that branch; the other stays | S07 |
| T13 | a branch terminal | late events on that branch | stopped | none | none | same branch terminal | a terminal row for that branch | convention, not a legal trace; not a signal to the other branch | S04 |

`filter.ts` lines 72: `predicate.call(thisArg, value, index++) && subscriber.next(value)`. The post-increment runs even when the result is falsy or when the call throws (the argument is evaluated before the call). On throw, the branch is terminal, so the incremented index is not observable.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Each branch preserves the order of values it forwards. Indexes on a branch count every value that branch received (`filter.ts` line 64 and 72). |
| one terminal | yes | Per branch: T06/T09, T10, or T11. The other branch is a different subscriber. |
| silence after terminal | yes | T13, per branch. |
| cancel does not complete | yes | T12, per branch. |
| upstream/inner lifetime | yes | One upstream subscription per subscribed branch, none before T02/T03. No shared parent. Unsubscribing one does not unsubscribe the other. |
| cleanup once | yes | Each branch’s `OperatorSubscriber` unsubscribe is idempotent. |
| per-subscription state | yes | Each branch’s `index` is inside that `filter`’s `operate`. Two subscribers of the same pass observable are two `filter` subscriptions. |
| empty/error/silence | yes | A subscribed branch whose source completes with no values completes with no `next` (T11). A branch that is never subscribed stays `idle` and emits nothing. Source error on one subscription is T10 for that branch only. |
| pending buffer on terminal | no | `filter` does not buffer. A value in flight whose predicate throws is not emitted (T06, T09). |
| callback throw/reenter/cancel | yes | T06 and T09. If both branches are subscribed and both evaluate a throwing predicate, each branch errors on its own evaluation. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. The two branches are not ordered against each other by this operator. |

## E. Scenario specification

### S01 Apply, then only the pass branch

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02, T04 |
| Starting state | `unapplied` |
| Reset/fixture | `predicate` is `v => v > 0`; cold source `1`, `-1` is not subscribed on fail |
| State-reaching prefix | `partition(predicate)` |
| Target event | `apply(source)`, subscribe pass, source `next(1)` |
| Expected notifications | pass `next(1)`; fail has no subscriber and no notification |
| Expected lifecycle observations | one source subscription; fail remains `idle`; `predicate` called once with index 0 |
| Distinguishing suffix | pass source `complete` completes only pass |
| Expected final state | pass `active(1)` before that suffix; fail `idle` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | single subscription and pass payload |
| Oracle source | `source characterization` |

### S02 Fail branch is an independent subscription

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T03, T07 |
| Starting state | `paired`, both `idle` |
| Reset/fixture | cold source of `-1`; `thisArg` is a sentinel; `predicate` checks `this` |
| State-reaching prefix | T01 |
| Target event | subscribe fail only, then the value |
| Expected notifications | fail `next(-1)` |
| Expected lifecycle observations | pass still `idle` and unsubscribed; `predicate` called once as `predicate.call(thisArg, -1, 0)` from inside `not` |
| Distinguishing suffix | a later positive value on that same fail subscription is not emitted (T08) and still consumes an index |
| Expected final state | fail `active(1)`; pass `idle` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `thisArg` and independence |
| Oracle source | `source characterization` |

### S03 Truthiness splits the two subscribed branches

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T05, T08 |
| Starting state | both branches `active(0)` |
| Reset/fixture | hot source, both subscribed, values `0` then `2`. `0` is falsy. |
| State-reaching prefix | T01, T02, T03 |
| Target event | those two source events, delivered to both subscriptions |
| Expected notifications | for `0`: fail `next(0)`, pass silent. for `2`: pass `next(2)`, fail silent. |
| Expected lifecycle observations | `predicate` evaluated twice per value; each branch index ends at 2 |
| Distinguishing suffix | either branch’s complete does not complete the other |
| Expected final state | both `active(2)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | per-branch traces and double evaluation |
| Oracle source | `source characterization` |

### S04 Throw isolates the branch that evaluated it

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T06, T09, T13 |
| Starting state | pass `active(0)`, fail `idle` in the first case; both `active(0)` in the second |
| Reset/fixture | `predicate` throws `e` |
| State-reaching prefix | T01 and the subscribes for the case |
| Target event | the throwing value |
| Expected notifications | only subscribed branches error, each with `e`. An `idle` branch does not error. |
| Expected lifecycle observations | each errored branch unsubscribes its own source subscription; the other active branch is not unsubscribed by the first branch’s error. If both are active they each run `predicate` and each can error. |
| Distinguishing suffix | silence on a branch that already errored |
| Expected final state | each evaluating branch `errored(e)`; a branch that was `idle` stays `idle` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error isolation |
| Oracle source | `source characterization` |

### S05 Source error is per subscription

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T10 |
| Starting state | pass `active(0)`, fail `active(0)`, on a hot source |
| Reset/fixture | source `error(e)` |
| State-reaching prefix | both subscribes |
| Target event | the source error, observed by both subscriptions if the source multicasts it |
| Expected notifications | each subscribed branch `error(e)` when its own subscription delivers it |
| Expected lifecycle observations | `predicate` not called for the error signal |
| Distinguishing suffix | silence per errored branch |
| Expected final state | both `errored(e)` if both received it |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error forwarding without a predicate call |
| Oracle source | `contract` |

### S06 Complete is per branch

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T11 |
| Starting state | pass `active`, fail `idle` |
| Reset/fixture | pass’s source completes |
| State-reaching prefix | subscribe pass only |
| Target event | that complete |
| Expected notifications | pass `complete`; fail nothing |
| Expected lifecycle observations | pass source unsubscribed; fail still `idle` |
| Distinguishing suffix | fail can still be subscribed later to a new execution if the caller subscribes it |
| Expected final state | pass `completed`; fail `idle` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | one terminal, one branch |
| Oracle source | `source characterization` |

### S07 Cancel one branch

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T12 |
| Starting state | both `active` |
| Reset/fixture | hot source, both subscribed |
| State-reaching prefix | both subscribes |
| Target event | unsubscribe pass |
| Expected notifications | none |
| Expected lifecycle observations | pass source unsubscribed; fail still subscribed and can still emit |
| Distinguishing suffix | a later value is evaluated only on fail |
| Expected final state | pass `cancelled`; fail `active` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `complete` on pass and continued fail subscription |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 13 section C rows (T01–T13).

Section E references every row. Specified coverage = 13/13.

Execution: not executed.

Evidence: `src/internal/operators/partition.ts` lines 56–62, `src/internal/operators/filter.ts` lines 61–75, and `src/internal/util/not.ts` lines 1–3. No `share`, `multicast`, or `connect` appears in `partition.ts`. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the function builds two independent `filter` observables. Independence is the observable fact (two `filter(...)(source)` calls, no sharing), and each branch is the `filter` predicate machine.

Known limitations: truthiness rather than `=== true`. A cold source runs twice when both branches are subscribed, so predicate side effects and upstream side effects run twice. Indexes are not a single counter shared by the pair. Reentrancy is excluded. The static creation function that will replace this operator is not this source file.

Contract vs version characterization: JSDoc lines 16–21 say the result is two observables, the second being the negated predicate. Separate subscriptions, per-branch indexes, truthiness, and “a throw affects the branch that evaluated it” are source characterization. The JSDoc’s “i-th emission since the subscription” matches a per-branch reading once the two subscriptions are recognized.

Tests still required: S01–S07, especially a cold source with both branches subscribed (two upstream subscriptions) and a hot source where only one branch is cancelled.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
