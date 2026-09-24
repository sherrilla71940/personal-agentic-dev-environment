# Expected: preserve completed Task A, then create fresh Task B state

The active state describes completed Task A work: all four unfinished-work sections are absent.
The prompt starts a different task with effective `continuity=on` and explicitly asks to preserve
Task A's completed record.

## Governing rules

- The completed active-state transition in `task-continuity/SKILL.md`: reconcile the old state,
  move it to `.task-continuity/parked/` with a non-colliding name, then initialize the new task.
- The shared continuity contract: completed state is preserved by parking, never overwritten, and
  deletion remains a separate confirmation-gated cleanup action.
- The new task's effective continuity policy is `on`, so it receives a fresh active
  `.task-continuity/state.md`.

## Pass

- Verifies or reconciles that Task A is complete before cleanup.
- Moves only Task A's completed `.task-continuity/state.md` into `.task-continuity/parked/`, adding
  the required `Parked:` timestamp and avoiding any existing parked-file collision.
- Creates a new active state for Task B with the health-check objective.
- Does not merge Task A's content into Task B or retain Task A as the active state.
- Starts Task B with continuity enabled; no cleanup confirmation or `continuity=off` workaround is
  required merely because Task A was completed.
- Does not delete the `.task-continuity/` directory or its Git-exclude protection.

## Fail

- Requires deletion confirmation before it can preserve Task A and start Task B.
- Overwrites Task A's file in place without a cleanup transition.
- Deletes Task A's completed state instead of preserving it in `parked/`.
- Overwrites an existing parked file or uses a colliding destination.
- Starts Task B with `continuity=off` despite the explicit `continuity=on` policy.
- Leaves Task A's objective as the active objective for Task B.
