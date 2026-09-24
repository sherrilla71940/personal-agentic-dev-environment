# ADR-0041: Rename task workflow and continuity surfaces

- Status: Accepted
- Date: 2026-09-24

This decision is superseded by [ADR-0045](./0045-coordinated-naming-cleanup.md) for the final
naming cleanup; its migration-window rationale remains historical.

## Context

The workflow supports both `workspace=checkout` and `workspace=worktree`, so `task-workflow` is
still narrower than the behavior it exposes. Likewise, `project-continuity` describes the
repository rather than the task state that the record actually carries. The names appear in skill
folders, slash commands, hooks, rendered targets, state paths, tests, and documentation.

The rename must not strand existing client prompts, hook registrations, or ignored continuity state.
The active checkout currently has one state file and parked handoffs under `.task-continuity/`,
migrated from the old directory during this change.

## Decision

Use these canonical names:

- `run-task-end-to-end` for the end-to-end task workflow;
- `task-continuity` for the continuity skill;
- `.task-continuity/` for active and parked state; and
- `maintain-task-continuity.sh` for the shared lifecycle hook.

Keep `task-workflow`, `worktree-task-workflow`, and `project-continuity` as explicit-only
compatibility wrappers. Keep `.project-continuity/` and `maintain-project-continuity.sh` readable
and protected as legacy paths during migration. The lifecycle hook reads canonical state first and
falls back to the legacy path; it never merges two directories or silently overwrites state.

The canonical workflow and continuity bodies remain single-sourced. Client-specific adapters,
symlinks, manifests, tests, and documentation use the canonical names; compatibility files contain
only redirects or legacy protections. Historical archive paths are not renamed.

## Alternatives considered

### Remove the old names immediately

Rejected because existing prompts, client history, hook approvals, and explicit invocations would
break at once.

### Keep the old names as the canonical names

Rejected because both names hide the actual scope: the task workflow is not worktree-only and the
continuity record belongs to a task, not a whole project.

### Automatically merge old and new continuity directories

Rejected because two active state files could describe different tasks. Migration must preserve the
whole directory and stop when both paths exist.

## Consequences

New sessions and documentation use names that describe the behavior. Existing clients continue to
resolve the old names while the compatibility period lasts. The ignored-state migration preserves
the active task and all parked handoffs, while both old and new exclude entries protect state from
accidental tracking.

## Reconsider when

Remove compatibility wrappers only after known prompts and client history no longer depend on them,
and only as an explicit breaking change. Remove the legacy state fallback only after all existing
working directories have migrated without collision.

## Related files and verification

- [`home/.chezmoitemplates/skills/run-task-end-to-end/`](../../home/.chezmoitemplates/skills/run-task-end-to-end/)
- [`home/dot_agents/skills/task-continuity/`](../../home/dot_agents/skills/task-continuity/)
- [`home/dot_local/share/maintain-task-continuity.sh.tmpl`](../../home/dot_local/share/maintain-task-continuity.sh.tmpl)
- [`home/.chezmoitemplates/continuity.md`](../../home/.chezmoitemplates/continuity.md)
- [`scripts/tests/test-task-continuity.sh`](../../scripts/tests/test-task-continuity.sh)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
