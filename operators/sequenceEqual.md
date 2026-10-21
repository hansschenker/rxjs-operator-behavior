# sequenceEqual

`sequenceEqual(compareTo, comparator?)` subscribes to the source and to `innerFrom(compareTo)` together (`sequenceEqual.ts:122-123`). It emits one boolean and then completes (`sequenceEqual.ts:74-77`). The default comparator is `===` (`sequenceEqual.ts:65`). Each side keeps a buffer and a complete flag (`sequenceEqual.ts:130-146`). A value is compared against the other side's oldest buffered value when that buffer is non-empty: `comparator(justArrived, otherBuffered)` (`sequenceEqual.ts:101`). Argument order is arrival order, not a stable `(source, compareTo)` order. A falsy result emits `false` and completes, which unsubscribes both because both subscribers were added to the destination (`Subscriber.ts:53-54`, `Subscriber.ts:124-129`). If the other buffer is empty and the other side is already complete, the extra value emits `false` (`sequenceEqual.ts:89-96`). If the other side is not complete, the value is buffered. On complete, the side marks itself complete, emits only if the other side is already complete, and the boolean is `other.buffer.length === 0` (`sequenceEqual.ts:104-112`). It then unsubscribes itself (`sequenceEqual.ts:114`). `true` is that second-complete path with an empty other buffer, after pairwise comparisons have not already failed. A comparator throw is a user-callback fault: `buffer.shift()` has already removed the other value, and `OperatorSubscriber` sends `destination.error` (`sequenceEqual.ts:101`, `OperatorSubscriber.ts:67-74`). Either side's error is forwarded and unsubscribes the other side with the destination (`onError` omitted).

The complete-path predicate does not read the completing side's own buffer. If the longer side already buffered extras, the shorter side completes first (no decision, because the longer side is not complete), and the longer side then completes, the code sees an empty other buffer and emits `true` (`sequenceEqual.ts:111`). A later `next` on the longer side after the shorter side completed emits `false` (`sequenceEqual.ts:89-96`). Synchronous sources often avoid the hole because the source is subscribed first and, when it is the longer synchronous sequence, it completes first and leaves leftovers for the compareTo completer to see (`sequenceEqual.ts:122-123`).

## A. Identity, contract, and scope

| Field | Value |
| --- | --- |
| Name | `sequenceEqual` |
| Kind | Public pipeable operator |
| Module | `/tmp/rxjs/src/internal/operators/sequenceEqual.ts` |
| Package | RxJS 7.8.2, commit `e5351d02e225e275ac0e497c7b66eaa5f0c88791` |
| Signature | `(compareTo: ObservableInput<T>, comparator?: (a: T, b: T) => boolean) => OperatorFunction<T, boolean>` (`sequenceEqual.ts:63-66`) |
| Default comparator | `(a, b) => a === b` (`sequenceEqual.ts:65`) |
| Output | At most one `outNext(boolean)` followed by `outComplete` (`sequenceEqual.ts:74-77`) |
| Subscribe order | Source, then `innerFrom(compareTo)` (`sequenceEqual.ts:122-123`) |
| Mismatch | `false` then complete, both unsubscribed via destination complete |
| Equal | `true` then complete only from the complete handler when the other side is complete and its buffer is empty (`sequenceEqual.ts:111`) |
| Error | Either side: `outError` of that error. Comparator throw: `outError(thrown)`, not `false` |
| `innerFrom` throw | Inside `operate` init, caught as `subscriber.error` (`lift.ts:23-26`, `innerFrom.ts:41`) |
| Deprecated | No |
| Notifier | None. `waiting-for-notifier` and `resubscribing` are unused |

## B. Six-tuple

`M = (S, Σ, Γ, δ, λ, s₀)`.

`s₀ = (phase=init, aBuf=[], bBuf=[], aDone=false, bDone=false, aOpen=false, bOpen=false, terminalReason=none)`.

`a` is the source. `b` is `compareTo`.

### S

| Field | Domain | Role |
| --- | --- | --- |
| phase | `init`, `active`, `terminal` | `active` covers both-open and one-side-complete. No notifier wait and no resubscribe |
| aBuf, bBuf | queues | Unmatched values on that side. At most one is non-empty after a comparison step, because a value is buffered only when the other buffer is empty (`sequenceEqual.ts:89-96`) |
| aDone, bDone | bool | Set in the complete handler before the equality test (`sequenceEqual.ts:106`) |
| aOpen, bOpen | bool | False after that side's subscriber unsubscribes |
| terminalReason | `none`, `complete`, `error`, `unsub` | `complete` here means the boolean decision completed the output |

### Σ (8 categories)

| Category | Applicable? | Symbols |
| --- | --- | --- |
| Initialization subscribe | Yes | `sub` subscribes `a` then `b` |
| Source next | Yes | `aNext(v)` |
| Source error | Yes | `aError(e)` forwarded |
| Source completion | Yes | `aComplete` |
| Cancellation cancel | Yes | `unsub` drops both |
| Inner notifications | Yes, the compareTo side is the inner | `bNext(v)`, `bError(e)`, `bComplete` are distinct. They are not a retry notifier |
| Time | No | No clock in this file |
| User callback outcomes | Yes | `cmpThrow(e)` from `comparator`. `innerFromThrow(e)` if `compareTo` is not an observable input |

### Γ

`outNext(false)` | `outNext(true)` | `outComplete` | `outError(e)` | `ε`

Lifecycle: `eff:SubscribeA`, `eff:SubscribeB`, `eff:UnsubscribeA`, `eff:UnsubscribeB`. Destination complete or error unsubscribes whichever of A and B is still a child.

## C. Transition obligations

| ID | From | Event | Guard | To | λ |
| --- | --- | --- | --- | --- | --- |
| T01 | init | `sub` | `innerFrom(compareTo)` ok | active, aOpen, bOpen | `ε` + `eff:SubscribeA` + `eff:SubscribeB` (`sequenceEqual.ts:122-123`) |
| T02 | init | `sub` | `innerFrom` throws | terminal, terminalReason=error | `outError(thrown)` (`lift.ts:23-26`). Source may already have run synchronously before the throw |
| T03 | active | `aNext(v)` or `bNext(v)` | other buffer non-empty and comparator truthy | active, other buffer shifted | `ε` (`sequenceEqual.ts:97-102`) |
| T04 | active | `aNext(v)` or `bNext(v)` | other buffer non-empty and comparator falsy | terminal, terminalReason=complete | `outNext(false)`, `outComplete`, both unsubscribed (`sequenceEqual.ts:101`, `sequenceEqual.ts:74-77`) |
| T05 | active | `aNext(v)` or `bNext(v)` | other buffer empty and other not done | active, value pushed on self | `ε` (`sequenceEqual.ts:96`) |
| T06 | active | `aNext(v)` or `bNext(v)` | other buffer empty and other done | terminal, terminalReason=complete | `outNext(false)`, `outComplete` (`sequenceEqual.ts:89-96`) |
| T07 | active | `aComplete` or `bComplete` | other not done | active, self done, self unsubscribed, self open=false | `ε` + `eff:UnsubscribeSelf` (`sequenceEqual.ts:104-114`) |
| T08 | active | `aComplete` or `bComplete` | other done and other buffer empty | terminal, terminalReason=complete | `outNext(true)`, `outComplete` (`sequenceEqual.ts:111-112`) |
| T09 | active | `aComplete` or `bComplete` | other done and other buffer non-empty | terminal, terminalReason=complete | `outNext(false)`, `outComplete` (`sequenceEqual.ts:111`) |
| T10 | active | `aNext` or `bNext` | comparator throws | terminal, terminalReason=error | `outError(thrown)`. Not `outNext(false)` (`OperatorSubscriber.ts:67-74`) |
| T11 | active | `aError(e)` or `bError(e)` | — | terminal, terminalReason=error | `outError(e)`, other side unsubscribed with destination |
| T12 | active | `unsub` | — | terminal, terminalReason=unsub | `ε`. No boolean |
| T13 | terminal | any | — | terminal | `ε` |

T08 is not "both buffers empty". It is "other buffer empty". Own buffered values are not consulted. That is the length-mismatch hole.

T04/T06/T08/T09 all end by `subscriber.next` then `subscriber.complete`. A second decision hits a stopped destination and is not a second boolean (`Subscriber.ts:68-70`, `Subscriber.ts:95-97`).

Comparator call shape: `comparator(arrived, bufferedOther)` (`sequenceEqual.ts:101`). If `b` arrives second, the call is `comparator(bValue, aValue)`.

`waiting-for-notifier` and `resubscribing`: no rows. One-sided completion is still `active` (T07), waiting for the other side's next or complete.

## D. Contract invariants

1. At most one boolean is emitted, and a boolean is always followed by `outComplete` from `emit` (`sequenceEqual.ts:74-77`).
2. Pairwise failure (falsy comparator) emits `false` immediately and does not wait for the tails.
3. A next on a side whose partner is already complete with an empty buffer emits `false` (the partner was shorter).
4. The second complete emits `true` only when the other buffer is empty, and `false` when it is not. Own buffer is not part of that boolean.
5. While one side is not complete, the output is silent even if the other completed (T07), unless a later next takes T06.
6. Either side's error is `outError` and prevents a boolean. Comparator throw is the same shape of terminal but the error is the throw, not the source error.
7. Buffers are FIFO. `shift` happens before the comparator runs, including when the comparator throws.
8. No resubscribe. Both subscriptions start at T01 and only end.

## E. Scenario specification

### E1

| Field | Value |
| --- | --- |
| Test ID | E1 |
| Covered row IDs | T01, T05, T03, T07, T08 |
| Starting state | `phase=init, aBuf=[], bBuf=[], aDone=false, bDone=false, aOpen=false, bOpen=false, terminalReason=none` |
| Reset/fixture | Default `===`. Source and compareTo both emit `1` then `2` then complete. CompareTo emits slightly later |
| State-reaching prefix | `sub` |
| Target event | `aNext(1)`, `aNext(2)`, `bNext(1)`, `bNext(2)`, `aComplete`, `bComplete` |
| Expected notifications | `outNext(true)`, `outComplete` |
| Expected lifecycle observations | `eff:SubscribeA`, `eff:SubscribeB`. Comparisons are `comparator(1, 1)` and `comparator(2, 2)` because `b` arrives against `a`'s buffer. Completes unsubscribe each side; the second complete completes the destination |
| Distinguishing suffix | No second boolean |
| Expected final state | `phase=terminal, aBuf=[], bBuf=[], aDone=true, bDone=true, aOpen=false, bOpen=false, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence (notifications, lifecycle, final state) |
| Oracle source | source characterization (`sequenceEqual.ts:87-115`) |

### E2

| Field | Value |
| --- | --- |
| Test ID | E2 |
| Covered row IDs | T03, T04 |
| Starting state | `phase=active, aBuf=[1], bBuf=[], aDone=false, bDone=false, aOpen=true, bOpen=true, terminalReason=none` |
| Reset/fixture | Default comparator. Next compareTo value is `9` |
| State-reaching prefix | `sub`, `aNext(1)` buffered |
| Target event | `bNext(9)` |
| Expected notifications | `outNext(false)`, `outComplete` |
| Expected lifecycle observations | Both unsubscribed by destination complete. `aBuf` shifted before the comparison |
| Distinguishing suffix | The remaining tails are not read |
| Expected final state | `phase=terminal, terminalReason=complete, aOpen=false, bOpen=false` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`sequenceEqual.ts:97-102`) |

### E3

| Field | Value |
| --- | --- |
| Test ID | E3 |
| Covered row IDs | T07, T06 |
| Starting state | `phase=active, aBuf=[], bBuf=[], aDone=false, bDone=false, aOpen=true, bOpen=true, terminalReason=none` |
| Reset/fixture | compareTo completes with no values. Source later emits `1` |
| State-reaching prefix | `sub`, `bComplete` → T07, `bDone=true`, `bOpen=false`, no output |
| Target event | `aNext(1)` |
| Expected notifications | `outNext(false)`, `outComplete` |
| Expected lifecycle observations | `eff:UnsubscribeB` at T07. T06 unsubscribes A via destination complete |
| Distinguishing suffix | Not silent, because the extra next happened after the short side completed. Contrast E5 |
| Expected final state | `phase=terminal, aDone=false, bDone=true, terminalReason=complete` (`aDone` stays false because A did not complete; the destination stopped on T06) |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`sequenceEqual.ts:89-96`, `sequenceEqual.ts:104-114`) |

### E4

| Field | Value |
| --- | --- |
| Test ID | E4 |
| Covered row IDs | T10, T11 |
| Starting state | `phase=active, aBuf=[1], bBuf=[], aDone=false, bDone=false, aOpen=true, bOpen=true, terminalReason=none` |
| Reset/fixture | Comparator throws on the first comparison. Separate row: `bError(e)` instead |
| State-reaching prefix | `sub`, `aNext(1)` |
| Target event | `bNext(1)` with `cmpThrow(bad)`, or alternatively `bError(e)` before any next |
| Expected notifications | `outError(bad)` for the throw. `outError(e)` for the side error. Neither emits a boolean |
| Expected lifecycle observations | `shift` already happened if the throw is inside `comparator(...)`. Destination error unsubscribes both |
| Distinguishing suffix | Not `outNext(false)` |
| Expected final state | `phase=terminal, terminalReason=error, aOpen=false, bOpen=false` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`sequenceEqual.ts:101`, `OperatorSubscriber.ts:67-74`, default `_error` `Subscriber.ts:116-121`) |

### E5

| Field | Value |
| --- | --- |
| Test ID | E5 |
| Covered row IDs | T05, T07, T08 |
| Starting state | `phase=active, aBuf=[], bBuf=[], aDone=false, bDone=false, aOpen=true, bOpen=true, terminalReason=none` |
| Reset/fixture | Source emits `a` and does not complete yet. compareTo then completes with no values. Source completes later with no further next |
| State-reaching prefix | `sub` |
| Target event | `aNext("a")`, `bComplete`, `aComplete` |
| Expected notifications | `outNext(true)`, `outComplete` |
| Expected lifecycle observations | `aBuf=["a"]` after the next (T05). `bComplete` is T07 because A is not done, so no boolean yet, and B's buffer is empty. `aComplete` is T08 because B is done and `bBuf.length === 0`. Own buffer `["a"]` is ignored |
| Distinguishing suffix | The sequences are not the same length. `false` would be the informal contract; the source emits `true`. A further `aNext` instead of `aComplete` would have been T06 and `false` |
| Expected final state | `phase=terminal, aBuf=["a"], bBuf=[], aDone=true, bDone=true, terminalReason=complete` |
| Version and scheduler | RxJS 7.8.2, no scheduler |
| Assertion type | Trace equivalence |
| Oracle source | source characterization (`sequenceEqual.ts:104-112`). Not an executed spec |

## F. Coverage and evidence

Denominator: 13 transition rows T01–T13. Specified 13/13. Executed 0/13.

Secondary denominator, not executed: 23 `it(...)` cases in `/tmp/rxjs/spec/operators/sequenceEqual-spec.ts`.

No pass/fail fraction is claimed.

## G. Review decision

Decision: accept with documented limits

Reviewer: source-derived analysis (Grok)

Date: 2026-10-21

Mutations: none

Limits:

- `true` is not quite "both sides complete with equal length". It is "the second completer sees an empty other buffer" after earlier pairwise checks passed. E5 is the own-buffer hole: extras already stored on the completing side are not read (`sequenceEqual.ts:111`).
- `false` on a longer sequence is reliable when the extra element is a `next` after the short side has completed (T06), or when the second completer observes leftovers in the other buffer (T09), or when the comparator is falsy (T04).
- Comparator order is `(arrived, bufferedOther)`, so a non-commutative comparator is arrival-sensitive.
- `innerFrom` failure and comparator throw are `outError`, not `false`.
- No notifier and no resubscribe. Unbounded reentrancy is excluded. Synchronous emission during T01 is ordered: all source signals before `compareTo` is subscribed.
