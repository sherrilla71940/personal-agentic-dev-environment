# ADR-0046: Retire tracked workflow archives in favor of Git recovery

- Status: Accepted
- Date: 2026-09-24

## Context

The repository introduced a tracked archive format for reusable workflow source bundles. It
created a second copy of tracked source inside `archives/workflows/`, plus separate archive,
restore, and archive-deletion skills. No archive instance exists in the repository today.

Git already preserves the contents and commit identity of tracked source files and can restore
selected paths from a reviewed commit. The archive copy therefore duplicates data without
providing stronger protection against a rewritten or lost Git repository. The useful part of the
workflow is the reviewed ownership boundary and the mapping from deleted source files to generated
chezmoi targets; Git does not provide those decisions.

## Decision

- Remove the tracked archive/restore format, archive and restore skills, archive engine, and
  archive-focused regression suite.
- Keep `workflow-delete` as a confirmation-gated, bounded source-deletion workflow.
- Use `scripts/workflows/workflow-delete.py` to validate explicit inventories and queue generated
  target removals in `home/.chezmoiremove`.
- Use Git history for source recovery with `git log` and `git restore --source`; do not create a
  second repository archive copy.
- Keep generated-target removal separate from source deletion. `chezmoi diff` and `chezmoi apply`
  remain separately reviewed operations.
- Keep continuity state, application-owned data, secrets, generated targets, and runtime state
  outside the deletion workflow.
- Mark ADR-0018, ADR-0019, and ADR-0020 as superseded while preserving them as historical records.

## Alternatives considered

- **Keep the archive format:** rejected because no archive has been used and the tracked copy
  duplicates Git history.
- **Delete source files directly with Git:** rejected because Git cannot identify workflow-owned
  versus shared files or queue generated-target cleanup.
- **Let `chezmoi apply` infer deleted targets:** rejected because removing a source entry does not
  express the intended target deletion and could leave stale targets behind.
- **Use an external archive store:** deferred until a real retention, repository-loss, or private
  archive requirement exists.

## Consequences

Source recovery now depends on retained Git history and a known commit or path. The repository has
fewer client surfaces and no duplicated archive bytes. Workflow retirement remains reviewable and
safe because it still requires an explicit inventory, a second confirmation, and a separate
chezmoi target-application step.

## Reconsider when

- Git history is no longer a reliable retention boundary for this repository;
- a workflow must be exported independently of the repository;
- private or external archive retention becomes a real requirement; or
- a client supplies a native workflow package format that should become authoritative.

## Related files and verification

- [`docs/workflow-deletion.md`](../workflow-deletion.md) — current deletion and Git recovery procedure
- [`scripts/workflows/workflow-delete.py`](../../scripts/workflows/workflow-delete.py) — bounded deletion engine
- [`home/dot_agents/skills/workflow-delete/SKILL.md`](../../home/dot_agents/skills/workflow-delete/SKILL.md) — user-facing skill
- [`scripts/tests/test-workflow-delete.sh`](../../scripts/tests/test-workflow-delete.sh) — focused suite

Verify with:

```bash
bash scripts/tests/test-workflow-delete.sh
python -m py_compile scripts/workflows/workflow-delete.py
```
