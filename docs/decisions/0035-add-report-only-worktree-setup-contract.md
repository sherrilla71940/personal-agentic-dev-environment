# ADR-0035: Add a report-only worktree setup contract

- Status: Accepted
- Date: 2026-09-22

## Context

Generic worktree provisioning can identify approved ignored files and explicit configuration
references, but it cannot safely infer or execute application-specific setup. A consuming
repository may still need a build prerequisite, a local configuration file, or a documented setup
step that is not represented by `.worktreeinclude`.

The workflow needs a discoverable handoff for that project-owned knowledge without turning a
dotfiles-level helper into an application installer or trusting adjacent folders that may contain
secrets.

## Decision

Support an optional tracked, repository-root `.worktree-provision` contract with this deliberately
small format:

```text
schemaVersion=1
script=scripts/setup-worktree.sh
documentation=docs/worktree-setup.md
```

The Windows and macOS helpers will:

- report whether the contract is absent, valid, or invalid;
- report only the repository-relative paths declared by a valid contract;
- require the declared script and optional documentation to be tracked and present;
- report the contract during read-only provisioning and readiness checks; and
- never execute the script, print its contents, copy its files, or treat it as a replacement for
  `.worktreeinclude`.

The contract is a pointer to project-owned instructions, not permission to perform project setup.
The consuming repository remains responsible for the script's behavior, approval, credentials,
runtime assumptions, and application-specific validation. An unavailable source repository remains
an inspection limitation; the generic helper does not guess a contract or an external source.

## Alternatives considered

- Execute the declared script automatically. Rejected because a generic helper cannot safely infer
  approval, side effects, credential access, or compatibility with the target branch.
- Use a free-form command field. Rejected because command text can expose secrets and encourages
  the helper to become an application-specific launcher.
- Search adjacent folders for setup scripts or secrets. Rejected because location does not establish
  repository authority, provenance, or safety.
- Put setup instructions in `.worktreeinclude`. Rejected because that file is an ignored-file
  allowlist and must remain limited to explicitly approved ignored files.

## Consequences

Agents receive a stable, repository-provided pointer when project-specific setup exists, while the
global workflow remains read-only and bounded. A valid contract does not make a worktree ready by
itself: build, server, authentication, credentials, and application behavior still require the
consuming repository's documented procedure and explicit user verification.

The helper implementations must keep parsing, validation, and report wording aligned across
Windows and macOS. Focused fixtures verify report-only behavior and ensure script contents are not
executed or printed.

## Reconsider when

Revisit this decision if a supported client exposes a native, explicit, and verifiable project setup
contract, or if the repository needs a formally approved execution protocol with a separate trust
boundary and secret-handling design.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `docs/worktree-provisioning.md`
- `home/.chezmoitemplates/skills/worktree-task-workflow/lifecycle.md`
- `home/dot_agents/skills/worktree-task-workflow/SKILL.md`
- `home/dot_claude/skills/worktree-task-workflow/SKILL.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run both provisioning suites. The setup-contract fixtures must verify that a valid contract is
reported without executing its script or exposing its contents.
