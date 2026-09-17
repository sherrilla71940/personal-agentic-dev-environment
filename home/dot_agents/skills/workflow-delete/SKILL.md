---
name: workflow-delete
description: "Discover and permanently delete a reusable workflow without creating an archive; schedule only confirmed generated-target cleanup."
argument-hint: "[workflow name or description]"
disable-model-invocation: true
---

# Workflow delete

Discover and delete a reusable workflow from this repository's canonical source state. This is a
destructive operation: it can delete source files and change `home/.chezmoiremove`, but it never
creates an archive, deletes live targets directly, commits, pushes, renders, applies, changes an
AI profile, or deletes an existing archive.

Deletion is explicit-only and user-invokable in each supported client. The examples are prompts,
not shell commands, and accept a name or description rather than requiring a manifest path:

Claude Code:

```text
/workflow-delete the old worktree task workflow
/workflow-delete the project continuity implementation
```

Codex CLI or IDE extension:

```text
$workflow-delete the old worktree task workflow
$workflow-delete the project continuity implementation
```

## Discover the deletion boundary

1. Establish the repository root and read its instructions. Confirm that the request concerns
   canonical workflow source, not `.project-continuity/state.md`, parked handoffs, a conversation,
   or an application's local state.
2. Perform bounded discovery from the named or described workflow. Inspect the primary skill or
   entry point, direct client adapters, directly referenced shared templates, referenced scripts,
   operational documentation, and direct references found with `rg`. Use `chezmoi target-path`
   for source-to-target checks where it is applicable.
3. Present and obtain confirmation for an inventory with these separate categories:
   - **owned canonical sources:** exact tracked files eligible for deletion;
   - **shared dependencies:** exact shared files or infrastructure that must remain;
   - **generated targets:** exact home-relative targets to add to `home/.chezmoiremove`;
   - **catalog definition:** keep it, or delete it with `--delete-definition` only when it is
     tracked and the user confirms;
   - **archives:** keep all archives by default;
   - **continuity:** keep `.project-continuity/` and all parked state.
4. Never infer a recursive dependency closure. If a source is shared or a target mapping is
   uncertain, leave it out of the deletion plan and report the uncertainty.
5. If the user wants a recoverable copy, stop this operation and use `workflow-archive` instead.
   Do not silently create an archive as part of deletion.

## Dry-run, then delete

After the inventory is confirmed, use the reviewed catalog definition or a temporary explicit
definition created from the discovery result:

```bash
python scripts/workflows/workflow-archive.py delete \
  --definition scripts/manifests/workflows/<name>.json
```

The engine must show the owned files to delete, shared files to keep, catalog treatment, generated
targets to queue, the fact that no archive is created, existing archives, and continuity
preservation. Stop and ask for a second, immediate confirmation before repeating with `--apply`:

```bash
python scripts/workflows/workflow-archive.py delete \
  --definition scripts/manifests/workflows/<name>.json \
  --apply
```

`--apply` deletes only the confirmed canonical source files and appends only the confirmed target
paths to `home/.chezmoiremove`. It does not delete a live target. The next separate operation is to
review `chezmoi diff`; only after that review may the user choose `chezmoi apply` to remove those
targets on this machine. Keep `.chezmoiremove` entries until every managed machine has applied the
deletion, then remove them in a later reviewed change. Add `--delete-definition` only when the user
has separately confirmed deletion of the tracked catalog definition.

This operation does not create an archive. If an older archive already exists for the workflow, it
is independent and remains restorable until the user explicitly deletes that archive. Git history
may also retain deleted source files.

## Safety boundary

Never delete:

- generated targets directly;
- shared source files listed as `sharedFiles`;
- `.project-continuity/`, parked state, credentials, private local instructions, or runtime data;
- `archives/workflows/` unless the user separately invokes archive-copy deletion and confirms the
  exact archive directory.

Read [the workflow archive guide](../../../../docs/workflow-archives.md) for the manifest fields,
chezmoi removal behavior, archive behavior, and focused tests. Use `workflow-archive` when a
recoverable archive is wanted and `workflow-restore` for restoration.
