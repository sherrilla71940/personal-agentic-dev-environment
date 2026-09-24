# ADR-0045: Complete coordinated naming cleanup

- Status: Accepted
- Date: 2026-09-24

## Context

The earlier migration established `run-task-end-to-end`, `task-continuity`, and
`.task-continuity/` as the intended names, but it left compatibility wrappers and several local
directory names in place. That mixed vocabulary made it unclear whether a path held supplied task
materials, manual-test inputs, durable handoffs, or resumable task state.

## Decision

Use these names as the current public vocabulary:

- `run-task-end-to-end` for the full managed task lifecycle;
- `task-continuity` and `.task-continuity/` for resumable task state;
- `task-materials/` for stable reference inputs such as specifications, screenshots, spreadsheets,
  source documents, and external reference files;
- `test-materials/` for reusable test inputs and fixtures such as sample files, manual-test inputs,
  and reproducible testing artifacts;
- `handoffs/` for durable, updateable coordination records such as PM/BE notes, deferred decisions,
  unresolved dependencies, and ownership or status notes; and
- `.task-continuity/` for transient operational task state and pointers to those durable materials.

Rename the existing local `reference-docs/` and `handoff/` directories in place when their target
directory does not already exist. Do not create aliases for those material directories. No existing
`test-files/` directory was present during this migration; new consumers use `test-materials/`.

Remove the obsolete `project-continuity` skill, helper, symlink, and broad test aliases. Treat an
existing `.project-continuity/` directory only as a one-time migration input: verify that
`.task-continuity/` does not exist, move the complete directory including `parked/`, and never merge,
overwrite, or delete either directory silently. The lifecycle hook may read and report legacy state
or collisions, but it does not migrate state automatically.

Retain `task-workflow` and `worktree-task-workflow` as explicit compatibility aliases because
existing client prompts and invocation surfaces may still use those workflow names. New docs and
manifests use `run-task-end-to-end` as the primary name.

## Consequences

The source tree, rendered path definitions, local material directories, ignore policy, tests, and
documentation use one vocabulary. Historical decision records may still mention former names when
describing the decision that was made; their links point to the current source paths. A generated
target still requires the normal reviewed chezmoi application step after source changes.

## Verification

- `Documents/reference-docs/` moved to `Documents/task-materials/`.
- `Documents/personal/reference-docs/` moved to `Documents/personal/task-materials/`.
- `Documents/handoff/` moved to `Documents/handoffs/`.
- No `.project-continuity/` state was found in the primary checkout or known local workspaces.
- Focused continuity, route, profile, archive, and pre-commit checks remain the completion gate.
