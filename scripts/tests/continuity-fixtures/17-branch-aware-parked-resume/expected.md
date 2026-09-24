# Expected: locate and restore one parked task by Git identity

The fixture has no active state and one parked record whose `Branch`, `Task`, `Base commit`, and
`Started from` metadata match the current named branch and reachable history.

## Governing rules

- The branch-aware parked-state discovery section in `task-continuity/SKILL.md` permits one strong,
  exact-branch candidate to be selected after the current request matches its objective and start
  commit.
- The branch is supporting evidence, not the only identity. The task label, objective, and immutable
  start commit must also be reconciled.
- Restoring moves the selected record to the single active `.task-continuity/state.md`, removes its
  `Parked` marker, preserves the task identity metadata, and never copies over an existing active
  state.

## Pass

- Runs the repository identity preflight and confirms the current branch and `HEAD`.
- Finds the unique parked record by exact branch plus `Task` and `Base commit`/`Started from` metadata.
- Verifies that the recorded start commit is reachable from current `HEAD`.
- Confirms that the WaterFee FE-04 request matches the parked objective before restoring it.
- Moves the selected file to `.task-continuity/state.md` and removes `Parked` from the active record.
- Reconciles the restored state with Git before implementation.
- Leaves no second active state and does not alter unrelated parked records.

## Fail

- Starts a new state without inspecting parked records.
- Selects the record from the branch or filename alone.
- Restores a legacy or ambiguous candidate without explicit selection or confirmation.
- Overwrites an active state, copies the parked file instead of moving it, or deletes the parked record.
- Treats the parked record as proof of current code state without reconciling `HEAD`, branch, and status.
