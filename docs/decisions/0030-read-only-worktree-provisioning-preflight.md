# ADR-0030: Add a read-only worktree provisioning preflight

- Status: Accepted
- Date: 2026-09-22

## Context

`git worktree add` creates a clean working tree from tracked files and does not report that
ignored local configuration was left behind. The repository fallback previously discovered the
manifest only after creation, while a raw Git fallback could create a worktree with no
provisioning result at all. That made a missing manifest, an unlisted ignored file, and an
application-required local file indistinguishable until a build or startup failure.

Native Claude, Codex desktop local, and VS Code paths have their own provisioning mechanisms and
must not be made to depend on the terminal fallback. The fallback still needs one explicit,
cross-platform contract for terminal, CLI, remote, and IDE paths.

## Decision

Provide `git wt-check` in the Windows and macOS helpers as a read-only provisioning classifier.
It reports:

- whether `.worktreeinclude` is absent, tracked, or untracked;
- ignored files matched by the tracked manifest;
- eligible ignored files outside the manifest;
- missing manifest patterns and explicitly named required local files; and
- existing target conflicts when a target worktree is supplied.

The check never creates a manifest, worktree, directory, or copied file. Tracked files are not
manifest candidates because enumeration is limited to Git-ignored, untracked regular files.
Application-specific requirements remain explicit through `--required`; without that option the
check reports the requirement as unknown rather than inferring it from a filename.

`git wt-add` runs the check before invoking Git. It blocks when eligible ignored files are
unlisted and requires an explicit `--allow-unprovisioned` or `--skip-copy` decision to continue.
That override does not copy unlisted files. After creation, the normal copy step remains limited
to tracked manifest entries that also match Git's ignored-file classification, and never overwrites
an existing target.

The workflow skills require the same preflight before raw `git worktree add`; after creation they
run `git wt-check --target` and use `git wt-copy` only for approved entries. Native Claude,
Codex desktop local, and VS Code provisioning remains client-owned and is reported separately.
The repository does not attempt to intercept arbitrary direct Git invocations globally.

## Alternatives considered

- Keep discovering the manifest after creation. Rejected because it preserves the silent omission
  at the point where the user chooses a worktree path.
- Copy every ignored file. Rejected because ignored files include credentials, agent state,
  dependencies, data, and build output.
- Create `.worktreeinclude` automatically from discovered files. Rejected because the allowlist is
  a durable copy-approval decision and must be reviewed by the user.
- Force native clients through the terminal helper. Rejected because native clients have distinct
  creation, session, and application-owned provisioning contracts.
- Install a global Git hook to intercept raw `worktree add`. Rejected because Git does not provide
  a reliable repository-local hook boundary for every direct invocation and it would add behavior
  outside the supported workflow.

## Consequences

Non-native worktree creation now has a visible, repeatable decision point and a safe default when
eligible ignored configuration exists. The terminal helpers and their Windows/macOS tests must
remain behaviorally aligned. A user who intentionally wants a tracked-only worktree must make
that intent explicit, and a raw Git invocation outside the documented workflow remains outside the
repository's enforcement boundary.

The check cannot determine application necessity by itself. The workflow must either name required
files, build/start the application, or report the requirement as unresolved. Existing worktrees
can be inspected and repaired without recreating them.

## Reconsider when

Revisit this decision if Git or a supported client provides a reliable pre-creation provisioning
hook for all relevant worktree entry points, or if the repository adopts a reviewed project-level
declaration for required local configuration that can replace explicit `--required` arguments.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `home/dot_gitconfig.tmpl`
- `home/.chezmoitemplates/skills/task-workflow/lifecycle.md`
- `home/dot_agents/skills/task-workflow/SKILL.md`
- `home/dot_claude/skills/task-workflow/SKILL.md`
- `home/dot_agents/skills/worktree-manifest/SKILL.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run the Windows and macOS provisioning suites listed in the repository README. The tests cover
unlisted-file blocking, read-only reports, empty manifests, raw-worktree omissions, target
conflicts, required local configuration, tracked-file exclusion, and the explicit override.
