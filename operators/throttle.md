# throttle

`throttle(durationSelector, config?)` rate-limits with `{ leading = true, trailing = false }` (`throttle.ts` 84–86). When no duration is open, a source value either emits immediately and then starts a duration (`leading`) or only starts a duration (`!leading`). Values that arrive while the duration is open overwrite `sendValue` and are not emitted yet. Duration `next` ends the throttle: if `trailing` and a value is pending, that latest value is emitted and, if the source is not complete, a new duration starts from that emitted value. Duration `complete` without `next` does not emit; it only clears the slot and completes the output if the source already completed. Source error is immediate and does not flush a trailing value. Source complete flushes a trailing value only when `trailing` is set, a value is pending, and the duration is still open. `cancel` emits nothing. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/throttle.ts`. Not deprecated. `ThrottleConfig` is declared here (lines 15–36).

## A. Identity, contract, and scope

- Operator/overload: `throttle<T>(durationSelector: (value: T) => ObservableInput<any>, config?: ThrottleConfig)` (`throttle.ts` 84). Defaults `{ leading: true, trailing: false }`.
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 48–55 describes the default leading path only. The config flags are normative in the interface JSDoc (16–35) and in the code (92–140). Both flags true can emit a leading value and later a different trailing value. Both false emits no values.
- Model kind: extended/timed, not finite. Config is a parameter of `δ`, not four unrelated operators.
- Parameter domain: `durationSelector` is called with the value passed to `startThrottle`: the value just sent on the leading path (`send` → `startThrottle(value)`, lines 118–119), or the value that arrived while idle on the trailing-only path (line 134). It is not called with later suppressed values. Throws are callback faults.
- Payload/error domain: `hasValue` distinguishes a stored `T` that may be nullish (`throttle.ts` 87–88, 110). Duration payloads ignored. Duration `error` uses default `onError` and becomes output `error`.
- Subscription boundary: source subscriber (`throttle.ts` 123–141) has no custom error handler and no finalize. Duration subscription is parented to the destination (`startThrottle`, line 107).
- Scheduler and tie ordering: no scheduler in this file. User durations may be timed; same-virtual-time order is an assumption, not a proof. Synchronous duration `next` during `subscribe` is explicitly supported: `throttled.closed` is checked (lines 126–134) because a sync duration assigns an already-closed subscription back onto `throttled`.
- Callback assumptions: selector and duration signals run under `OperatorSubscriber` try/catch. `send` clears `hasValue` before `subscriber.next` to avoid reentrant double-sends (lines 111–114); ordinary model still excludes reentrancy. Duration `complete` is `cleanupThrottling`, not `endThrottling` (107 vs 101–104).
- Cleanup assumptions: `endThrottling` unsubscribes the duration before any trailing send (92–94). `cancel` unsubscribes the child duration and does not call `send` or `complete`.
- Explicit exclusions: reentrancy beyond the `closed` check already in the source; both-false as a useful stream (legal but silent); infinite sync trailing loops if a duration `next`s synchronously while `hasValue` stays true (not the ordinary async case).

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
parameters L = leading, R = trailing
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Idle` | `throttled` null or closed, `isComplete = false` | Next source value may start or send. `hasValue` may still be true after a non-trailing end; it is not emitted until a later `send`. |
| `Throttled(v)` | duration open (`throttled && !closed`), `sendValue = v`, `hasValue = true`, `isComplete = false` | Suppressing. `v` is the latest source value. |
| `ThrottledDone(v)` | duration open, `isComplete = true`, `hasValue = true` | Source completed; trailing flush still possible. |
| `Stopped` | terminal | — |

After a leading `send`, `hasValue` is false until another source value arrives, so the location can be “duration open, nothing to trail.” That is `Throttled(⊥)` below.

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | Reads `config ?? {}` once (line 86). |
| `sourceNext(v)` | yes | source | Lines 131–134. |
| `sourceError(e)` | yes | source | Immediate; no trailing flush (error handler omitted). |
| `sourceComplete` | yes | source | Lines 136–138. Waits only for trailing. |
| `cancel` | yes | unsubscribe | No emit, no complete. |
| `durationNext` | yes | duration | `endThrottling` (line 107). |
| `durationComplete` | yes | duration | `cleanupThrottling` (line 107). No trailing emit. |
| `durationError(e)` | yes | duration | Output `error`. |
| `selectorThrow(e)` | yes | `startThrottle` / `durationSelector` | If this happens after a leading `subscriber.next`, that `next` already happened (lines 118–119) and then the throw becomes `error`. |
| `timerFired` | no | — | Not in this file. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required for sync durations and for complete-versus-duration ordering.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | capture `L`,`R`; subscribe source | `Idle` | ε | source | S01 |
| T02 | `Idle` | `sourceNext(v)` | `L` and not currently throttled | `next(v)` | `send` clears flags, `next`, then `startThrottle(v)` (109–119, 134) | `Throttled(⊥)` if duration stays open | T01 | suppressed values may follow | S01 |
| T03 | `Idle` | `sourceNext(v)` | `!L` and not throttled | `none` | `hasValue=true`, `sendValue=v`, `startThrottle(v)` (134) | `Throttled(v)` | T01 | wait duration | S02 |
| T04 | `Throttled(v)` or `Throttled(⊥)` | `sourceNext(w)` | `throttled && !closed` | `none` | overwrite pending (132–133); do not call selector | `Throttled(w)` | T02 or T03 | trailing may emit `w` | S02 |
| T05 | `Throttled(*)` | `durationNext` | `R` and `hasValue` and `!isComplete` | `next(pending)` | `endThrottling` (92–98) calls `send`, which starts a new duration on the emitted value (119) | `Throttled(⊥)` of the new duration | T04 | no second leading emit of the same value | S02 |
| T06 | `Throttled(⊥)` | `durationNext` | `R` and `!hasValue` | `none` | unsubscribe duration; `send` no-op; throttle ends | `Idle` | T02 with no later values | next source value is a new leading/start | S01 |
| T07 | `Throttled(*)` | `durationNext` | `!R` | `none`; pending not emitted | `endThrottling` skips `send` (95–98). `hasValue` may remain true but `throttled` is null | `Idle` | T02, T04 | next idle `sourceNext` can emit if `L` | S03 |
| T08 | `Throttled(*)` | `durationComplete` | no preceding `next` | `none` | `cleanupThrottling` sets `throttled=null` (101–104). Does not `send`. Sync case: assignment `throttled = subscribe(...)` may then store the already-closed subscriber (126–130) | `Idle` (closed counts as not throttled) | T03 | next value is not suppressed | S04 |
| T09 | `Throttled(v)` | `sourceComplete` | `R && hasValue && throttled && !closed` | `none` yet | `isComplete=true` (136–138) | `ThrottledDone(v)` | T04 | wait `durationNext` | S05 |
| T10 | `ThrottledDone(v)` | `durationNext` | `R` | `next(v)` then `complete` | `send` does not `startThrottle` because `isComplete` (119); then line 97 completes | `Stopped` | T09 | none | S05 |
| T11 | `ThrottledDone(v)` | `durationComplete` | — | `complete`; `v` dropped | `cleanupThrottling` (101–104) | `Stopped` | T09 | none | S04 |
| T12 | `Idle` or `Throttled` with `!R` or `!hasValue` | `sourceComplete` | line 138 guard false | `complete`; no trailing `next` | — | `Stopped` | T01, T06, T07 | none | S03, S06 |
| T13 | any non-terminal | `sourceError(e)` | even if `R && hasValue` | `error(e)`; trailing dropped | default error | `Stopped` | T04 | none | S07 |
| T14 | any non-terminal | `durationError(e)` | — | `error(e)` | default error on the duration subscriber | `Stopped` | T02 | none | S07 |
| T15 | any non-terminal | `cancel` | — | `none` | duration child unsubscribed; no `complete` | `Stopped` | T02 | none | S08 |
| T16 | `Idle` | `sourceNext` | `L` and selector throws inside `startThrottle` after `next` | `next(v)` then `error(e)` | `send` order 118–119 | `Stopped` | T01 | none | S09 |
| T17 | `Idle` | `sourceNext` | `!L` and selector throws | `error(e)`; no `next` | `startThrottle` before any `send` | `Stopped` | T01 | none | S09 |
| T18 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T19 | `L=false, R=false` | full source | durations open and end | `complete` or `error` only | `send` never called (95 and 134) | `Stopped` on termination | T01, T03, T07 | silence is legal | S06 |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | Default config is leading true, trailing false (line 86). |
| I02 | Leading emit happens before the duration is subscribed, and the selector sees that emitted value. |
| I03 | While a duration is open and not closed, source values only update `sendValue`. |
| I04 | Trailing emit uses the latest suppressed value, then starts a new duration if the source is not complete. It does not also count as a new leading emit. |
| I05 | If no value arrived during the window, trailing `send` is a no-op (`hasValue` was cleared by the leading send). |
| I06 | Duration `complete` without `next` does not trailing-emit. |
| I07 | `sourceError` never trailing-flushes. `sourceComplete` trailing-flushes only under the guard on line 138. |
| I08 | `cancel` does not emit and does not complete. |
| I09 | `hasValue` is cleared before `subscriber.next` (lines 111–118). |

## E. Scenario specification

### S01 Default leading, no suppressed values

- Test ID: S01
- Covered row IDs: T01, T02, T06
- Starting state: unsubscribed
- Reset/fixture: default config; duration `next`s once; no second source value
- prefix: `subscribe`
- target event: `sourceNext(a)` then `durationNext`
- expected notifications: `next(a)` at the source event; nothing at `durationNext`
- lifecycle: duration started with `a`; unsubscribed in `endThrottling`; slot idle
- suffix: a later `sourceNext(b)` leads again
- final state: `Idle`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`throttle.ts` 109–119, 92–98)

### S02 Leading and trailing both true

- Test ID: S02
- Covered row IDs: T02, T04, T05
- Starting state: `Idle`
- Reset/fixture: `{ leading: true, trailing: true }`
- prefix: `sourceNext(a)` emits `a` and starts duration
- target event: `sourceNext(b)` then `durationNext`
- expected notifications: `next(a)` then `next(b)`; selector for the second duration receives `b` (the trailing value), not a further leading `next`
- lifecycle: first duration unsubscribed; `send` starts the next duration because `!isComplete`
- suffix: `Throttled(⊥)` until another suppressed value or duration end
- final state: `Throttled(⊥)` if the new duration stays open
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S03 Trailing false drops suppressed values on duration next and on complete

- Test ID: S03
- Covered row IDs: T04, T07, T12
- Starting state: `Throttled(⊥)` after leading `a`
- Reset/fixture: default config; `sourceNext(b)` while throttled
- prefix: leading `next(a)`
- target event: `durationNext`, or instead `sourceComplete` while still throttled
- expected notifications: no `next(b)`. Duration end: `none`. Source complete while throttled: `complete` only
- lifecycle: `endThrottling` does not call `send` when `!trailing`
- suffix: `Idle` or `Stopped`
- final state: `Idle` after duration next; `Stopped` after complete
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 95–98, 136–138)

### S04 Duration complete does not trailing-emit

- Test ID: S04
- Covered row IDs: T08, T11
- Starting state: `Throttled(v)` with `R=true` (so a trailing value is owed) or `ThrottledDone`
- Reset/fixture: duration is `EMPTY` (complete, no next)
- prefix: value stored, duration subscribed
- target event: `durationComplete`
- expected notifications: if source already complete, `complete` and not `next(v)`; if not, `none`
- lifecycle: `cleanupThrottling`; sync `EMPTY` may leave `throttled.closed === true` (126–130) so the next source value is not stuck
- suffix: not suppressed
- final state: `Idle` or `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Trailing flush on source complete

- Test ID: S05
- Covered row IDs: T09, T10
- Starting state: `Throttled(b)` with `R=true`
- Reset/fixture: duration still open; `hasValue`
- prefix: suppressed `b`
- target event: `sourceComplete` then `durationNext`
- expected notifications: `next(b)`, `complete`
- lifecycle: no new duration after the flush (`isComplete`, line 119)
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S06 Both flags false, and idle complete

- Test ID: S06
- Covered row IDs: T12, T19
- Starting state: `Idle`
- Reset/fixture: `{ leading: false, trailing: false }` and a separate default run with no values
- prefix: `subscribe`
- target event: `sourceNext` values then `sourceComplete`
- expected notifications: `complete` only
- lifecycle: durations may be subscribed and torn down (`!L` still calls `startThrottle`) but `send` is never reached
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S07 Error does not trailing-flush

- Test ID: S07
- Covered row IDs: T13, T14
- Starting state: `Throttled(b)` with `R=true`
- Reset/fixture: separate source-error and duration-error runs
- prefix: pending trailing value
- target event: `sourceError(e)` or `durationError(e)`
- expected notifications: `error(e)`, not `next(b)`
- lifecycle: destination teardown
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S08 Cancel

- Test ID: S08
- Covered row IDs: T15
- Starting state: `Throttled(v)`
- Reset/fixture: live duration
- prefix: throttle armed
- target event: `cancel`
- expected notifications: none
- lifecycle: duration unsubscribed; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S09 Selector throw differs by leading

- Test ID: S09
- Covered row IDs: T16, T17
- Starting state: `Idle`
- Reset/fixture: selector throws `e`
- prefix: `subscribe`
- target event: `sourceNext(a)`
- expected notifications: if `L`, `next(a)` then `error(e)`; if `!L`, `error(e)` only
- lifecycle: throw escapes the source `onNext` wrapper
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 118–119 vs 134)

## F. Coverage and evidence

Denominator = 19 (T01–T19). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01, S02 | not executed |
| T03 | S04 (setup), S06 | not executed |
| T04 | S02, S03 | not executed |
| T05 | S02 | not executed |
| T06 | S01 | not executed |
| T07 | S03 | not executed |
| T08 | S04 | not executed |
| T09 | S05 | not executed |
| T10 | S05 | not executed |
| T11 | S04 | not executed |
| T12 | S03, S06 | not executed |
| T13 | S07 | not executed |
| T14 | S07 | not executed |
| T15 | S08 | not executed |
| T16 | S09 | not executed |
| T17 | S09 | not executed |
| T18 | none | not executed |
| T19 | S06 | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Sync duration subscribe-order (`throttled = subscribe(...)` overwriting `cleanupThrottling`’s null) is specified from the comment at lines 126–130, not from an executed test. `{leading:false, trailing:false}` is a real configuration with an empty value stream. Reentrancy excluded except the `closed` flag the source itself checks.
- Contract vs 7.8.2 characterization: the narrative JSDoc (48–55) omits trailing mode. The interface defaults and the implementation are the contract used here.
- Tests still required: all four boolean combinations, `EMPTY` versus a notifier that `next`s, source complete during the window, source error during the window, selector throw, cancel.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
