---
name: workflow-restore
description: "Validate and restore a tracked workflow archive into canonical repository source files with a dry-run, collision protection, and explicit confirmation."
argument-hint: "[archives/workflows/<name>/<id>]"
disable-model-invocation: true
---

# Workflow restore

Restore a workflow archive into the canonical source tree of
`personal-agentic-dev-environment`. This workflow restores source files only. It never restores
generated targets, private state, application settings, conversation history, or machine profiles.

Restoration is user-invokable in each supported client. The examples are prompts, not shell
commands:

Claude Code:

```text
/workflow-restore archives/workflows/worktree-task-workflow/v1
```

Codex CLI or IDE extension:

```text
$workflow-restore archives/workflows/worktree-task-workflow/v1
```

## Contract

1. Establish the repository root and verify that the archive path is under
   `archives/workflows/`.
2. Validate the archive manifest, schema, path safety, exact source-file inventory, source commit,
   and basic metadata. Do not infer missing files or resolve dependencies automatically.
3. Run the dry run and show which canonical files are already identical and which files would be
   created:

   ```bash
   python scripts/workflows/workflow-archive.py restore \
     archives/workflows/worktree-task-workflow/v1
   ```

4. Stop and ask for confirmation immediately before writing source files. If any existing target
   differs from the archive, stop with a collision; never overwrite it and never offer a force
   option.
5. After confirmation, run the same command with `--apply`:

   ```bash
   python scripts/workflows/workflow-archive.py restore \
     archives/workflows/worktree-task-workflow/v1 --apply
   ```

6. Re-read the restored files, review `git diff`, run `git diff --check`, and run the repository
   pre-commit hook when the restored files affect its checks. Do not commit or run `chezmoi apply`
   automatically; those are separate user-approved actions.

An archive can record the profile assumptions and dependencies it had when created. Restoration
must report them without changing the machine's `ai_context`, `ai_continuity`, or `ai_workflow`
values. Use `ai-profile` separately when a user wants to select an existing profile.

Read [the workflow archive guide](../../../../docs/workflow-archives.md) for the manifest contract,
archive layout, exclusions, and post-restore validation. Use `workflow-archive` to create a new
archive and remove its active sources; do not add archive behavior to this skill.
