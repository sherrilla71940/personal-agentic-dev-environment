---
name: workflow-archive
description: "Discover, confirm, archive, and remove the active sources of a reusable workflow as one recoverable operation; do not archive generated or private state."
argument-hint: "[workflow name or description] [archive-id?] [reason?]"
disable-model-invocation: true
---

# Workflow archive

Create a recoverable archive of a reusable workflow after bounded discovery and user confirmation.
This is the one user-facing archive operation for `personal-agentic-dev-environment`: it creates
the archive copy and removes the active canonical workflow sources as one lifecycle. It does not
archive a conversation, a worktree's runtime state, application state, or a machine profile.

It never removes live home-directory targets directly. It queues their removal for a later,
separate `chezmoi apply` after the user reviews the rendered diff. Use `workflow-delete` when the
active sources should be removed without creating an archive.

Archiving is explicit-only and user-invokable in each supported client. The examples are prompts,
not shell commands. The user may name a workflow or describe what should be archived; the user
does not need to know its manifest path:

Claude Code:

```text
/workflow-archive archive the current worktree task workflow and remove its active sources
/workflow-archive archive the project-continuity implementation only; exclude runtime state
```

Codex CLI or IDE extension:

```text
$workflow-archive archive the current worktree task workflow and remove its active sources
$workflow-archive archive the project-continuity implementation only; exclude runtime state
```

## Discovery and confirmation

1. Establish the repository root and read the repository instructions. Confirm that the request
   refers to this repository's source state and not to a client session or `.project-continuity/`.
2. Perform bounded source discovery from the named or described workflow. Inspect its primary
   skill or entry point, direct client adapters, directly referenced shared templates, referenced
   scripts, operational documentation, and direct references found with `rg`. Inspect the current
   `state.md` only to keep runtime continuity out of the archive; never copy it.
3. Classify the result and show a proposed plan with four separate lists:
   - **owned canonical sources:** exact tracked files to copy and then delete;
   - **shared dependencies:** exact shared files or infrastructure to keep but not copy;
   - **generated targets:** exact home-relative targets, verified with `chezmoi target-path` where
     applicable, for the target cleanup this archive operation will queue;
   - **excluded or uncertain:** runtime state, generated output, private files, and anything that
     could not be attributed confidently.
4. Do not silently recurse through directories or include every file a shared helper happens to
   reference. If the boundary is uncertain, ask the user to resolve it before creating a
   definition.
5. After the user confirms the inventory, create or update an optional catalog definition under
   `scripts/manifests/workflows/<name>.json`. A one-off candidate may remain untracked; it does not
   have to be committed before archiving. The definition's `files` list is the confirmed owned
   source list, `sharedFiles` records files to keep, and `targets` records generated targets for
   the target cleanup this operation will queue.
6. Show the proposed archive name, ID, source commit, reason, exact file list, dependencies,
   profile assumptions, target metadata, and the fact that the listed sources will be deleted
   after the archive is created. Ask for confirmation immediately before the archive-and-delete
   operation. If the user did not provide an archive ID, inspect existing IDs and propose a new
   lowercase kebab-case ID; never overwrite an existing archive.

## Archive and remove the active sources

After the inventory confirmation, run the repository engine with the reviewed definition. The
first run is a dry run:

```bash
python scripts/workflows/workflow-archive.py archive \
  --definition scripts/manifests/workflows/<name>.json \
  --id <archive-id> \
  --reason "<reason>"
```

Show its complete plan and ask for immediate confirmation. Then repeat the same command with
`--apply`:

```bash
python scripts/workflows/workflow-archive.py archive \
  --definition scripts/manifests/workflows/<name>.json \
  --id <archive-id> \
  --reason "<reason>" \
  --apply
```

The engine creates the archive first, then deletes only the confirmed canonical source files and
queues only the confirmed generated targets. If the catalog definition is tracked and the user
also confirms its deletion, add `--delete-definition`; the definition is included in the archive
before it is deleted. Otherwise it remains available as catalog metadata. Re-read
`archives/workflows/<name>/<id>/manifest.json` and inspect the generated source tree after the
apply.

This engine `--apply` is not `chezmoi apply`: it changes repository source state and archive data.
It does not stage, commit, push, render, or remove live home-directory targets. Review `git diff`
and `chezmoi diff`, then ask separately before running `chezmoi apply`.

## What belongs in an archive

The definition's `files` list must contain every required canonical source file explicitly,
including client adapters and workflow-specific shared templates when they are part of the
workflow. The engine requires each listed file to be tracked and refuses paths outside the
repository's canonical source roots. The definition file is catalog metadata and is optional in
the archive's source inventory.

`sharedFiles` and `targets` are explicit classification fields. Shared files are kept in the
repository but are not copied. Targets are home-relative generated paths used only to queue later
live-target removal; they are never copied into the archive.

Never archive:

- generated client targets or rendered chezmoi output;
- secrets, credentials, private local instructions, or authentication state;
- `.project-continuity/`, caches, logs, dependencies, build output, or runtime data; or
- an inferred recursive file closure.

Record shared or machine-local prerequisites as metadata instead of copying unrelated state. The
archive records profile assumptions for readers, but it never changes `ai_context`,
`ai_continuity`, or `ai_harness`.

Read [the workflow archive guide](../../../../docs/workflow-archives.md) for the manifest contract,
archive layout, exclusions, and restore boundary. Use `workflow-restore` for restoration; do not
add restore behavior to this skill. Use `workflow-delete` for source deletion without creating an
archive.

## Delete an archive copy

Deleting an archived copy is separate from deleting the active workflow. It makes that archive no
longer restorable through this feature, while Git history may still contain the source. First
dry-run the exact archive:

```bash
python scripts/workflows/workflow-archive.py delete-archive \
  archives/workflows/<name>/<archive-id>
```

After explicit confirmation, repeat with `--apply`. This deletes only that validated archive
directory; it does not delete canonical source files or generated targets. This maintenance
operation is not the same as `/workflow-delete`.
