# ADR-0026: Integrate the current base before publishing

- Status: Accepted
- Date: 2026-09-18

## Context

`worktree-task-workflow` pinned each task to the exact `origin/<base>` commit used to create its
worktree, but it did not require the task branch to integrate later changes to that base before
push or pull/merge request creation. A long-running task could therefore be published against an
older base without an explicit decision. Updating the branch can also produce conflicts, especially
when the task branch has already been published or when another client resumes the work.

## Decision

The publish stage adds a base-freshness and integration gate:

1. Recheck the redacted fetch and push identities, fetch `origin`, and resolve the current
   `origin/<base>` commit.
2. Publish directly only when the current base equals the recorded checkpoint.
3. Stop when the base advanced and ask the user to choose merge or rebase. Do not use `git pull` as
   an implicit strategy, and do not stash, reset, discard, or resolve conflicts automatically.
4. Preserve a conflict state for user- or agent-assisted resolution. Record conflict paths and the
   next operation in continuity, then rerun applicable verification and the manual-test gate.
5. Recheck the remote and base immediately before pushing. Never silently change the request target.

Merging is the safe default for a task branch that has already been published. Rebasing a published
branch requires separate explicit approval and `--force-with-lease`; plain force-push remains
forbidden. An unpublished branch may be rebased and pushed normally after the user selects that
strategy.

## Alternatives considered

- Publish from the original task commit without checking the current base. This leaves integration
  surprises to the forge or reviewers and makes the workflow's base contract incomplete.
- Run `git pull` automatically. Its configured upstream and merge/rebase behavior are not the
  workflow's explicit `origin/<base>` contract.
- Automatically rebase, stash, or resolve conflicts. These actions can rewrite history or discard
  user intent, and conflict resolution requires repository-specific judgment.
- Require a merge only. This avoids history rewriting but is unnecessarily restrictive for an
  unpublished task branch where the user prefers a linear history.

## Consequences

The workflow can pause after the manual-test gate when the base moves, and a successful integration
can require a second automated and manual verification pass. Conflicts remain visible and resumable
in the same physical worktree, including when another supported client takes over. The workflow
does not guarantee that the remote base cannot advance after the final check; another advance simply
requires another integration cycle.

## Reconsider when

Revisit this decision if the forge enforces a stronger up-to-date-base policy, if the clients expose
a reliable conflict-aware integration mechanism that preserves this contract, or if the repository
adopts a different branch publication policy.

## Related files and verification

- [`home/.chezmoitemplates/skills/worktree-task-workflow/publish.md`](../../home/.chezmoitemplates/skills/worktree-task-workflow/publish.md)
- [`home/.chezmoitemplates/skills/worktree-task-workflow/lifecycle.md`](../../home/.chezmoitemplates/skills/worktree-task-workflow/lifecycle.md)
- [`home/dot_claude/skills/worktree-task-workflow/SKILL.md`](../../home/dot_claude/skills/worktree-task-workflow/SKILL.md)
- [`home/dot_agents/skills/worktree-task-workflow/SKILL.md`](../../home/dot_agents/skills/worktree-task-workflow/SKILL.md)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
- [`scripts/tests/test-ai-configuration-profiles.sh`](../../scripts/tests/test-ai-configuration-profiles.sh)
