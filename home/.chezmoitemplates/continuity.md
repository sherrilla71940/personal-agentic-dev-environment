{{- $profile := includeTemplate "ai-profile.yaml" . | fromYaml -}}
{{- if and (eq $profile.ai_continuity "on") (eq $profile.ai_harness "managed") }}
## Task continuity

When `run-task-end-to-end` is active (including the legacy `task-workflow` and
`worktree-task-workflow` entry points), its
resolved continuity policy governs the task:
the requested `continuity=auto|on|off` value is separate from its effective value. `auto` inherits
the rendered profile value `ai_continuity`, while `on` and `off` are explicit task overrides. The
resolved echo reports both values and the source. Do not apply a second task-size heuristic inside
that workflow. When run-task-end-to-end selects a branch policy, record `Branch policy` and the resolved
task branch in the `Verification` block. Record `Flow` there as well when
`branch_policy=company-flow`; do not invent or copy a flow ID for `repository-standard` or an
explicitly declared project exception. Outside the workflow, use the reassessment guidance below.

The workflow may enter guided no-argument intake, prompted natural-language intake, or explicit
structured intake. These styles do not change continuity semantics. Guided answers are confirmation-
sourced; prompt values are prompt-sourced; explicit values are argument-sourced. A missing or
ambiguous value remains unresolved until the applicable question is answered.

When the managed harness has continuity enabled, reassess whether task state needs persistence
before substantive repository work. Do not initialize it for discussion, explanation-only
questions, trivial self-contained edits, formatting, or work fully recoverable from the diff.

Reassess continuity when a task develops meaningful scope, produces important investigation
findings, makes decisions that constrain later work, gains an unresolved dependency, reaches a
verified feature-completion boundary, is about to transition to another feature, reaches an
explicit handoff or resume boundary, or follows conversation compaction. Initialize it when the
resulting state is not cheaply recoverable from the repository, diff, or other durable sources.
An explicit handoff, resume, or compaction recovery may require state so another session can act
without guessing. Before ending a response while unfinished work remains, checkpoint enough for
the next session to identify the first unfinished action. After a commit, push, request creation,
merge, rebase, manual-test result, or decision to pause publishing, reconcile the delivery state
before ending the response. A commit may be a useful checkpoint when it changes what must be
recovered, but a commit by itself does not require rerunning the continuity decision.

When implementation differs from an approved artifact, classify it as an accepted scope difference,
a deferred dependency, or an unresolved decision. Keep deferred dependencies and unresolved
decisions in a durable PM/BE handoff or issue record, with only a concise pointer in `state.md`.
Do not treat a feature as fully closed until the difference is classified, owned, and durably
linked; an explicitly unverified ticket is valid, but an invented ticket is not.

When a task reaches a reassessment point, make the decision visible in the next progress update:
`Continuity: enabled` once state exists, or `Continuity: not needed — <reason>` when the task
remains cheaply recoverable. Keep trivial work quiet.

If the working tree root contains `.task-continuity/state.md`, read its `Objective` first and
decide whether it describes the task you were just asked to do. **State belonging to a different
unfinished task is never reconciled, merged into, or replaced without asking.** If it matches, use
the `task-continuity` skill and reconcile before substantive work. If it does not match, determine
whether the tracked task is still unfinished. Leave it untouched for a lightweight unrelated
request. If the new task also needs continuity and the existing task is unfinished, park the existing
state with the skill before initializing the new one. If the existing task is complete, apply the
completed-state transition: reconcile the finished invariant, then move the completed state into
`.task-continuity/parked/` using a non-colliding objective-derived name, and initialize the new
task with a fresh active state when effective continuity is enabled. Never overwrite the active or
parked record. This preservation move does not require deletion confirmation or force
`continuity=off`; deletion of the parked completed record remains a separate, confirmation-gated
cleanup decision. There is only one active `state.md`, and "parked" means it was actually moved
into `.task-continuity/parked/`.

When no active state exists and the current checkout has a named branch, use the
branch-aware parked-state discovery rules before treating the branch as a new task. A unique parked
record must match `Branch`, contain `Task` and `Base commit` or legacy `Started from`, and have a
start commit reachable from current `HEAD`; compare its objective and task intent before restoring
it. Legacy, branch-only, ambiguous, detached-HEAD, or conflicting candidates require explicit
selection or confirmation. Branch alone never selects a state, and the lifecycle hook remains
report-only.

If only the legacy `.project-continuity/state.md` exists, treat it as the same continuity state,
invoke `task-continuity`, and perform the one-time migration only after confirming that
`.task-continuity/` does not exist. Move the complete directory, including `parked/`, without
rewriting or deleting files. If both directories exist, stop and resolve the collision; never merge
or choose between them silently.

If state is absent and losing the conversation would cost materially more than rereading the diff,
use the skill and initialize continuity before proceeding. If the skill cannot be resolved by name,
read `~/.agents/skills/task-continuity/SKILL.md` directly. Always write continuity state in
English, regardless of the conversation language.

Use the `task-continuity` skill for initialization, reconciliation, parking, resume, handoff,
and cleanup. When `.task-continuity/state.md` already matches the current task, reconcile it
before substantive work and apply the skill's completion gate on every terminal workflow path, not
only after publishing. The gate is a required final-response step: a lifecycle-hook reminder does
not replace reconciliation or the user's explicit cleanup decision. Before ending a completed task,
report whether cleanup was completed, declined and recorded, or remains pending with the named
state files. Keep continuity cleanup separate from worktree and branch cleanup.
{{- end }}
