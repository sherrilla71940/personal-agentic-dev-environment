# ADR-0017: Review completed parked continuity state

- Status: Accepted
- Date: 2026-09-16

## Context

Project continuity keeps one active handoff in `.project-continuity/state.md`. When a developer
switches to another substantive task in the same working directory, the active handoff moves to
`.project-continuity/parked/<slug>.md` so the new task can use `state.md`.

The existing completion gate checks only the active file. The parking rules say that a parked file
should be closed when its task is done, but the lifecycle reporter does not inspect parked files.
As a result, a task can finish while parked without any review that identifies the file as ready to
close. Continuing work from a parked file also bypasses the active-state resume gate.

## Decision

Review every `parked/*.md` during continuity review and apply the same finished-state invariant as
the active state: `In progress`, `Next actions`, `Blockers`, and `TODO / deferred` must all be
empty or absent. Report a parked file that meets the invariant as a completed closure candidate.

Completion never authorizes deletion. The user must confirm each named parked file before cleanup,
and a declined candidate records `Cleanup: declined` in that file's Verification block. A parked
task must be moved back to `state.md` and resumed through the ordinary Resume workflow before work
continues on it.

The shared lifecycle reporter performs the structural check on `Stop` and reports candidates even
when no active state exists. It remains a reporter, not a cleanup mechanism: it does not delete
parked state and does not decide whether reasoning belongs in durable documentation. The skill
performs the reconciliation and confirmation step.

## Alternatives considered

- Keep parked review limited to cleanup or explicit listing: rejected because a completed parked
  file can remain indefinitely when no active task reaches cleanup.
- Delete completed parked files automatically: rejected because the finished-state invariant is
  structural and cannot decide whether a parked handoff still contains reasoning worth preserving.
- Treat parked files as an archive: rejected because Git history and the pull request hold durable
  project reasoning; parked state exists only to resume unfinished work.

## Consequences

Completed parked state becomes visible as a closure candidate without being removed unexpectedly.
The skill and the automatic reporter now agree about active and parked completion. Users must
confirm each parked deletion, and a parked task cannot be modified accidentally without first
resuming it. Existing age-based stale review remains a separate report during cleanup or an
explicit parked-task listing.

## Reconsider when

- Continuity gains a durable task registry that can distinguish active, parked, completed, and
  abandoned state without relying on the handoff file's sections.
- A supported client gains a safe, user-confirmed cleanup API for parked continuity files.
- The workflow changes from one active state per working directory to a different task model.

## Related files and verification

- [`home/dot_agents/skills/project-continuity/SKILL.md`](../../home/dot_agents/skills/project-continuity/SKILL.md)
- [`home/dot_agents/skills/project-continuity/references/state-format.md`](../../home/dot_agents/skills/project-continuity/references/state-format.md)
- [`home/dot_agents/skills/project-continuity/README.md`](../../home/dot_agents/skills/project-continuity/README.md)
- [`home/dot_local/share/maintain-project-continuity.sh.tmpl`](../../home/dot_local/share/maintain-project-continuity.sh.tmpl)
- [`scripts/tests/test-project-continuity-hook.sh`](../../scripts/tests/test-project-continuity-hook.sh)
