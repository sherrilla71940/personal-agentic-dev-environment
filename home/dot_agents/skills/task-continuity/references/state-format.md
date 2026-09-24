# Continuity state format

Use this as the default shape for `.task-continuity/state.md`. Keep sections concise and omit empty optional sections when that improves readability.

```markdown
# Task Continuity

## Objective

One or two sentences describing the tracked outcome.

## Current phase

The phase another session should resume from.

## In progress

- Work that has started but is not verified complete.

## Blockers

- External dependencies, missing APIs, decisions needed, or other conditions that prevent progress.

## Next actions

1. The most useful concrete next step.
2. Additional ordered steps only when they materially help resumption.

## TODO / deferred

- Unresolved work that is real but not the immediate next action.
- Use labels such as `TODO integration` when appropriate to the project.
- When an implementation differs from an approved artifact, classify the difference as an
  accepted scope difference, a deferred dependency, or an unresolved decision. For the latter
  two, keep only a concise pointer here, for example:
  `Deferred follow-up: <slug> - unresolved; durable record: <path or issue URL>; owner: <role>;
  ticket: <verified ID/link or unverified>; trigger: <event>`.

## Decisions still in force

- Decisions that continue to constrain implementation and would be costly to rediscover.

## Verification

- Working tree: `<absolute path of this working directory>`
- Task: `<short stable task label, when known>`
- Branch: `<branch or unknown>`
- HEAD: `<commit or unknown>`
- Base commit: `<immutable origin/<base> commit used to start this task, when known>`
- Started from: `<commit this task began at, when known>`
- Base branch: `<workflow base branch, when a task workflow selected one>`
- Origin fetch: `<redacted origin identity, when a task workflow selected one>`
- Origin push: `<redacted push identity, when a task workflow selected one>`
- Branch policy: `<company-flow / repository-standard / project-exception, when a task workflow selected one>`
- Flow: `<one to nine digit flow ID, when company-flow selected>`
- Status: `<clean / modified / concise description>`
- Delivery: `<not applicable / commit pending / local-only complete / publish pending / published / publish declined>`
- Last reconciled: `<ISO 8601 timestamp with timezone>`
- Cleanup: `<omit normally; set to declined once the user has refused cleanup for this task>`
- Parked: `<omit normally; set to an ISO 8601 timestamp with timezone when this file is moved into parked/>`
```

## Maintenance rules

- Treat the continuity file's existence as the marker that continuity is active here.
- New workflow-created records should include a short stable `Task` label, the exact `Branch`, the
  immutable `Base commit`, and the selected `Base branch`. Keep `Started from` and set it to the same
  immutable commit as `Base commit`; `Started from` remains the compatibility field for older records.
- `Task` plus `Objective` plus the immutable `Base commit` (or legacy `Started from`) forms the task
  identity. These fields detect an obvious mismatch when a working tree is reused for a different
  task; do not add version or identifier machinery beyond them.
- Branch is supporting evidence, not identity. A branch switch in the same working tree does not by
  itself mean a different task. Update the recorded branch when reconciling the same task, never merely
  to silence a drift notice. A parked file may be considered for branch-based discovery only when it
  also has task and start-commit metadata; branch alone never selects a parked state.
- Record in `Status` whether this task's uncommitted changes were stashed or carried, naming the stash message or ref when they were stashed. A branch switch is the common cause but not the only one; a plain `git stash` produces the same clean tree. Without that, a later reconciliation may conclude the work was finished or lost. Nothing can be recorded when someone stashes outside the session, so Resume also runs `git stash list` against a clean tree.
- Obtain `Last reconciled` from the executing environment's current clock immediately before the
  whole-file checkpoint write. Use a full ISO 8601 timestamp with timezone, for example
  `2026-09-03T17:13:26+08:00`, so stale or overlapping updates can be distinguished precisely.
  Never estimate it, copy a conversation timestamp, or reuse an older value; if the current clock
  cannot be read, stop before writing rather than inventing a timestamp.
- Obtain `Parked` from the executing environment's current clock immediately before moving the file
  into `parked/`, using a full ISO 8601 timestamp with timezone. During every continuity review,
  inspect parked files for completion and report files with no unfinished sections as closure
  candidates; never delete them automatically. During cleanup or an explicit parked-task listing,
  also report entries older than 14 days as stale candidates with their paths and timestamps.
  Missing or invalid timestamps have unknown age.
- Keep the file under about 120 lines when practical. Compact it by removing resolved history, duplicated context, superseded decisions, and details already durable in the repository before it grows past that.
- Treat the file as subject to concurrent edits from another session or client. Re-read it immediately before writing and compare against what was loaded earlier; merge non-conflicting changes automatically and ask the user only on an actual contradiction. Never overwrite a version that was not just re-read.
- Concurrent edits are detected opportunistically, not transactionally protected. Two clients can
  each re-read the same version and both write, and the file is untracked, so nothing holds the
  version that lost. Rewriting whole is what limits the damage: a clobbered file still describes
  one task coherently, which the Resume gate can catch, where a half-merged one would read as
  valid while contradicting itself.
- Keep state language independent of conversation language: write every section in English, quoting a foreign-language string verbatim only where its exact wording matters. User-facing replies may follow the conversation language.
- Rewrite the file whole at every checkpoint rather than editing one section. Two sections
  disagreeing about the same item is the characteristic failure of this file, and patching
  in place is what produces it.
- Prefer current state over historical narrative.
- Replace superseded information instead of keeping both versions.
- Remove resolved blockers and completed TODOs from active sections.
- Record a completed step only inside `Current phase` or a decision that still constrains the work; there is no `Completed` section, because finished work belongs to Git.
- Label assumptions and unverified claims explicitly.
- Keep durable deferred-follow-up details in the PM/BE handoff or issue tracker rather than
  duplicating them in `state.md`. A deferred dependency or unresolved decision must have a durable
  record containing the source artifact and version, missing or mismatched fields, exact reason
  and current limitation, owner, verified ticket/link or explicit `unverified`, reopening trigger,
  required follow-up, acceptance criteria, and originating commit. Git remains authoritative for
  code and historical rationale; the state file is only the resumability pointer.
- When recording feature-level progress and verification, prefer the explicit form
  `Feature: \`<name>\` - <status>` outside and inside `Verification`. The lifecycle reporter uses
  that narrow vocabulary to flag an obvious contradiction such as a feature marked `complete`
  outside `Verification` while its verification line still says `pending`, `unverified`, or
  `failed`; free-form prose remains the skill's responsibility.
- Keep implementation details in the repository rather than copying large code snippets here.
- Do not invent next actions when the tracked work is complete; ask about cleanup instead.
- **Finished-state invariant.** `In progress`, `Next actions`, `Blockers` and `TODO / deferred` are
  the sections that carry unfinished work, and the task is finished exactly when all four are
  empty or absent. Claude's Stop hook reads that same test to raise the cleanup offer, so do not
  park a placeholder item in them to keep a finished file alive. Being finished is not by itself
  sufficient for cleanup, which also requires that nothing remains worth promoting elsewhere.
- A feature may be implementation-complete while a deferred follow-up remains open, but it is not
  fully closed until the discrepancy is classified, owned, and linked to a durable record. An
  unverified ticket is allowed; an invented ticket is not.
- Apply the finished-state invariant to active `state.md` and to every file in `parked/` during a
  continuity review. A completed parked file is a closure candidate, not permission to delete it;
  ask for confirmation for the named file first.
- Set `Cleanup: declined` only after the user has actually refused cleanup. It suppresses the offer for the rest of the task, so it must never be used to pre-empt asking.
- A file in `parked/` keeps this same format. Add `Parked` and change nothing else; it is a
  handoff that was set aside or a completed record preserved for a later task, not a summary of one. Do not continue work on a parked task until
  it has been moved back to `state.md`, remove its `Parked` marker, and resume it through the ordinary
  Resume workflow. When returning to a branch, a unique candidate with exact `Branch`, `Task`, and
  `Base commit`/`Started from` metadata may be selected after reconciling the current task and Git
  state. Multiple candidates, branch-only records, legacy records without the required identity, and
  detached HEAD require explicit file selection or user confirmation; never guess.
- Keep durable environment facts out of this file - a toolchain version, a shell workaround,
  a local URL. They are not task state, they inflate the file, and a longer file is what
  makes rewriting it whole feel expensive. They belong in the client's private project
  instructions instead.
- Do not store secrets or credentials.
