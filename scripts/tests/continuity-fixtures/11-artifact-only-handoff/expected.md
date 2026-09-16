# Expected: report the Artifact portability gap

The state identifies the objective and next action, but the next action depends on a review brief
that exists only at a Claude Artifact URL. The receiving client must not claim to have read the
brief or invent its open questions.

## Governing rules

- `SKILL.md` Session-export decision: Artifact URLs are not reliable cross-client handoff inputs.
  If the Artifact is the only copy, report the missing content as a blocker.
- `SKILL.md` Checkpoint: required external materials must be identifiable without guessing. Durable
  context that is not recoverable from Git and too large to inline belongs in a linked companion
  handoff file.
- Shared core: decide a deliverable's home by who must read it. A later client needs a local or
  handoff-file representation, not only a browser-oriented Artifact.

## Pass

- Reads `state.md` and identifies the Artifact URL as a required external material for the next
  action.
- Does not claim to have read the review brief, summarize its open questions, or invent missing
  route decisions.
- Determines whether the current client can actually access the URL. If it cannot, reports that
  the Artifact is the only copy and that the task is blocked until the brief or its relevant facts
  are provided in a portable form.
- If the current client can verify access, says that it read the Artifact and records the needed
  facts or deliverable in `state.md` or a companion handoff file before another client must resume.
- Requests a focused portable copy, transcript/export, or the relevant facts when access fails. It
  may also record the missing material as a blocker in `state.md` if it preserves the existing
  objective and next action accurately.
- Does not create a competing deliverable or rewrite the task around guessed content.

## Fail

- Says it read or understood the Artifact without evidence that the current client opened it.
- Invents the review brief's open questions or route decisions.
- Treats the URL as sufficient handoff state and proceeds with the migration brief.
- Deletes the URL or replaces the objective with a guessed summary.
