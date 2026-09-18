{{- $profile := includeTemplate "ai-profile.yaml" . | fromYaml -}}
{{- if and (eq $profile.ai_continuity "on") (eq $profile.ai_harness "managed") }}
## Project continuity

When the managed harness has continuity enabled, decide whether task state needs persistence before
substantive repository work. Do not initialize it for discussion, explanation-only questions,
trivial self-contained edits, formatting, or work fully recoverable from the diff.

Initialize continuity once the task produces non-obvious state worth preserving: implementation
with meaningful scope, important investigation findings, decisions constraining later work, or an
unresolved dependency. Reassess whenever a previously small task materially expands, produces new
non-obvious state, reaches an explicit handoff or resume boundary, or follows conversation
compaction. A commit may be a useful checkpoint when it changes what must be recovered, but a
commit by itself does not require rerunning the continuity decision.

Once a task reaches an activation signal, make the decision visible in the first progress update:
`Continuity: enabled` once state exists, or `Continuity: not needed — <reason>` if it was considered
but remains fully recoverable from the diff. Keep trivial work quiet.

If the working tree root contains `.project-continuity/state.md`, read its `Objective` first and
decide whether it describes the task you were just asked to do. **State belonging to a different
unfinished task is never reconciled, merged into, or replaced without asking.** If it matches, use
the `project-continuity` skill and reconcile before substantive work. If it does not, leave it
untouched for a lightweight unrelated request. If the new task also needs continuity, park the
existing state with the skill before initializing the new one. There is only one active `state.md`,
and "parked" means it was actually moved into `.project-continuity/parked/`.

If state is absent and losing the conversation would cost materially more than rereading the diff,
use the skill and initialize continuity before proceeding. If the skill cannot be resolved by name,
read `~/.agents/skills/project-continuity/SKILL.md` directly. Always write continuity state in
English, regardless of the conversation language.

Use the `project-continuity` skill for initialization, reconciliation, parking, resume, handoff,
and cleanup. When `.project-continuity/state.md` already matches the current task, reconcile it
before substantive work and apply the skill's completion gate when the task is complete.
{{- end }}
