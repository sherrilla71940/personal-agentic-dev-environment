# Reusable workflow deletion

Git is the recovery mechanism for tracked workflow source. This repository does not maintain a
second archive or restore format. Use Git history to locate an earlier source version, and use
`git restore --source <commit> -- <paths>` to recover selected files after reviewing the diff.

The deletion workflow remains useful because Git does not know which files make up one workflow,
which files are shared, or which generated home-directory targets must be removed by chezmoi. It
therefore provides a bounded, confirmation-gated source deletion plan and queues only confirmed
target paths in `home/.chezmoiremove`. It never commits, pushes, deletes live targets, or changes
continuity state.

## User-facing workflow

Use the explicit `workflow-delete` skill with a workflow name or description:

```text
/workflow-delete the old workflow
$workflow-delete the old workflow
```

The skill performs bounded discovery and presents:

- owned canonical source files eligible for deletion;
- shared dependencies that remain in place;
- generated home-relative targets to queue for chezmoi removal; and
- the catalog definition and any uncertainty requiring a decision.

It never recursively deletes everything reachable from a shared helper. Review the exact
inventory, then run the dry run and obtain a second immediate confirmation before `--apply`.

## Definition and engine

Definitions use `schemaVersion: 1` and explicit `files`, `sharedFiles`, and `targets` lists:

```json
{
  "schemaVersion": 1,
  "name": "example-workflow",
  "files": ["home/dot_agents/skills/example-workflow/SKILL.md"],
  "sharedFiles": [],
  "targets": [".agents/skills/example-workflow"]
}
```

The repository engine is:

```bash
python scripts/workflows/workflow-delete.py \
  --definition scripts/manifests/workflows/<name>.json
```

After reviewing the dry run and confirming the exact inventory:

```bash
python scripts/workflows/workflow-delete.py \
  --definition scripts/manifests/workflows/<name>.json \
  --apply
```

Use `--delete-definition` only when the tracked catalog definition is also explicitly confirmed
for deletion. The engine refuses untracked definitions, generated paths, private files,
continuity state, archives, symlinks, path traversal, and source files that are not tracked.

## Recovery and generated targets

To recover tracked source from Git:

```bash
git log --all -- <path>
git restore --source <commit> -- <path>...
```

After source deletion, review `git diff` and `chezmoi diff`. Run `chezmoi apply` separately only
after reviewing the generated target removals. Keep `.chezmoiremove` entries until every managed
machine has applied the deletion, then remove them in a later reviewed change.

Git history restores source contents; it does not restore application-owned settings, generated
targets, authentication, runtime state, or `.task-continuity/`. Those remain outside this
workflow's ownership boundary.

The focused regression suite is:

```bash
bash scripts/tests/test-workflow-delete.sh
```
