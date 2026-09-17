# ADR-0015: Organize repository tooling by purpose

- Status: Superseded by [ADR-0016](./0016-rename-the-project-facing-tooling-command.md)
- Date: 2026-09-14

## Context

The repository's top-level `scripts/` directory had grown into a flat mixture of new-machine
bootstrap helpers, application installers, manifests, diagnostics, regression suites, and
continuity fixtures. That made paths in setup guidance harder to scan and made it unclear whether
a script was safe to run during ordinary configuration work. The repository also needed one
diagnostic command that could report source identity, rendered profile state, live drift, shared
skill-link health, and tool availability in one run.

The diagnostic needs both repository state and live chezmoi state. It is therefore different from
a command rendered into a user's home directory: it should be available from a clone and should
not become another managed target or depend on a machine-wide `PATH` convention.

## Decision

Group repository tooling under `scripts/` by purpose while keeping the Git hook directory stable:

```text
scripts/dotfiles                 command entry point
scripts/bootstrap/               new-machine setup
scripts/install/                 application-specific installers
scripts/manifests/               installer and extension data
scripts/diagnostics/             read-only health and usage reports
scripts/tests/                   regression suites and continuity fixtures
scripts/git-hooks/               Git's configured hook path
```

Expose the first repository command as `bash scripts/dotfiles doctor`. Its implementation stays
under `scripts/diagnostics/` and reports, without applying changes:

- chezmoi source identity and the repository checkout it resolves to;
- the resolved `ai_context`, `ai_continuity`, `ai_workflow`, and `artifact_language` values;
- unapplied `chezmoi status` output;
- the managed Claude shared-skill symlink set;
- chezmoi, Git, Node.js, and Python versions.

Keep `scripts/git-hooks/` at its existing path because `core.hooksPath` and bootstrap procedures
already refer to it. Update documentation and script callers when a purpose-grouped path changes.
The command remains repository tooling rather than a rendered `~/.local/bin` command, so it does
not add a new live ownership surface or a Windows/macOS command-discovery requirement.

## Alternatives considered

- Keep the flat directory: smallest immediate diff, but it preserves the ambiguity and makes the
  diagnostic entry point harder to discover.
- Render a `dotfiles` command into the home directory: convenient from any working directory, but
  it would mix repository diagnostics with managed machine tooling and require new PATH and
  cross-platform wrapper conventions.
- Create separate doctor scripts per operating system: unnecessary for the read-only checks here;
  Bash is already the repository's portable validation shell and the Windows bootstrap can invoke
  the same command through Git Bash when needed.

## Consequences

The layout is easier to navigate and the diagnostics have a single documented entry point. Moves
require path-reference updates and file-count checks, and users must run the doctor from a clone
unless they explicitly invoke it through that clone's path. No live target changes and no
application-owned configuration changes are implied by the reorganization.

## Reconsider when

- users need a stable command from outside a clone often enough to justify a managed command;
- the diagnostic must support a native PowerShell-only environment without Git Bash;
- the repository adds enough tooling that a subcommand dispatcher needs command discovery or
  completion beyond the current `doctor` entry point.

## Related

- [`docs/chezmoi-workflow.md`](../chezmoi-workflow.md)
- [`README.md`](../../README.md#repository-layout)
- [`AGENTS.md`](../../AGENTS.md)
