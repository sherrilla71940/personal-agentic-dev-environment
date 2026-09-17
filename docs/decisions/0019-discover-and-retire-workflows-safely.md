# ADR-0019: Discover workflow boundaries and retire sources explicitly

- Status: Superseded by ADR-0020
- Date: 2026-09-17

## Context

The first workflow archive implementation required a user to know the exact catalog manifest
before preservation was possible. That is an unreasonable discovery burden for a workflow that
may span a skill, client adapters, shared templates, scripts, documentation, and user-level
instruction sources. A recursive archive would remove that burden by making ownership ambiguous.

Retiring a workflow has a second boundary problem. Removing a chezmoi source does not normally
remove the old live target on the next apply, while deleting shared source files or continuity
state would damage unrelated workflows and active handoffs.

## Decision

- Accept a workflow name or description at the skill boundary.
- Perform bounded, evidence-based discovery of direct workflow files and references, then present
  owned sources, shared dependencies, generated targets, exclusions, and uncertainties for user
  confirmation.
- Keep the final inventory explicit. The catalog definition under
  `scripts/manifests/workflows/` is optional for one-off archives; the generated archive
  `manifest.json` is the durable self-describing inventory.
- Add `sharedFiles` and `targets` to the V1 definition contract. Shared files are retained and not
  copied. Targets are home-relative generated paths used only for a later cleanup plan.
- Separate archive creation, source retirement, and archive deletion. Each defaults to dry-run and
  requires an immediate explicit confirmation before mutation.
- Retire only confirmed workflow-owned canonical source files. Preserve shared files, catalog
  definitions unless separately selected, archives, `.project-continuity/`, and parked state.
- Queue generated target removal through `home/.chezmoiremove`; never assume that deleting a source
  and running `chezmoi apply` removes the target, and never delete a live target directly.
- Keep profile selection, dependency installation, commits, pushes, and chezmoi apply outside the
  archive/retire engine.

## Alternatives considered

- **Require users to author a complete manifest first:** rejected as the only entry point because
  it makes the feature useful only to people who already know the repository's internal graph.
- **Recursively archive every referenced file:** rejected because shared infrastructure and
  transitive references do not establish workflow ownership.
- **Delete sources and rely on `chezmoi apply`:** rejected because missing source entries do not
  express a target deletion; explicit `.chezmoiremove` entries are required for repository-wide
  cleanup.
- **Delete every discovered file:** rejected because discovery is evidence for a proposal, not
  authorization to remove shared or uncertain files.
- **Build a package manager:** rejected for V1. Dependency resolution, content identities,
  compatibility matrices, and migrations remain deferred until real use requires them.

## Consequences

Users can request preservation or retirement by outcome instead of memorizing source paths. The
agent still has to show and obtain approval for the exact boundary, and the resulting archive or
retirement definition remains inspectable and reproducible.

One-off archive creation can proceed before the catalog definition is committed. A catalog file
may be kept as a future authoring aid or omitted; the archive records its source path as provenance
but does not depend on the catalog for restoration.

Retirement can leave a temporary `.chezmoiremove` entry until all managed machines apply the
change. This is intentional lifecycle state and requires a later cleanup commit.

## Reconsider when

- real workflows repeatedly need transitive dependency closure or machine-readable compatibility;
- discovery produces too many uncertain boundaries to review efficiently;
- external or private archive storage becomes necessary; or
- chezmoi or a client provides a native workflow archive/retirement contract.

## Related files and verification

- [`docs/workflow-archives.md`](../workflow-archives.md) — archive, restore, and retirement procedure
- [`scripts/workflows/workflow-archive.py`](../../scripts/workflows/workflow-archive.py) — shared engine
- [`home/dot_agents/skills/workflow-archive/SKILL.md`](../../home/dot_agents/skills/workflow-archive/SKILL.md) — archive skill
- [`home/dot_agents/skills/workflow-delete/SKILL.md`](../../home/dot_agents/skills/workflow-delete/SKILL.md) — delete skill
- [`scripts/tests/test-workflow-archive.sh`](../../scripts/tests/test-workflow-archive.sh) — focused suite

Verify with:

```bash
bash scripts/tests/test-workflow-archive.sh
python -m py_compile scripts/workflows/workflow-archive.py
```
