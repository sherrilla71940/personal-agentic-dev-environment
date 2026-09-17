# ADR-0018: Track explicit workflow archives outside active source and discovery paths

- Status: Superseded by ADR-0020
- Date: 2026-09-17

## Context

Reusable workflows in this repository can span a shared skill, a client-specific adapter,
workflow-specific templates, scripts, and operational documentation. Git history can recover each
tracked file at a commit, but it does not identify which files were intentionally one reusable
workflow. Project continuity is deliberately transient and cannot serve as an archive.

The repository also has a strict distinction between chezmoi source state and generated client
targets. An archive must preserve source material without becoming an active skill, a chezmoi
target, a copy of private state, or an inferred collection of unrelated shared files.

## Decision

Use a small, explicit workflow archive system:

- Track archives under `archives/workflows/<name>/<id>/`, outside `home/` and active skill-discovery
  directories.
- Define each workflow with an optional JSON catalog manifest under `scripts/manifests/workflows/`.
  The manifest lists every repository-relative canonical source file explicitly and records basic
  dependency and profile-assumption notes. The discovery-assisted lifecycle was initially defined
  by ADR-0019 and its separate preserve/retire user surface was later superseded by ADR-0020.
- Use `scripts/workflows/workflow-archive.py` as the shared archive, restore, and retirement
  engine. It requires a clean tracked source tree for archive creation, rejects generated/private
  paths and symlinks, and does not stage or commit.
- Expose workflow preservation and restoration as separate portable skills. Preservation is
  read-only with respect to existing source files; restore defaults to a dry run, requires explicit
  `--apply` for writes, and never overwrites an existing file.
- Restore only canonical source files. Profile selection, dependency installation, generated output
  rendering, `chezmoi apply`, commits, and pushes remain separate operations.
- Keep V1 free of content-derived IDs, hash trees, compatibility matrices, profile enforcement,
  schema migrations, automatic dependency installation, and semantic dependency resolution. Git
  supplies history and integrity for tracked archives.

The initial catalog definition covers `worktree-task-workflow`, including its Codex skill, Claude
adapter, workflow-specific shared templates, and provisioning guide. The catalog entry is optional;
the generated archive manifest is the required explicit archive inventory.

## Alternatives considered

- **Store archives only outside the repository:** rejected for V1. Tracked archives are reviewable,
  portable with the workflow system, and protected by Git history. Add an external store later if
  repository size or private archive needs justify it.
- **Discover files recursively:** rejected because shared dependencies and client adapters would be
  ambiguous, and an unrelated file could enter a reusable bundle silently.
- **Archive generated client targets:** rejected because targets are rendered outputs, may contain
  machine-local state, and can be recreated from canonical source.
- **Use one combined archive/restore skill:** rejected because archive creation and restore have
  different mutation and confirmation risks; they share an engine instead.
- **Build a package manager:** rejected for V1. Content identity, dependency resolution, migration,
  and compatibility machinery can be added only when actual usage requires them.

## Consequences

Archives duplicate selected source bytes, but they make a curated multi-file workflow boundary
visible and recoverable. A workflow author or archive request must produce an explicit inventory
when source paths change. Archive creation produces an ordinary uncommitted repository change, and
restoration can produce new source files that still require ordinary review, validation, commit,
and chezmoi apply.

Tracked archives do not protect uncommitted source changes; archive creation refuses them. Profile
assumptions and dependencies are documentation, not enforcement. The system therefore stays
portable without silently changing the receiving machine.

## Reconsider when

- tracked archive size or private archives make an external archive root more useful;
- repeated restores require file-level tamper detection beyond Git;
- workflows need dependency closure or compatibility checks rather than recorded notes;
- source schema changes require migration support; or
- a client introduces a native workflow archive format that should become the canonical boundary.

## Related files and verification

- [`docs/workflow-archives.md`](../workflow-archives.md) — current procedure and V1 limits
- [`scripts/workflows/workflow-archive.py`](../../scripts/workflows/workflow-archive.py) — engine
- [`scripts/manifests/workflows/worktree-task-workflow.json`](../../scripts/manifests/workflows/worktree-task-workflow.json) — initial definition
- [`home/dot_agents/skills/workflow-archive/SKILL.md`](../../home/dot_agents/skills/workflow-archive/SKILL.md) — archive skill
- [`home/dot_agents/skills/workflow-restore/SKILL.md`](../../home/dot_agents/skills/workflow-restore/SKILL.md) — restore skill
- [`scripts/tests/test-workflow-archive.sh`](../../scripts/tests/test-workflow-archive.sh) — focused suite

Verify with:

```bash
bash scripts/tests/test-workflow-archive.sh
python -m py_compile scripts/workflows/workflow-archive.py
```
