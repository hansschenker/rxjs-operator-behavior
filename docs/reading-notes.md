# Reading notes for 7.8.2

These are load-bearing version facts. Each one is argued in the linked
operator file from the pinned sources. They are characterizations of 7.8.2,
not advice to rely on accidental behavior, and not claims about later majors.

The ordinary contract (what a careful reader expects from the guide) is stated
first when it differs from the code.

## Counting and emptiness

- **`take(count <= 0)` does not subscribe.** It returns `EMPTY`
  (`take.ts`). `take(NaN)` does subscribe, because `NaN <= 0` is false.
  Early completion happens only when a positive integer `seen` meets `count`.
  `take(2.5)` forwards two values and then waits for the source; it does not
  complete on the second next. See [take](../operators/take.md).
- **`skipLast(count <= 0)` is `identity`.** Other non-lengths can throw
  `RangeError` from `new Array` before subscribe. The ring is not flushed on
  error or cancel. See [skipLast](../operators/skipLast.md).
- **`repeat(n)` counts subscriptions. `retry(n)` counts retries.**
  `repeat` uses `++soFar < count`, so `repeat(1)` subscribes once and
  `repeat(count <= 0)` is `EMPTY`. `retry` uses `soFar++ < count`, so
  `retry(1)` subscribes twice and `retry(count <= 0)` is `identity` (the
  error still flows). See [repeat](../operators/repeat.md) and
  [retry](../operators/retry.md).
- **Seedless `reduce` on an empty source completes with no `next`.**
  `scanInternals` emits on complete only when `hasState` is already true.
  There is no `EmptyError` in that path. `min` and `max` are seedless
  `reduce`s, so they complete the same way. A provided seed, including an
  explicit `undefined` (`arguments.length >= 2`), is emitted on that empty
  complete. `scan` does not use the complete-flush flag, so a seed is not
  emitted until a source value arrives. The `reduce` JSDoc line that equates
  `reduce` with `scan` + `last` does not hold for the empty seedless case:
  `last` would error. See [reduce](../operators/reduce.md),
  [scan](../operators/scan.md), [min](../operators/min.md).

## Notifiers and terminals

- **`takeUntil` completes on notifier `next` only.** Notifier `complete`
  leaves the source mirrored. **`skipUntil` opens on notifier `next` only.**
  Notifier `complete` leaves values skipped. A synchronous notifier error
  still reaches `source.subscribe` in `skipUntil`; `takeUntil` checks
  `subscriber.closed` first. See [takeUntil](../operators/takeUntil.md) and
  [skipUntil](../operators/skipUntil.md).
- **Delay notifiers that only `complete` do not count as a signal** for
  `debounce` and `audit`. `auditTime` still flushes because `timer` sends
  `next` before `complete`. `debounceTime` flushes a pending value on source
  `complete` and drops it on source `error`. See
  [debounceTime](../operators/debounceTime.md) and
  [audit](../operators/audit.md).
- **`sample`'s notifier `complete` is a no-op.** It does not emit the pending
  value and does not complete the output. Source `complete` drops an
  unsampled value. See [sample](../operators/sample.md).
- **`retry` / `repeat` delay:** notifier `next` resubscribes; notifier
  `complete` with no `next` completes the output without forwarding the
  original terminal; notifier `error` fails the output. See
  [retry](../operators/retry.md).
- **`onErrorResumeNext` moves on after `complete` and after `error`.**
  The last error is swallowed and the output completes. The name describes
  the interesting case; the 7.8.2 implementation also continues after a
  normal complete, which is what its own JSDoc says. See
  [onErrorResumeNextWith](../operators/onErrorResumeNextWith.md).

## Higher-order

- **`mergeMap` queues. `exhaustMap` drops. `switchMap` unsubscribes.**
  Default concurrency is `Infinity` (no queue). A finite cap FIFO-queues in
  `mergeInternals`. `concatMap` is that machine with concurrency 1.
  `exhaustMap` ignores outer values while an inner subscription exists,
  including a bad `ObservableInput` that would have thrown if subscribed.
  `switchMap` unsubscribes the previous inner before calling `project`.
  See [mergeMap](../operators/mergeMap.md),
  [exhaustMap](../operators/exhaustMap.md),
  [switchMap](../operators/switchMap.md).
- **`combineLatestAll` and `zipAll` do not join inners as they arrive.**
  `joinAllInternals` is `toArray`, then one `mergeMap` of the join on the
  collected array. Inners start after the outer completes. See
  [joinAllInternals](../operators/joinAllInternals.md).
- **`sequenceEqual(true)` checks the other buffer, not its own.**
  On `complete`, the source emits `true` when the other side is already
  complete and the other buffer is empty. Values already sitting in the
  completing side's own buffer are not rechecked. A longer sequence can
  therefore characterize as equal if the extra values were buffered before
  the short side completed. A later `next` after the short side completed
  still emits `false`. The JSDoc describes the intended pairwise contract;
  the complete-handler is the 7.8.2 characterization. See
  [sequenceEqual](../operators/sequenceEqual.md).

## Multicast defaults

- **`share` defaults:** `resetOnError`, `resetOnComplete`, and
  `resetOnRefCountZero` are all `true`, connector `() => new Subject()`.
  Reset runs before the terminal is forwarded, so a reset-on-error connection
  does not replay that error to the next subscriber. See
  [share](../operators/share.md).
- **`shareReplay` defaults `refCount` to `false` and `bufferSize` to
  `Infinity`.** The positional call `shareReplay(bufferSize, windowTime, scheduler)`
  does not enable `refCount`. `resetOnComplete` stays false; `resetOnError`
  is true. See [shareReplay](../operators/shareReplay.md).
- **Deprecated `publish*` captures one subject at operator-call time**, not
  per subscription. `publishBehavior` emits its seed before `connect`.
  `publishLast` is `AsyncSubject`: the last value is emitted on complete,
  including to late subscribers; an error does not flush it. See
  [publishBehavior](../operators/publishBehavior.md) and
  [publishLast](../operators/publishLast.md).

## Small contract traps

- **`find` / `findIndex` miss with `undefined` / `-1`, then complete.**
  They are not `first`. `every` on an empty source emits `true`.
- **`first` / `last` build `EmptyError` in the valueless complete path**,
  not at subscribe. An explicit `undefined` default counts
  (`arguments.length >= 2`).
- **`partition` subscribes twice.** It is two `filter`s with no `share`.
  A predicate throw fails only the branch that evaluated it.
- **`timestamp` defaults to `dateTimestampProvider`**, not `asyncScheduler`.
  The JSDoc that says otherwise does not match the default parameter.
  `timeInterval` does default to `asyncScheduler`.
- **`withLatestFrom()` with no others never becomes ready**, so source
  values are dropped. Another source's `complete` is ignored; its `error`
  is forwarded. There is no `EmptyError` for an other that completes without
  a value.
- **`race` treats the first `next`, `error`, or `complete` as the winner.**
  It does not wait for every source to complete before a lone complete wins.

Buffers generally drop a partial array on source error and emit it on source
complete. Windows error the open inners. Those splits are per file under
[buffer](../operators/buffer.md), [window](../operators/window.md), and their
siblings, because closing-notifier `complete` is not the same rule for
`buffer` / `bufferWhen` as for `windowWhen`.
