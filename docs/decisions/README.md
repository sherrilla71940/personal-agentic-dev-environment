# Architecture decision records

This directory contains architecture decision records (ADRs). Each record explains why the
repository uses a particular structure, which alternatives were rejected, and which future
change should trigger reconsideration.

Operational steps belong in [`docs/chezmoi-workflow.md`](../chezmoi-workflow.md). Current
constraints that every coding agent must obey belong in [`AGENTS.md`](../../AGENTS.md).
ADRs provide the reasoning behind those documents without adding that history to every
agent session.

## Working with ADRs

- Use the next four-digit number and a short kebab-case title.
- Set the status to `Proposed`, `Accepted`, `Superseded`, or `Rejected`.
- Once accepted, preserve the record. If the decision changes, add a new ADR and mark the
  old one `Superseded by ADR-NNNN`.
- Keep the current procedure in the workflow guide; link to it from the ADR rather than
  duplicating it.
- Include concrete reconsideration triggers so a later session can distinguish an
  intentional constraint from accidental legacy structure.

## Records

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](./0001-separate-operational-guides-from-decision-records.md) | Accepted | Separate current procedures from durable decision history |
| [0002](./0002-share-cross-tool-configuration-with-thin-wrappers.md) | Accepted | Share portable content while keeping tool-specific wrappers |
| [0003](./0003-track-vscode-user-configuration-selectively.md) | Accepted | Track portable VS Code user configuration selectively |
| [0004](./0004-manage-mixed-state-claude-settings-by-key.md) | Superseded by 0005 | Manage durable Claude settings while preserving app-owned choices |
| [0005](./0005-merge-durable-claude-settings-as-json.md) | Accepted | Merge durable Claude settings from a JSON source and narrow repository ownership |
| [0006](./0006-keep-the-working-tree-at-dotfiles.md) | Accepted | Keep the Git working tree at ~/dotfiles and link the default source directory |
| [0007](./0007-host-gate-codex-targeted-skills.md) | Accepted | Isolate a Codex-targeted skill by host gates rather than by directory |
| [0008](./0008-manage-windows-terminal-settings-by-key.md) | Accepted | Manage durable Windows Terminal settings while preserving generated profiles |
| [0009](./0009-own-windows-terminal-actions-and-keybindings.md) | Accepted | Own the Windows Terminal actions and keybindings arrays for a Shift+Enter newline |
| [0010](./0010-normalize-the-working-tree-to-lf.md) | Accepted | Normalize the whole working tree to LF so chezmoi diff shows only real changes |
| [0011](./0011-fix-the-continuity-state-path.md) | Accepted | Fix the continuity state path at `.project-continuity/` and keep both privacy layers |
| [0012](./0012-support-codex-worktree-entry-points.md) | Accepted | Support native Codex Handoff and safe CLI/IDE worktree provisioning |
| [0013](./0013-ignore-personal-ai-instructions-globally.md) | Accepted | Ignore personal Claude and Codex instruction files globally |
| [0014](./0014-machine-local-ai-configuration-profiles.md) | Accepted | Compose machine-local context and continuity profiles without duplicating skills; extended by 0022 |
| [0015](./0015-organize-repository-tooling-by-purpose.md) | Superseded by 0016 | Organize repository tooling by purpose and expose one diagnostic entry point |
| [0016](./0016-rename-the-project-facing-tooling-command.md) | Accepted | Rename the project-facing diagnostic command to `dev-env` while retaining chezmoi and local-path compatibility |
| [0017](./0017-review-completed-parked-continuity-state.md) | Accepted | Review parked continuity state for completion and require confirmation before closure |
| [0018](./0018-track-explicit-workflow-archives.md) | Superseded by 0020 | Track explicit workflow archives outside active source and discovery paths |
| [0019](./0019-discover-and-retire-workflows-safely.md) | Superseded by 0020 | Discover workflow boundaries by outcome and retire sources with explicit target cleanup |
| [0020](./0020-archive-or-delete-workflow-lifecycle.md) | Accepted | Make archive a recoverable copy plus source deletion, with an explicit no-archive delete path |
| [0021](./0021-add-native-workflow-profile-mode.md) | Superseded by 0022 | First, narrower native mode; retained as historical context |
| [0022](./0022-define-native-and-managed-ai-harness-modes.md) | Accepted | Define `ai_harness` native and managed boundaries, including retained notifications and conditional lifecycle hooks |
| [0023](./0023-optional-per-worktree-runtime-isolation.md) | Accepted | Add explicit, descriptor-driven per-worktree HTTP port isolation without coupling it to AI profiles |
| [0024](./0024-refine-continuity-and-material-filing-policy.md) | Accepted | Clarify instruction provenance, continuity reassessment, verification scope, and material filing timestamps |
| [0025](./0025-pin-worktree-task-origin-and-base.md) | Accepted | Pin each task to a verified origin identity and immutable base commit |
| [0026](./0026-integrate-current-base-before-publishing.md) | Accepted | Require an explicit base-freshness and conflict-safe integration gate before publishing |
| [0027](./0027-add-repository-identity-preflight.md) | Accepted | Add a read-only repository-identity gate before substantive work |
| [0028](./0028-classify-instruction-ownership-before-adding.md) | Accepted | Classify instruction ownership and scope before adding behavior |

## Template

```markdown
# ADR-NNNN: Title

- Status: Proposed
- Date: YYYY-MM-DD

## Context

What forces or constraints require a decision?

## Decision

What will the repository do?

## Alternatives considered

What credible alternatives were rejected, and why?

## Consequences

What becomes easier, harder, or intentionally unsupported?

## Reconsider when

Which observable changes should cause this decision to be reviewed?

## Related files and verification

Where is the decision implemented, and how can it be checked?
```
