# ADR-0025: Pin the worktree task to a verified origin and base commit

- Status: Accepted
- Date: 2026-09-18

## Context

`worktree-task-workflow` already required a named branch on `origin` and checked that
`origin/<base>` existed. The workflow then passed that mutable remote-tracking ref to worktree
creation and described the starting commit in continuity. That left two related identities
implicit: `origin` could be changed between preflight and publishing, and the base ref could move
between validation and provisioning. Either change could make a task start from or publish to a
repository state different from the one the user approved.

## Decision

The workflow records the redacted fetch and push identities of `origin`, resolves the requested
base branch to one full commit, and rechecks the identities and base commit immediately before
provisioning. Worktrees and task branches start from that recorded commit ID rather than the moving
`origin/<base>` ref. Continuity may record the base branch and redacted origin identities so a
later client can detect a changed remote before publishing. Publishing rechecks the same origin
identities and confirms that the named base branch still exists.

The base branch name remains the request target. A later advance of that branch does not rewrite a
task's recorded starting commit. Embedded credentials are never shown or written to continuity.

## Alternatives considered

- Keep resolving `origin/<base>` at each step. This is simpler but allows a moving remote-tracking
  ref or changed `origin` URL to silently alter the task's start or destination.
- Bind the workflow to the repository directory or current checked-out branch. This is not a
  reliable repository identity and would reintroduce the branch/base ambiguity the workflow exists
  to prevent.
- Add a general remote registry. The workflow needs only the user-selected `origin` contract;
  additional remote management would be an unrelated abstraction.

## Consequences

The resolved plan contains one more remote-base checkpoint, and a remote or base-ref change causes
the workflow to stop and require re-resolution. Long-running tasks can still target a base branch
that advances after the task starts; the request targets the branch name while the task's starting
commit remains explicit. Older continuity files without these optional fields remain valid, but a
resumed task must establish the checkpoint before publishing.

## Reconsider when

Revisit this decision if the clients or Git provide a reliable immutable repository/worktree
identity that covers fetch, push, base selection, and cross-client resume without the workflow's
checkpoint, or if the project adopts a multi-remote request contract.

## Related files and verification

- [`home/.chezmoitemplates/skills/worktree-task-workflow/invocation.md`](../../home/.chezmoitemplates/skills/worktree-task-workflow/invocation.md)
- [`home/.chezmoitemplates/skills/worktree-task-workflow/publish.md`](../../home/.chezmoitemplates/skills/worktree-task-workflow/publish.md)
- [`home/dot_claude/skills/worktree-task-workflow/SKILL.md`](../../home/dot_claude/skills/worktree-task-workflow/SKILL.md)
- [`home/dot_agents/skills/worktree-task-workflow/SKILL.md`](../../home/dot_agents/skills/worktree-task-workflow/SKILL.md)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
- Render/profile checks and the worktree provisioning suites cover the affected source contracts.
