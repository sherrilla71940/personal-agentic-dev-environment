# Reusable workflow archives

Workflow archives preserve a deliberate bundle of repository source files after a workflow is
removed or moved between environments. An archive is not a backup of the home directory and is
not a copy of a client session.

Native client artifacts are a separate category. [Claude Code can save reusable JavaScript
workflows](https://code.claude.com/docs/en/workflows), and both Claude Code and Codex can retain
client-local session or skill state. This archive feature does not automatically capture those
artifacts. It archives only the explicit, reviewed canonical source files in its definition, so a
native client workflow is in scope only when its managed source file is deliberately included in
that inventory. Session history, transcripts, `.project-continuity/`, generated targets, and
machine-local configuration remain outside the archive boundary.

The user-facing lifecycle is intentionally simple:

| Operation | Result | Recoverable through this feature? |
| --- | --- | --- |
| `workflow-archive` | Copy the confirmed source bundle, then delete its active sources | Yes, until the archive copy is deleted |
| `workflow-delete` | Delete the confirmed active sources without creating an archive | No new recovery copy; an older archive remains independent |
| `workflow-restore` | Restore missing source files from one archive | Yes |
| `delete-archive` | Delete one archive copy | No, although Git history may still contain the source |

The archive operation includes the source-copy step and active-source deletion. Users do not call
a separate preparatory command.

The boundaries are separate:

| System | Answers |
| --- | --- |
| Git history | Which tracked file contents existed at a commit |
| Workflow archive | Which source files intentionally made up one reusable workflow |
| Project continuity | Where one unfinished task stopped in one physical working tree |
| Chezmoi | How source state renders into live application targets |

## The user-facing workflow

You do not need to remember every related skill, adapter, document, or instruction file. Give the
archive or delete skill a workflow name or description:

```text
/workflow-archive archive the old worktree task workflow and remove its active sources
/workflow-delete delete the old worktree task workflow without creating an archive
/workflow-restore archives/workflows/worktree-task-workflow/v1
```

The equivalent Codex prompts use `$workflow-archive`, `$workflow-delete`, and `$workflow-restore`.
These are client invocations, not terminal commands. The skills perform bounded discovery and show
the proposed source/dependency/target boundary before mutation.

`workflow-archive` shows one combined plan: it will create the archive first, delete the confirmed
owned sources, keep shared dependencies, and queue generated-target cleanup. `workflow-delete` shows
the same source and target plan but explicitly says that no archive will be created. Both require a
second immediate confirmation before applying the plan.

Discovery is deliberately bounded. It checks the named workflow's primary entry point, direct
client adapters, directly referenced shared templates, referenced scripts and documentation, and
direct references found with `rg`. It does not silently recursively collect everything reachable
from a shared helper. The proposal identifies:

- owned canonical source files;
- shared dependencies that remain in place but are not copied or deleted;
- generated home-directory targets, if cleanup is needed later;
- exclusions and unresolved attribution questions.

The skill creates an explicit definition for the engine after the inventory is confirmed. A
definition under `scripts/manifests/workflows/<name>.json` is an optional catalog/authoring file;
it may be an untracked one-off candidate and does not need to be committed before archiving or
deletion. The generated archive manifest is the durable, self-describing inventory.

The current catalog contains the repository's `worktree-task-workflow` definition as an example of
a reusable source bundle. It is not a registry of every skill or every native client workflow. For
another workflow, the skill performs bounded discovery, shows the proposed inventory, and can use
a reviewed one-off definition. It must not infer a recursive dependency closure.

## V1 archive layout

Archive data is tracked under `archives/workflows/`, outside the chezmoi source tree and every
active skill-discovery directory:

```text
scripts/manifests/workflows/<name>.json   optional catalog definition
scripts/workflows/workflow-archive.py    shared archive, restore, and delete engine
archives/workflows/<name>/<id>/
  manifest.json                           generated archive metadata and inventory
  source/<repository-relative paths>      copied owned canonical source files
```

The archive directory is ordinary repository data. Chezmoi does not render it, and clients do not
discover skills from it. Running `chezmoi apply` therefore cannot restore an archive: apply reads
the selected `home/` source state, not `archives/`. Restoring is an explicit
`workflow-restore` operation that writes source files first; normal chezmoi preview/apply remains
separate.

## Definition fields

The engine accepts a JSON definition with `schemaVersion: 1`, a lowercase kebab-case `name`, an
optional description, dependency and profile-assumption notes, and these explicit lists:

| Field | Meaning |
| --- | --- |
| `files` | Required tracked canonical source files owned by this workflow and copied into an archive |
| `sharedFiles` | Tracked canonical files used by the workflow but shared and therefore kept in place |
| `targets` | Home-relative generated targets to queue in `home/.chezmoiremove` during archive/delete |
| `dependencies` | Human-readable prerequisites that are not part of this workflow bundle |
| `profileAssumptions` | Notes for readers; never profile enforcement |

Example:

```json
{
  "schemaVersion": 1,
  "name": "example-workflow",
  "description": "A reusable workflow definition.",
  "dependencies": ["Git worktree support"],
  "profileAssumptions": [
    "Uses the current profile resolver; restoration does not change profile selectors."
  ],
  "sharedFiles": ["home/.chezmoidata.yaml"],
  "targets": [".agents/skills/example-workflow", ".claude/skills/example-workflow"],
  "files": [
    "home/dot_agents/skills/example-workflow/SKILL.md"
  ]
}
```

List shared templates and client adapters in `files` when they are part of the workflow. List
shared infrastructure in `sharedFiles` when it must remain available to other workflows. The
catalog definition itself is not required in `files`; including it is optional and means the
catalog file is treated as workflow-owned source for restore and deletion purposes.

## Archive a workflow

`workflow-archive` resolves the workflow, creates or reviews the explicit definition, and runs the
engine twice: first as a dry run, then with `--apply` after confirmation.

```bash
python scripts/workflows/workflow-archive.py archive \
  --definition scripts/manifests/workflows/<name>.json \
  --id <archive-id> \
  --reason "<reason>"
```

The dry run reports the archive destination, source commit, files that will be copied and then
deleted, shared files kept, catalog treatment, targets to queue, and continuity exclusions. The
confirmed run is:

```bash
python scripts/workflows/workflow-archive.py archive \
  --definition scripts/manifests/workflows/<name>.json \
  --id <archive-id> \
  --reason "<reason>" \
  --apply
```

The engine creates the archive before deleting the confirmed source files. If the tracked catalog
definition should also be deleted, confirm that separately and add `--delete-definition`; the
definition is included in the archive before deletion. Otherwise it remains catalog metadata. The
engine queues generated target paths in
`home/.chezmoiremove`; it does not delete live targets. Review `git diff` and `chezmoi diff`, then
ask separately before running `chezmoi apply` to remove those targets on this machine.

The engine `--apply` is not `chezmoi apply`: it changes repository source state and archive data,
but never stages, commits, pushes, renders, or applies live configuration.

## Delete a workflow without archiving

Use `workflow-delete` when active-source deletion is intended and no new recovery copy is wanted.
The first command is a dry run:

```bash
python scripts/workflows/workflow-archive.py delete \
  --definition scripts/manifests/workflows/<name>.json
```

After reviewing the plan and confirming deletion, run:

```bash
python scripts/workflows/workflow-archive.py delete \
  --definition scripts/manifests/workflows/<name>.json \
  --apply
```

This deletes only the confirmed canonical source files and queues only the confirmed generated
targets. It does not create, modify, or delete an archive. An older archive for the same workflow
is independent and remains restorable until it is explicitly deleted. Git history may also retain
deleted source files.

## Restore an archive

Use `workflow-restore` for restoration. The first invocation is a dry run:

```bash
python scripts/workflows/workflow-archive.py restore \
  archives/workflows/<name>/<id>
```

The engine validates the manifest, confirms that the archive source inventory exactly matches its
file list, checks path safety, reports existing identical files, and stops on any collision. It
never overwrites an existing file and has no force option.

After reviewing the dry run, explicitly confirm the restore and run:

```bash
python scripts/workflows/workflow-archive.py restore \
  archives/workflows/<name>/<id> --apply
```

Restore writes only missing canonical repository source files. It does not change machine-local
`ai_context`, `ai_continuity`, or `ai_harness`, install dependencies, recreate generated client
targets, commit, or run `chezmoi apply`. After restoration, review `git diff`, run `git diff
--check`, run the repository pre-commit hook when applicable, and use the ordinary chezmoi
preview/apply workflow separately.

## Delete an archived copy

Deleting an archive is independent of deleting the active workflow. Dry-run the exact archive:

```bash
python scripts/workflows/workflow-archive.py delete-archive \
  archives/workflows/<name>/<id>
```

After explicit confirmation, repeat with `--apply`. This deletes only that validated archive
directory. It does not delete canonical source files, generated targets, shared dependencies, or
continuity state. This maintenance command is not the same as `/workflow-delete`.

## Exclusions and limits

The engine excludes generated client targets, private local instructions, credentials,
authentication state, `.project-continuity/`, archives from source inventories, caches, logs,
dependencies, build output, runtime data, symlinks, absolute paths, parent-directory traversal,
and untracked source files listed in `files`.

V1 does not provide an external archive store, automatic dependency installation, semantic
dependency resolution, client compatibility matrices, profile enforcement, schema migrations, or
package-manager behavior. Add those only when real archive use demonstrates a need.

The focused regression suite uses throwaway repositories and does not create or delete an archive
in this repository:

```bash
bash scripts/tests/test-workflow-archive.sh
```
