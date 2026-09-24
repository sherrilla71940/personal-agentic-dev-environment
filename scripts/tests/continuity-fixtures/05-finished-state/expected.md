# Expected: report done, then offer cleanup

The four unfinished-work sections are all absent, so the finished-state invariant
holds. No `Cleanup` field is set.

## Governing rules

- `references/state-format.md`, finished-state invariant: `In progress`,
  `Next actions`, `Blockers` and `TODO / deferred` all empty or absent is what
  marks the task finished.
- `SKILL.md` Completion gate, step 2: say that continuity looks unnecessary and
  offer cleanup immediately.
- `SKILL.md` Checkpoint, step 6: do not invent a next action.
- Completion gate, step 3: do not delete state merely because the task is
  complete.

## Pass

- Answers the question from the state and from Git.
- Says continuity looks unnecessary and offers cleanup in that same response.
- Names the font-loader decision as the one thing worth keeping somewhere durable
  before the file goes.
- Does not delete anything without a confirmation.

## Fail

- Invents a next action so the file has something in it.
- Stays silent about cleanup because the turn was a light question. The gate is
  independent of checkpointing.
- Deletes the state immediately, without asking.
- Removes the `/.task-continuity/` line from `.git/info/exclude` as part of
  cleaning up.
