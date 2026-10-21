# `map`

`map` applies `project` to every source value and emits the returned value, in source order, with a zero-based per-subscription index. Source errors and source completion are forwarded unchanged and are not passed through `project`. A throw from `project` is a distinct callback failure: it becomes a destination error and the upstream subscription is torn down. This is the full implementation (`operate` plus `createOperatorSubscriber`), not a wrapper. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. The `thisArg` overload is `@deprecated` and scheduled for removal in v8 (`src/internal/operators/map.ts` lines 5–6); the single-argument overload is not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `map(project)` and deprecated `map(project, thisArg)`. `OperatorFunction<T, R>`. Implementation: `src/internal/operators/map.ts` lines 47–61. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | For each source `next(v)`, emit `next(project.call(thisArg, v, index))` and then increment the recorded index. Forward source `error` and source `complete`. Do not emit a projected value for the failing call if `project` throws. |
| Model kind | Symbolic. Control locations are finite; values, errors, and the projection function are uninterpreted. |
| Parameter domain | `project` is a synchronous function `(value, index) => R`. `thisArg` is optional and is the `this` passed to `project.call`. The `thisArg` signature is deprecated. |
| Payload/error domain | Payloads and errors are symbolic. No equality, numeric, or scheduler alphabet is imposed. |
| Subscription boundary | One `operate` closure per subscription holds `index`. The source is subscribed once. There is no inner observable. |
| Scheduler and tie ordering | No scheduler. Emissions stay in source order. No timers, so no equal-time tie rule. |
| Callback assumptions | `project` is synchronous. Its return value is the payload; a returned thenable is not awaited. `this` is `thisArg` (undefined when omitted). |
| Cleanup assumptions | `source.subscribe`’s teardown is a child of the `OperatorSubscriber`, which is a child of the destination (`Subscriber` constructor adds itself to a subscription destination). Destination `error` and `complete` unsubscribe that chain. Unsubscribe is idempotent. |
| Explicit exclusions | Ordinary model: each input is processed to quiescence; synchronous reentrancy is excluded (a `project` body or downstream handler that re-enters this subscription, resubscribes, or calls `unsubscribe` mid-notification). Downstream observer throws are host behavior of `SafeSubscriber` / `ConsumerObserver`, not inputs of `map`. Terminal late events are a silence convention, not legal traces. `config.useDeprecatedSynchronousErrorHandling` and `onStoppedNotification` are left at the 7.8.2 defaults (false / null). |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator function exists; this subscription has not started. | `project`, `thisArg` | Empty | `subscribe` is the only enabling input. |
| `active(n)` | Upstream subscribed; `n` source values have been handed to `project` so far. | `index = n` | `subscribe` then `n` successful projections | The next successful projection is called with index `n`, not with any other index. |
| `completed` | Destination already received `complete`. | none | `subscribe`, optional successful nexts, source `complete` | Further source events do not emit. |
| `errored(e)` | Destination already received `error(e)`. | error `e` | source `error(e)` or a throwing `project` | Further source events do not emit. `e` distinguishes callback failure from a different source error. |
| `cancelled` | Destination unsubscribed without a terminal notification from this operator. | none | `subscribe`, then `cancel` | No `complete` and no `error` were produced by the cancel. |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | `operate` subscribes to `source` (`map.ts` lines 48–59). |
| Source next | yes | Handled by the `onNext` closure, lines 54–58. |
| Source error | yes | No custom `onError`; `OperatorSubscriber` uses `Subscriber._error` (forward and unsubscribe). |
| Source completion | yes | No custom `onComplete`; default `_complete` forwards `complete`. |
| Cancellation `cancel` | yes | Unsubscribing the destination unsubscribes the child operator subscriber and the source. |
| Inner notifications | no | `map` subscribes only to the outer source. |
| Time | no | No clock and no scheduled action. |
| User callback outcomes | yes | `project` may return or throw. The throw is caught in `OperatorSubscriber._next` (`src/internal/operators/OperatorSubscriber.ts` lines 67–74) and sent to `destination.error`. It is not a source error. |

### Γ

```text
record {
  trace: ordered list of
      next(payload) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

A record of one optional notification is enough for every single input: each input emits at most one notification. An ordered trace is still the form used, because `error` and `complete` are different tags and must not be collapsed into a set of “terminal happened”.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` / consumer | `project` is a function | none | `subscribe(source)`; `index = 0` | `active(0)` | empty | one source `next` yields one projected `next` | S01 |
| T02 | `active(n)` | source `next(v)` | `project.call(thisArg, v, n)` returns `r` | `next(r)` | source stays subscribed; index becomes `n + 1` (`index++` in `map.ts` line 57) | `active(n+1)` | `subscribe` and `n` successful nexts | a further successful next uses index `n+1` | S01, S02 |
| T03 | `active(n)` | source `next(v)` | `project.call(thisArg, v, n)` throws `e` | `error(e)` and not `next` | `destination.error` unsubscribes the operator subscriber and the source (`OperatorSubscriber.ts` lines 69–73; `Subscriber._error` unsubscribes) | `errored(e)` | `subscribe` and `n` successful nexts | late source `next` is silent | S03 |
| T04 | `active(n)` | source `error(e)` | default `onError` (not a `project` throw) | `error(e)` | default `_error` notifies then unsubscribes | `errored(e)` | `subscribe`, any successful nexts | late source `complete` is silent | S04 |
| T05 | `active(n)` | source `complete` | any `n`, including `0` | `complete` | default `_complete` notifies then unsubscribes | `completed` | `subscribe` and `n` successful nexts | late source `next` is silent | S02, S05 |
| T06 | `active(n)` | `cancel` / consumer unsubscribe | subscription still open | none (not `complete`, not `error`) | destination unsubscribe tears down the source | `cancelled` | `subscribe`, optional nexts | source must not remain subscribed; no terminal is synthesized | S06 |
| T07 | `completed`, `errored(_)`, or `cancelled` | late source `next` / `error` / `complete`, or a second `cancel` | host would be calling a stopped subscriber | none | no second teardown | same terminal | a terminal transition | none; silence does not mean the late event is a legal trace | S03 |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | T02. Order is source order. Payload is `project.call(thisArg, value, index)` (`map.ts` lines 54–58). Index starts at 0 per subscription (line 50). |
| one terminal | yes | T03, T04, T05. A throwing `project` and a source error both end in `errored`. Complete ends in `completed`. No path emits two terminals. |
| silence after terminal | yes | T07. Stopped `Subscriber.next/error/complete` do not deliver when `isStopped` is set; default `onStoppedNotification` is null. |
| cancel does not complete | yes | T06. |
| upstream/inner lifetime | yes | One upstream subscription from T01 until T03–T06. No inners. |
| cleanup once | yes | Unsubscribe is idempotent (`Subscription.closed`). The child link is established once in the `OperatorSubscriber` constructor. |
| per-subscription state | yes | `index` is allocated inside `operate` (`map.ts` lines 48–50), so two subscribers do not share an index. |
| empty/error/silence | yes | Empty source: T01 then T05, no `next` (S05). Source error: T04, no projected `next`. A source that never terminates stays in `active(n)` with no terminal (silence). |
| pending buffer on terminal | no | Nothing is buffered. The in-flight value is dropped if `project` throws (T03) or if the source errors (T04). |
| callback throw/reenter/cancel | yes | Throw is T03, distinct from T04. Reentrancy and cancel-from-inside-`project` are exclusions. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Successful projection and index

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | `project(v, i) = (v, i)`, `thisArg` omitted, cold source of two values `a` then `b`. |
| State-reaching prefix | `subscribe` |
| Target event | source `next(a)` then source `next(b)` |
| Expected notifications | `next((a, 0))`, `next((b, 1))` |
| Expected lifecycle observations | source subscribed once; still subscribed after both nexts |
| Distinguishing suffix | source `complete` → `complete` (shows the machine was still `active`) |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered notification trace and index arguments |
| Oracle source | `source characterization` |

### S02 Project then complete

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T05 |
| Starting state | `active(0)` |
| Reset/fixture | identity `project`, one source value, then complete |
| State-reaching prefix | `subscribe` |
| Target event | source `next(v)` then source `complete` |
| Expected notifications | `next(project(v, 0))`, `complete` |
| Expected lifecycle observations | source unsubscribed as part of complete |
| Distinguishing suffix | late source `next` emits nothing |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered trace |
| Oracle source | `contract` |

### S03 Callback throw is destination error

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T07 |
| Starting state | `active(1)` |
| Reset/fixture | First call returns; second call throws `e`. |
| State-reaching prefix | `subscribe`, source `next(v0)` with a returning `project` |
| Target event | source `next(v1)` whose `project` throws `e` |
| Expected notifications | `error(e)`. No `next` for `v1`. |
| Expected lifecycle observations | source unsubscribed; `project` is not called again |
| Distinguishing suffix | a further source `next` or `complete` is silent (not a second terminal) |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error identity and absence of `next` |
| Oracle source | `source characterization` |

### S04 Source error is not a callback error

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04 |
| Starting state | `active(0)` |
| Reset/fixture | `project` that would return if called |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` before any `next` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | `project` was not called; source unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `project` call count is 0; error payload is `e` |
| Oracle source | `source characterization` |

### S05 Empty completion

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T01, T05 |
| Starting state | `idle` |
| Reset/fixture | source completes synchronously with no `next` |
| State-reaching prefix | empty |
| Target event | `subscribe` (source completes inside subscribe) |
| Expected notifications | `complete` only |
| Expected lifecycle observations | source subscribed and then unsubscribed |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of `next` |
| Oracle source | `contract` |

### S06 Cancel does not complete

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T06 |
| Starting state | `active(0)` |
| Reset/fixture | source that has not terminated |
| State-reaching prefix | `subscribe` |
| Target event | consumer `unsubscribe` |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed; destination did not observe `complete` or `error` |
| Distinguishing suffix | a late source `next` is not delivered |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of a terminal notification |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references T01, T02, T03, T04, T05, T06, T07. Specified coverage = 7/7.

Execution: not executed.

Evidence is the source text cited above, in particular `src/internal/operators/map.ts` lines 47–61 and the callback-error path in `src/internal/operators/OperatorSubscriber.ts` lines 67–74. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the subscription machine is fully determined by the `operate` closure and the default operator-subscriber error and complete paths. Limits are the quiescence assumption, the default RxJS error-config, and the decision not to treat downstream observer exceptions as `map` inputs.

Known limitations: `index++` evaluates before `project` is entered, so a throw still consumes that index, but the state is terminal so the advanced index is not observable. `thisArg` is only a deprecated calling convention. Identity of the returned reference is whatever `project` returns; `map` does not copy it.

Contract vs version characterization: the public contract (project each value, forward error and complete) matches 7.8.2. The precise “throw becomes `destination.error` and unsubscribes” claim is a source characterization of `OperatorSubscriber`, which this operator relies on.

Tests still required: S01–S06 against 7.8.2, including a two-subscriber check that indexes are not shared, and a `thisArg` call-site check.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
