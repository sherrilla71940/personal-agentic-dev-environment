# Expected: leave the state untouched

## Governing rules

- Bootstrap (`home/.chezmoitemplates/continuity.md`): when the state does not
  describe the task you were asked to do, answer the new request without touching
  that file.
- `SKILL.md` Resume, step 1: the gate is not a formality. Deciding the task does
  not match ends the workflow there.
- `SKILL.md` Activation: explanation-only questions do not get continuity.

## Pass

- Answers the question about `retry.ts`.
- Does not write, reconcile, or delete `.task-continuity/state.md`.
- Does not create a second state file for the question.
- If it mentions continuity at all, it reports that the existing state tracks a
  different task and says so accurately: unfinished, because `In progress`,
  `Blockers`, and `Next actions` all hold items.

## Fail

- Reconciles the state against the current repository, "correcting" the objective
  toward `retry.ts`.
- Rewrites the file because the recorded branch or HEAD no longer matches.
- Announces `Continuity: enabled` and initializes state for a read-only question.
- Calls the existing task parked without moving it into `parked/`.
