# rxjs-operator-behavior

Source-derived Mealy analyses of every file in
[`ReactiveX/rxjs` `src/internal/operators`](https://github.com/ReactiveX/rxjs/tree/7.8.2/src/internal/operators)
on the **7.x** line, pinned to **RxJS 7.8.2**, commit
[`e5351d02e225e275ac0e497c7b66eaa5f0c88791`](https://github.com/ReactiveX/rxjs/commit/e5351d02e225e275ac0e497c7b66eaa5f0c88791).

The shape of each file is the operator template in
[hansschenker/rxjs-mealy-analysis](https://github.com/hansschenker/rxjs-mealy-analysis/blob/main/docs/operator-analysis-template.md).
The method those files follow is
[docs/method.md](https://github.com/hansschenker/rxjs-mealy-analysis/blob/main/docs/method.md)
in that repository. This repo does not vendor that method; it applies it.

```text
M = (S, Σ, Γ, δ, λ, s₀)
```

Incoming `next` / `error` / `complete` are not the outgoing ones. Cancellation
is not completion. A throw from a user callback is not a source error.
`δ` and `λ` are the transition tables in each file: the same state and input
determine both the next state and the observable response.

## What is here

| Path | What it is |
| --- | --- |
| [operators/](operators/) | One analysis per source file (117 files, including four internal helpers) |
| [diagrams/](diagrams/) | State transition diagram and state × input table derived from section C. Currently `audit` and `auditTime` |
| [docs/index.md](docs/index.md) | Catalog grouped by behavior |
| [docs/reading-notes.md](docs/reading-notes.md) | Version facts that disagree with the usual one-line description |
| [docs/sources.md](docs/sources.md) | Pin, template, and what was not done |

## How to read one file

Sections A–G match the template:

| Section | Question it answers |
| --- | --- |
| A | Contract, parameter domain, model kind, exclusions |
| B | Six-tuple, state inventory, input inventory, output record |
| C | Guarded transitions. Every reachable active state accounts for next, error, complete, and cancel, or says why that pair cannot occur |
| D | Notification and lifetime invariants |
| E | State-reaching scenarios. These are specifications, not recorded test runs |
| F | Coverage against the rows in C. Execution status is `not executed` |
| G | `accept with documented limits` |

Model kind is stated per operator. A finite machine is claimed only where the
control state is finite. Counters, buffers, key sets, inner identities, and
deadlines are symbolic, extended, or timed.

## Status of the evidence

These documents were written by reading the 7.8.2 TypeScript, not by running
the RxJS test suite and not by running an executable reference model.

- No scenario in section E was executed here.
- No mutation experiment was performed.
- Section G is therefore **accept with documented limits** on every file.
- A row in C is an obligation. It is not a passing test.
- Where JSDoc and the implementation disagree, the file treats the
  implementation as the version characterization and says so.

Ordinary transitions assume each input runs to quiescence before the next
input arrives. Synchronous inner subscriptions that the operator itself
starts are in-model events. Calls from a downstream subscriber back into the
source during delivery are excluded unless a file says otherwise.
`take` is the exception to mention: the 7.8.2 source comments on reentrant
increments, and [operators/take.md](operators/take.md) keeps that outside the
ordinary model.

## Helpers that are not pipeable operators

| File | Role |
| --- | --- |
| [operators/OperatorSubscriber.md](operators/OperatorSubscriber.md) | Destination delivery, stopped flag, teardown |
| [operators/scanInternals.md](operators/scanInternals.md) | Shared accumulator used by `scan` and `reduce` |
| [operators/mergeInternals.md](operators/mergeInternals.md) | Concurrent flatten, queue, and complete-wait used by `mergeMap` and `expand` |
| [operators/joinAllInternals.md](operators/joinAllInternals.md) | `toArray`, then one join, used by `combineLatestAll` and `zipAll` |

## Not this repo

This is not an official RxJS document and not a proof that the implementation
matches a spec for every JavaScript value, scheduler, or reentrant callback.
Exclusions are modeling boundaries. They are not claims that RxJS rejects
those calls.

Reviewer note on the analyses: source-derived, 2026-10-21. Human review is
still required before treating a transition row as a test oracle.
