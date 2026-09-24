# ADR-0042: Preserve completed continuity by parking at task transition

- Status: Accepted
- Date: 2026-09-24

## Context

Continuity allows one active `state.md` per working directory and already has a `parked/` area for
state that must remain available while another task runs. The previous completed-state transition
treated a completed active record differently: it required deletion confirmation before a new
continuity-enabled task could initialize, and otherwise forced the new task to use
`continuity=off` or wait. That made completed state a recurring blocker even though its contents
were no longer active work.

The repository still must not silently discard or overwrite handoff information. Unfinished state
also still needs an explicit finish, park, or abandon decision because it may represent work that
another session must resume.

## Decision

When a different task encounters a completed active `.task-continuity/state.md`:

1. Reconcile the finished invariant and run the completion check. Because this is a transition to a
   different task, do not pause for active-state deletion confirmation first.
2. Move it to `.task-continuity/parked/` with its `Parked:` timestamp and an objective-derived,
   non-colliding name. Never overwrite an existing active or parked record.
3. Initialize a fresh active state for the new task when effective continuity is enabled.
4. Treat deletion of the preserved completed record as a separate cleanup decision. Report it as a
   closure candidate and delete it only after the user confirms that named file.

This transition applies to both `workspace=checkout` and `workspace=worktree`. It does not change
the unfinished-task rule: an unfinished state must be finished, explicitly parked, or explicitly
abandoned before another continuity-enabled task starts. If effective continuity is `off`, the
workflow does not initialize or update the new task's state; it also does not delete or overwrite
the existing record.

## Alternatives considered

- **Require deletion confirmation before starting the next continuity-enabled task.** Rejected
  because completed state should not block a new task when the existing parked area can preserve it.
- **Delete completed active state automatically.** Rejected because completion does not prove that
  the user no longer needs the handoff record.
- **Overwrite the active file with the new task.** Rejected because it destroys recoverable state.
- **Treat a completed record like unfinished state and require an explicit park decision.** Rejected
  because the transition is deterministic and preservation is the safe default for a completed task.

## Consequences

Starting a new continuity-enabled task no longer requires cleanup confirmation or a temporary
`continuity=off` override solely because a completed record exists. The parked directory can contain
completed closure candidates as well as unfinished handoffs, so the existing non-destructive review
and confirmation-gated deletion rules remain necessary. A parked record is local preservation, not a
durable project archive; Git history and the pull request remain authoritative for project reasoning.

## Reconsider when

Revisit this decision if continuity gains a durable task registry, a supported client provides a
portable atomic move-and-create operation, or parked-state growth becomes a material operational
problem despite the existing review and explicit deletion rules.

## Related files and verification

- [`home/dot_agents/skills/task-continuity/SKILL.md`](../../home/dot_agents/skills/task-continuity/SKILL.md)
- [`home/.chezmoitemplates/continuity.md`](../../home/.chezmoitemplates/continuity.md)
- [`home/.chezmoitemplates/skills/run-task-end-to-end/lifecycle.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/lifecycle.md)
- [`home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
- [`scripts/tests/continuity-fixtures/16-completed-state-to-new-task/`](../../scripts/tests/continuity-fixtures/16-completed-state-to-new-task/)
- [`scripts/tests/test-run-task-end-to-end.sh`](../../scripts/tests/test-run-task-end-to-end.sh)

Verify with the route contract test, the continuity hook test, and the manual fixture under
`scripts/tests/continuity-fixtures/`.
