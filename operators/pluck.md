# `pluck`

`pluck(...properties)` maps each source value to the nested property at that path. A missing step, a `null` or `undefined` intermediate, or a final `undefined` becomes `next(undefined)` and is not an error. A throw while reading the path (for example a getter) is a `map` callback error: destination `error` and unsubscribe. The operator is a wrapper around `map` (`src/internal/operators/pluck.ts` lines 89–106). RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. Every overload and the implementation JSDoc are `@deprecated`; the documented replacement is `map` with optional chaining, and the operator is scheduled for removal in v8 (`pluck.ts` lines 5–52 and 87). Calling `pluck()` with an empty list throws synchronously and does not return an operator (lines 90–93).

## A. Identity, contract, and scope

| Field | Content |
| --- | --- |
| Operator / overload | `pluck(k1, ...)`, from one key up through a rest overload. Implementation lines 89–106. |
| Package version / source commit | 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`. |
| Intended behavior | If `properties.length === 0`, throw `Error('list of properties cannot be empty.')` at the call to `pluck`. Otherwise return `map` of a walker that starts at the source value and, for each key, reads `current?.[key]`. If that read is `undefined`, the walker returns `undefined` immediately. Otherwise it continues. The final `current` is the emission, which may be `null`, `0`, `false`, or `''`. |
| Model kind | Symbolic. Paths and object graphs are uninterpreted except for the `undefined` / throw distinction. |
| Parameter domain | At least one property key. Keys may be `string`, `number`, or `symbol` (implementation rest type, line 89). The empty list is outside the operator domain; it fails before subscription. |
| Payload/error domain | Output is the resolved value or `undefined`. A thrown getter or proxy is an error payload. Source errors pass through. |
| Subscription boundary | After a successful `pluck(...)` call, subscription state is exactly `map`’s per-subscription index. No extra state is kept in `pluck`. The key list is closed over once (`length` at line 90). |
| Scheduler and tie ordering | No scheduler. |
| Callback assumptions | The walker is synchronous. Property getters run inside the `map` project. `this` is not bound by `pluck`. |
| Cleanup assumptions | Inherited from `map` and `OperatorSubscriber`. |
| Explicit exclusions | Ordinary model, no reentrancy. Mutating the key list after the call is excluded (`length` and the array closed over by the project are the call-time array). Terminal late events are silent by convention. The deprecation text `x?.foo?.bar` is the suggested migration, not a second implementation; differences are noted under T03. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = idle
```

`idle` is only reached when `pluck` returned an operator. The empty-list throw is T00 and has no subscription state.

### S

| State | Meaning | Stored data | Reachability prefix | Distinguishing future behavior |
| --- | --- | --- | --- | --- |
| `idle` | Operator function returned. | key list of length ≥ 1 | `pluck(keys)` with non-empty keys | `subscribe` starts `map`. |
| `active(n)` | `map` subscribed; `n` values already walked. | `map` index `n` | `subscribe` and `n` walks | next walk uses the same key list |
| `completed` | Source completed and destination completed. | none | source `complete` | silence |
| `errored(e)` | Source error or walker throw. | `e` | T04 or T05 | silence; a walker `TypeError` is distinguishable from a prior source error |
| `cancelled` | Unsubscribed with no terminal. | none | `cancel` | no `complete` |

### Σ

| Input | Included | Reason |
| --- | --- | --- |
| Initialization `subscribe` | yes | Only after T00 did not throw. `map` subscribes. |
| Source next | yes | Runs the walker. |
| Source error | yes | `map` default forward. |
| Source completion | yes | `map` default forward. |
| Cancellation `cancel` | yes | Same as `map`. |
| Inner notifications | no | No inner observable. |
| Time | no | No clock. |
| User callback outcomes | yes | The walker can return a value, return `undefined`, or throw. There is no separate user predicate. Empty-list failure is a call-time exception, not a notification. |

### Γ

```text
record {
  trace: ordered list of next(payload) | error(err) | complete,
  effects: subscribe(source) | unsubscribe(source),
  callTime: throw(Error) | return(OperatorFunction)
}
```

Subscription inputs emit at most one notification, so a one-notification record is enough there. The call-time result is not a notification on a subscriber; it is a separate effect of applying `pluck`.

## C. Transition obligations

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T00 | before return | call `pluck()` | `properties.length === 0` (lines 91–93) | none (no subscriber) | no subscribe | no operator; synchronous `Error('list of properties cannot be empty.')` | empty | no observable to subscribe | S01 |
| T01 | `idle` | `subscribe` | keys non-empty | none | `subscribe(source)` | `active(0)` | `pluck(keys)` | a next walks the path | S02 |
| T02 | `active(n)` | source `next(x)` | every segment `typeof p !== 'undefined'` | `next(final)` | stay subscribed; index `n+1` | `active(n+1)` | `subscribe` | a missing path on a later value yields `undefined` rather than `error` | S02 |
| T03 | `active(n)` | source `next(x)` | some segment reads `undefined`, including a missing property, an explicit `undefined`, or the next key after a `null` intermediate (`current?.[key]`, lines 97–102) | `next(undefined)` | stay subscribed; index `n+1` | `active(n+1)` | `subscribe` | source `complete` still completes normally | S03 |
| T04 | `active(n)` | source `next(x)` | a property access throws `e` | `error(e)`; no `next` | `map` callback path unsubscribes | `errored(e)` | `subscribe` | silence | S04 |
| T05 | `active(n)` | source `error(e)` | walker not running | `error(e)` | unsubscribe | `errored(e)` | `subscribe` | silence | S05 |
| T06 | `active(n)` | source `complete` | any | `complete` | unsubscribe | `completed` | `subscribe` | silence | S03 |
| T07 | `active(n)` | `cancel` | open | none | unsubscribe | `cancelled` | `subscribe` | no `complete` | S06 |
| T08 | terminal | late source events | stopped | none | none | same | terminal row | convention, not a legal trace | S04 |

A final segment whose value is `null` takes T02, not T03: `typeof null !== 'undefined'` (`pluck.ts` lines 98–104). A `null` intermediate takes T03 on the following key because `null?.[key]` is `undefined`. That matches optional chaining for the next read; `pluck` does not throw on `null`. An explicit `undefined` segment stops the walk even if a later key might have been meaningful on some other object. This is the same observable result as stopping, not a throw.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| order/payloads | yes | T02, T03. One output next per source next, same order. |
| one terminal | yes | T04, T05, or T06. |
| silence after terminal | yes | T08. |
| cancel does not complete | yes | T07. |
| upstream/inner lifetime | yes | One upstream after T01. No inners. T00 never subscribes. |
| cleanup once | yes | Inherited from `map`. |
| per-subscription state | yes | Only `map`’s index. The key list is per operator call, shared by subscribers of that result. |
| empty/error/silence | yes | Empty source: T01, T06, no `next`. Source error: T05. Unresolved path is `next(undefined)`, not an error (T03). |
| pending buffer on terminal | no | No buffer. |
| callback throw/reenter/cancel | yes | T04 is the walker throw. Reentrancy excluded. T00 is not a callback throw on a subscriber. |
| equal-time/timers | no | No scheduler. |

## E. Scenario specification

### S01 Empty key list

| Field | Content |
| --- | --- |
| Test ID | S01 |
| Covered row IDs | T00 |
| Starting state | not yet called |
| Reset/fixture | `pluck()` with no arguments |
| State-reaching prefix | empty |
| Target event | call `pluck` |
| Expected notifications | none |
| Expected lifecycle observations | no subscription; synchronous exception whose message is `list of properties cannot be empty.` |
| Distinguishing suffix | there is no operator function to subscribe |
| Expected final state | no machine |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | synchronous throw |
| Oracle source | `source characterization` |

### S02 Resolved path

| Field | Content |
| --- | --- |
| Test ID | S02 |
| Covered row IDs | T01, T02 |
| Starting state | `idle` |
| Reset/fixture | `pluck('a', 'b')`, source value `{a: {b: 1}}` |
| State-reaching prefix | `pluck('a','b')` |
| Target event | `subscribe` and source `next` of that object |
| Expected notifications | `next(1)` |
| Expected lifecycle observations | source subscribed |
| Distinguishing suffix | source `complete` → `complete` |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | payload equality |
| Oracle source | `contract` |

### S03 Missing property is undefined

| Field | Content |
| --- | --- |
| Test ID | S03 |
| Covered row IDs | T03, T06 |
| Starting state | `active(0)` |
| Reset/fixture | `pluck('a', 'b')`, source value `{}`, then complete. Also distinguished from `{a: null}` and `{a: {b: undefined}}`, both of which emit `undefined`, and from `{a: {b: null}}`, which emits `null` (T02). |
| State-reaching prefix | `subscribe` |
| Target event | source `next({})` then source `complete` |
| Expected notifications | `next(undefined)`, `complete` |
| Expected lifecycle observations | unsubscribed on complete |
| Distinguishing suffix | silence; a sibling scenario value `{a: {b: null}}` would have emitted `null` instead of `undefined` |
| Expected final state | `completed` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | `undefined` payload, not `error` |
| Oracle source | `source characterization` |

### S04 Getter throw

| Field | Content |
| --- | --- |
| Test ID | S04 |
| Covered row IDs | T04, T08 |
| Starting state | `active(0)` |
| Reset/fixture | property getter throws `e` |
| State-reaching prefix | `subscribe` |
| Target event | source `next` of that object |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | source unsubscribed; no `next(undefined)` |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error versus `undefined` |
| Oracle source | `source characterization` |

### S05 Source error

| Field | Content |
| --- | --- |
| Test ID | S05 |
| Covered row IDs | T05 |
| Starting state | `active(0)` |
| Reset/fixture | source errors before any next |
| State-reaching prefix | `subscribe` |
| Target event | source `error(e)` |
| Expected notifications | `error(e)` |
| Expected lifecycle observations | walker not called |
| Distinguishing suffix | silence |
| Expected final state | `errored(e)` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | error payload |
| Oracle source | `contract` |

### S06 Cancel

| Field | Content |
| --- | --- |
| Test ID | S06 |
| Covered row IDs | T07 |
| Starting state | `active(0)` |
| Reset/fixture | live source |
| State-reaching prefix | `subscribe` |
| Target event | consumer unsubscribe |
| Expected notifications | none |
| Expected lifecycle observations | source unsubscribed |
| Distinguishing suffix | no projected next |
| Expected final state | `cancelled` |
| Version and scheduler | 7.8.2, no scheduler |
| Assertion type | absence of terminal |
| Oracle source | `source characterization` |

## F. Coverage and evidence

Denominator = 9 section C rows (T00–T08).

Section E references T00, T01, T02, T03, T04, T05, T06, T07, T08. Specified coverage = 9/9.

Execution: not executed.

Evidence: `src/internal/operators/pluck.ts` lines 89–106, plus `map`’s project call. No tests were run. Mutation experiments: none performed.

## G. Review decision

Decision: accept with documented limits

Reason: call-time validation and the per-value walker are local and small; terminal behavior is delegated to `map` without a custom error or complete handler.

Known limitations: the walk uses `typeof p !== 'undefined'`, so a stored `undefined` is indistinguishable from a missing key, while a stored `null` is a real value when it is the last segment. The deprecation comment’s optional-chaining sketch matches those results for ordinary data but is not what the function calls. Exotic receivers that throw on `typeof` or on `in` are out of scope; the code only uses optional property access.

Contract vs version characterization: JSDoc says an unresolved property returns `undefined` (lines 63–66). That matches T03. The empty-list throw and the `null`-versus-`undefined` split are source characterization. There is no `EmptyError` and no error for a missing property.

Tests still required: S01–S06, including `null` as a final value, a symbol key, and two subscribers on one `pluck(...)` result.

Mutation experiments: none performed.

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
