# `take`

`take` is a full operator with a non-subscribing shortcut. When `count <= 0` the operator function is `() => EMPTY`, so subscribe completes immediately and the source is never subscribed (`take.ts` lines 49-51, `empty.ts` line 66). Otherwise it subscribes, increments a `seen` counter on every source `next`, forwards while `seen <= count`, and completes and unsubscribes when a forwarded `next` also satisfies `count <= seen` (`take.ts` lines 52-69). There is no `@deprecated` tag.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Operator | `take` |
| Pin | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Source | `src/internal/operators/take.ts` lines 48-71 |
| Helpers read | `empty.ts` line 66; `lift.ts` lines 17-31; `OperatorSubscriber.ts` lines 67-74; `Subscriber.ts` lines 95-130 |
| Shape | Branch: `EMPTY` if `count <= 0`; otherwise `operate` |
| Parameters | `count` (JS number) |
| Output | A prefix of the source, then `outComplete`, or the whole source if it ends first |
| Model kind | Symbolic |
| Scheduler | None. `EMPTY` completes synchronously on subscribe |
| Introduced errors | None. Does not throw `ArgumentOutOfRangeError` |
| Upstream | No source subscription when `count <= 0`. One source subscription otherwise, dropped on the completing `next` or on source terminal or cancel |
| Inners | None |
| Per-subscription state | `seen`, starting at 0 (line 53) |
| Exclusions | No reentrant callback. The `<=` complete check is commented as protection against a reentrant `next` incrementing `seen` twice (`take.ts` lines 62-63). That reentry is excluded; under quiescence the completing next is exactly the one where the integer `seen` equals `count`. Teardown throws out of scope. Downstream observer throws are not `outError`. |

## B. Six-tuple

```text
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = s_idle
S  = { s_idle, s_active(seen), s_completed, s_errored, s_cancelled }
     seen ∈ ℕ₀
Σ  = { subscribe, sourceNext(v), sourceError(e), sourceComplete, cancel }
Γ  = records below
δ, λ tabulated in section C
kind = symbolic
parameter count ∈ IEEE numbers
```

`NaN <= 0` is false, so `take(NaN)` is not the `EMPTY` branch.

### S: state inventory

| State | Meaning | Terminal? |
| --- | --- | --- |
| `s_idle` | Not subscribed. `s₀` | No |
| `s_active(seen)` | Source subscribed. `seen` source nexts already handled | No |
| `s_completed` | Complete delivered, either by `EMPTY`, by the count, or by the source | Yes |
| `s_errored` | Source error delivered | Yes |
| `s_cancelled` | Cancelled with no terminal notification | Yes |

### Σ: input inventory — mandatory review

| Category | Applicable? | Reason |
| --- | --- | --- |
| Initialization subscribe | Yes | `count <= 0` returns `EMPTY` and completes with no `source.subscribe`. Otherwise `operate` subscribes |
| Source next | Yes | Only on the operate branch. `seen` increments even when the value is not forwarded (line 59) |
| Source error | Yes | Default forward on the operate branch. Impossible on the `EMPTY` branch because the source is not subscribed and the output is already complete |
| Source completion | Yes | Forwarded if the count has not already completed the output |
| Cancellation cancel | Yes | Operate branch unsubscribes the source and does not complete. `EMPTY` has already completed synchronously, so a later cancel is terminal-silent |
| Inner notifications | No | No notifier |
| Time | No | No timer |
| User callback outcomes | No | No user callback |

### Γ: output inventory

```text
notifications ::= ε | outNext(v) | outNext(v) then outComplete | outError(e) | outComplete
lifecycle     ::= ε | subSrc | unsubSrc
record        ::= (notifications in order, lifecycle in order)
```

Absence of `subSrc` on the `EMPTY` path is observable and is not the same as subscribe-then-immediate-unsub.

## C. Transition obligations

After a next, `k` is the incremented `seen` (`++seen`). The three next guards partition every JS `count` and every integer `k >= 1`:

- emit and finish: `k <= count` and `count <= k` (so `k` equals `count`; `count` is that positive integer)
- emit and continue: `k <= count` and not `count <= k`
- drop: not `k <= count`

So a positive integer `n` completes on the `n`th next after forwarding it. `take(2.5)` forwards two values (`1 <= 2.5`, `2 <= 2.5`) and does not early-complete (`2.5 <= 2` is false), then drops from the third next until the source terminates. `take(0.5)` and `take(NaN)` subscribe and forward nothing. `take(+Infinity)` forwards every next and never early-completes. `take(0)`, negatives, and `-Infinity` hit T02.

| ID | State / data | Input / origin | Guard | Notifications | Lifecycle | Next state / update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | `s_idle` | source signals or `cancel` | Not subscribed | ε | ε | `s_idle` | None | Inapplicable | — |
| T02 | `s_idle` | `subscribe` | `count <= 0` | `outComplete` | ε | `s_completed` | None | No `subSrc`. A synchronous source cannot run | E01 |
| T03 | `s_idle` | `subscribe` | `!(count <= 0)` | ε | `subSrc` | `s_active(0)` | None | Includes `NaN` and positives | E02 |
| T04 | `s_active(seen)` | `sourceNext(v)` | Let `k = seen+1`. `k <= count` and `count <= k` | `outNext(v)`, `outComplete` | `unsubSrc` | `s_completed` | `seen = k-1` source nexts already handled | No further source value is forwarded | E02 |
| T05 | `s_active(seen)` | `sourceNext(v)` | `k = seen+1`, `k <= count`, not `count <= k` | `outNext(v)` | ε | `s_active(k)` | Same | Source stays subscribed | E03 |
| T06 | `s_active(seen)` | `sourceNext(v)` | `k = seen+1`, not `k <= count` | ε | ε | `s_active(k)` | Count not reached by an equal integer, or already past it | Value is not emitted on a later complete | E04 |
| T07 | `s_active(seen)` | `sourceError(e)` | Any `seen` | `outError(e)` | `unsubSrc` | `s_errored` | Subscribed | No complete, no extra next | E05 |
| T08 | `s_active(seen)` | `sourceComplete` | Any `seen` | `outComplete` | `unsubSrc` | `s_completed` | Fewer forwarded values than an early-complete, or values were only dropped | Does not invent nexts to fill `count` | E04 |
| T09 | `s_active(seen)` | `cancel` | Any `seen` | ε | `unsubSrc` | `s_cancelled` | Subscribed | No `outComplete` | E06 |
| T10 | terminal states | source signals or `cancel` | Protocol-illegal | ε | ε | unchanged | Already stopped | Silent by convention | — |

## D. Contract invariants

| Obligation | Applies? | Tests / evidence |
| --- | --- | --- |
| Output order and payloads | Yes | Forwarded values are a prefix of the source, same payloads. E02, E03 |
| At most one terminal | Yes | Early complete, source complete, or source error. T02 already terminals |
| No downstream after terminal | Yes | T10. Early complete unsubscribes via `subscriber.complete` |
| Cancellation does not synthesize completion | Yes | T09, E06. Distinct from T02, which completes because the result is `EMPTY`, not because of cancel |
| Upstream / inner lifetime | Yes | T02 does not subscribe. T04 unsubscribes on the completing next. No inner |
| Cleanup once | Yes | No `onFinalize`. Destination unsubscribe drops the source once |
| Per-subscription state | Yes | `seen` is an init local |
| Empty source | Yes | Operate branch: `outComplete` with zero nexts (T08 from `seen = 0`). `EMPTY` branch: `outComplete` without `subSrc` |
| Source error | Yes | Forwarded if it happens before an early complete. E05 |
| Silence | Yes | Only if the operate branch is subscribed to a source that never nexts and never terminates. `count <= 0` is not silent |
| Pending value or buffer on terminal | No | No buffer. The completing value is emitted before complete, not held |
| Callback throws / reenters / cancels | No user callback. Reentry excluded | Lines 62-63 document why complete uses `count <= seen` rather than `count === seen` |
| Equal-time ordering and timer cancellation | No | No timer. `EMPTY` is synchronous but not scheduled |

## E. Scenario specification

### E01

| Field | Value |
| --- | --- |
| Test ID | E01 |
| Covered row IDs | T02 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 0` (same branch for negatives) |
| State-reaching prefix | None |
| Target event | `subscribe` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | No `subSrc`. `EMPTY` calls `subscriber.complete()` (`empty.ts` line 66) |
| Distinguishing suffix | Source nexts are impossible because subscribe never attached. Different from `take(0.5)`, which does subscribe |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E02

| Field | Value |
| --- | --- |
| Test ID | E02 |
| Covered row IDs | T03, T04 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 1` |
| State-reaching prefix | `subscribe` → `s_active(0)` with `subSrc` |
| Target event | `sourceNext('a')` |
| Expected notifications | `outNext('a')`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` after the next. `++seen` is 1, `1 <= 1`, then `1 <= seen` |
| Distinguishing suffix | A second source next is not subscribed and must not emit |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E03

| Field | Value |
| --- | --- |
| Test ID | E03 |
| Covered row IDs | T05, T08 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 5`, source emits two values then completes |
| State-reaching prefix | `subscribe` |
| Target event | `sourceNext(1)`, `sourceNext(2)`, `sourceComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `unsubSrc` on source complete, not earlier. Both nexts take T05 because `count <= k` is false |
| Distinguishing suffix | No third synthetic next |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | contract |

### E04

| Field | Value |
| --- | --- |
| Test ID | E04 |
| Covered row IDs | T03, T06, T08 |
| Starting state | `s_idle` |
| Reset/fixture | `count = 0.5` |
| State-reaching prefix | `subscribe` → `s_active(0)` with `subSrc` (`0.5 <= 0` is false) |
| Target event | `sourceNext(1)`, `sourceComplete` |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | `subSrc` then `unsubSrc`. `++seen` becomes 1 and `1 <= 0.5` is false, so no early complete |
| Distinguishing suffix | Contrast E01: `take(0)` would not have subscribed |
| Expected final state | `s_completed` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E05

| Field | Value |
| --- | --- |
| Test ID | E05 |
| Covered row IDs | T07 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 3` |
| State-reaching prefix | `subscribe` |
| Target event | `sourceError(e)` |
| Expected notifications | `outError(e)` |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | No `outComplete` and no `ArgumentOutOfRangeError` |
| Expected final state | `s_errored` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization |

### E06

| Field | Value |
| --- | --- |
| Test ID | E06 |
| Covered row IDs | T05, T09 |
| Starting state | `s_active(0)` |
| Reset/fixture | `count = 2` |
| State-reaching prefix | `subscribe`, `sourceNext(1)` → `s_active(1)` with `outNext(1)` |
| Target event | `cancel` |
| Expected notifications | ε |
| Expected lifecycle observations | `unsubSrc` |
| Distinguishing suffix | The second allowed value is not emitted, and there is no `outComplete` |
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

Denominator = 10. Specified 10/10. Executed 0/10.

Residual risk: `NaN` and `+Infinity` sit in T03/T05/T06/T08 and are specified only by the comparisons, not by a dedicated scenario. Reentrant double increment is excluded even though the source comments on it. No test was executed.

## G. Review decision

Decision: accept with documented limits

Reason: The `count <= 0` shortcut and the `++seen` / `count <= seen` pair are the whole value policy. The machine keeps "do not subscribe" distinct from "subscribe and drop".

Known implementation limitations: Only a count that is equal to some positive integer `seen` early-completes. Non-integers, `NaN`, and `+Infinity` do not. `seen` still increments on dropped nexts. There is no `ArgumentOutOfRangeError` in this file. The complete check uses `<=` because of excluded reentrancy.

Differences between intended contract and version characterization: The public text says the first `count` values (`take.ts` lines 7-16). For a positive integer that matches the code. `take(0)` completes without subscribing, which is stronger than "emit nothing until the source completes". `src/internal/util/ArgumentOutOfRangeError.ts` lists `take` in a `@see` tag, but `take.ts` never constructs that error.

Tests still required: executable reference model and RxJS 7.8.2 integration tests.

Mutation experiments performed and findings: none performed

Reviewer / date: source-derived analysis (Grok) / 2026-10-21
