# `tap`

`tap` mirrors the source. If it is called with no usable observer (`tap()`, `tap(null)`, `tap(null, null, null)`, or any other falsy first argument with no truthy error or complete argument), it returns `identity` and does not install hooks: `source.pipe(tap())` is that same source. Otherwise it runs optional side effects. `subscribe` runs at subscription, before `source.subscribe`. `next` runs before the value is forwarded; a throw there becomes destination `error`, the value is not forwarded, and `tap`’s own `error` hook is not called. Source `error` and source `complete` set an `isUnsub` flag false, run the matching hook, then forward the original signal if the hook did not throw. `unsubscribe` runs only when teardown happens while `isUnsub` is still true (explicit cancel, and also teardown after a `next`-hook throw). `finalize` runs on every teardown that reaches the operator subscriber. `unsubscribe` and `finalize` are not notifications. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/tap.ts` lines 167–215. The three-callback overload is `@deprecated` and scheduled for removal in v8 (lines 75–80). The partial-observer overload is not deprecated.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `tap()`, `tap(partialObserver)`, `tap(next)`, and deprecated `tap(next, error, complete)`. Lines 74–80 and 167–215. `MonoTypeOperatorFunction<T>`. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | Mirror notifications, after the corresponding hook when one was supplied. Hooks are optional (`?.`). See the opening paragraph for `isUnsub`. |
| Model kind | Symbolic payloads. Control is finite aside from the mirrored values. Two installation modes: identity bypass, or the observer machine. |
| Parameter domain | Either a partial `TapObserver` as the only argument, or a next function/null plus optional error and complete handlers. If the second or third argument is truthy, the first argument is stored as `next` even when it is an object (lines 175–178). That object is later called as a function. The documented use is not that mix. |
| Payload/error domain | Forwarded next payloads are the same references. Errors are source errors, or exceptions thrown by `subscribe`, `next`, `error`, or `complete` hooks. |
| Subscription boundary | Observer mode: one `operate` closure per subscription holds `isUnsub`. One source subscription. No inners. Identity mode: no extra subscription layer. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | All hooks are synchronous and may be omitted. `next` is `(value) => void`. `error` is `(err) => void`. `complete`, `subscribe`, `unsubscribe`, and `finalize` take no arguments. |
| Cleanup assumptions | `onFinalize` is the fifth `createOperatorSubscriber` argument (lines 202–207), invoked from `OperatorSubscriber.unsubscribe` after `super.unsubscribe` if the operator subscriber was not already closed (`OperatorSubscriber.ts` lines 104–110). |
| Explicit exclusions | Ordinary model: each input to quiescence. A hook that re-enters the source or unsubscribes is excluded, except for the teardown the operator itself performs. Throws from `unsubscribe` or `finalize` are not converted into next/error/complete by `tap`; `unsubscribe` runs first, so its throw skips `finalize` (lines 203–206). Those throws escape `unsubscribe` and are collected by `Subscription.unsubscribe` as `UnsubscriptionError` when a parent finalizer loop is running (`Subscription.ts` lines 75–93). That host error is not an observable notification and is not fully modeled. `useDeprecatedSynchronousErrorHandling` is off. Terminal late events are silent by convention. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

Identity selection happens when `tap` is called, before `s₀` of a subscription. If the returned function is `identity`, subscription does not enter this machine.

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `bypassed` | `tap` returned `identity`. | none | falsy observer and no error/complete args (lines 211–214) | subscribing the result is subscribing the source; no tap hooks exist |
| `idle` | Observer operator created, not subscribed. | the partial observer | a truthy `tapObserver` | `subscribe` will call the subscribe hook |
| `active` | Source subscribed, `isUnsub === true`. | `isUnsub` | a subscribe hook that returned | explicit cancel runs the unsubscribe hook; a source error will not |
| `completed` | Destination completed. | none | source complete whose complete hook returned | unsubscribe hook did not run; finalize did |
| `errored(e)` | Destination errored. | `e` | source error, or a hook throw | which hook ran distinguishes the cause |
| `cancelled` | Consumer unsubscribed. | none | `cancel` from `active` | no destination terminal; unsubscribe hook and finalize ran if they did not throw |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 182–209, or no-op installation in identity mode. |
| Source next | yes | Lines 188–191. |
| Source error | yes | Lines 197–201. Distinct from a next-hook throw. |
| Source completion | yes | Lines 192–196. |
| Cancellation `cancel` | yes | `onFinalize` with `isUnsub` still true. |
| Inner notifications | no | No inner subscribe. |
| Time | no | No clock. |
| User callback outcomes | yes | Each of `subscribe`, `next`, `error`, and `complete` may return or throw. `unsubscribe` and `finalize` are lifecycle; their throws are excluded as notifications. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: in order,
      hook(subscribe|next|error|complete|unsubscribe|finalize)
      | subscribe(source) | unsubscribe(source)
}
```

An unordered record is not enough. Several inputs run a hook and then a notification, or a notification and then `finalize`, and that order is observable. Identity mode emits whatever the source emits and has no tap effects.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | call `tap` | arguments | `isFunction(observerOrNext)` is false and `error` and `complete` are falsy and the remaining value is falsy (lines 175–181, 211–214) | none | return `identity`; no `operate` | `bypassed` | empty | `pipe` result `=== source` | S01 |
| T02 | `idle` | `subscribe` | `subscribe` hook missing or returns | none | call `subscribe` hook, set `isUnsub = true`, `subscribe(source)` (lines 183–185) | `active` | observer-form `tap` | a next forwards the same value | S02 |
| T03 | `idle` | `subscribe` | `subscribe` hook throws `e` | `error(e)` via `operate`’s catch (`lift.ts` lines 22–27) | `source.subscribe` is not called; `onFinalize` is not installed, so neither `unsubscribe` nor `finalize` runs | `errored(e)` | observer-form `tap` | no source effect | S03 |
| T04 | `active` | source `next(v)` | `next` hook missing or returns | `next(v)` same reference, after the hook | stay subscribed; `isUnsub` stays true | `active` | T02 | source complete still completes | S02 |
| T05 | `active` | source `next(v)` | `next` hook throws `e` | `error(e)`; no `next(v)`; `error` hook is not called | `isUnsub` stays true, so teardown runs `unsubscribe` hook then `finalize` (`OperatorSubscriber._next` catch, lines 67–74 of `OperatorSubscriber.ts`, then tap lines 202–206) | `errored(e)` | T02 | silence | S04 |
| T06 | `active` | source `error(e)` | `error` hook missing or returns | `error(e)` after the hook | `isUnsub = false` before the hook; teardown runs `finalize` and not `unsubscribe` | `errored(e)` | T02 | silence | S05 |
| T07 | `active` | source `error(eSrc)` | `error` hook throws `e` | `error(e)`, not `error(eSrc)` | `isUnsub` already false; `finalize` runs; `unsubscribe` hook does not | `errored(e)` | T02 | silence | S06 |
| T08 | `active` | source `complete` | `complete` hook missing or returns | `complete` after the hook | `isUnsub = false`; `finalize` runs; `unsubscribe` hook does not | `completed` | T02 | silence | S07 |
| T09 | `active` | source `complete` | `complete` hook throws `e` | `error(e)`; no `complete` | `isUnsub` already false; `finalize` runs; `unsubscribe` hook does not | `errored(e)` | T02 | silence | S08 |
| T10 | `active` | `cancel` | open | none | `isUnsub` still true: `unsubscribe` hook, then `finalize`; source unsubscribed | `cancelled` | T02 | no `complete` | S09 |
| T11 | terminal | late source events | stopped | none | `onFinalize` does not run again (`OperatorSubscriber.unsubscribe` uses the previous `closed` bit) | same | a terminal row | convention, not a legal trace | S04 |

Hook order relative to the consumer: on T08 the consumer’s `complete` runs inside `subscriber.complete()`, and `finalize` runs when that complete unsubscribes the child. So the order is tap `complete` hook, consumer `complete`, tap `finalize`. On T06 the order is tap `error` hook, consumer `error`, tap `finalize`. On T05 the order is consumer `error` (tap `error` hook skipped), tap `unsubscribe`, tap `finalize`.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | T04 forwards the same value after `next`. Identity mode forwards the source unchanged because the source is returned. |
| one terminal | yes | T03, T05, T06, T07, T08, T09. T10 is not a terminal notification. |
| silence after terminal | yes | T11. |
| cancel does not complete | yes | T10. |
| upstream/inner lifetime | yes | Observer mode: one source subscription from T02 until a later terminal or cancel. T03 does not subscribe. Identity mode: the source’s own subscription only. No inners. |
| cleanup once | yes | `isUnsub` and `OperatorSubscriber.unsubscribe`’s `closed` check. `finalize` is not paired with a second call on the `finally` of a custom error handler once the child is already closed. |
| per-subscription state | yes | `isUnsub` is inside `operate` (line 184). The observer object is shared across subscribers; the flag is not. |
| empty/error/silence | yes | Empty source in observer mode: T02 then T08, `complete`, `subscribe` and `complete` and `finalize` hooks, no `unsubscribe` hook. Source error: T06. Identity empty source: the source’s own complete, no hooks (S01). Never terminates: stays `active`, no finalize yet. |
| pending buffer on terminal | no | Nothing is buffered. A next whose hook throws is dropped (T05). |
| callback throw/reenter/cancel | yes | T03, T05, T07, T09. Next-hook throw is not a source error and does not call the error hook. Reentrancy excluded. `unsubscribe`/`finalize` throws excluded as notifications. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Identity bypass

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01 |
| Starting state | not called |
| Reset/fixture | `tap()`, and separately `tap(null, null, null)` |
| State-reaching prefix | empty |
| Target event | call `tap` and subscribe the piped result to a source that emits `v` and completes |
| Expected notifications | `next(v)`, `complete` |
| Expected lifecycle observations | no subscribe/next/error/complete/unsubscribe/finalize hook runs; the function returned by `tap()` is `identity`, so the piped observable is the source |
| Distinguishing suffix | none |
| Expected final state | `bypassed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | reference equality with the source and zero hook calls |
| Oracle source | `source characterization` |

### S02 Next mirror

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T02, T04 |
| Starting state | `idle` |
| Reset/fixture | `tap({ subscribe, next })`; source emits `v` |
| State-reaching prefix | call `tap` |
| Target event | `subscribe` and source `next(v)` |
| Expected notifications | `next(v)` |
| Expected lifecycle observations | `subscribe` hook once, before the source is subscribed; `next` hook with `v` before the consumer sees `v`; `isUnsub` still true |
| Distinguishing suffix | consumer unsubscribe runs the unsubscribe hook (T10), which would not run after a source complete |
| Expected final state | `active` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | hook order and payload identity |
| Oracle source | `contract` |

### S03 subscribe hook throws

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03 |
| Starting state | `idle` |
| Reset/fixture | `subscribe` hook throws `e`; `finalize` and `unsubscribe` hooks record calls |
| State-reaching prefix | `tap({subscribe, finalize, unsubscribe})` |
| Target event | consumer `subscribe` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source not subscribed; `finalize` call count 0; `unsubscribe` call count 0 |
| Distinguishing suffix | none |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error and hooks absent |
| Oracle source | `source characterization` |

### S04 next hook throws

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05, T11 |
| Starting state | `active` |
| Reset/fixture | `next` throws `e`; `error`, `unsubscribe`, and `finalize` hooks record calls |
| State-reaching prefix | T02 |
| Target event | source `next(v)` |
| Expected notifications | `error(e)`; no `next(v)` |
| Expected lifecycle observations | `error` hook call count 0; then `unsubscribe` hook; then `finalize`; source unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | which hooks run |
| Oracle source | `source characterization` |

### S05 Source error runs error and finalize only

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `active` |
| Reset/fixture | source `error(e)`; hooks record calls |
| State-reaching prefix | T02 |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | order: `error` hook, consumer `error`, `finalize`. `unsubscribe` hook call count 0 |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | hook order and error identity |
| Oracle source | `source characterization` |

### S06 error hook replaces the error

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T07 |
| Starting state | `active` |
| Reset/fixture | source `error(eSrc)`; `error` hook throws `e` |
| State-reaching prefix | T02 |
| Target event | source `error(eSrc)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | `unsubscribe` hook not called; `finalize` called; source unsubscribed |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | thrown error wins over `eSrc` |
| Oracle source | `source characterization` |

### S07 Complete hooks

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T08 |
| Starting state | `active` |
| Reset/fixture | source completes with no values; `complete`, `unsubscribe`, `finalize` record calls |
| State-reaching prefix | T02 |
| Target event | source `complete` |
| Expected notifications | `complete` |
| Expected lifecycle observations | order: `complete` hook, consumer `complete`, `finalize`. `unsubscribe` call count 0 |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | hook order |
| Oracle source | `source characterization` |

### S08 complete hook throws

| Field | Content |
| --- | --- |
| Test ID | S08 |
| Covered row IDs | T09 |
| Starting state | `active` |
| Reset/fixture | `complete` hook throws `e` |
| State-reaching prefix | T02 |
| Target event | source `complete` |
| Expected notifications | `error(e)`; no `complete` |
| Expected lifecycle observations | `unsubscribe` hook not called; `finalize` called |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error instead of complete |
| Oracle source | `source characterization` |

### S09 Explicit cancel

| Field | Content |
| --- | --- |
| Test ID | S09 |
| Covered row IDs | T10 |
| Starting state | `active` |
| Reset/fixture | live source; `unsubscribe` and `finalize` record calls |
| State-reaching prefix | T02 |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | `unsubscribe` hook then `finalize`; source unsubscribed |
| Distinguishing suffix | no `complete` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal and presence of both hooks |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 11 section C rows (T01–T11).

Section E references every row. Specified coverage = 11/11.

Execution: not executed.

Evidence: `src/internal/operators/tap.ts` lines 167–215, `OperatorSubscriber.ts` lines 67–110, and `lift.ts` lines 22–27. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: the flag `isUnsub` is the whole policy for `unsubscribe` versus `finalize`, and each handler is a straight-line optional call before the matching destination signal.

Known limitations: a throw from `next` does call `unsubscribe`, because it never clears `isUnsub` and never enters the source-error handler. That is stricter than a reading of the `TapObserver` comment that “unsubscribe is not invoked on error” (lines 59–63) if “error” is taken to include callback failures. `unsubscribe`/`finalize` throws are excluded as notifications. Mixing an observer object with a separate error argument is outside the intended parameter domain. Reentrancy is excluded.

Contract vs version characterization: “mirror the source; a synchronous handler error is emitted as an error” is the JSDoc (lines 97–98). Which lifecycle hooks run for each cause is source characterization of lines 183–207.

Tests still required: S01–S09. In particular S04 must not be collapsed into S05.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
