# ADR-0043: Restore parked continuity by Git identity

- Status: Accepted
- Date: 2026-09-24

## Context

Continuity is scoped to a working directory, so one checkout can be reused by several sequential
tasks. Parking preserves the earlier task, but a directory listing alone does not tell a later
session which parked record belongs to the branch it has reopened. The branch is useful evidence,
but branches can be renamed, rebased, or reused. Older parked records also lack the metadata needed
for a machine-readable match.

## Decision

New workflow-created continuity records retain these identity fields in `Verification`:

- `Task`: a short stable label derived from the explicit task or prompt;
- `Branch`: the task branch, when the checkout has one;
- `Base branch`: the selected workflow base, when one exists;
- `Base commit`: the immutable `origin/<base>` commit used to start the task; and
- `Started from`: the same immutable commit as `Base commit`, retained as a compatibility alias.

Parking preserves these fields and adds only `Parked`. When no active state exists and the current
checkout has a named branch, the continuity skill may select one parked record only when all of the
following conditions hold:

1. The parked `Branch` exactly matches the current branch.
2. The parked record has a non-placeholder `Task` and `Base commit`, or legacy `Started from`.
3. The recorded start commit is reachable from the current `HEAD`.
4. The current task request matches the parked task and objective after reconciliation.

A unique exact-branch match is a discovery result, not proof that the task is current. The skill
moves the selected file back to `state.md`, removes its `Parked` marker, preserves the identity
fields, and runs the ordinary Resume workflow. Multiple candidates, branch-only or legacy records,
detached `HEAD`, rebased-away start commits, and conflicting task intent require explicit file
selection or user confirmation. The lifecycle hook reports candidates but never moves, rewrites, or
deletes continuity state.

## Alternatives considered

- **Use branch name as the sole lookup key.** Rejected because branches can be renamed, rebased, or
  reused, and detached worktrees have no branch name.
- **Use only objective text or the parked filename.** Rejected because prose and filenames are not
  stable machine identity and can collide.
- **Automatically choose the first branch match.** Rejected because directory order is not task
  identity and would silently restore the wrong handoff.
- **Rewrite every existing parked record immediately.** Rejected because legacy records must remain
  preserved and explicit review is safer than an unverified bulk rewrite.
- **Make the hook perform the restore.** Rejected because hook execution is report-only and cannot
  safely resolve user intent or active-state conflicts.

## Consequences

Returning to a previous named branch can resume a unique, well-formed parked task without requiring
the user to remember a filename. The task and Git checks still prevent branch-only restoration, and
legacy records remain usable through explicit selection and reconciliation. New records are more
verbose, and older parked records will produce manual-review notices until a user reconciles them.

## Reconsider when

Revisit this decision if the continuity format gains a durable task identifier registry, if clients
provide a portable atomic restore operation, or if branch reuse and rebasing require a stronger
repository-level identity than task label plus objective and immutable start commit.

## Related files and verification

- [`home/dot_agents/skills/task-continuity/SKILL.md`](../../home/dot_agents/skills/task-continuity/SKILL.md)
- [`home/dot_agents/skills/task-continuity/references/state-format.md`](../../home/dot_agents/skills/task-continuity/references/state-format.md)
- [`home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md)
- [`home/dot_local/share/maintain-task-continuity.sh.tmpl`](../../home/dot_local/share/maintain-task-continuity.sh.tmpl)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
- [`scripts/tests/test-task-continuity.sh`](../../scripts/tests/test-task-continuity.sh)
- [`scripts/tests/continuity-fixtures/17-branch-aware-parked-resume/`](../../scripts/tests/continuity-fixtures/17-branch-aware-parked-resume/)

Verify with the continuity hook test, the task-route contract test, and the manual fixture under
`scripts/tests/continuity-fixtures/`.
