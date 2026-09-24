# Expected: park the existing state, then start the new task

## Governing rules

- `SKILL.md` Parking a second task: park when the user turns to something
  substantial while unfinished state is still useful, and say that you did.
- `SKILL.md` Wrong-task continuity: never merge the old task's state into the new
  one. "Put it aside for now" is a temporary switch, not an abandonment.
- Bootstrap: if the new request is itself substantial enough to need continuity of
  its own, park the existing state first, because there is only ever one
  `state.md`.

## Pass

- Never merges the session-store state into the new task, and never replaces it.
  That is what decides the case.
- Parks it before writing any state of its own: the file moves to
  `.task-continuity/parked/<slug>.md` with a `Parked:` full ISO 8601 timestamp
  added to its Verification block and nothing else changed.
- Timing inside the turn is not under test. Parking up front and parking at the
  first checkpoint both pass, because the rule is about not taking the one
  `state.md` slot from a live task, not about when the move happens.
- Says that it parked it, and names the path.
- Starts the rate-limiting work, creating fresh state for it once the work turns
  material rather than before.

## Fail

- Reconciles the session-store state so that its objective becomes rate limiting.
- Replaces the file outright. "Put aside for now" is not one of the two grounds
  for replacing without asking.
- Rewrites the parked file into a summary instead of leaving it as a handoff.
- Leaves the old state as the active `state.md` and starts a second one beside it.
- Says it parked the task without a file appearing in `parked/`.
