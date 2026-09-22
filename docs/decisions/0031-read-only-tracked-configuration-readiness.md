# ADR-0031: Add read-only tracked-configuration readiness

- Status: Accepted
- Date: 2026-09-22

## Context

Git worktree creation checks out tracked files, but it does not carry a source worktree's local
modifications into the new worktree. That behavior is correct for tracked configuration such as
`Web.config`: copying a modified local override can change the target branch's runtime behavior.
The provisioning manifest must therefore remain limited to explicitly approved ignored files.

The existing `git wt-check` classifier answers which ignored files are eligible for provisioning,
but it does not answer whether a tracked environment or configuration candidate was modified in the
source worktree and consequently will not be copied. That gap can leave an agent unsure whether the
absence is intentional or needs manual review.

## Decision

Add a separate `git wt-readiness` command to the Windows and macOS helpers. The command is
read-only, reports the exact source and target worktree paths and branches, and classifies:

- ignored files authorized by `.worktreeinclude`;
- ignored files present but not authorized;
- modified tracked configuration candidates that were not copied; and
- the absence of local configuration differences.

The command examines Git path names and status only. It never prints configuration values,
connection strings, secrets, or tokens. Its tracked-configuration warning uses the exact message
`modified tracked configuration was not copied; review only if this worktree requires the local
override.`

The warning is advisory and does not change `git wt-add`'s existing provisioning decision. No
tracked configuration file is copied, added to `.worktreeinclude`, or used to create a manifest.
The check also does not start a build, IIS Express, or an authenticated browser session; those
remain separate verification steps.

Native Claude, Codex desktop local, and VS Code provisioning remain client-owned. The readiness
command documents the terminal and raw-Git fallback boundary only.

## Alternatives considered

- Copy modified tracked configuration into the new worktree. Rejected because the source override
  can be incompatible with the target branch, as demonstrated by the `Web.config` incident.
- Add tracked configuration to `.worktreeinclude`. Rejected because Git already provisions tracked
  files and the manifest is intentionally an ignored-file allowlist.
- Block `git wt-add` when tracked configuration is modified. Rejected because the modification may
  be intentional and the check cannot infer the application's requirement.
- Start a build or application server from the readiness command. Rejected because it would expand
  a read-only provisioning check into application-specific automation and authentication handling.
- Infer requirements from every configuration-looking filename. Rejected because filenames do not
  establish whether a local override is required, safe to copy, or sensitive.

## Consequences

Agents get an explicit, non-blocking signal when source and target configuration may differ, while
the safe Git behavior remains unchanged. The warning requires a human or application-specific
verification step when the local override matters. The Windows and macOS helpers and their focused
tests must remain behaviorally aligned, including their no-value output boundary.

## Reconsider when

Revisit this decision if a supported client provides a reliable, cross-platform readiness contract
for tracked local configuration, or if consuming repositories adopt a reviewed declaration that
can identify required tracked overrides without inspecting their values.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `home/dot_gitconfig.tmpl`
- `docs/worktree-provisioning.md`
- `home/.chezmoitemplates/skills/worktree-task-workflow/lifecycle.md`
- `home/dot_agents/skills/worktree-task-workflow/SKILL.md`
- `home/dot_claude/skills/worktree-task-workflow/SKILL.md`
- `home/dot_agents/skills/worktree-manifest/SKILL.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run the Windows and macOS provisioning suites listed in the repository README. The readiness
regression covers a modified tracked `Web.config`, authorized and unlisted ignored files, exact
source and target identity, no copied target override, and the no-local-differences state.
