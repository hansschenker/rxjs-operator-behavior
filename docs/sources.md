# Sources

Reviewed 2026-10-21. Version-pinned URLs target **RxJS 7.8.2**. They are not a
recommendation to avoid later releases. Modeling choices in this repository
are analysis, not an RxJS guarantee.

## Pin

- Package: `rxjs@7.8.2`
- Commit: `e5351d02e225e275ac0e497c7b66eaa5f0c88791`
- Commit subject: `chore(publish): 7.8.2`
- Tag / branch tip used: `7.8.2`, which was the tip of `7.x` when this pin was taken
- Tree: `src/internal/operators/*.ts` (117 files)

Operator behavior was read from that tree and from the creation functions
those files call (`src/internal/observable/`, `Subscriber`, `Notification`).
No upstream source file is vendored here.

## Template and method

- Template: <https://github.com/hansschenker/rxjs-mealy-analysis/blob/main/docs/operator-analysis-template.md>
- Method: <https://github.com/hansschenker/rxjs-mealy-analysis/blob/main/docs/method.md>
- Worked `take` example in that repo: <https://github.com/hansschenker/rxjs-mealy-analysis/blob/main/docs/take-analysis.md>

The Mealy six-tuple used there is the classical one: current state and input
determine next state and output. Error and completion stay inside `Σ` and `Γ`.
See that repo's `docs/sources.md` for the formal reference it cites.

## What was not done

- RxJS specs under `spec/operators/` were not executed.
- No executable `step` model was added in this repository.
- No mutation testing.
- Schedulers are described as ordering assumptions. Same-timestamp order is
  not treated as a proof about `asyncScheduler` wall-clock interleavings.

A test file's absence is the status. Do not read section E as a green run.
