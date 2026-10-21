# onErrorResumeNextWith

`onErrorResumeNextWith` does not use `operate`. It returns `(source) => onErrorResumeNext(source, ...nextSources)` (`onErrorResumeNextWith.ts:84-93`), and the work is the creation function (`onErrorResumeNext.ts:73-97`). The upstream source is source 0 of one sequence. Each source is subscribed only after the previous one terminates. Both `error` and `complete` advance. The handler passed for both is `noop` (`onErrorResumeNext.ts:89`), so neither terminal is forwarded; `unsubscribe` in `finally` runs the `subscribeNext` finalizer (`onErrorResumeNext.ts:91`, `OperatorSubscriber.ts:76-98`). If the current source is the last, the output completes, including when that source errored (`onErrorResumeNext.ts:92-94`). A later source's error does not become `outError`; the chain continues or completes. `innerFrom` throwing on a source skips that source and continues (`onErrorResumeNext.ts:83-88`). Source nexts are forwarded. A source that never terminates does not move on. The deprecated operator name `onErrorResumeNext` is this same function and is marked for removal in v8 (`onErrorResumeNextWith.ts:96-99`).

The informal claim "complete does not skip to the next; only error does" is false for this commit. The long JSDoc says complete or error both continue (`onErrorResumeNextWith.ts:13-30`). The `@return` line mentions only the error case (`onErrorResumeNextWith.ts:80-82`) and understates the complete path. The implementation moves on for both.

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `onErrorResumeNextWith` |
| Kind | Public pipeable operator. Also exported as deprecated `onErrorResumeNext` (`onErrorResumeNextWith.ts:96-99`) |
| Module | `/tmp/rxjs/src/internal/operators/onErrorResumeNextWith.ts` |
| Delegated body | `/tmp/rxjs/src/internal/observable/onErrorResumeNext.ts` lines 73-97 |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Arguments | Rest list, or one array (`argsOrArgArray.ts:7-9`, `onErrorResumeNextWith.ts:91`) |
| Lift | None. Result is a new `Observable`, not `source.lift` |
| Projected sequence | `[upstream, ...user sources]` via `oERNCreate(source, ...nextSources)` (`onErrorResumeNextWith.ts:93`) |
| Per-source subscriber | `new OperatorSubscriber(subscriber, undefined, noop, noop)` (`onErrorResumeNext.ts:89`) |
| Error policy | Swallowed for every source, including the last. Last terminal becomes `outComplete` |
| Complete policy | Also advances. Not "only errors advance" |
| `innerFrom` failure | Caught, index already incremented, `subscribeNext()` again. No `outError` (`onErrorResumeNext.ts:83-88`) |
| No user sources | Upstream alone. Its error or complete both end as `outComplete` |
| Empty factory | Not this operator's path. The creation function with no arguments completes immediately (`onErrorResumeNext.ts:81-94`). The operator always passes at least the upstream |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, index=0, active=none, terminalReason=none)` with fixed list `sources[0..n-1]`, `sources[0]` the upstream.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `resubscribing`, `terminal` | `waiting-for-notifier` is unused. There is no notifier. `resubscribing` is the ordered move to `sources[index]` after a terminal |
| index | nat | Next slot to subscribe. Incremented before `innerFrom` (`onErrorResumeNext.ts:84`) |
| active | none or id `< index` | The source currently subscribed |
| n | nat | `sources.length` |
| terminalReason | `none`, `complete`, `unsub` | There is no error terminal from source terminals. `outError` is not produced by T03/T04/T05 |

### Σ (8 categories)

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub` subscribes `sources[0]` |
| Source next | Yes | `srcNext(v)` on the active source |
| Source error | Yes | `srcError(e)` consumed. Advances or completes. Never `outError(e)` from this operator |
| Source completion | Yes | `srcComplete` consumed the same way as error. Does not by itself mean the output is done unless this was the last source |
| Cancellation cancel | Yes | `unsub` |
| Inner notifications | No separate notifier | Later sources are the same source alphabet with a new active id, not `notifierNext` / `notifierError` / `notifierComplete` |
| Time | No | No timer |
| User callback outcomes | Yes | `innerFromThrow` skips the bad slot (`onErrorResumeNext.ts:85-87`). No selector |

### Γ

`outNext(v)` | `outComplete` | `ε`. `outError` is not in the image of source terminals.

Lifecycle: `eff:SubscribeSource(i)`, `eff:UnsubscribeSource` (handler `finally`), `eff:SkipInvalid` (innerFrom catch, no subscribe).

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | `sub` | `n >= 1` | active, active=0, index=1 | `ε` + `eff:SubscribeSource(0)` (`onErrorResumeNext.ts:80-91`) |
| T02 | active | `srcNext(v)` | subscriber not stopped | active | `outNext(v)` (`onNext` omitted, `Subscriber.ts:112-114`) |
| T03 | active | `srcError(e)` | `index < n` | resubscribing then active, active=old index, index=index+1 | `ε` (error swallowed) + `eff:UnsubscribeSource` + `eff:SubscribeSource(next)` |
| T04 | active | `srcComplete` | `index < n` | resubscribing then active | same λ as T03. Complete does not finish the output yet |
| T05 | active | `srcError(e)` or `srcComplete` | `index == n` | terminal, terminalReason=complete | `outComplete`. A last error is still not `outError` (`onErrorResumeNext.ts:92-94`) |
| T06 | resubscribing | `innerFromThrow` | slot invalid | stay in the subscribe-next loop | `ε` + `eff:SkipInvalid`. If no slots remain, T05's complete (`onErrorResumeNext.ts:83-88`) |
| T07 | active | `unsub` | downstream unsubscribes | terminal, terminalReason=unsub | `ε` for observer notifications. See limit: `subscribeNext` is a finalizer |
| T08 | terminal | any | — | terminal | `ε` |

Sync termination: `subscribe` may complete or error before `innerSubscriber.add(subscribeNext)` (`onErrorResumeNext.ts:90-91`). `Subscription.add` on an already closed subscription runs the finalizer immediately (`Subscription.ts:120-123`), so the next source is still entered. Order stays "finalize this source, then subscribe the next".

T03 and T04 are the same control state. The noop handlers make error and complete indistinguishable to `δ` except that the error value is discarded in T03.

No `waiting-for-notifier` row: unused phase.

## D. Contract invariants

1. At most one source is actively delivering. Index only moves forward.
2. No source error is emitted. The sequence's only success terminal is `outComplete`, including an all-error sequence.
3. Source complete of a non-last source does not complete the output. It subscribes the next source. This contradicts the "only error advances" reading.
4. A non-terminating active source blocks the tail. Later sources are not subscribed (`index` does not move).
5. `innerFrom` failure does not fail the output.
6. Nexts keep source order across the concatenation. Nothing is buffered across a boundary; the next source simply starts.
7. With no extra arguments, upstream error becomes `outComplete` after its nexts. That is T05, not identity.

## E. Scenario specification

### E1

| Field | Value |
| --- | --- |
| Test ID | E1 |
| Covered row IDs | T01, T02, T03, T02, T05 |
| Starting state | `phase=init, index=0, active=none, n=2, terminalReason=none` |
| Reset/fixture | `sources = [upstream, extra]`. Upstream nexts `1` then errors. Extra nexts `2` then completes |
| State-reaching prefix | `sub` |
| Target event | `srcNext(1)`, `srcError(e)`, `srcNext(2)`, `srcComplete` |
| Expected notifications | `outNext(1)`, `outNext(2)`, `outComplete` |
| Expected lifecycle observations | `eff:SubscribeSource(0)`, `eff:UnsubscribeSource`, `eff:SubscribeSource(1)`, `eff:UnsubscribeSource` |
| Distinguishing suffix | `e` is absent from the trace. There is no `outError` |
| Expected final state | `phase=terminal, index=2, active=1, n=2, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization (`onErrorResumeNext.ts:89-94`) |

### E2

| Field | Value |
| --- | --- |
| Test ID | E2 |
| Covered row IDs | T04 |
| Starting state | `phase=active, index=1, active=0, n=3, terminalReason=none` |
| Reset/fixture | Three sources. First completes successfully |
| State-reaching prefix | `sub`, `srcNext("a")` |
| Target event | `srcComplete` on source 0 |
| Expected notifications | `outNext("a")` then the next source's later nexts. No `outComplete` yet |
| Expected lifecycle observations | `eff:SubscribeSource(1)` because complete advances |
| Distinguishing suffix | Contrast a concat that would also advance on complete: same move here, but E1 shows error advances too, which concat would not |
| Expected final state | `phase=active, index=2, active=1, n=3, terminalReason=none` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`onErrorResumeNext.ts:89` complete handler is `noop`, then unsubscribe finalizer) |

### E3

| Field | Value |
| --- | --- |
| Test ID | E3 |
| Covered row IDs | T03, T05 |
| Starting state | `phase=active, index=1, active=0, n=2, terminalReason=none` |
| Reset/fixture | Upstream already finished by error. Second source errors |
| State-reaching prefix | T03 onto source 1 |
| Target event | `srcError(e2)` and `index == n` after this source was entered |
| Expected notifications | `outComplete` |
| Expected lifecycle observations | No further `eff:SubscribeSource` |
| Distinguishing suffix | Not `outError(e2)`. The last error is swallowed |
| Expected final state | `phase=terminal, index=2, active=1, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`onErrorResumeNext.ts:92-94`) |

### E4

| Field | Value |
| --- | --- |
| Test ID | E4 |
| Covered row IDs | T06, T05 |
| Starting state | `phase=init, index=0, n=3, active=none, terminalReason=none` |
| Reset/fixture | `sources = [upstream that nexts 1 and completes, invalid non-observable, of(5)]` |
| State-reaching prefix | `sub` |
| Target event | source 0 `srcComplete`, then `innerFromThrow` on slot 1, then source 2 next `5` and complete |
| Expected notifications | `outNext(1)`, `outNext(5)`, `outComplete` |
| Expected lifecycle observations | `eff:SkipInvalid` for the bad slot. No `outError` |
| Distinguishing suffix | The invalid slot does not stick the index |
| Expected final state | `phase=terminal, index=3, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, synchronous `innerFrom` throw (`innerFrom.ts:41`) |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`onErrorResumeNext.ts:83-88`) |

### E5

| Field | Value |
| --- | --- |
| Test ID | E5 |
| Covered row IDs | T02 |
| Starting state | `phase=active, index=1, active=0, n=2, terminalReason=none` |
| Reset/fixture | Upstream never terminates. A second source exists |
| State-reaching prefix | `sub` |
| Target event | `srcNext(1)` and no terminal |
| Expected notifications | `outNext(1)` only |
| Expected lifecycle observations | No `eff:SubscribeSource(1)` |
| Distinguishing suffix | Silence of the tail is because the active source is still open, not because of an error policy |
| Expected final state | `phase=active, index=1, active=0, terminalReason=none` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (index moves only from the terminal finalizer) |

## F. Coverage and evidence

Denominator: 8 transition rows T01–T08. Specified 8/8. Executed 0/8.

Secondary denominator, not executed: 15 `it(...)` cases in `/tmp/rxjs/spec/operators/onErrorResumeNext-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- Complete and error both advance. The last of either is `outComplete`. The hypothesis that complete does not skip is not what `onErrorResumeNext.ts:89-94` does.
- No source error is reported, so callers cannot branch on which source failed. `catchError` is the operator that sees the error.
- `subscribeNext` is added as a finalizer of the active inner (`onErrorResumeNext.ts:91`). Downstream `unsub` unsubscribes that inner and therefore runs `subscribeNext`. Further sources can still be constructed. Each new `OperatorSubscriber` is added to an already closed destination, which unsubscribes it immediately (`Subscription.ts:120-123`), so further nexts are not delivered (`Subscriber.ts:68-70`), but the tail's subscribe functions can still run. Output-silent, lifecycle not a pure stop. Excluded as a reentrancy detail beyond T07's observer trace.
- Forwarded next uses `Subscriber._next` with no try/catch (`onNext` omitted). A throw from `destination.next` is not converted by this operator.
- Synchronous handoff is in-model (add-on-closed runs the finalizer). Unbounded user reentrancy is excluded.
