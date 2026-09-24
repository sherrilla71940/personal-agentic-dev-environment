# ADR-0040: Require company flow branch identifiers

- Status: Accepted
- Date: 2026-09-24

## Context

Company application repositories use flow numbers as the shared task identity in branch names. A
generic task workflow that derives its usual `type/slug/suffix` branch can therefore create a valid
Git branch that violates the team's review and tracking convention. Inferring a flow number from
prose, filenames, or an existing branch is unsafe, and allowing `continuity=off` or a verification
choice to bypass the branch rule would make the policy unreliable.

The dotfiles repository is different: its root instructions deliberately override the machine's
`company` selector with effective `personal` context while the repository's own source is edited.
The company rule must not force a flow number onto this user-level configuration repository.

## Decision

The task workflow resolves branch policy from the effective context after repository instructions
are applied:

- Effective `company` context uses `branch_policy=company-flow` for execution tasks that create a
  task branch. The invocation must provide `flow=<digits>`, validated as `^[0-9]{1,9}$`, and the
  workflow generates `flow/<flow>-<ascii-description>`.
- An explicit `branch=` under `company-flow` must match
  `^flow/[0-9]{1,9}(?:-[A-Za-z0-9_-]+)?$` and use the same flow number. A flow number is never
  inferred from task prose or materials.
- Effective `personal` context retains the repository-standard branch naming contract and does not
  require `flow=`.
- A project may explicitly declare `branch_policy=project-exception` in applicable repository
  instructions, name the allowed pattern and instruction source, and require an explicit `branch=`.
  The workflow never infers an exception from a branch that merely resembles `feat/{series}`.
- Plan-only prompts do not require a flow value, but a generated execution invocation for a
  company-flow task must show `flow=<digits>`. The resolved echo and continuity `Verification`
  block report the policy, flow source/value, and resolved task branch.

The rule applies equally to `workspace=checkout` and `workspace=worktree`, and is independent of
verification, continuity, and publish authorization.

## Alternatives considered

- Infer the flow number from the task prompt or attached materials. Rejected because branch identity
  would depend on untrusted or ambiguous text.
- Accept any explicit `branch=` as a project exception. Rejected because a branch name cannot
  authorize its own policy bypass.
- Require flow numbers globally. Rejected because personal repositories and user-level configuration
  do not share the company tracking convention.

## Consequences

Company task prompts must include a named `flow` argument before an execution branch is created.
The branch and continuity records are easier to correlate with the company's tracker. Projects with
legitimate legacy branch conventions must document their exception explicitly instead of relying on
agent inference. This repository continues to use its existing personal branch convention.

## Reconsider when

Revisit this decision if the company changes its branch convention, a project-tracker integration can
verify flow existence, or the profile model gains a first-class repository policy descriptor.

## Related files and verification

- [`home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md)
- [`home/.chezmoitemplates/skills/run-task-end-to-end/lifecycle.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/lifecycle.md)
- [`home/.chezmoitemplates/skills/run-task-end-to-end/publish.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/publish.md)
- [`home/dot_agents/skills/run-task-end-to-end/SKILL.md`](../../home/dot_agents/skills/run-task-end-to-end/SKILL.md)
- [`home/dot_agents/skills/task-continuity/references/state-format.md`](../../home/dot_agents/skills/task-continuity/references/state-format.md)
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md#company-flow-branch-policy)
- [`scripts/tests/test-run-task-end-to-end.sh`](../../scripts/tests/test-run-task-end-to-end.sh)
