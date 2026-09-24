# ADR-0039: Canonicalize the task-workflow skill name

- Status: Superseded by ADR-0041
- Date: 2026-09-24

## Context

The task workflow now supports both `workspace=checkout` and `workspace=worktree`. The existing
`worktree-task-workflow` name describes only one of those workspace modes and is therefore
misleading for new invocations. Existing prompts, client history, and user habits still depend on
the old entry point.

## Decision

Use `task-workflow` as the canonical skill name and invocation. Keep `worktree-task-workflow` as a
thin compatibility entry point that delegates to the canonical skill and preserves explicit-only
invocation behavior in Codex and Claude.

The shared workflow body and rendered references have one canonical source under
`home/.chezmoitemplates/skills/task-workflow/`. The Codex and Claude adapters, including their
host-specific metadata, remain separate thin wrappers. The compatibility adapters contain no
second workflow implementation; they direct the client to the canonical skill.

New documentation and examples use `$task-workflow` or `/task-workflow`. Existing
`$worktree-task-workflow` and `/worktree-task-workflow` invocations remain supported during the
migration. The former tracked archive paths are retired by ADR-0046; Git history is the recovery
source for deleted tracked files.

## Alternatives considered

### Keep the old name as the only public name

Rejected because it makes the checkout route look like an exception to a worktree-only workflow.

### Duplicate the complete skill under both names

Rejected because the two implementations would drift and could produce different workspace,
verification, continuity, or publishing behavior.

### Remove the old name immediately

Rejected because existing prompts and client discovery surfaces would break without a migration
period.

## Consequences

New users see a name that covers both supported workspace modes. Existing users can continue using
the old command while migrating. The compatibility wrappers add a small amount of discovery
surface, but the behavior remains single-sourced and both names resolve to the same policy.

## Reconsider when

- Usage shows that the compatibility entry point is no longer needed.
- All supported client surfaces and known user prompts have migrated to `task-workflow`.
- Removing the old adapters can be treated as an explicit breaking change.

This decision is superseded by ADR-0041, which retains this compatibility layer but introduces
`run-task-end-to-end` as the canonical workflow name.

## Related files and verification

- [`home/.chezmoitemplates/skills/task-workflow/`](../../home/.chezmoitemplates/skills/task-workflow/)
- [`home/dot_agents/skills/task-workflow/SKILL.md`](../../home/dot_agents/skills/task-workflow/SKILL.md)
- [`home/dot_claude/skills/task-workflow/SKILL.md`](../../home/dot_claude/skills/task-workflow/SKILL.md)
- [`home/dot_agents/skills/worktree-task-workflow/SKILL.md`](../../home/dot_agents/skills/worktree-task-workflow/SKILL.md)
- [`home/dot_claude/skills/worktree-task-workflow/SKILL.md`](../../home/dot_claude/skills/worktree-task-workflow/SKILL.md)
- [`scripts/tests/test-run-task-end-to-end.sh`](../../scripts/tests/test-run-task-end-to-end.sh)
- [`scripts/tests/test-ai-configuration-profiles.sh`](../../scripts/tests/test-ai-configuration-profiles.sh)
