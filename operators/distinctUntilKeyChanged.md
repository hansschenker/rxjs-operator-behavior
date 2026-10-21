# `distinctUntilKeyChanged`

`distinctUntilKeyChanged` is a thin wrapper. It returns `distinctUntilChanged` with a single comparator and no `keySelector` (`distinctUntilKeyChanged.ts` lines 70-75):

```ts
distinctUntilChanged((x, y) => (compare ? compare(x[key], y[key]) : x[key] === y[key]))
```

The first source value is emitted without reading `key`. Later values compare `previousValue[key]` with `currentValue[key]` at comparison time, because the stored "key" is the previous value itself (`identity`). There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `distinctUntilKeyChanged` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/distinctUntilKeyChanged.ts` lines 70-75, induced behavior from `distinctUntilChanged.ts` lines 139-178 |
| Helpers read | `distinctUntilChanged.ts` lines 146-173 and 180-182 |
| Shape | Thin wrapper around `distinctUntilChanged` |
| Parameters | `key`; optional `compare(previousProp, currentProp)` |
| Output | First value, then values whose property at `key` is not "same" as the previous emitted value's property |
| Model kind | Symbolic |
| Scheduler | None |
| Introduced errors | Property read or `compare` can throw on the second and later values. That throw is a comparator callback failure (`outError`), not a source error. The first value does not read `key` |
| Upstream | One source subscription, via `distinctUntilChanged` |
| Inners | None |
| Per-subscription state | `distinctUntilChanged`'s `first` and `previousKey`. Here `previousKey` is the previous emitted source value, not a snapshotted property |
| Exclusions | No reentrant callback. Teardown throws out of scope. Downstream observer throws are not `outError`. Mutating the previous object before the next source value changes what `x[key]` reads; that is in-model if the mutation happens between inputs, because the property is not copied at emit time. A missing `compare` uses `===` on the properties. A truthy `compare` is called as `compare(x[key], y[key])`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_fresh, s_held(prev), s_completed, s_errored, s_cancelled }
     prev is a symbolic source value
Σ  = { subscribe,
       sourceNext(v, prop),
       sourceError(e), sourceComplete, cancel }
     prop ∈ { notRead, read(p), throw(err) }
     When prop = read(p), the comparison outcome is separate:
       cmp ∈ { same, different, throw(err) } after both properties are read
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

On a later next the wrapper runs only as the comparator of `distinctUntilChanged`. `keySelector` is `identity`, so `currentKey` is `v` and `previousKey` is `prev`. The wrapper then evaluates `prev[key]` and `v[key]`.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_fresh` | Subscribed, nothing emitted | No |
| `s_held(prev)` | Last emitted value is `prev`. Its property has not been snapshotted | No |
| `s_completed` | Source complete forwarded | Yes |
| `s_errored` | Property or `compare` throw, or source error | Yes |
| `s_cancelled` | Cancelled without a terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | Inherited `source.subscribe` (`distinctUntilChanged.ts` lines 155-176). `key` is not read at subscribe |
| Source next | Yes | First next emits `v` and stores `v`. Later nexts read properties |
| Source error | Yes | Default forward |
| Source completion | Yes | Default forward |
| Cancellation cancel | Yes | Does not complete |
| Inner notifications | No | No notifier |
| Time | No | No clock |
| User callback outcomes | Yes | `compare`, when provided, is called only after both property reads succeed, and only when `first` is already false. A throw from a property read is also a callback outcome of that comparator. The first next does not call it |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

Payloads are source values, not the extracted properties.

## C. Transition obligations

`compare` absent or falsy: same iff `prev[key] === v[key]`. `compare` truthy: same iff `compare(prev[key], v[key])` is truthy. Argument order is previous property, then current property (`distinctUntilKeyChanged.ts` line 74), matching `distinctUntilChanged`'s `(previous, current)`.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | `key` fixed. `compare` either absent or callable | ε | `subSrc` | `s_fresh` | None | First next will not read `key` | E01 |
| T02 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T03 | `s_fresh` | `sourceNext(v, notRead)` | First value. Comparator not called | `outNext(v)` | ε | `s_held(v)` | `first === true` in the inner operator | `v` may be `null`. `key` is unread. State is stored before `outNext` | E01 |
| T04 | `s_held(prev)` | `sourceNext(v, throw(err))` | Reading `prev[key]` or `v[key]` throws `err` | `outError(err)` | `unsubSrc` | `s_errored` | A value was emitted | `compare` is not called. `prev` is not replaced | E02 |
| T05 | `s_held(prev)` | `sourceNext(v, read)` and `compare` throws `err` | Both properties were read, then `compare` throws | `outError(err)` | `unsubSrc` | `s_errored` | `compare` is truthy | Not a source error | E03 |
| T06 | `s_held(prev)` | `sourceNext(v, read)` and comparison is same | Default `===` is true, or `compare` returns truthy | ε | ε | `s_held(prev)` | Properties read now, not at the earlier emit | `v` dropped. A mutation of `prev[key]` since the emit is visible to this read | E04 |
| T07 | `s_held(prev)` | `sourceNext(v, read)` and comparison is different | Default `===` is false, or `compare` returns falsy | `outNext(v)` | ε | `s_held(v)` | Properties differ at comparison time | Stored value becomes `v` before `outNext` | E01 |
| T08 | `s_fresh` or `s_held(prev)` | `sourceError(e)` | Any | `outError(e)` | `unsubSrc` | `s_errored` | Open | No property read required | E05 |
| T09 | `s_fresh` or `s_held(prev)` | `sourceComplete` | Any | `outComplete` | `unsubSrc` | `s_completed` | Open | No extra value | E04 |
| T10 | `s_fresh` or `s_held(prev)` | `cancel` | Any | ε | `unsubSrc` | `s_cancelled` | Open | No complete | E06 |
| T11 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T04, T05, T06, and T07 partition a next that occurs while a value is held. T04 happens before T05 when the property access itself throws. T03 does not overlap them.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Emitted items are source values. The property is only a comparison key. E01 |
| At most one terminal | Yes | Complete, source error, or one callback throw |
| No downstream after terminal | Yes | T11 |
| Cancellation does not synthesize completion | Yes | T10, E06 |
| Upstream / inner lifetime | Yes | One source. No inner. No flush |
| Cleanup once | Yes | Inherited. No extra finalizer in this file |
| Per-subscription state | Yes | The held value is per `distinctUntilChanged` subscription |
| Empty source | Yes | Complete from `s_fresh` emits nothing else |
| Source error | Yes | Forwarded. E05 |
| Silence | Yes | After the first value, identical properties emit nothing until the source terminates or the property comparison changes |
| Pending value or buffer on terminal | No | Suppressed values are dropped. The held object is not re-emitted on complete |
| Callback throws / reenters / cancels | Property and `compare` throws yes, and only after the first value. Reentry excluded | First value cannot throw via `key` |
| Equal-time ordering and timer cancellation | No | No second stream and no timer |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T03, T07 |
| Starting state | `s_idle` |
| Reset/fixture | `key = 'name'`, no `compare`. Values `{name:'Foo'}`, `{name:'Bar'}` |
| State-reaching prefix | `subscribe` → `s_fresh` |
| Target event | `sourceNext(foo, notRead)`, `sourceNext(bar, read)` with `'Foo' === 'Bar'` false |
| Expected notifications | `outNext(foo)`, `outNext(bar)` |
| Expected lifecycle observations | `name` is not read while handling `foo`. It is read on both objects while handling `bar`. The stored state after `foo` is the object `foo`, not the string `'Foo'` |
| Distinguishing suffix | A third `{name:'Bar'}` would be T06 and would not emit |
| Expected final state | `s_held(bar)` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_fresh` |
| Reset/fixture | `key = 'name'`. First value is `null` |
| State-reaching prefix | `subscribe`, `sourceNext(null, notRead)` → `s_held(null)` with `outNext(null)` |
| Target event | `sourceNext({name:'a'}, throw(TypeError))` because `null['name']` throws |
| Expected notifications | `outError(TypeError)` for the second next |
| Expected lifecycle observations | The first `outNext(null)` already happened. `unsubSrc` on the second next. `compare` not called |
| Distinguishing suffix | The first value did not error. This is not `sourceError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05 |
| Starting state | `s_held(prev)` |
| Reset/fixture | `compare` throws `err` after reading both properties |
| State-reaching prefix | `subscribe`, one successful first value |
| Target event | `sourceNext(v, read)` then comparator `throw(err)` |
| Expected notifications | `outError(err)` |
| Expected lifecycle observations | `unsubSrc`. Held value not replaced |
| Distinguishing suffix | Properties were read; the throw is the user's `compare` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T06, T09 |
| Starting state | `s_held(prev)` |
| Reset/fixture | `key = 'name'`. `prev.name` is `'Foo'` at comparison time. Next value also has `name:'Foo'`. Then complete |
| State-reaching prefix | `subscribe`, first value emitted |
| Target event | `sourceNext(next, read)` same, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `next` suppressed. If `prev.name` had been mutated to `'Bar'` before this next, the same input shape would be T07 instead |
| Distinguishing suffix | The mutation contrast is the snapshot gap: the wrapper does not pass a `keySelector` that copies `value[key]` at emit time (`distinctUntilKeyChanged.ts` line 74 versus `distinctUntilChanged.ts` lines 141 and 158) |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T08 |
| Starting state | `s_held(prev)` |
| Reset/fixture | One value emitted |
| State-reaching prefix | `subscribe`, one next |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`. `key` need not be read |
| Distinguishing suffix | No second next of `prev` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T10 |
| Starting state | `s_fresh` |
| Reset/fixture | Subscribed |
| State-reaching prefix | `subscribe` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

## F. Coverage and evidence

| Row | Status | Execution |
| --- | --- | --- |
| T01 | specified | not executed |
| T02 | specified | not executed |
| T03 | specified | not executed |
| T04 | specified | not executed |
| T05 | specified | not executed |
| T06 | specified | not executed |
| T07 | specified | not executed |
| T08 | specified | not executed |
| T09 | specified | not executed |
| T10 | specified | not executed |
| T11 | specified | not executed |

Denominator = 11. Specified 11/11. Executed 0/11.

Residual risk: mutation of the previous object is specified in E04's suffix and not executed as its own trace. `compare` returning a truthy non-boolean is specified as "same" and not executed. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The file is one call that supplies a comparator and does not supply `distinctUntilChanged`'s `keySelector`. The induced machine follows that call plus the inner first-value and update-before-emit rules.

Known implementation limitations: `key` is not read for the first value. Later comparisons read the live property of the previously emitted object. A first `null` or `undefined` emits, and the next value throws when the property is read. Falsy `compare` selects `===` on the properties; a truthy `compare` receives property values, not the whole objects. There is no `thisArg` and no flush.

Differences between intended contract and version characterization: JSDoc lines 7-15 say items are distinct by a property accessed with `key`, and that the optional comparator tests that value. That matches the comparison. It does not say the property is read only when the next value arrives, or that the previous object is stored whole. Those are consequences of not passing a `keySelector` at line 74. A natural reading that the key string is snapshotted at emission time is stronger than this source.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
