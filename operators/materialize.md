# `materialize`

`materialize` turns every source notification into a `next` of a `Notification` instance, and the output then completes. A source `next(v)` becomes `next(Notification.createNext(v))`. A source `error(e)` becomes `next(Notification.createError(e))` and then `complete`; the destination does not error. A source `complete` becomes `next(Notification.createComplete())` and then `complete`. Cancel emits nothing. There is no user callback. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/materialize.ts` lines 54–73. Not deprecated. The factories return `Notification` class instances (`src/internal/Notification.ts` lines 194–222), not plain objects. `createComplete` returns one shared singleton (lines 183 and 220–222).

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `materialize()`. `OperatorFunction<T, Notification<T> & ObservableNotification<T>>`. Lines 54–73. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. Next notifications have `kind: 'N'`, `value`, `hasValue: true`. Error notifications have `kind: 'E'`, `value: undefined`, `error`, `hasValue: false`. The complete notification has `kind: 'C'`, `hasValue: false`, and is the module singleton. |
| Model kind | Symbolic. Notification payloads are uninterpreted. The three kinds are a finite tag set. |
| Parameter domain | No parameters. |
| Payload/error domain | Output payloads are `Notification` instances. This operator does not produce an `error` notification on the destination for a source error. |
| Subscription boundary | No per-value local state. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. Output order is source order, with the synthetic `complete` immediately after a materialized error or complete. |
| Callback assumptions | No user callback. The factories do not throw for ordinary values and errors. |
| Cleanup assumptions | Custom `onComplete` and `onError` (`materialize.ts` lines 62–69). `OperatorSubscriber` runs those handlers and then unsubscribes in `finally` (`OperatorSubscriber.ts` lines 76–100). `subscriber.complete()` also unsubscribes the destination, which unsubscribes this child. |
| Explicit exclusions | Ordinary model, no reentrancy. Mutating the shared complete singleton is excluded. Terminal late events are silent by convention: after the operator completes the destination, a further call is a stopped-subscriber no-op under default config. `Notification.createNext` / `createError` / `createComplete` are marked deprecated in favor of POJOs (`Notification.ts` lines 189–219) but this operator still calls them. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Not subscribed. | none | empty | `subscribe` emits nothing |
| `active` | Mirroring notifications as `next`. | none | T01 | a source error completes the destination instead of erroring it |
| `completed` | Destination completed, either after a complete-notification or after an error-notification. | none | T03 or T04 | silence; the two prefixes are distinguished by the last `next` kind |
| `cancelled` | Unsubscribed with no notification. | none | `cancel` | no complete-notification |

There is no `errored` state. Source error does not take the destination to an error terminal.

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Lines 56–71. |
| Source next | yes | `createNext` (lines 59–61). |
| Source error | yes | `createError` then `complete` (lines 66–69). This input is not an output error. |
| Source completion | yes | `createComplete` then `complete` (lines 62–65). |
| Cancellation `cancel` | yes | No notification. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | no | No user function. |

### Γ

```text
record {
  trace: ordered list of next(Notification) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

A record of unordered notifications is not enough. T03 and T04 each emit `next` and then `complete`, in that order, and never `error`. T02 emits a single `next`.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)` | `active` | empty | a source next yields kind `N` | S01 |
| T02 | `active` | source `next(v)` | any `v` | `next(N)` where `N.kind === 'N'`, `N.value === v`, `N.hasValue === true`, `N` is a new `Notification` | stay subscribed | `active` | T01 | another next allocates another instance | S01 |
| T03 | `active` | source `error(e)` | any `e` | ordered `next(E)`, `complete`. `E.kind === 'E'`, `E.error === e`, `E.value === undefined`, `E.hasValue === false`. No destination `error`. | unsubscribe | `completed` | T01, optional T02 | silence | S02 |
| T04 | `active` | source `complete` | any | ordered `next(C)`, `complete`. `C` is `Notification.completeNotification` (`kind === 'C'`, `hasValue === false`) | unsubscribe | `completed` | T01, optional T02 | silence; a second `materialize` complete is the same `C` reference | S03 |
| T05 | `active` | `cancel` | open | none | unsubscribe | `cancelled` | T01 | no kind-`C` next and no `complete` | S04 |
| T06 | `completed` or `cancelled` | late source events | stopped | none | none | same | T03, T04, or T05 | convention, not a legal trace | S02 |
| T07 | `active` | user callback | inapplicable | none | none | unchanged | — | no user function is registered | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Source nexts stay in order as kind `N`. A terminal source signal is one kind `E` or kind `C` next and then destination `complete` (lines 62–69). |
| one terminal | yes | T03 and T04 produce one `complete`. They do not also produce `error`. |
| silence after terminal | yes | T06. |
| cancel does not complete | yes | T05. Cancel also does not emit a complete-notification. |
| upstream/inner lifetime | yes | One source subscription until T03, T04, or T05. No inners. |
| cleanup once | yes | Custom handler `finally` and destination `complete` both unsubscribe; `Subscription.closed` makes the second a no-op. |
| per-subscription state | yes | No mutable cell. The complete singleton is process-wide, not per subscription (`Notification.ts` line 183). |
| empty/error/silence | yes | Empty source: T04, one kind-`C` next and `complete` (S03). Source error: T03, kind `E` then `complete`, not `error` (S02). Open source: only kind `N` nexts. |
| pending buffer on terminal | no | Nothing is buffered. The terminal source signal itself is converted, not queued. |
| callback throw/reenter/cancel | no user callback | T07 inapplicable. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Next values become kind N

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | source emits `a` then `b` |
| State-reaching prefix | empty |
| Target event | `subscribe` and both nexts |
| Expected notifications | `next(Na)`, `next(Nb)` with distinct instances, `kind === 'N'`, values `a` and `b`, `hasValue === true` |
| Expected lifecycle observations | still subscribed |
| Distinguishing suffix | source `complete` emits kind `C` and then `complete` |
| Expected final state | `active` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `Notification` shape and instance inequality |
| Oracle source | `source characterization` |

### S02 Source error becomes next then complete

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T03, T06 |
| Starting state | `active` |
| Reset/fixture | source `error(e)` |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `next(E)`, `complete`. No `error`. `E.kind === 'E'` and `E.error === e`. |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | silence; a late source `complete` is not a second terminal |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered trace and absence of destination `error` |
| Oracle source | `contract` |

### S03 Source complete becomes kind C then complete

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T04 |
| Starting state | `active` |
| Reset/fixture | empty source, and a second empty `materialize()` subscription |
| State-reaching prefix | `subscribe` |
| Target event | source `complete` |
| Expected notifications | `next(C)`, `complete`, with `C.kind === 'C'` |
| Expected lifecycle observations | both subscriptions observe the same `C` reference (`createComplete` singleton) |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | ordered trace and singleton identity |
| Oracle source | `source characterization` |

### S04 Cancel

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no kind-`C` notification |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 7 section C rows (T01–T07).

Section E references T01, T02, T03, T04, T05, T06. T07 is an explicit inapplicable callback row. Specified coverage of applicable rows = 6/6.

Execution: not executed.

Evidence: `src/internal/operators/materialize.ts` lines 54–73 and `src/internal/Notification.ts` lines 64–66 and 183–222. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: both terminal source signals are rewritten in the custom handlers, and nexts are a direct `createNext`. The output alphabet has no `error`.

Known limitations: the complete notification is a shared singleton. `hasValue` is `kind === 'N'` (`Notification.ts` lines 64–66). Deprecated factory methods are what 7.8.2 actually calls. Reentrancy is excluded.

Contract vs version characterization: JSDoc lines 17–22 state that error and complete are wrapped in `next` and that the output then completes. The class fields and the singleton are source characterization, not POJO factories.

Tests still required: S01–S04, including `hasValue` and the shared complete instance.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
