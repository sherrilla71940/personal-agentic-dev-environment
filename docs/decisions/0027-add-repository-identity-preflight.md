# ADR-0027: Add a repository-identity preflight before substantive work

- Status: Accepted
- Date: 2026-09-21

## Context

The shared instructions already said to confirm the current repository before substantial Git work,
and the worktree workflow already resolved its task branch and base before provisioning. Neither
rule defined a common preflight that compared the execution workspace with an active IDE file or
task repository. The workflow could therefore read a second repository's materials after noticing a
context mismatch, as happened when the execution workspace was TaoyuanSewer2 and the IDE active file
belonged to HsinchuGIS.

The incident exposed two gaps:

- **Workflow-design gap:** the task workflow read supplied materials before it established the
  execution workspace, Git root, branch, upstream or base, continuity path, and clean/dirty status.
- **Communication gap:** the existing repository rule did not require a standard identity report,
  an explicit stop, or a clear switch-versus-continue question.

The current Claude and Codex lifecycle hooks receive the execution `cwd`, hook event, and session
metadata. The current source does not provide an IDE active-file path to those hooks, and Copilot
has no equivalent lifecycle hook. The design must not claim an IDE integration that the host does
not expose.

## Decision

Add a lightweight, read-only repository-identity preflight to the shared core and the task-workflow
invocation contract.

Before substantive repository inspection, the client shall report:

- the execution workspace root;
- the active task repository when the host or user provides it, or `unavailable`;
- the current Git root and branch;
- the current upstream and selected workflow base, when applicable;
- the physical `.project-continuity/state.md` path and whether it exists; and
- whether the working tree is clean.

When a known active file or repository resolves to a different Git root, the client shall warn,
perform only read-only identity checks, stop before reading project files or editing, and ask whether
to switch context or continue with the current workspace. A second repository requires explicit user
confirmation and becomes a separate task. The client shall not reconcile, park, replace, or update
the current worktree's continuity state for that separate task.

When the active-file path is unavailable, the client shall report that limitation and use the
explicit execution-workspace preflight. It shall ask for confirmation when the intended repository
is ambiguous. It shall not infer repository identity from a filename, tab title, or directory name.

The preflight does not apply to explanation-only, formatting-only, or other lightweight requests
that do not inspect repository files. Git remains authoritative for repository and code state, and
continuity remains scoped to the physical worktree.

The shared core carries the general rule for Claude, Codex, and Copilot. The worktree-task-workflow
reference applies the ordering before material content is read. The Claude and Codex adapter files
describe the same preflight without adding host-specific behavior. No adapter attempts to obtain an
IDE active-file path that the host does not provide.

## Alternatives considered

- **Rely on IDE integration.** Rejected because the current hook payloads do not include the active
  file, Copilot has no matching lifecycle hook, and an unavailable capability cannot be treated as
  a repository identity signal.
- **Add a new mandatory standalone helper.** Rejected for this gap. A helper would not know the
  active IDE repository and would add installation and synchronization surface without improving
  the decision boundary. Reconsider if a host later exposes a stable active-workspace API.
- **Make the preflight mandatory for every request.** Rejected because explanation-only and other
  lightweight requests should not incur repository-workflow overhead.
- **Block every task with a dirty working tree.** Rejected because unrelated user changes belong to
  the user and must remain untouched. Existing worktree adapters keep their own clean/approved-state
  checks where isolation requires them.

## Consequences

The first substantive response has a consistent repository identity report and a fail-closed path for
known cross-repository context. The workflow performs a few additional read-only Git and filesystem
checks before reading materials. A missing active-file path remains a communication limitation, so
the fallback depends on an explicit workspace confirmation when the target is ambiguous.

The design does not switch an existing client session by changing a terminal CWD. The user or the
client's native context control must perform that switch. A confirmed second repository is not folded
into the current physical worktree's continuity lifecycle.

## Reconsider when

Revisit this decision when Claude, Codex, Copilot, or the editor host provides a stable active-file or
active-workspace path to the lifecycle adapter, or when a shared host-neutral context API can compare
that path without relying on heuristics.

## Related files and verification

- [`home/.chezmoitemplates/core.md`](../../home/.chezmoitemplates/core.md) — shared rule
- [`home/.chezmoitemplates/skills/task-workflow/invocation.md`](../../home/.chezmoitemplates/skills/task-workflow/invocation.md) — ordering and identity report
- [`home/dot_agents/skills/task-continuity/SKILL.md`](../../home/dot_agents/skills/task-continuity/SKILL.md) — continuity boundary
- [`home/dot_claude/skills/task-workflow/SKILL.md`](../../home/dot_claude/skills/task-workflow/SKILL.md) — Claude adapter
- [`home/dot_agents/skills/task-workflow/SKILL.md`](../../home/dot_agents/skills/task-workflow/SKILL.md) — Codex adapter
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md) — cross-client behavior and IDE limitation
- [`scripts/tests/continuity-fixtures/15-repository-identity-mismatch/expected.md`](../../scripts/tests/continuity-fixtures/15-repository-identity-mismatch/expected.md) — manual judgment fixture
- Run the pre-commit render and link checks, the project-continuity hook suite, and the profile suite.
