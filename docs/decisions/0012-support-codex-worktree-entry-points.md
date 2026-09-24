# ADR-0012: Support Codex worktree entry points

- Status: Accepted
- Date: 2026-09-14

## Context

The `worktree-task-workflow` adapter already handled the implementation lifecycle after a Codex
chat entered a linked worktree. That made its behavior asymmetric with Claude Code: a Claude
workflow could create and enter its worktree, while a Codex workflow stopped and required the
chat to be moved first.

Codex has two supported local surfaces with different ownership boundaries. The desktop app owns
its Local-to-Worktree Handoff and can keep the chat associated with the managed worktree. The CLI
and IDE extension do not expose an equivalent operation that a skill can invoke. A terminal
wrapper can create and provision a Git worktree, but changing a shell's directory cannot relocate
the already-running chat.

## Decision

`worktree-task-workflow` accepts a clean primary checkout as an entry point, but never edits or
branches in it:

- Codex desktop uses native Handoff to Worktree after the task and remote base have been resolved.
- Codex CLI and the IDE extension use `git wt-add -- --detach` from `origin/<base>` at a sibling
  worktree path. The adapter reports the path and stops so Codex can be started there and the same
  resolved workflow can be invoked again.
- An already-linked worktree follows the existing branch, implementation, verification, manual
  test, publishing, and cleanup lifecycle.
- The adapter verifies that the entered worktree starts at the recorded remote-base commit. It
  never resets a worktree created by native Handoff to force a match.

The manual-test gate remains mandatory. Agent-run verification happens first; the user must then
report the manual test as passed before commit, push, or request creation.

## Alternatives considered

- **Require a linked worktree before invocation:** safe, but preserves the avoidable Codex/Claude
  entry-point asymmetry.
- **Always use `git wt-add` for Codex:** works for CLI and IDE sessions, but creates an unassociated
  duplicate when the desktop app already owns the Handoff lifecycle.
- **Run `cd` into the new worktree and continue:** rejected. A shell directory change does not
  move the current Codex chat's workspace and could make the transcript and edits disagree about
  which checkout is active.
- **Create the task branch in the primary checkout:** rejected because it changes the user's
  active checkout and defeats isolation.

## Consequences

Desktop Codex remains app-managed, including its worktree association and lifecycle. CLI and IDE
sessions now get an automatic, provisioned worktree creation step, but still require a deliberate
restart or attachment in the new directory. The continuation boundary is explicit rather than
silently switching the agent's workspace.

The existing `.worktreeinclude` contract remains the source of approved ignored-file provisioning
for both paths. Continuity still belongs to the physical worktree and is initialized only after
the task session enters it.

## Reconsider when

- Codex CLI or the IDE extension exposes a supported operation to move an existing chat into a
  newly created worktree.
- Codex desktop allows a skill or local command to select an arbitrary existing worktree while
  preserving the chat association.
- The Codex worktree and Handoff lifecycle changes its `.worktreeinclude` behavior.

## Related files and verification

- [`home/dot_agents/skills/task-workflow/SKILL.md`](../../home/dot_agents/skills/task-workflow/SKILL.md)
- [`home/.chezmoitemplates/skills/task-workflow/`](../../home/.chezmoitemplates/skills/task-workflow/)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md#codex-worktree-task-workflow)
- Run `scripts/git-hooks/pre-commit` and the platform-specific worktree provisioning fixtures.
