# `skipLast`

`skipLast` is a full operator for a positive valid ring length and a pure `identity` passthrough when `skipCount <= 0`. It keeps a ring of `skipCount` values and emits a value only once a newer value has pushed it out of the skipped tail (`skipLast.ts` lines 48-94). Completion, error, and cancellation do not flush the ring. There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `skipLast` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/skipLast.ts` lines 48-94 |
| Helpers read | `src/internal/util/identity.ts` lines 43-45; `lift.ts` lines 22-27; `OperatorSubscriber.ts` lines 67-74 and 104-110; `Subscriber.ts` lines 81-130 |
| Shape | Branch: `identity` if `skipCount <= 0`; otherwise `operate` |
| Parameters | `skipCount` |
| Output | Source values delayed by `skipCount` emissions, tail dropped |
| Model kind | Symbolic (ring contents are unbounded in value domain; length is fixed when the ring is allocated) |
| Scheduler | None |
| Introduced errors | Host `RangeError` from `new Array(skipCount)` at subscribe time when the length is not a valid array length. Not `ArgumentOutOfRangeError` |
| Upstream | `<= 0`: the returned observable is the source itself. Ring path: one source subscription after the array is allocated. Invalid length: source is not subscribed |
| Inners | None |
| Per-subscription state | `ring`, `seen` (`skipLast.ts` lines 57-59) |
| Exclusions | No reentrant callback. The source comment (`skipLast.ts` lines 81-84) updates the ring before `next` specifically so a synchronous reentrant source cannot observe a stale slot; that reentry is excluded here, but the swap-before-emit order is still an obligation. Teardown throws out of scope. Downstream `next` throws are not `outError`. Huge successful allocations that fail for memory are the same subscribe-time `this.error` path as `RangeError` if the host throws before `source.subscribe`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle,
       s_mirror,
       s_ring(seen, ring),
       s_completed, s_errored, s_cancelled }
     seen ∈ ℕ₀
     ring = an N-slot list of symbolic values, N = skipCount
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
```

Branches selected when the operator function is applied, before subscribe: `skipCount <= 0` chooses identity (`skipLast.ts` lines 49-51). Otherwise the ring init runs at subscribe.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_mirror` | `skipCount <= 0`. Consumer subscription is the source subscription. No ring | No |
| `s_ring(seen, ring)` | Ring allocated, `seen` values received | No |
| `s_completed` | Complete delivered | Yes |
| `s_errored` | Error delivered | Yes |
| `s_cancelled` | Cancelled, ring not flushed | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | Identity returns the source (`identity.ts` lines 43-45). Ring path allocates then subscribes (`skipLast.ts` lines 57-88). Invalid `new Array` is caught by `operate` (`lift.ts` lines 22-27) |
| Source next | Yes | Either mirror, store, or shift-and-emit |
| Source error | Yes | Default forward. Ring not emitted |
| Source completion | Yes | Default forward. Values still in the ring are the skipped tail and are not emitted (`skipLast.ts` has no custom `onComplete`) |
| Cancellation cancel | Yes | Returned teardown sets `ring = null` (`skipLast.ts` lines 90-93) and does not emit. JSDoc lines 20-21 |
| Inner notifications | No | No notifier |
| Time | No | Emission is delayed by count, not by a clock |
| User callback outcomes | No | No user callback |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc | releaseRing
record        ::= (notifications in order, lifecycle in order)
```

`releaseRing` is the init teardown `ring = null`, registered after `source.subscribe` returns, so it runs on destination unsubscribe after the operator subscriber finalizer. It is not a downstream notification.

## C. Transition obligations

`N` denotes a `skipCount` for which `new Array(N)` succeeds: an integer in `1 .. 2^32-1`. `k` is `seen` before the next. The slot written on the overflow path is `k % N`, and the value emitted is the previous occupant of that slot. Swap happens before `subscriber.next` (`skipLast.ts` lines 75-85).

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | `subscribe` | `skipCount <= 0` | ε | `subSrc` (the subscription is the source's) | `s_mirror` | None | Next values are not delayed | E01 |
| T02 | `s_idle` | `subscribe` | `!(skipCount <= 0)` and `new Array(skipCount)` throws `err` (typical host `RangeError`: `NaN`, non-integer, `+Infinity`, or length `> 2^32-1`) | `outError(err)` | ε (source line not reached) | `s_errored` | None | No `subSrc` | E02 |
| T03 | `s_idle` | `subscribe` | `N` valid and allocation succeeds | ε | `subSrc` | `s_ring(0, empty N-slot ring)` | None | The first `N` nexts emit nothing | E03 |
| T04 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T05 | `s_mirror` | `sourceNext(v)` | Identity branch | `outNext(v)` | ε | `s_mirror` | `skipCount <= 0` | No ring | E01 |
| T06 | `s_mirror` | `sourceError(e)` | Identity branch | `outError(e)` | `unsubSrc` | `s_errored` | Same | — | — |
| T07 | `s_mirror` | `sourceComplete` | Identity branch | `outComplete` | `unsubSrc` | `s_completed` | Same | No dropped tail | E01 |
| T08 | `s_mirror` | `cancel` | Identity branch | ε | `unsubSrc` | `s_cancelled` | Same | No complete | — |
| T09 | `s_ring(k, ring)` | `sourceNext(v)` | `k < N` | ε | ε | `s_ring(k+1, ring[k]=v)` | Fewer than `N` values stored | Those stored values are absent from a following complete | E03 |
| T10 | `s_ring(k, ring)` | `sourceNext(v)` | `k >= N`. Let `i = k % N`, `old = ring[i]` | `outNext(old)` | ε | `s_ring(k+1, ring[i]=v)` | Ring was full | `old` is `N` emissions behind `v`; slot already holds `v` when `outNext` is delivered | E04 |
| T11 | `s_ring(k, ring)` | `sourceError(e)` | Any `k` | `outError(e)` | `unsubSrc`, `releaseRing` | `s_errored` | Ring may be non-empty | Occupants are not emitted | E05 |
| T12 | `s_ring(k, ring)` | `sourceComplete` | Any `k` | `outComplete` | `unsubSrc`, `releaseRing` | `s_completed` | Ring may hold the tail | Tail not emitted. Distinguishes `skipLast` from `takeLast` | E03 |
| T13 | `s_ring(k, ring)` | `cancel` | Any `k` | ε | `unsubSrc`, `releaseRing` | `s_cancelled` | Ring may be non-empty | No flush. Matches JSDoc lines 20-21 | E06 |
| T14 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

T09 and T10 partition ring nexts. T01-T03 partition subscribe for numeric `skipCount` plus allocation failure.

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Overflow emits the displaced older value, in arrival order. E04 |
| At most one terminal | Yes | Default `Subscriber` terminal paths, or the subscribe-time `this.error` |
| No downstream after terminal | Yes | T14 |
| Cancellation does not synthesize completion | Yes | T08, T13, E06 |
| Upstream / inner lifetime | Yes | No subscribe on allocation failure (T02). Identity does not add an operator subscriber. Ring path subscribes once |
| Cleanup once | Yes | Teardown closure runs on unsubscribe if registered. Idempotent `unsubscribe` does not run it twice. Teardown throws excluded |
| Per-subscription state | Yes | `ring` and `seen` are init locals |
| Empty source | Yes | Ring path: `outComplete` and an unused ring. Identity: source complete only |
| Source error | Yes | Forwarded with no partial tail. E05 |
| Silence | Yes | A non-completing source emits only after the ring is full, then continues; it never emits the last `N` live values because those are not yet displaced |
| Pending value or buffer on terminal | Yes | The ring is pending data and is dropped on complete, error, and cancel. E03, E05, E06 |
| Callback throws / reenters / cancels | No user callback. Reentry excluded | Swap-before-emit is still required by lines 81-85 |
| Equal-time ordering and timer cancellation | No | Delay is counted in emissions, not time |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T01, T05, T07 |
| Starting state | `s_idle` |
| Reset/fixture | `skipCount = 0` (same branch as any `skipCount <= 0`, not `NaN`) |
| State-reaching prefix | `subscribe` → `s_mirror` |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | Direct source subscription. No `new Array` |
| Distinguishing suffix | Contrast T02: `skipLast(NaN)` does not take this branch because `NaN <= 0` is false |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T02 |
| Starting state | `s_idle` |
| Reset/fixture | `skipCount = NaN` (also `1.5`, `+Infinity`) |
| State-reaching prefix | None |
| Target event | `subscribe` |
| Expected notifications | `outError(RangeError)` from `new Array` |
| Expected lifecycle observations | `source.subscribe` is not reached (`skipLast.ts` line 57 runs first; `lift.ts` lines 22-27) |
| Distinguishing suffix | No later source next can appear, because there was no source subscription |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T03, T09, T12 |
| Starting state | `s_idle` |
| Reset/fixture | `skipCount = 2`, source values `1, 2` then complete |
| State-reaching prefix | `subscribe` → empty ring |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `subSrc`, then `unsubSrc` and `releaseRing`. Both values remain the skipped tail |
| Distinguishing suffix | No `outNext` |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T09, T10 |
| Starting state | `s_ring(0, [_, _])` |
| Reset/fixture | `N = 2` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext('a')`, `sourceNext('b')`, `sourceNext('c')`, `sourceNext('d')` |
| Expected notifications | `outNext('a')`, `outNext('b')` |
| Expected lifecycle observations | After `'c'`, slot 0 holds `'c'` before `'a'` is delivered. After `'d'`, slot 1 holds `'d'` |
| Distinguishing suffix | `sourceComplete` emits nothing further (the tail `'c','d'` is skipped) |
| Expected final state | `s_ring(4, ['c','d'])` before suffix |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T11 |
| Starting state | `s_ring(2, ['a','b'])` |
| Reset/fixture | `N = 2`, ring full, nothing emitted yet |
| State-reaching prefix | `subscribe`, two nexts |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc`, `releaseRing`. `'a'` and `'b'` are not nexted |
| Distinguishing suffix | No `outComplete` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T13 |
| Starting state | `s_ring(1, ['a', _])` |
| Reset/fixture | `N = 2` |
| State-reaching prefix | `subscribe`, `sourceNext('a')` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc`, `releaseRing` |
| Distinguishing suffix | Not `outNext('a')` and not `outComplete` |
| Expected final state | `s_cancelled` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

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
| T12 | specified | not executed |
| T13 | specified | not executed |
| T14 | specified | not executed |

Denominator = 14. Specified 14/14. Executed 0/14.

Residual risk: host-dependent messages and memory failure for very large valid lengths are not separately modeled beyond "allocation throw becomes `outError` before subscribe". Identity versus ring for `-0` follows `<= 0` and was not executed. Reentrant overlap of ring swap and `next` is excluded.

## G. Review decision

Decision: accept with documented limits

Reason: The file's two branches and the ring update order are explicit. Complete and cancel both leave the current ring unemitted, which is the opposite of `takeLast`.

Known implementation limitations: `skipCount <= 0` is `identity`, so the result is the source reference, but `NaN` is not `<= 0` and goes to `new Array`. Non-integers and non-finite positive lengths error at subscribe without subscribing. The ring is released only by the returned teardown, not by an `onFinalize`. Only one slot is replaced per next.

Differences between intended contract and version characterization: JSDoc describes the positive-count delay and the cancel-does-not-flush rule, which match the ring path. It does not describe the identity short circuit or the `RangeError` path. Those are version characterizations of lines 49-57.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
