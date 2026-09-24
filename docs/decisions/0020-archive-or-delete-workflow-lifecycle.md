# ADR-0020: Make archive and delete distinct workflow lifecycles

- Status: Superseded by ADR-0046
- Date: 2026-09-17

## Context

The first workflow-management design exposed preservation and retirement as separate user-facing
operations. That required a user to know that a recoverable copy had to be created before source
deletion, even though the natural user choice was simply archive or delete. The separate names also
made it unclear whether an archive operation changed the active workflow.

The repository still needs bounded discovery, an explicit file inventory, and a separate cleanup
step for generated chezmoi targets. Archives must remain outside `home/`, because `chezmoi apply`
must never mistake stored source copies for active configuration.

## Decision

- Expose `/workflow-archive` and `/workflow-delete` as the two destructive workflow choices.
- Make `workflow-archive` one confirmed lifecycle: discover the boundary, create a recoverable
  archive copy, delete the confirmed active canonical sources, and queue confirmed generated-target
  removals in `home/.chezmoiremove`.
- Make `workflow-delete` delete the confirmed active canonical sources and queue the same target
  cleanup without creating or deleting an archive.
- Keep `/workflow-restore` as the explicit recovery operation. It restores missing canonical source
  files only, never generated targets, profiles, application state, or conversations.
- Keep archive-copy deletion as the separate internal maintenance operation `delete-archive`.
  Deleting an active workflow does not delete existing archives; deleting an archive copy is what
  removes that recovery copy.
- Keep live-target removal separate from source deletion. The workflow engine changes repository
  source state and `.chezmoiremove`; the user reviews `chezmoi diff` and separately chooses
  `chezmoi apply`.
- Keep the catalog definition optional for one-off discovery results. The generated archive
  `manifest.json` remains the durable explicit inventory.

## Alternatives considered

- **Keep separate preserve and retire commands:** rejected because the user-facing lifecycle is
  naturally archive-or-delete and the split invites source deletion without preservation.
- **Make archive automatically run `chezmoi apply`:** rejected because apply changes live machine
  configuration and must remain a separately reviewed operation.
- **Use one command with a `--preserve` or `--delete` switch:** rejected because two explicit skills
  make the irreversible difference visible in client discovery and confirmation prompts.
- **Delete active sources and existing archives together:** rejected because an existing archive is
  an independent recovery copy and should require its own confirmation.
- **Infer a recursive source closure:** rejected because shared dependencies and client adapters
  would become ambiguous; bounded discovery still ends in an explicit inventory.

## Consequences

Users can say “archive this workflow” and receive a source copy followed by active-source removal
in the expected order. Users can say “delete this workflow” when no new recovery copy is wanted.
Both operations still require exact-boundary review, and neither silently removes live targets.

An archive operation can leave an archive copy if a later source-deletion step fails; the engine
reports that partial result so it can be reviewed rather than silently retrying. Existing archives
remain available after a no-archive delete until explicitly removed. Git history may also contain
older source versions, so “delete” means no archive is created by that operation, not guaranteed
cryptographic erasure.

## Reconsider when

- repeated use shows that archive and source deletion need independent transactional recovery;
- `.chezmoiremove` needs a repository-wide lifecycle beyond the current reviewed apply boundary;
- users need archive discovery without an explicit workflow name or description; or
- a client introduces a native workflow archive format that should become canonical.

## Related files and verification

This decision is historical and is superseded by
[ADR-0046](./0046-retire-tracked-workflow-archives.md). The current deletion and Git-recovery
procedure is documented in [`docs/workflow-deletion.md`](../workflow-deletion.md).
