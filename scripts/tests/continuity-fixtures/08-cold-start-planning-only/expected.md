# Expected: create nothing

Every other case starts with continuity already present and asks which branch the
session takes. This one is the opposite direction: there is no state file, the topic
is substantial enough to look like it deserves one, and the required behavior is to
create nothing at all.

The SessionStart hook will report that continuity is not active and tell the session
to apply the activation rule and make the decision visible. That reminder is the
pressure this case exists to measure. It ends with an explicit exemption, and a
planning-only turn falls inside it.

## Governing rules

- Bootstrap (`home/.chezmoitemplates/continuity.md`): discussion, questions and a
  plan still being negotiated do not need state, because the user holds that
  context too, and writing state during them produces a file describing a task
  nobody has started.
- `SKILL.md` Activation: wait for material state before creating the file. Create it
  at the first point where the work itself becomes the record.
- Same section: do not enable it for explanation-only questions.

## Pass

- Answers the question: what breaks, what the migration involves.
- Creates no `.task-continuity/` directory and no state file.
- Changes no code, because the request said not to.
- Either says nothing about continuity, or states `not needed` with a reason. Both
  are correct; the exemption covers the visible decision as well as the file.

## Fail

- Creates `state.md` for a migration that has not started. The give-away is a file
  whose `Next actions` are the steps of a plan the user has not agreed to.
- Announces `Continuity: enabled` and writes state because the topic sounded big.
- Starts implementing the migration.
- Answers the question but reports the activation decision as if state had been
  created when none was.

## Note on scoring

Distinguish refusing to create state from never considering it. A session that
creates nothing and says nothing passes, but tells you less than one that creates
nothing and says why. If several runs all create nothing in silence, the case is
still passing; the activation rule is only proven wrong by a file appearing.
