# ADR-0011: Fix the continuity state path at `.project-continuity/`

- Status: Accepted
- Date: 2026-09-02

## Context

The `project-continuity` skill writes work-session state to `.project-continuity/state.md` at
the root of the working tree, and sets a second task aside under
`.project-continuity/parked/<slug>.md`. Fifty references to that path are spread across fifteen
files, counting neither this record nor its index row: the skill body, its state-format
reference and its README, the shared instruction body every client receives, the continuity hook,
the managed global ignore entry, the `worktree-manifest` skill that must keep the directory out of
a new worktree, both worktree provisioning scripts, three test scripts, and three documents.

The name is imprecise, and a reader is entitled to notice. The skill scopes state to one
physical working directory and one unfinished task, not to a project: the same repository can
hold several working trees, each with its own state, and reusing a tree for a second task
replaces or parks the first. `.task-continuity/` would describe that more accurately.

The same complaint was raised in the same session against `frontend-task-workflow`, and that
skill was renamed to `worktree-task-workflow` in 6d720b6. The two cases are not alike, which is
the distinction this record exists to fix. A skill name is a precondition a reader acts on:
`frontend-task-workflow` implied a restriction to frontend work and hid the worktree the skill
actually requires, so the wrong name sent readers to the wrong skill. A state directory name is
a label on a location the reader has already found. `.project-continuity/` sitting beside `.git/`
tells that reader what the directory holds.

Two further facts constrain a rename, and one of them was first assessed from memory and
assessed wrongly. The path's privacy does not come from per-clone Git excludes:

1. `home/dot_config/git/ignore` carries `/.project-continuity/` and renders to
   `~/.config/git/ignore`. Git anchors a leading slash in the global excludes file to each
   repository's own root, so one managed line covers every repository on every machine that
   applies this repository.
2. The skill adds `/.project-continuity/` to a clone's own `info/exclude` only when
   `git check-ignore` reports the path unignored. That path is a fallback for a machine without
   the global line, not the primary mechanism.

Renaming the directory is therefore a bounded edit rather than the per-clone migration it first
appeared to be. It still carries one hazard that the skill rename did not. Dropping the old
ignore entry while an orphaned `.project-continuity/` remains in any repository makes private
work-session state visible to Git, one `git add -A` away from a commit.

## Decision

Keep `.project-continuity/` as the continuity state path, and treat the name's imprecision as
accepted rather than outstanding.

Keep both privacy layers. The managed global entry is the mechanism; the per-clone fallback
stays because a machine can read this repository's skills before it has applied the repository's
Git configuration.

A future rename is a repository-wide convention change and needs its own ADR superseding this
one. It must also keep the old ignore entry in place until no orphaned directory remains, then
remove the entry in a separate commit.

## Alternatives considered

- **Rename to `.task-continuity/` or `.continuity/`:** rejected for now. The gain is one more
  accurate word at a location where the current word misleads nobody, and the cost is fifty
  references, two live state directories on this machine, a stale per-clone exclude entry, and a
  transition window in which private state can become committable.
- **Rename the skill but keep the directory:** rejected. The skill and its state directory are
  the same feature, so splitting their names moves the confusion instead of removing it.
- **Store state inside `.git/`:** rejected. Each linked worktree has its own Git directory, which
  matches the scoping, but state hidden there is not readable by a user inspecting their own
  working tree, and Codex and Copilot reach the file as an ordinary path.
- **Store state outside the repository, keyed by working-tree path:** rejected. It would need a
  machine-local index to map paths to files, it breaks when a worktree moves, and it removes the
  property that deleting a working tree deletes its state.
- **Track the file in Git:** rejected. Continuity holds unfinished, unreviewed working notes, and
  Copilot's repository memory is already shared where Claude's and Codex's are private.

## Consequences

The path is settled, so a session that notices the naming mismatch can read this record instead
of re-deriving the trade-off, which happened twice in one session before this record existed.

The name stays mildly inaccurate. A reader who expects project-wide or repository-wide state
finds task-scoped, working-tree-scoped state instead, and the skill's own scope section is what
corrects that.

Privacy now depends on a documented two-layer mechanism rather than on a claim about per-clone
excludes. A future session assessing this again has the verification commands below and does not
need to reconstruct them.

## Reconsider when

- The skill's scope stops being one working tree and one task, which would make the current name
  wrong rather than imprecise.
- The path stops being a literal in fifteen files, for example if the skill and hook read it from
  one shared definition, which would cut the rename cost to that definition.
- Another tool claims `.project-continuity/` and creates a real collision.
- A supported client gains native private per-working-tree state, which would replace the
  directory rather than rename it.

## Related files and verification

The path convention lives in the skill and is enforced by nothing but consistency:

- `home/dot_agents/skills/task-continuity/SKILL.md` — location, privacy and parking rules
- `home/dot_agents/skills/task-continuity/references/state-format.md` — file format
- `home/.chezmoitemplates/continuity.md` — the activation rule all three clients receive
- `home/dot_config/git/ignore` — the managed global ignore entry
- `home/dot_local/share/maintain-task-continuity.sh.tmpl` — `ensure_private_state_path`, the
  per-clone fallback, and the SessionStart and Stop reporting

Verify the two privacy layers from any repository that has continuity state:

```bash
git check-ignore -v .project-continuity/state.md   # names which layer is doing the work
git status --porcelain -- .project-continuity      # must print nothing
```

`~/.config/git/ignore` answering the first command is the expected result. A clone's own
`info/exclude` answering it means the global entry was missing when the skill ran there.
