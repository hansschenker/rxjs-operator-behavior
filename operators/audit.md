# audit

`audit(durationSelector)` starts a duration when a source value arrives and no duration is active. Further source values only update the pending value. When the duration emits `next`, the pending value (the latest, not necessarily the opener) is emitted once and the duration slot clears. Duration `complete` without `next` does not emit; it only clears the slot and, if the source has already completed, completes the output, dropping the pending value. Source error is immediate and drops the pending value. Source complete while a duration is still open waits; the pending value is emitted only if that duration `next`s. `cancel` emits nothing. Pin: RxJS **7.8.2**, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791`, `src/internal/operators/audit.ts`. Not deprecated.

## A. Identity, contract, and scope

- Operator/overload: `audit<T>(durationSelector: (value: T) => ObservableInput<any>): MonoTypeOperatorFunction<T>` (`audit.ts` 53).
- Package version/source commit: 7.8.2 / `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
- Intended behavior: JSDoc 18–27 says the most recent source value is emitted when the duration emits. Code: `lastValue` is overwritten on every `sourceNext` (`audit.ts` 80–82); `durationSelector` is called only when `!durationSubscriber` (83–86), with the value that opened the window. `endDuration` (60–70) emits on duration `next`. `cleanupDuration` (72–75) is the duration `complete` handler and does not emit.
- Model kind: extended/timed, not finite.
- Parameter domain: `durationSelector(openingValue)` returns an `ObservableInput`. Throws and `innerFrom` failures are callback faults.
- Payload/error domain: pending `T` tracked by `hasValue`. Duration values ignored. Duration errors and selector throws become output errors. Inner error is not a distinct outer error type; the default `onError` forwards it (`OperatorSubscriber` falls through to `Subscriber._error`, `Subscriber.ts` 116–121).
- Subscription boundary: source subscriber has no custom error handler and no finalize (`audit.ts` 77–93). Duration subscriber is parented to the destination.
- Scheduler and tie ordering: none in this file. If the duration uses a scheduler, same-virtual-time actions run in schedule order — assumption, not a proof. Micro-trace required when source complete overlaps an open duration.
- Callback assumptions: selector runs in source `onNext` try/catch. Duration `next` → `endDuration`; duration `complete` → `cleanupDuration`; duration `error` → destination error. Ordinary model: no reentrancy. `endDuration` unsubscribes the duration before `subscriber.next` (60–67).
- Cleanup assumptions: no `onFinalize` on the source subscriber. `cancel` unsubscribes the duration because it is a child of `subscriber`. That does not run `endDuration` or `cleanupDuration` unless the duration itself completes, which unsubscribe prevents. Pending value is dropped. No output `complete`.
- Explicit exclusions: reentrancy; durations that error after a `next` (already unsubscribed in `endDuration`); proving timer tie-breaks inside user durations.

## B. Six-tuple

```
M = (S, Σ, Γ, δ, λ, s₀)
s₀ = Idle
```

### S

| Location | Data | Meaning |
| --- | --- | --- |
| `Idle` | `durationSubscriber = null`, `hasValue = false`, `isComplete = false` | Not auditing. |
| `Open(v)` | duration live, `hasValue = true`, `lastValue = v`, `isComplete = false` | Auditing; `v` is the latest source value. |
| `OpenDone(v)` | duration live, `hasValue = true`, `isComplete = true` | Source already completed; waiting for the duration to end the operator. |
| `IdleDone` | source completed, no live duration, pending either absent or abandoned | Output must complete without a flush if this is reached from source complete. Represented as the complete transition itself when the guard passes. |
| `Stopped` | terminal | Error, complete delivered, or cancel. |

### Σ

| Input | In alphabet? | Origin | Notes |
| --- | --- | --- | --- |
| `subscribe` | yes | downstream | — |
| `sourceNext(v)` | yes | source | Updates pending; starts duration only if unset (`audit.ts` 80–87). |
| `sourceError(e)` | yes | source | Immediate forward; no flush. |
| `sourceComplete` | yes | source | Sets `isComplete`; completes immediately unless a value is pending and a duration is still open and not closed (`audit.ts` 89–91). |
| `cancel` | yes | unsubscribe | No emit, no complete. |
| `durationNext` | yes | duration | `endDuration`: emit pending once, then complete if `isComplete`. |
| `durationComplete` | yes | duration | `cleanupDuration`: no emit; complete iff `isComplete`. |
| `durationError(e)` | yes | duration | Output `error(e)`, pending dropped. |
| `selectorThrow(e)` | yes | user callback | Output `error(e)`. `hasValue` may already be true (`audit.ts` 81–84) but is not emitted. |
| `timerFired` | no | — | Not in this file. |

### Γ

`none` | `next(v)` | `error(e)` | `complete`. Micro-trace required for source-complete versus duration `next`/`complete`/`error`.

## C. Transition obligations

| ID | State/data | Input/origin | Guard | Notifications | Lifecycle | Next state/update | Prefix | Suffix | Test IDs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | ∅ | `subscribe` | — | `none` | flags cleared (`audit.ts` 55–58) | `Idle` | ε | source | S01 |
| T02 | `Idle` | `sourceNext(v)` | `!durationSubscriber` and selector returns | `none` | `hasValue=true`, `lastValue=v`, subscribe duration with `endDuration`/`cleanupDuration` (80–86) | `Open(v)` | T01 | duration signal | S01 |
| T03 | `Open(v)` | `sourceNext(w)` | duration already set | `none` | overwrite `lastValue=w`; do not call selector (83) | `Open(w)` | T02 | duration `next` emits `w` | S02 |
| T04 | `Open(v)` | `durationNext` | `hasValue` | `next(v)` | unsubscribe duration; `durationSubscriber=null`; clear cache (60–68); `isComplete` false so no `complete` | `Idle` | T02 or T03 | a new `sourceNext` may open again | S01 |
| T05 | `Open(v)` | `durationComplete` | — | `none`; pending `v` retained in variables but the slot is cleared | `durationSubscriber=null` (72–74); `hasValue` left true | `Idle` with stale `hasValue` until overwritten or source ends | T02 | next `sourceNext` overwrites; source complete will not flush | S03 |
| T06 | `Open(v)` | `durationError(e)` | — | `error(e)`; no `next` | default error; destination teardown | `Stopped` | T02 | none | S04 |
| T07 | `Open(v)` | `sourceComplete` | `hasValue && durationSubscriber && !closed` | `none` yet | `isComplete=true` (89–91). The `&& subscriber.complete()` guard fails. | `OpenDone(v)` | T02 | must wait for duration | S05 |
| T08 | `OpenDone(v)` | `durationNext` | — | `next(v)` then `complete` | `endDuration` (63–69) | `Stopped` | T07 | none | S05 |
| T09 | `OpenDone(v)` | `durationComplete` | — | `complete` only; `v` dropped | `cleanupDuration` (72–74) | `Stopped` | T07 | none | S03 |
| T10 | `Idle` | `sourceComplete` | `!hasValue \|\| !durationSubscriber \|\| closed` | `complete`; no flush of a stale `hasValue` | line 91 short-circuit | `Stopped` | T01 or T05 | none | S03, S06 |
| T11 | any non-terminal | `sourceError(e)` | — | `error(e)`; pending dropped | default `onError` omitted (`audit.ts` 77–93) | `Stopped` | T02 | none | S04 |
| T12 | any non-terminal | `cancel` | — | `none` | duration child unsubscribed; `endDuration` not called; no `complete` | `Stopped` | T02 | none | S07 |
| T13 | `Idle` | `sourceNext` | selector throws | `error(e)` | assignment of `hasValue`/`lastValue` happens first (81–82) | `Stopped` | T01 | none | S08 |
| T14 | `Stopped` | any | — | `none` | inapplicable | `Stopped` | terminal | none | — |
| T15 | `Idle` | `durationNext` | no duration | — | inapplicable | `Idle` | — | — | — |
| T16 | `OpenDone` | `sourceNext` | source already completed | — | inapplicable; source subscriber completes or is stopped | `OpenDone` | T07 | — | — |

## D. Contract invariants

| ID | Invariant |
| --- | --- |
| I01 | A duration is started only when `durationSubscriber` is null (`audit.ts` 83). Later values do not restart it. |
| I02 | `durationSelector` receives the opening value. The emitted value is `lastValue` at `endDuration`, which may be newer (`audit.ts` 81–82, 63–67). |
| I03 | Duration `next` emits at most one pending value, then clears the slot. |
| I04 | Duration `complete` does not emit. If `isComplete`, the output completes and the pending value is dropped (72–74, 89–91). |
| I05 | Source complete does not emit by itself. It either completes immediately or waits. |
| I06 | Source error never emits the pending value. |
| I07 | `cancel` does not emit and does not complete. |
| I08 | After a normal `durationNext` flush, `isComplete` false implies the output stays open (`endDuration` line 69). |

## E. Scenario specification

### S01 Open and emit the opening value

- Test ID: S01
- Covered row IDs: T01, T02, T04
- Starting state: unsubscribed
- Reset/fixture: duration `next`s once
- prefix: `subscribe`, `sourceNext(a)` with no intervening value
- target event: `durationNext`
- expected notifications: `next(a)`
- lifecycle: duration unsubscribed in `endDuration`; output stays open
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (`audit.ts` 60–70, 80–86)

### S02 Latest value wins inside the open window

- Test ID: S02
- Covered row IDs: T03, T04
- Starting state: `Open(a)`
- Reset/fixture: duration still silent
- prefix: `sourceNext(a)` which called `durationSelector(a)`
- target event: `sourceNext(b)` then `durationNext`
- expected notifications: `next(b)`; selector not called for `b`
- lifecycle: same duration subscription
- suffix: `Idle`
- final state: `Idle`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (lines 80–86). The opener is stored first and then overwritten; the emission is the latest value.

### S03 Duration complete drops pending; source complete does not revive it

- Test ID: S03
- Covered row IDs: T05, T09, T10
- Starting state: `Open(a)`
- Reset/fixture: duration completes with no `next` (`EMPTY`)
- prefix: `sourceNext(a)`, `durationComplete` (`none`, slot cleared, `hasValue` still true)
- target event: `sourceComplete`
- expected notifications: `complete` only, not `next(a)`
- lifecycle: guard line 91 is true because `durationSubscriber` was set null
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization. Contrast `debounce`, which flushes this case.

### S04 Errors drop pending

- Test ID: S04
- Covered row IDs: T06, T11
- Starting state: `Open(a)`
- Reset/fixture: separate runs for duration error and source error
- prefix: `sourceNext(a)`
- target event: `durationError(e)` or `sourceError(e)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: destination teardown
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S05 Source complete waits, duration next flushes then completes

- Test ID: S05
- Covered row IDs: T07, T08
- Starting state: `Open(a)`
- Reset/fixture: duration still open
- prefix: `sourceNext(a)`
- target event: `sourceComplete` then `durationNext`
- expected notifications: `none` on source complete; then `next(a)`, `complete`
- lifecycle: output subscription stays alive across the gap; duration remains subscribed until `endDuration`
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (89–91, 60–69)

### S06 Complete with nothing pending

- Test ID: S06
- Covered row IDs: T10
- Starting state: `Idle`, `hasValue = false`
- Reset/fixture: no values, or a prior T04 flush
- prefix: `subscribe`
- target event: `sourceComplete`
- expected notifications: `complete`
- lifecycle: none extra
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

### S07 Cancel

- Test ID: S07
- Covered row IDs: T12
- Starting state: `Open(a)`
- Reset/fixture: live duration
- prefix: `sourceNext(a)`
- target event: `cancel`
- expected notifications: none
- lifecycle: duration unsubscribed with destination; no `complete`
- suffix: none
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization (child subscription via `Subscriber` constructor 47–55)

### S08 Selector throw

- Test ID: S08
- Covered row IDs: T13
- Starting state: `Idle`
- Reset/fixture: selector throws `e`
- prefix: `subscribe`
- target event: `sourceNext(a)`
- expected notifications: `error(e)`, not `next(a)`
- lifecycle: no duration subscription
- suffix: `Stopped`
- final state: `Stopped`
- version and scheduler: 7.8.2
- assertion type: source characterization
- oracle source: source characterization

## F. Coverage and evidence

Denominator = 16 (T01–T16). Execution: **not executed**.

| Row | Scenario | Executed |
| --- | --- | --- |
| T01 | S01 | not executed |
| T02 | S01 | not executed |
| T03 | S02 | not executed |
| T04 | S01, S02 | not executed |
| T05 | S03 | not executed |
| T06 | S04 | not executed |
| T07 | S05 | not executed |
| T08 | S05 | not executed |
| T09 | S03 | not executed |
| T10 | S03, S06 | not executed |
| T11 | S04 | not executed |
| T12 | S07 | not executed |
| T13 | S08 | not executed |
| T14 | none | not executed |
| T15 | none | not executed |
| T16 | none | not executed |

## G. Review decision

accept with documented limits

- Limitations: no tests run. Stale `hasValue` after duration `complete` (T05) is easy to misread as a second buffer; the next `sourceNext` overwrites it, and source complete does not flush it. No reentrancy. No scheduler proof in this file.
- Contract vs 7.8.2 characterization: JSDoc describes the `next`-driven success path, not the complete-without-next drop. The emission is the latest value; the opener is only the selector argument and the initial store.
- Tests still required: S01–S08, especially `EMPTY` duration versus `timer`, and source complete both during and after the duration.
- Mutations: none performed.
- Reviewer: source-derived analysis (Grok) / 2026-10-21.
