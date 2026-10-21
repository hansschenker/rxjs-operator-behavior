# `dematerialize`

`dematerialize` unwraps source `next` payloads that look like notifications. A next whose `kind` is the string `'N'` becomes destination `next(value)`. A next whose `kind` is `'E'` becomes destination `error(error)` and does not complete. Any other string `kind`, including `'C'`, becomes destination `complete`. A missing or non-string `kind`, or a `null`/`undefined` payload, throws and becomes destination `error` of that exception (`TypeError`), which is a callback failure, not a materialized error. A source `error` that is not wrapped in a next is forwarded as destination `error` and is not turned into a notification. A source `complete` is forwarded as destination `complete` with no extra next. RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Full implementation: `src/internal/operators/dematerialize.ts` lines 54–58, delegating each next to `observeNotification` (`src/internal/Notification.ts` lines 232–237). Not deprecated. Both `Notification` instances and plain objects work, because only `kind`, `value`, and `error` are read.

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `dematerialize()`. Lines 54–58. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | As in the opening paragraph. `observeNotification` does not require a `Notification` instance and does not consult `hasValue`. |
| Model kind | Symbolic payloads with a finite kind tag. An unknown string kind is not rejected; it completes. |
| Parameter domain | No parameters. The source is assumed to emit notification-shaped values, but the implementation does not check that ahead of time. |
| Payload/error domain | Kind `'N'` emits `value` (which may be `undefined`). Kind `'E'` errors with the `error` property (which may be `undefined`). Other strings complete. A non-string `kind` produces `TypeError('Invalid notification, missing "kind"')` if the object could be destructured (`Notification.ts` lines 233–236). |
| Subscription boundary | No local cells. One source subscription. No inners. |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | The only “callback” is `observeNotification` inside `onNext`. A throw there is caught by `OperatorSubscriber._next` (`OperatorSubscriber.ts` lines 67–74) and sent to `destination.error`. There is no custom `onError` or `onComplete`, so a real source error and a real source complete use the default forwarders. |
| Cleanup assumptions | Destination `error` or `complete` unsubscribes the child operator subscriber and therefore the source. |
| Explicit exclusions | Ordinary model, no reentrancy. After a kind `'E'` next, `materialize` itself will still call `complete` on its destination; if that destination is this operator, the subscriber is already stopped and the late `complete` is the silence convention, not a second terminal. `observeNotification`’s non-`'N'` non-`'E'` branch calls `complete` for every other string, which is broader than the three documented kinds. Terminal late events are not legal traces. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Not subscribed. | none | empty | `subscribe` emits nothing |
| `active` | Waiting for a source next or a real source terminal. | none | T01 | kind `'N'` stays here; kind `'E'` and kind `'C'` leave |
| `completed` | Destination completed because of kind `'C'` (or any other string kind) or because the source completed. | none | T04 or T07 | silence |
| `errored(e)` | Destination errored. | `e` | kind `'E'`, a throw, or a source error | the three causes are distinguished by `e` and by whether a source `error` was the input |
| `cancelled` | Unsubscribed. | none | `cancel` | no synthesized complete |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Line 56. |
| Source next | yes | Passed to `observeNotification`. The kind splits this input. |
| Source error | yes | Default `_error`. Not interpreted as a notification. |
| Source completion | yes | Default `_complete`. Not preceded by a synthetic next. |
| Cancellation `cancel` | yes | Child teardown. |
| Inner notifications | no | None. |
| Time | no | No clock. |
| User callback outcomes | yes | `observeNotification` may throw `TypeError` before it notifies. That throw is not a kind `'E'` notification. A well-formed notification does not throw. |

### Γ

```text
record {
  trace: ordered list of next(value) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source)
}
```

Each input emits at most one notification, so a one-notification record is enough. The important distinction is which tag is chosen, not an order of several tags from one input.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `idle` | `subscribe` | any | none | `subscribe(source)` | `active` | empty | a kind `'N'` next emits the value | S01 |
| T02 | `active` | source `next(note)` | `typeof note.kind === 'string'` and `kind === 'N'` | `next(note.value)` | stay subscribed | `active` | T01 | a later kind `'C'` completes without emitting `value` again | S01 |
| T03 | `active` | source `next(note)` | `kind === 'E'` | `error(note.error)` | unsubscribe. This is an output error caused by a source next, not by a source error. | `errored(note.error)` | T01 | silence; not `complete` | S02 |
| T04 | `active` | source `next(note)` | `typeof kind === 'string'` and `kind` is neither `'N'` nor `'E'` (includes `'C'`) | `complete` | unsubscribe | `completed` | T01 | silence | S03 |
| T05 | `active` | source `next(note)` | `note` is `null`/`undefined`, or `kind` is not a string | `error(TypeError)` from the throw in `observeNotification` or from reading `.kind` | unsubscribe | `errored(TypeError)` | T01 | silence; this is not `error(undefined)` from a kind `'E'` note | S04 |
| T06 | `active` | source `error(e)` | the source itself errors | `error(e)` | default `_error` unsubscribes | `errored(e)` | T01 | silence | S05 |
| T07 | `active` | source `complete` | the source itself completes | `complete` | default `_complete` unsubscribes | `completed` | T01 | silence; no preceding kind-`C` next from this operator | S06 |
| T08 | `active` | `cancel` | open | none | unsubscribe | `cancelled` | T01 | no `complete` | S07 |
| T09 | terminal | late source events | stopped | none | none | same | a terminal row | convention, not a legal trace | S02 |

`observeNotification` (`Notification.ts` lines 232–237):

```ts
const { kind, value, error } = notification as any;
if (typeof kind !== 'string') {
  throw new TypeError('Invalid notification, missing "kind"');
}
kind === 'N' ? observer.next?.(value!) : kind === 'E' ? observer.error?.(error) : observer.complete?.();
```

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | Kind `'N'` nexts stay in source order and carry `value`. Kind `'E'` stops the sequence with that `error`. |
| one terminal | yes | T03, T04, T05, T06, T07 each produce one terminal. |
| silence after terminal | yes | T09. A following source `complete` after T03 is not delivered. |
| cancel does not complete | yes | T08. |
| upstream/inner lifetime | yes | One source subscription until a terminal or cancel. No inners. |
| cleanup once | yes | Destination terminal unsubscribes the child once. |
| per-subscription state | yes | No shared mutable cell. |
| empty/error/silence | yes | Source that only completes: T07, bare `complete` (S06). Source error: T06, still an error (S05). Kind `'E'` next: T03, also an error, but the input was a next. Open stream of kind `'N'`: no terminal. |
| pending buffer on terminal | no | Nothing is stored. |
| callback throw/reenter/cancel | yes | T05 is the throw path and is distinct from T03 and T06. Reentrancy excluded. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Kind N

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | source nexts `{kind: 'N', value: 'A'}` then a `Notification` created with kind `'N'` and value `'B'` |
| State-reaching prefix | empty |
| Target event | `subscribe` and both nexts |
| Expected notifications | `next('A')`, `next('B')` |
| Expected lifecycle observations | still subscribed; both a POJO and a `Notification` instance are accepted |
| Distinguishing suffix | a kind `'C'` next completes |
| Expected final state | `active` before that suffix |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payloads and continued subscription |
| Oracle source | `source characterization` |

### S02 Kind E is an output error

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T03, T09 |
| Starting state | `active` |
| Reset/fixture | source `next({kind: 'E', error: e})` |
| State-reaching prefix | `subscribe` |
| Target event | that next |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source unsubscribed; destination did not receive `complete` |
| Distinguishing suffix | a late source `complete` is silent |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `error` rather than `next` or `complete` |
| Oracle source | `contract` |

### S03 Kind C and other strings complete

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T04 |
| Starting state | `active` |
| Reset/fixture | one subscription receives `{kind: 'C'}`; a separate subscription receives `{kind: 'X'}` |
| State-reaching prefix | `subscribe` |
| Target event | that next |
| Expected notifications | `complete` in both cases |
| Expected lifecycle observations | unsubscribed; the `'X'` string is not an error in this version |
| Distinguishing suffix | silence |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `complete` for both strings |
| Oracle source | `source characterization` |

### S04 Invalid notification throws

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T05 |
| Starting state | `active` |
| Reset/fixture | source `next({kind: 1})`, and a separate case `next(null)` |
| State-reaching prefix | `subscribe` |
| Target event | that next |
| Expected notifications | `error(TypeError)`. For a non-string `kind`, the message is `Invalid notification, missing "kind"`. For `null`, the throw is from reading `kind`. |
| Expected lifecycle observations | unsubscribed; no `next` |
| Distinguishing suffix | silence |
| Expected final state | `errored(TypeError)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `TypeError`, not a kind-`E` payload |
| Oracle source | `source characterization` |

### S05 Real source error stays an error

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T06 |
| Starting state | `active` |
| Reset/fixture | source `error(e)` with no next |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | `observeNotification` was not called |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error payload is the source error |
| Oracle source | `source characterization` |

### S06 Real source complete

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T07 |
| Starting state | `active` |
| Reset/fixture | source completes with no next |
| State-reaching prefix | `subscribe` |
| Target event | source `complete` |
| Expected notifications | `complete` only |
| Expected lifecycle observations | no synthesized notification next |
| Distinguishing suffix | none |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | bare `complete` |
| Oracle source | `source characterization` |

### S07 Cancel

| Field | Content |
| --- | --- |
| Test ID | S07 |
| Covered row IDs | T08 |
| Starting state | `active` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no `complete` |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 9 section C rows (T01–T09).

Section E references every row. Specified coverage = 9/9.

Execution: not executed.

Evidence: `src/internal/operators/dematerialize.ts` lines 54–58 and `src/internal/Notification.ts` lines 232–237. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: unwrapping is a single call to `observeNotification`, and source terminals use the default operator-subscriber paths, so they stay terminals.

Known limitations: any non-`'N'` non-`'E'` string completes, including kinds the type `ObservableNotification` does not list. `null` throws a different `TypeError` than a bad `kind`. Reentrancy is excluded. A `materialize`+`dematerialize` chain’s extra `complete` after an error notification hits a stopped subscriber and is silent under default config.

Contract vs version characterization: JSDoc lines 15–19 describe unwrapping next, error, and complete notifications and assume the source does not itself error. Forwarding a real source error, the `TypeError` on a bad `kind`, and the treatment of unknown string kinds are source characterization of `observeNotification`.

Tests still required: S01–S07, including POJO versus `Notification` instances and kind `'X'`.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
