{{- $profile := includeTemplate "ai-profile.yaml" . | fromYaml -}}
{{- if eq $profile.ai_continuity "on" }}
## Project continuity

{{- if eq $profile.ai_workflow "managed" }}
Decide whether continuity is needed before the first substantive repository action, and create
it only once the work has produced something material: implementation started, a change spanning
several files, a non-obvious investigation finding, a decision that constrains what follows, or
an unresolved dependency. Discussion, questions and a plan still being negotiated do not need
state — the user holds that context too. This is later activation, not optional activation: once
that point is reached, create it without asking. In the first progress update for such work,
state either `Continuity: enabled` or `Continuity: not needed — <reason>` so the decision cannot
be skipped silently. A `not needed` verdict covers the task you were asked to do, not the one it
turns into, so reassess it at your first commit and at every commit after: a commit is already a
point where you stop to report a hash, which makes it the one moment the question cannot be
silently carried past. Reassess too whenever a small task grows into one of those, and always
use continuity for an explicit handoff or resume and after conversation compaction.

{{- else }}
Continuity is manual in native workflow mode. Do not automatically initialize, reconcile,
checkpoint, park, or clean up `.project-continuity/` state. Use the `project-continuity` skill
when the user explicitly asks to start, resume, checkpoint, hand off, or clean up continuity; the
normal lifecycle hook does not report or modify continuity state in this mode.
{{- end }}

{{- if eq $profile.ai_workflow "managed" }}
If the working tree root contains `.project-continuity/state.md`, continuity is already active.
Read its `Objective` first and decide whether it describes the task you were just asked to do.
**State that belongs to a different unfinished task is never reconciled, merged into, or
replaced without asking** — reconciling is how you update the state of the task it already
tracks, not how you take the file over for a new one. If the task matches, use the
`project-continuity` skill and reconcile before substantive work. If it does not, answer the
new request without touching that file, and report what it still tracks — check whether it
records unfinished work before describing it as unfinished. If the new request is itself
substantial enough to need continuity of its own, use the skill and park the existing state
first: there is only ever one `state.md`, so starting a second task without parking is what
destroys the first one's handoff. Say `parked` only if you actually parked it — parking is a
deliberate move into `.project-continuity/parked/`, not a word for state you merely left alone.
If the file is absent and losing the conversation would cost materially more than re-reading
the diff, use the skill and initialize continuity before proceeding. If the client cannot
resolve the skill by name, read and follow `~/.agents/skills/project-continuity/SKILL.md`
directly instead. Write that file in English whatever language this conversation uses.

Skip initializing continuity, and the visible decision, for explanation-only questions, small
self-contained edits, formatting, and work the diff already explains. That exemption covers
starting continuity only. When `.project-continuity/state.md` already exists and tracks the
current task, still reconcile it before substantive work, and still offer cleanup once that task
is complete, however light the current turn is.
{{- else }}
If the working tree root contains `.project-continuity/state.md`, it is available context, but do
not read, reconcile, checkpoint, park, or clean it up unless the user explicitly asks to use
continuity. If the user asks to resume it, use the `project-continuity` skill and reconcile it
against Git. If the user asks to start a separate task that needs continuity, use the skill's
parking procedure before creating a new state. Say `parked` only if you actually moved the file
into `.project-continuity/parked/`.

If the file is absent, use the skill and initialize continuity only when the user explicitly asks
for continuity. If the client cannot resolve the skill by name, read and follow
`~/.agents/skills/project-continuity/SKILL.md` directly instead. Write that file in English
whatever language this conversation uses.
{{- end }}
{{- end }}
