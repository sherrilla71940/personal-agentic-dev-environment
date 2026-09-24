# ADR-0037: Add an explicit in-place task route

- Status: Superseded by ADR-0038
- Date: 2026-09-23

This decision is retained as history. ADR-0038 replaces its current-branch in-place semantics with
the explicit `workspace=checkout|worktree` contract and adds independent verification and
continuity policies.

## Context

The `worktree-task-workflow` protects parallel work by pinning a task to a remote base, creating an
isolated worktree and branch, provisioning approved ignored files, and optionally allocating a
per-worktree runtime port. That process is appropriate when tasks must be isolated, but it is too
heavy for a small change that can safely remain in the current checkout.

Project continuity already belongs to a physical checkout rather than to a linked worktree. The
primary checkout can therefore host a substantive in-place task, while a trivial edit can remain
recoverable from its diff without continuity state. Parking protects the context of a sequential
task switch, but it does not isolate simultaneous code changes, branches, runtime ports, or
processes.

## Decision

Keep `$worktree-task-workflow` as the compatibility entry point and add an explicit
`isolation=worktree|in-place|auto` route option:

- `worktree` preserves the existing exact-base, provisioning, runtime, verification, manual-test,
  publishing, and branch-preserving lifecycle. It remains the default when `base` is supplied.
- `in-place` keeps the current Git root and branch. It never creates or switches a worktree or
  branch, provisions ignored files, or claims a separate runtime port. A supplied `base` is a pull
  or merge request target only.
- `auto` chooses `worktree` for an explicit base or isolation signal. It chooses `in-place` only
  when the current checkout has a named branch, no unrelated changes, and no conflicting unfinished
  continuity state. It stops when the signals or checkout are unsafe.

Both routes use the same material, verification, manual-test, and continuity completion boundaries.
One physical checkout has at most one active task and one active continuity state. If another
unfinished task occupies the checkout, the workflow stops for an explicit finish, park, or abandon
decision. A trivial self-contained edit does not initialize continuity.

Reject `runtime=auto` for in-place work unless the consuming project explicitly documents a safe
current-checkout lease. Do not rename the command or add the proposed `$task-workflow` alias in this
change; revisit that migration separately after client discovery and usage guidance are ready.

## Alternatives considered

### Keep the workflow worktree-only

This preserves the strongest isolation invariant but makes the workflow impractical for small,
sequential edits and encourages users to bypass it entirely.

### Infer in-place work from “small” or “quick”

Rejected because natural-language size estimates are ambiguous. The `auto` route uses explicit
signals and checkout safety, then reports the selected route before execution.

### Make parking provide concurrency isolation

Rejected. Parking moves continuity text only. It does not separate the working files, branches,
runtime ports, or running processes that require separate worktrees.

## Consequences

Small tasks can use one concise invocation without worktree creation. Existing worktree invocations
retain their behavior and exact-base safeguards. In-place tasks have fewer isolation guarantees and
must be explicit about publication targets; the workflow reports those limits instead of implying
that the current checkout is a separate task environment.

## Reconsider when

Revisit the route contract if a consuming project defines safe current-checkout runtime leasing, if
client-native route selection becomes available across supported clients, or if usage evidence shows
that the long command should gain a migration alias.

## Related files and verification

- [`home/.chezmoitemplates/skills/task-workflow/invocation.md`](../../home/.chezmoitemplates/skills/task-workflow/invocation.md)
- [`home/.chezmoitemplates/skills/task-workflow/lifecycle.md`](../../home/.chezmoitemplates/skills/task-workflow/lifecycle.md)
- [`home/.chezmoitemplates/skills/task-workflow/publish.md`](../../home/.chezmoitemplates/skills/task-workflow/publish.md)
- [`home/dot_agents/skills/task-workflow/SKILL.md`](../../home/dot_agents/skills/task-workflow/SKILL.md)
- [`home/dot_claude/skills/task-workflow/SKILL.md`](../../home/dot_claude/skills/task-workflow/SKILL.md)
- [`home/dot_agents/skills/task-continuity/SKILL.md`](../../home/dot_agents/skills/task-continuity/SKILL.md)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md#workspace-selection-and-continuity-boundary)
- [`scripts/tests/test-run-task-end-to-end.sh`](../../scripts/tests/test-run-task-end-to-end.sh)

Verify with the route contract test, profile rendering, continuity lifecycle suite, Markdown-link
validation, and the repository pre-commit hook.
