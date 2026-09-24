# ADR-0038: Generalize task workspace and verification policy

- Status: Superseded by ADR-0039
- Date: 2026-09-24

## Context

The task workflow began as a worktree-only lifecycle and later gained an in-place route for
sequential changes. That split made workspace selection, continuity, verification, and publishing
carry too much shared meaning. It also left the old `agent-test` option overlapping with the
workflow's actual verification responsibility.

The repository needs a small task to remain practical without weakening the safeguards required for
parallel work, while preserving project-specific rules such as this repository's prohibition on
editing from a linked worktree.

## Decision

Keep `worktree-task-workflow` as the compatibility entry point and define three independent policy
dimensions:

```text
workspace=checkout|worktree
verification=agent|balanced|user
continuity=auto|on|off
```

Workspace has no implicit default. It must resolve from an explicit argument, clear natural-language
intent, or user confirmation before any branch switch, branch creation, or worktree creation. The
resolved echo reports the source as `argument`, `prompt`, or `user-confirmation`. The defaults are
`verification=agent` and `continuity=auto`.

- `checkout` uses the current physical checkout but still establishes the resolved task branch
  from the selected base before implementation.
- `worktree` creates or enters an isolated worktree and establishes the same task branch from the
  same recorded base.
- `continuity=auto` inherits the active profile's `ai_continuity` value directly. `on` and `off`
  are explicit task overrides. The workflow does not add a second task-complexity heuristic.
- `verification=agent` is the default. It runs maximum feasible agent-verifiable coverage and asks
  the user only for genuinely user-only checks. `verification=balanced` runs the same coverage and
  then requires explicit user acceptance; `user` runs non-interactive checks and leaves browser/manual
  verification to the user. No mode permits claims about checks that were not run.
- Verification never authorizes publication. Commit, push, and MR/PR creation require the separate
  publish-authorization boundary.

The old `isolation=worktree|in-place|auto` and `agent-test=true|false` inputs remain deprecated
compatibility aliases during migration. `worktree` and `in-place` map to the canonical workspace
values. `isolation=auto` cannot choose a workspace silently and stops for explicit resolution.
Aliases are shown as deprecated in the resolved echo; they do not create a second active contract.

Repository and project instructions may override generic workspace behavior. Such an override must
be explicit in the resolved echo. Continuity cleanup remains separate from worktree and branch
cleanup, and `continuity=off` never deletes or overwrites an existing unfinished state.

When a different task encounters a completed active `state.md`, the workflow runs the completion
gate, asks before deleting that state, and initializes the new task only after cleanup is confirmed.
It never parks or overwrites completed state. If cleanup is declined, the old state remains intact;
the new task may proceed only with effective `continuity=off`, or it stops until cleanup is confirmed.

## Alternatives considered

### Keep the in-place route on the current branch

Rejected because it makes the same task workflow mean different branch and publication contracts.
The checkout mode now remains lightweight by avoiding a second directory and provisioning step,
while retaining a task branch from the resolved base.

### Infer continuity from task size

Rejected because task-size heuristics duplicate the active AI profile policy and can silently change
handoff behavior. `auto` must inherit `ai_continuity`.

### Infer workspace from task or checkout conditions

Rejected because the current checkout, branch availability, task size, and isolation signals do not
constitute user authorization to switch branches or create a worktree. Natural-language intent may
resolve the workspace, but an unresolved request must ask before mutation.

### Keep `agent-test` beside a new verification option

Rejected because two controls could disagree about browser and manual verification responsibility.
The legacy option maps to the new policy only when `verification` is absent.

## Consequences

Small sequential tasks can use the current checkout without creating a worktree, while parallel
tasks retain isolated source and runtime behavior. The workflow has one shared branch, continuity,
verification, and publishing lifecycle instead of route-specific exceptions. Callers should migrate
to the new names; legacy aliases are retained only to avoid an abrupt compatibility break.

The checkout workspace cannot claim a separate runtime port unless the consuming project documents a
safe current-checkout lease. A physical checkout still has at most one active continuity state, so
parking handles sequential task handoff but never substitutes for simultaneous isolation.

## Reconsider when

- A supported client can select and enter both workspace modes while preserving the same task state.
- A project defines a safe, deterministic runtime lease for a shared checkout.
- Usage shows that explicit workspace resolution creates less surprising branch and worktree changes
  than inferring a route from task or checkout conditions.
- The compatibility entry point can be replaced by a general `task-workflow` command without
  breaking existing prompts or client adapters.

## Related files

- [`docs/worktree-provisioning.md`](../worktree-provisioning.md)
- [`home/.chezmoitemplates/skills/task-workflow/invocation.md`](../../home/.chezmoitemplates/skills/task-workflow/invocation.md)
- [`home/.chezmoitemplates/skills/task-workflow/lifecycle.md`](../../home/.chezmoitemplates/skills/task-workflow/lifecycle.md)
- [`home/.chezmoitemplates/skills/task-workflow/publish.md`](../../home/.chezmoitemplates/skills/task-workflow/publish.md)
- [`scripts/tests/test-run-task-end-to-end.sh`](../../scripts/tests/test-run-task-end-to-end.sh)
