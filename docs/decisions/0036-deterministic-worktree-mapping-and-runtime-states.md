# ADR-0036: Make external worktree mappings deterministic and separate runtime states

- Status: Accepted
- Date: 2026-09-22

## Context

`.worktreeinclude` is intentionally limited to tracked, explicitly approved ignored files. Some
projects still have a local configuration file that is outside that manifest, but a generic helper
cannot safely infer whether an adjacent file, another worktree, or an external secrets directory is
the right source. Copying tracked application configuration such as `Web.config` or replacing a
whole `.env` file can make the target application invalid and can expose secrets in diagnostics.

The existing runtime descriptor also answers a different question. A file can be provisioned safely
while the application has not been built, started, authenticated, or health-checked. The workflow
needs these states to remain separate.

## Decision

Add `git wt-provision` as a separate, read-only-first mapping command. Its dry run reports the
sanitized source path and SHA-256 fingerprint, source classification and branch, exact target
worktree and branch, the target's current HEAD, destination, operation, and a deterministic approval
ID. The agent must show that report and receive affirmative user approval before repeating the command
with the approval ID. The ID verifies mapping integrity only; it is not evidence that a human approved
the mapping.
The helper recomputes the identity immediately before writing and refuses a changed source path,
source fingerprint, target worktree, target HEAD, destination, operation, or contract version.

The generic helper permits only one-file copy operations:

- `copy-ignored-file` for an explicitly named ignored source in the target repository's worktree set;
- `copy-external-file` for an explicitly named non-tracked source; and
- report-only refusals for `merge-named-section` and `replace-file`.

The target must be Git-ignored, absent, inside the target worktree, and free of symbolic-link or
reparse-point traversal. The helper never copies tracked files, searches external folders, overwrites
existing files, infers section merges, or replaces whole `Web.config` or `.env` files. A changed
source or destination requires a new approval. `.worktreeinclude` remains the standing allowlist for
ordinary ignored-file provisioning.

Provisioning and runtime use separate state labels. Provisioning may be `provisioning-ready` or
require review/blocking remediation. A copied or otherwise provisioned worktree remains
`runtime-unverified` until the tracked `.worktree-runtime.json` helper completes its health URL and
process-ownership checks, at which point it may report `runtime-health-verified`. The latter still
does not prove authentication, database credentials, background services, or feature behavior.

The existing lightweight ecosystem scan remains evidence-only. It may identify ASP.NET/.NET,
Node.js, React/Vite, Next.js, and generic configuration markers, but it does not claim that the
application consumes them or turn framework detection into automatic setup. Project-specific setup
continues through a tracked report-only `.worktree-provision` contract or an explicit user-approved
project procedure.

## Alternatives considered

- Automatically copy `Web.config`, `.env`, or a nearby secrets directory. Rejected because tracked
  application files and external paths are application-owned and may contain credentials or branch-
  specific behavior.
- Ask for a one-time approval based only on a filename. Rejected because the source contents,
  destination, operation, and target worktree can change.
- Infer a section merge from XML or environment-file syntax. Rejected because the generic workflow
  cannot know the application's schema or precedence rules.
- Treat a successful copy as runtime-ready. Rejected because provisioning does not build, launch,
  authenticate, or validate application dependencies.
- Add framework-specific installers to the global workflow. Rejected because detection is useful as
  sanitized evidence, while setup ownership belongs to the consuming repository.

## Consequences

Agents have a deterministic, auditable prompt boundary for the rare external mapping case, and
stale approvals cannot silently copy changed data. The safety model is intentionally conservative:
project repositories must provide their own setup procedure when a whole-file replacement or a
domain-specific merge is required. The two platform helpers and their tests must keep the mapping
identity, refusal rules, redaction, and state labels aligned.

## Reconsider when

Revisit this decision if a supported client or repository standard provides a verifiable mapping
contract with a trusted section-merge schema, explicit secret handling, and an independent runtime
health protocol.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `home/dot_local/share/worktree-runtime.py`
- `docs/worktree-provisioning.md`
- `docs/worktree-runtime.md`
- `home/.chezmoitemplates/skills/task-workflow/lifecycle.md`
- `home/dot_agents/skills/task-workflow/SKILL.md`
- `home/dot_claude/skills/task-workflow/SKILL.md`
- `home/dot_agents/skills/worktree-manifest/SKILL.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run both provisioning suites and the runtime suite. The mapping fixtures must cover approval
invalidation, tracked-source refusal, target conflicts, report-only operations, evidence-only
framework detection, and redacted output.
