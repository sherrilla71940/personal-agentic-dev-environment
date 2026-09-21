# ADR-0029: Enforce the continuity completion gate at task boundaries

- Status: Accepted
- Date: 2026-09-21

## Context

Project continuity already defines a completion gate for active and parked state. The lifecycle
hook reports stale Git evidence and finished-state candidates, but it treated those notices as
alternatives: a stale HEAD or branch warning could hide the active cleanup offer. The hook also
ignored parked files without a valid `Parked:` timestamp, so age-based review could not distinguish
an old entry from an entry with unknown age.

This behavior allowed completed state to accumulate after later tasks parked it. The skill required
cleanup confirmation, but the workflow did not require the agent to reconcile the state and expose
the cleanup outcome before ending the response.

## Decision

Keep cleanup user-confirmed and non-destructive, but enforce the completion gate at every task
completion boundary:

- The lifecycle reporter combines stale-state, completion, parked-candidate, and parked-metadata
  notices in one response. A stale warning must not suppress a required cleanup review.
- A finished active state produces a required completion-gate message. The agent must reconcile it
  against Git, ask for cleanup confirmation, record `Cleanup: declined` when the user keeps it, or
  retain a concrete unfinished next action.
- A completed parked state remains a named deletion candidate. The reporter never deletes it, and
  the agent must state whether cleanup completed, was declined and recorded, or remains pending.
- A parked file without a full `Parked:` timestamp is reported with unknown age. The agent must
  reconcile the file before applying the 14-day stale-review rule and must not infer age from a
  file-system modification time.
- The workflow and shared continuity instructions treat this gate as a required final-response
  step. Hook output remains advisory at the client boundary; it does not authorize deletion or
  block a response by itself.

## Alternatives considered

- **Delete completed state automatically.** Rejected because continuity may contain private
  handoff information, and completion does not prove that the user no longer needs it.
- **Let stale-state notices suppress cleanup until the next response.** Rejected because a stale
  state can remain stale indefinitely, which is the accumulation failure this decision addresses.
- **Use file-system timestamps for parked age.** Rejected because mtimes are not a portable or
  intentional record of when a task was parked.
- **Add a durable task registry.** Rejected because the existing private, per-working-tree state
  remains sufficient when the completion gate is enforced at task boundaries.
- **Make the hook delete or block.** Rejected because client hook behavior differs across hosts and
  deletion still requires explicit user confirmation. The hook reports; the skill decides.

## Consequences

Completed state becomes visible at the same response boundary where the task appears complete.
Stale Git evidence no longer hides cleanup work, and parked metadata defects become actionable
instead of silently disabling age review. Agents must spend one explicit completion step on
reconciliation and the user's cleanup decision. The repository still does not delete continuity
state automatically, so a user who declines or does not answer can leave a visible, named pending
cleanup decision.

## Reconsider when

Revisit this decision if supported clients provide a common, user-confirmed cleanup API or a
durable task registry becomes necessary for continuity across working directories.

## Related files and verification

- [`home/dot_local/share/maintain-project-continuity.sh.tmpl`](../../home/dot_local/share/maintain-project-continuity.sh.tmpl) — lifecycle reporting
- [`home/dot_agents/skills/project-continuity/SKILL.md`](../../home/dot_agents/skills/project-continuity/SKILL.md) — completion gate
- [`home/dot_agents/skills/worktree-task-workflow/SKILL.md`](../../home/dot_agents/skills/worktree-task-workflow/SKILL.md) — task-boundary requirement
- [`home/.chezmoitemplates/continuity.md`](../../home/.chezmoitemplates/continuity.md) — shared continuity instruction
- [`scripts/tests/test-project-continuity-hook.sh`](../../scripts/tests/test-project-continuity-hook.sh) — lifecycle regression coverage
- [`docs/worktree-provisioning.md`](../worktree-provisioning.md) — operational workflow boundary
- [`docs/setup.md`](../setup.md) — rendered lifecycle hook behavior

Verification: `bash scripts/tests/test-project-continuity-hook.sh`
