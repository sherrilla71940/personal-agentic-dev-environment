# ADR-0033: Refuse tracked-file provisioning and classify private client files

- Status: Accepted
- Date: 2026-09-22

## Context

`.worktreeinclude` is an ignored-file allowlist, not a general file-copy request. Git already
provides tracked files in every worktree, but a manifest pattern could previously match a tracked
path and be reported only as a missing ignored file. That left an unsafe ambiguity: a request to
copy application-owned tracked configuration, such as `Web.config`, was not explicitly refused.

The manifest guidance also treated private agent overrides and client-local settings as ordinary
eligible candidates. Those files can change agent behavior, permissions, or tool behavior and must
not be suggested merely because they are ignored.

## Decision

The provisioning helpers will:

- reject a tracked path matched by `.worktreeinclude` and return an invalid-manifest result for
  new-worktree preflight;
- report tracked application configuration as application-owned and requiring project-specific
  manual setup or an explicit repository contract;
- allow `git wt-copy` to reject the tracked entry while still copying separately approved ignored
  entries, then return failure so the unsafe request is visible;
- report tracked `CLAUDE.md` and `AGENTS.md` as already supplied by Git;
- classify private agent overrides as `[agent-override]` and client-local settings as
  `[client-settings]`, without suggesting either category as ordinary unlisted configuration;
- keep an explicitly manifest-listed ignored private file subject to the same user review and
  allowlist mechanism; and
- accept only a source worktree from the same Git repository. External folders, including secrets
  directories, are never implicit provisioning sources.

Project-specific setup remains an explicit repository contract or user-approved command. The
generic helper does not infer, discover, or execute setup from filenames or external directories.

## Alternatives considered

- Treat tracked manifest matches as ordinary missing files. Rejected because it hides an unsafe
  request and could invite copying application-owned configuration from another branch.
- Copy tracked configuration when the user asks. Rejected because the generic helper cannot know
  whether the source override is compatible with the target branch or contains sensitive values.
- Treat every ignored agent or settings file as an ordinary candidate. Rejected because copying can
  silently alter agent behavior, permissions, or tool behavior.
- Automatically search an adjacent secrets folder. Rejected because folder location does not prove
  project authority, provenance, safety, or compatibility.

## Consequences

Unsafe tracked-file requests fail visibly, while approved ignored files remain independently
provisionable through the manifest. Agents receive enough classification to ask for the right
project-specific or user-approved action without printing configuration contents. A consuming
repository must provide its own explicit setup contract when tracked application configuration or
external material is required.

## Reconsider when

Review this decision if a supported client introduces a native, explicit, and verifiable contract
for project setup and tracked configuration overrides, or if the manifest format gains a formally
scoped mechanism that distinguishes safe ignored files from application-owned state.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `home/dot_agents/skills/worktree-manifest/SKILL.md`
- `docs/worktree-provisioning.md`
- `README.md`
- `README.zh-TW.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run both provisioning suites. The focused cases must verify tracked-file rejection, unchanged
Git-provided tracked configuration, approved ignored-file copying, and separate private-file
classification without suggesting those files as ordinary candidates.
