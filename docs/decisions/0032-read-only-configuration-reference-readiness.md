# ADR-0032: Add read-only configuration-reference readiness

- Status: Accepted
- Date: 2026-09-22

## Context

Git checks out tracked configuration, but a configuration file can explicitly depend on another
file through XML-style `configSource` or `appSettings file` attributes. A raw worktree can therefore
contain the tracked parent file while missing the referenced local file. The provisioning manifest
must not solve that gap by copying modified tracked configuration or by guessing which external
secrets source a project trusts.

The existing read-only provisioning classifier answers which ignored files are eligible for the
manifest. The tracked-configuration readiness check reports modified tracked candidates. Neither
check reported explicit configuration references or whether a referenced file was missing,
unmapped, or absent from a target worktree.

## Decision

Extend the Windows and macOS provisioning helpers with a path-only configuration-reference scan.
The scan runs as part of `git wt-check` and `git wt-readiness` and:

- inspects only tracked configuration candidates;
- detects explicit `configSource` and `appSettings file` attributes without printing file values;
- maps safe relative references from the containing configuration file while leaving
  application-root semantics to an explicit project contract;
- reports expected, present, missing, and unmapped references;
- reports a target-worktree omission when `--target` is supplied; and
- keeps modified tracked configuration advisory and separate from ignored-file provisioning.

The scan never creates or changes a manifest, copies a tracked file, executes a setup command,
reads an external secrets folder, or validates build, server, authentication, or database state.
A consuming repository can provide a tracked wrapper or setup command that passes known required
paths to `git wt-check --required`; the generic helper does not discover or execute arbitrary
project commands. If the consuming repository is not available to inspect, the workflow reports
that limitation rather than inventing project-specific paths.

## Alternatives considered

- Copy referenced files automatically. Rejected because a reference does not prove that the file is
  safe to share, ignored, approved, or compatible with the target branch.
- Copy modified tracked configuration such as `Web.config`. Rejected because a source override can
  change the target branch's runtime behavior.
- Treat every configuration-looking filename as required. Rejected because filenames do not prove
  runtime necessity or establish the trusted source of secrets.
- Execute a setup script discovered in the repository. Rejected because arbitrary setup commands
  can mutate the worktree, access credentials, or make application-specific assumptions without
  explicit approval.
- Inspect configuration values to validate readiness. Rejected because the provisioning check must
  not expose connection strings, secrets, or tokens.

## Consequences

Non-native preflight now exposes explicit configuration dependencies before or after worktree
creation. Agents can distinguish a missing referenced file from a tracked local override and from a
present file that Git cannot classify. The result remains advisory; application-specific setup and
runtime verification stay with the consuming repository and the user.

The Windows and macOS helpers must keep their reference parsing and no-value output behavior aligned.
Focused fixtures cover `configSource`, multiline `appSettings file`, missing and unmapped files,
target omissions, and the modified tracked `Web.config` boundary.

## Related files and verification

- `home/dot_local/share/git-worktree-provision.ps1`
- `home/dot_local/share/git-worktree-provision.sh`
- `docs/worktree-provisioning.md`
- `home/.chezmoitemplates/skills/task-workflow/lifecycle.md`
- `home/dot_agents/skills/task-workflow/SKILL.md`
- `home/dot_claude/skills/task-workflow/SKILL.md`
- `home/dot_agents/skills/worktree-manifest/SKILL.md`
- `scripts/tests/test-git-worktree-provision.ps1`
- `scripts/tests/test-git-worktree-provision.sh`

Run both provisioning suites. The suites must verify that the scan is read-only, remains advisory,
does not copy `Web.config`, and never prints fixture secret values.
