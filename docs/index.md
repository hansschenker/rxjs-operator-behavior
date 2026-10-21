# Operator catalog

Pin: RxJS 7.8.2, `e5351d02e225e275ac0e497c7b66eaa5f0c88791`.
Each link is a Mealy analysis of the file of the same name under
`src/internal/operators`. Deprecated operators are still analyzed, because
they are still in that tree.

## Internal helpers

| Source | Analysis |
| --- | --- |
| `OperatorSubscriber.ts` | [OperatorSubscriber](../operators/OperatorSubscriber.md) |
| `scanInternals.ts` | [scanInternals](../operators/scanInternals.md) |
| `mergeInternals.ts` | [mergeInternals](../operators/mergeInternals.md) |
| `joinAllInternals.ts` | [joinAllInternals](../operators/joinAllInternals.md) |

## Transform and aggregate

| Operator | Analysis |
| --- | --- |
| `map` | [map](../operators/map.md) |
| `mapTo` | [mapTo](../operators/mapTo.md) |
| `pluck` | [pluck](../operators/pluck.md) |
| `scan` | [scan](../operators/scan.md) |
| `reduce` | [reduce](../operators/reduce.md) |
| `count` | [count](../operators/count.md) |
| `min` | [min](../operators/min.md) |
| `max` | [max](../operators/max.md) |
| `toArray` | [toArray](../operators/toArray.md) |
| `pairwise` | [pairwise](../operators/pairwise.md) |
| `materialize` | [materialize](../operators/materialize.md) |
| `dematerialize` | [dematerialize](../operators/dematerialize.md) |
| `timestamp` | [timestamp](../operators/timestamp.md) |
| `timeInterval` | [timeInterval](../operators/timeInterval.md) |

## Filter, slice, and search

| Operator | Analysis |
| --- | --- |
| `filter` | [filter](../operators/filter.md) |
| `distinct` | [distinct](../operators/distinct.md) |
| `distinctUntilChanged` | [distinctUntilChanged](../operators/distinctUntilChanged.md) |
| `distinctUntilKeyChanged` | [distinctUntilKeyChanged](../operators/distinctUntilKeyChanged.md) |
| `skip` | [skip](../operators/skip.md) |
| `skipLast` | [skipLast](../operators/skipLast.md) |
| `skipUntil` | [skipUntil](../operators/skipUntil.md) |
| `skipWhile` | [skipWhile](../operators/skipWhile.md) |
| `take` | [take](../operators/take.md) |
| `takeLast` | [takeLast](../operators/takeLast.md) |
| `takeUntil` | [takeUntil](../operators/takeUntil.md) |
| `takeWhile` | [takeWhile](../operators/takeWhile.md) |
| `first` | [first](../operators/first.md) |
| `last` | [last](../operators/last.md) |
| `single` | [single](../operators/single.md) |
| `elementAt` | [elementAt](../operators/elementAt.md) |
| `find` | [find](../operators/find.md) |
| `findIndex` | [findIndex](../operators/findIndex.md) |
| `every` | [every](../operators/every.md) |
| `ignoreElements` | [ignoreElements](../operators/ignoreElements.md) |
| `isEmpty` | [isEmpty](../operators/isEmpty.md) |
| `defaultIfEmpty` | [defaultIfEmpty](../operators/defaultIfEmpty.md) |
| `throwIfEmpty` | [throwIfEmpty](../operators/throwIfEmpty.md) |
| `partition` | [partition](../operators/partition.md) |

## Side effects

| Operator | Analysis |
| --- | --- |
| `tap` | [tap](../operators/tap.md) |
| `finalize` | [finalize](../operators/finalize.md) |

## Time, rate, buffer, window

| Operator | Analysis |
| --- | --- |
| `audit` | [audit](../operators/audit.md) |
| `auditTime` | [auditTime](../operators/auditTime.md) |
| `debounce` | [debounce](../operators/debounce.md) |
| `debounceTime` | [debounceTime](../operators/debounceTime.md) |
| `throttle` | [throttle](../operators/throttle.md) |
| `throttleTime` | [throttleTime](../operators/throttleTime.md) |
| `sample` | [sample](../operators/sample.md) |
| `sampleTime` | [sampleTime](../operators/sampleTime.md) |
| `delay` | [delay](../operators/delay.md) |
| `delayWhen` | [delayWhen](../operators/delayWhen.md) |
| `timeout` | [timeout](../operators/timeout.md) |
| `timeoutWith` | [timeoutWith](../operators/timeoutWith.md) |
| `observeOn` | [observeOn](../operators/observeOn.md) |
| `subscribeOn` | [subscribeOn](../operators/subscribeOn.md) |
| `buffer` | [buffer](../operators/buffer.md) |
| `bufferCount` | [bufferCount](../operators/bufferCount.md) |
| `bufferTime` | [bufferTime](../operators/bufferTime.md) |
| `bufferToggle` | [bufferToggle](../operators/bufferToggle.md) |
| `bufferWhen` | [bufferWhen](../operators/bufferWhen.md) |
| `window` | [window](../operators/window.md) |
| `windowCount` | [windowCount](../operators/windowCount.md) |
| `windowTime` | [windowTime](../operators/windowTime.md) |
| `windowToggle` | [windowToggle](../operators/windowToggle.md) |
| `windowWhen` | [windowWhen](../operators/windowWhen.md) |

## Higher-order

| Operator | Analysis |
| --- | --- |
| `mergeMap` | [mergeMap](../operators/mergeMap.md) |
| `mergeMapTo` | [mergeMapTo](../operators/mergeMapTo.md) |
| `mergeAll` | [mergeAll](../operators/mergeAll.md) |
| `flatMap` | [flatMap](../operators/flatMap.md) |
| `concatMap` | [concatMap](../operators/concatMap.md) |
| `concatMapTo` | [concatMapTo](../operators/concatMapTo.md) |
| `concatAll` | [concatAll](../operators/concatAll.md) |
| `switchMap` | [switchMap](../operators/switchMap.md) |
| `switchMapTo` | [switchMapTo](../operators/switchMapTo.md) |
| `switchAll` | [switchAll](../operators/switchAll.md) |
| `switchScan` | [switchScan](../operators/switchScan.md) |
| `exhaustMap` | [exhaustMap](../operators/exhaustMap.md) |
| `exhaustAll` | [exhaustAll](../operators/exhaustAll.md) |
| `exhaust` | [exhaust](../operators/exhaust.md) |
| `expand` | [expand](../operators/expand.md) |
| `mergeScan` | [mergeScan](../operators/mergeScan.md) |
| `combineLatestAll` | [combineLatestAll](../operators/combineLatestAll.md) |
| `combineAll` | [combineAll](../operators/combineAll.md) |
| `zipAll` | [zipAll](../operators/zipAll.md) |

## Combine, prefix, and suffix

| Operator | Analysis |
| --- | --- |
| `merge` | [merge](../operators/merge.md) |
| `mergeWith` | [mergeWith](../operators/mergeWith.md) |
| `concat` | [concat](../operators/concat.md) |
| `concatWith` | [concatWith](../operators/concatWith.md) |
| `combineLatest` | [combineLatest](../operators/combineLatest.md) |
| `combineLatestWith` | [combineLatestWith](../operators/combineLatestWith.md) |
| `zip` | [zip](../operators/zip.md) |
| `zipWith` | [zipWith](../operators/zipWith.md) |
| `race` | [race](../operators/race.md) |
| `raceWith` | [raceWith](../operators/raceWith.md) |
| `withLatestFrom` | [withLatestFrom](../operators/withLatestFrom.md) |
| `startWith` | [startWith](../operators/startWith.md) |
| `endWith` | [endWith](../operators/endWith.md) |
| `sequenceEqual` | [sequenceEqual](../operators/sequenceEqual.md) |

## Errors and resubscription

| Operator | Analysis |
| --- | --- |
| `catchError` | [catchError](../operators/catchError.md) |
| `retry` | [retry](../operators/retry.md) |
| `retryWhen` | [retryWhen](../operators/retryWhen.md) |
| `repeat` | [repeat](../operators/repeat.md) |
| `repeatWhen` | [repeatWhen](../operators/repeatWhen.md) |
| `onErrorResumeNextWith` | [onErrorResumeNextWith](../operators/onErrorResumeNextWith.md) |

## Multicast

| Operator | Analysis |
| --- | --- |
| `share` | [share](../operators/share.md) |
| `shareReplay` | [shareReplay](../operators/shareReplay.md) |
| `connect` | [connect](../operators/connect.md) |
| `multicast` | [multicast](../operators/multicast.md) |
| `publish` | [publish](../operators/publish.md) |
| `publishBehavior` | [publishBehavior](../operators/publishBehavior.md) |
| `publishLast` | [publishLast](../operators/publishLast.md) |
| `publishReplay` | [publishReplay](../operators/publishReplay.md) |
| `refCount` | [refCount](../operators/refCount.md) |
| `groupBy` | [groupBy](../operators/groupBy.md) |
