---
name: project-continuity
description: Maintain private, working-tree-local work-session continuity across Claude Code, Codex and GitHub Copilot. Use when the current working tree already has continuity state, when the user asks to start, resume, checkpoint, hand off or clean up continuity, or when substantive work would be expensive to reconstruct if the current session ended abruptly. Do not initialize it for trivial or self-contained work.
disable-model-invocation: true
---

# Project Continuity

Continuity does not try to remember everything. It minimizes the cost of suddenly losing the current client's conversation — most often because usage limits end a session with no chance to hand off.

Treat it as **where the work stopped and why**, not as project documentation, native client memory, or a transcript.

## Operating principles

1. Repository and Git reality are authoritative for what exists. Continuity is context and last-known state, never proof.
2. Native client memory may inform reasoning but never by itself establishes the current objective, progress, blockers, next actions, or whether work is complete. Treat any current-task claim it makes as potentially stale and reconcile against Git. Do not read, write, curate or synchronize native memory as part of continuity work; each client's memory system keeps following its own rules independently.
3. Keep only state that materially reduces the cost of resuming.
4. Reconcile and prune stale state whenever reading or writing.
5. Never claim work is complete unless repository evidence supports it.
6. Do not silently promote temporary state into durable instructions.
7. Once enabled for a task, maintain it without asking permission to checkpoint again.
8. Re-read before overwriting; another client may be in the same working tree.

Read [references/state-format.md](references/state-format.md) when creating or restructuring the file.

## Completion gate

Before ending a response that touched continuity, apply this mandatory final-response gate. The
lifecycle hook is a reminder, not a substitute for this reconciliation or for the user's cleanup
decision:

1. Reconcile the state against the current repository and Git reality.
2. Apply the finished-state invariant: if `state.md` exists and `In progress`, `Next actions`,
   `Blockers`, and `TODO / deferred` are all empty or absent, the task is finished. Unless the
   Verification block already records `Cleanup: declined`, say that continuity looks unnecessary
   and offer cleanup immediately. Do not end the response with only a stale-state warning; after
   reconciling the warning, run this completion step in the same response.
3. Review every `parked/*.md` during every continuity review, not only during cleanup or an
   explicit parked-task listing. Reconcile each file against Git enough to apply the same
   finished-state invariant. Report a parked file with no unfinished sections as a completed
   parked-state closure candidate. Validate its `Parked:` timestamp before applying the age rule;
   a missing or malformed timestamp has unknown age and must be reported rather than inferred from
   file-system metadata. Completion does not authorize deletion: ask for confirmation before
   deleting each named file. If the user declines, record `Cleanup: declined` in that parked
   file's Verification block and do not raise that candidate again.
4. If the user confirms cleanup for the active state or named parked candidates, follow
   [Cleanup](#cleanup) and delete only the confirmed targets; do not delete state merely because
   the task is complete.
5. If the user declines cleanup for the active state, record `Cleanup: declined` in its
   Verification block and do not raise the offer again for that task.

The completion outcome must be visible before the response ends: cleanup confirmed and completed,
cleanup declined and recorded, or unfinished continuity retained with a concrete next action. A
clean branch, a removed worktree, or a successful publish does not choose among those outcomes.

## Finalization matrix

Run the completion gate before every final response after continuity was enabled or touched.
Publishing is one exit path, not the trigger for finalization. Reconcile the actual checkout and
classify the terminal outcome as follows:

| Exit path | Continuity action | Required report |
| --- | --- | --- |
| Plan-only request with no state | Do not create or change continuity state. | Continuity is not needed for the plan-only response. |
| Manual gate waiting, failed verification, or an unresolved blocker | Reconcile the evidence and keep one concrete next action or blocker. | Continuity retained, with the first unfinished action or blocker named. |
| Implementation complete with an uncommitted working-tree diff | Record `Delivery: commit pending` and keep the review/commit action explicit. | Do not offer continuity cleanup while the durable Git checkpoint is pending. |
| Local commit complete without publishing | Record `Delivery: local-only complete` when no publish is requested, or `Delivery: publish pending` when publishing remains part of the task. | State whether cleanup is offered or why continuity remains active. |
| User declines or defers publishing | Record the delivery decision and the exact next action only when the task still requires publication. | Keep continuity cleanup separate from worktree or branch retention. |
| Publish, merge, or rebase complete | Reconcile HEAD, branch, status, request state, and verification, then apply the completion gate. | Report active cleanup and parked candidates separately. |

Never put “offer cleanup,” “ask before deleting state,” or a similar cleanup prompt in `Next
actions`. That section is reserved for unfinished task work. A completed task must leave the four
unfinished sections empty so the completion gate can raise the cleanup offer deterministically.

This check is independent of checkpointing: a finished task removes the reason to keep state,
so the cleanup offer must not depend on another checkpoint occurring.

## Supported clients

Claude Code, Codex, and GitHub Copilot. The file is client-neutral, so ordinary operations need no client detection — determine the client only when routing durable private instructions.

Copilot reaches this skill through `~/.copilot/instructions/**/*.instructions.md`, documented for Copilot CLI and for VS Code sessions running on Agent Host, which read user-level instructions from that harness-agnostic folder rather than VS Code profile data. Other Copilot surfaces are untested; if the bootstrap did not arrive, the user can invoke the skill by name.

One Copilot-specific caution: Copilot Memory is repository-scoped and shared with others who have access to that repository, where Claude and Codex memory are machine-local and private. Continuity itself stays untracked and local either way.

## Scope: the physical working tree

Continuity belongs to **one working directory**, and each working tree has at most one active continuity state, describing its current unfinished task. The same boundary means one active task per physical checkout: a linked worktree and the primary checkout are separate scopes, but two tasks cannot safely share one checkout at the same time.

- The repository's primary checkout is a working tree. Continuity does not require creating a worktree.
- The same working tree is reused over time: finish task 1, clean up, start task 2 there.
- Same repository does not imply same continuity. Neither does same branch.
- **Switching branches does not create a new continuity scope.** Continuity is scoped to the directory, not the branch. If a branch switch means a different task while useful unfinished state is still present, apply the wrong-task rules below before replacing it. When both tasks must stay independently resumable, park one of them, or use a separate worktree when they also need separate uncommitted changes.
- **A branch switch is not a reconciliation trigger.** Claude's Stop hook reports a recorded branch that no longer matches the checkout, and that report is a warning not to merge rather than an instruction to update. Do not fold the new branch's work into state describing the old task, and do not rewrite the recorded branch just to silence the notice. Reconcile only once the task is established to be the same one. Do not key state files by branch name to avoid this decision either: a detached HEAD has no branch to key on, which is how the Codex app runs its managed worktrees, and uncommitted work belongs to the directory rather than to any branch.
- **Uncommitted work does not follow a branch, and a stash hides it entirely.** If a branch switch stashed or carried the task's changes, record that in `Status` — and record any other stash of this task's work the same way, naming the stash message or ref. A branch switch is the common cause, not the only one: a plain `git stash` leaves the same clean tree while state still describes work in progress, and a later reconciliation may conclude the work was finished or lost. A stash made outside the session leaves nothing to record at all, which is why Resume checks `git stash list` instead of trusting `Status` alone.
- A new worktree starts with no continuity and must not inherit another task's state. Claude Code's
  Git-created worktrees and Codex desktop's local managed worktrees consult `.worktreeinclude` at
  the repository root to decide which ignored files to copy. VS Code's native Agent Worktree uses
  the user-level `git.worktreeIncludeFiles` setting instead. Codex desktop also automatically copies
  an ignored `AGENTS.override.md`; that is client-owned behavior, not generic manifest approval.
  This repository's non-native `git wt-add` fallback runs the read-only `git wt-check` first, and
  blocks eligible ignored files that are not manifest-listed until an explicit unprovisioned
  decision is made. A pattern there matching `.project-continuity/` would leak one task's state
  into every supported provisioning path. Never add one.
- Repository identity precedes continuity. Compare the current execution workspace's Git root with
  any host- or user-provided active task repository before reading or reconciling `state.md`. If the
  roots differ, stop after read-only identity checks and ask whether to switch context or continue
  in the current workspace. If the active-file path is unavailable, report that limitation and use
  the explicit workspace preflight; ask for confirmation when the intended repository is ambiguous.
  An explicitly confirmed second repository is a separate task, so leave this worktree's continuity
  state untouched and do not park it for work occurring elsewhere.

Client worktree support differs, and that affects only how a directory is *created*, never who may work in it:

- **Claude Code** creates worktrees natively (`--worktree`, `EnterWorktree`, `isolation: worktree`) under `.claude/worktrees/`.
- **Codex CLI** has no worktree flag; it operates on the directory you start it in, which is all interoperability requires.
- **The Codex app** manages worktrees itself, in `$CODEX_HOME/worktrees` and in detached HEAD. Archiving a chat can delete its worktree, so clean up or hand off before archiving. Do not assume CLI, IDE extension and app behave alike.
- **VS Code Agent Worktree** creates native worktrees for supported agent harnesses, including Copilot hosted by VS Code, and uses the user-level `git.worktreeIncludeFiles` setting.

Whoever created the directory, any supported client can work in it.

## Activation

Reassess continuity when losing the conversation might cost materially more than re-reading the
diff: substantive implementation, multi-file changes, investigation that produced real findings,
refactors, migrations, architectural work, unresolved dependencies, an explicit handoff or resume,
or recovery after compaction. Initialize it only when the resulting state is not cheaply recoverable
from the repository, diff, or another durable source.

**Wait for material state before creating the file.** Discussion, questions, options being weighed and a plan still being negotiated are not yet expensive to lose — the user holds that context too, and writing state during them produces a file describing a task nobody has started. Create it at the first point where the work itself becomes the record: implementation begins, a change spans several files, an investigation turns up something non-obvious, a decision is made that constrains what follows, or a dependency is left unresolved. This is later activation, not optional activation — once that point is reached, create it without asking.

Reassess when a small task grows into one of those. An explicit handoff, resume, or compaction
recovery may require state so the receiving session can continue without guessing.

Do not enable it for explanation-only questions, small self-contained edits, formatting, or work that is obvious from the diff.

The presence of `.project-continuity/state.md` means continuity is already active — resume it without asking to opt in again, once you have confirmed it tracks the current task. When the file is absent and the work qualifies, create it and say so rather than interrogating the user first. Ask only when it is genuinely unclear whether the work qualifies.

This skill cannot bootstrap its own discovery. The user's always-on instructions carry a small rule that checks for the file and invokes this skill by name, with `~/.agents/skills/project-continuity/SKILL.md` as an explicit fallback path when name resolution fails.

## Location and privacy

Continuity always lives at one canonical path, relative to the working tree root:

```text
.project-continuity/state.md
```

The directory belongs to this workflow. Never put anything else in it.

**State language is independent of conversation language.** Always write the file in English. It
is working state handed between agent sessions and clients, not a project artifact, so neither a
repository's comment-language convention nor the language of the current conversation reaches it.
A reconciling session should never have to translate before it can establish where the work
stopped. User-facing replies may follow the conversation language, and quoted material is exempt:
keep an error message, a UI string, or the user's own wording verbatim when the exact text matters,
and write the surrounding state in English.

In a Git repository, ensure it is ignored before relying on it as private:

1. Check whether `.project-continuity/` is already ignored, and stop if it is.
2. Resolve the exclude file with `git rev-parse --git-path info/exclude`.
3. Add the anchored entry `/.project-continuity/`.
4. Do not touch tracked `.gitignore` for this workflow unless the user asks.

`info/exclude` lives in the repository's common directory, so it is **shared by the primary checkout and every linked worktree**, and the anchored pattern resolves against each working tree's own root. One entry therefore protects every working tree, including ones created later — which is why cleanup must never remove it.

Being ignored is also what makes the file sweepable. `git stash -a` moves it into the stash and `git clean -x` deletes it outright, while a plain `git stash`, `git stash -u` and `git clean -d` all leave it alone. If continuity is missing from a working tree that should have it, check `git stash list` before concluding it was never created or was cleaned up.

Outside Git, keep the file local and tell the user that ignore-based protection is unavailable.

Never store secrets, credentials, personal data unrelated to the work, or large copied artifacts.

## Resume

Step 1 is a gate, not a formality. Everything after it assumes the answer was yes.

1. **After the repository identity preflight passes, read the `Objective` and `Started from`, and
   decide whether this state tracks the task you were just asked to do.** If it does not, stop here
   and follow the wrong-task rules below.
   Do not reconcile first and decide afterwards: reconciling rewrites the file to match what you
   are doing now, which is exactly how another task's handoff state gets destroyed.
2. Inspect enough repository state to establish reality: branch and HEAD, working-tree status and diffs, the files continuity names, and tests or build output when a claim depends on them.
   **When the tree is clean but state describes uncommitted work, run `git stash list` before concluding anything about it.** The user, another client, or a tool may have stashed that work without recording it, and a clean tree is otherwise indistinguishable from work that was finished, reverted or lost. Report a matching stash and let the user decide; never restore or drop one on your own.
3. Reconcile — correct claims that are no longer true, drop resolved blockers and completed TODOs, replace superseded decisions, absorb work done after the last checkpoint, and deduplicate.
4. Preserve reasoning that is still load-bearing, especially rejected approaches and constraints the code does not explain.
5. Identify the first genuinely unfinished action and continue the task. Do not spend the response restating continuity unless a status report was asked for.

When resuming because of a client switch, conversation loss, or an explicit handoff request, also
apply [Session-export decision](#session-export-decision) before asking the user for more context.

Where repository evidence and continuity disagree, the repository wins and continuity is corrected. Where the user's current instruction and continuity disagree about intent, the user wins.

## Wrong-task continuity

When the existing state clearly belongs to a different task, never merge it into the current one. Then:

- Replace it without asking on two grounds only: the finished-state invariant holds for it, or
  the user said to abandon that task. The first is a check you can run, the second is an
  instruction you were given.
- Otherwise preserve it and ask before replacing — including when it merely looks obsolete or no
  longer useful. That judgment has no oracle, and the file is untracked and ignored, so a wrong
  call destroys handoff state with nothing to recover it from. The test is whether replacing
  would destroy recoverable handoff state, not whether the new request is ambiguous — a user
  saying "forget that for now, fix the navbar" may be switching tasks temporarily, not
  abandoning the old one.

Before replacing, name anything in it that belongs in durable documentation or private
instructions, the way [Cleanup](#cleanup) requires before deleting. Parking is not how you keep
one fact from an abandoned task — it leaves a whole handoff nobody will return to, and a
session reaching for it to preserve a single constraint has picked the wrong mechanism.

Do not build an archive or history system to avoid this decision. When both tasks need to stay resumable in the same directory, park the first one.

## Parking a second task

A worktree is the right answer when two tasks need separate working trees — separate uncommitted changes, separate HEAD. It is the wrong answer when they do not, and it is unavailable in a repository whose own instructions forbid worktrees. Parking covers that case:

```text
.project-continuity/
  state.md                 the active task
  parked/<short-slug>.md   tasks set aside, same format, not active
```

- **Park:** move `state.md` to `parked/<short-slug>.md`, where the slug comes from the objective. Add `Parked: <ISO 8601 timestamp with timezone>` to its Verification block and change nothing else — a parked file is a handoff, not a summary.
- **Resume:** move it back to `state.md`, then run the ordinary Resume workflow against it. Park whatever was active first; there is never more than one `state.md`.
- **Continue a parked task:** do not continue work on a task while its state remains in `parked/`.
  Resume it first by moving it back to `state.md`, park the currently active state if needed, and
  run the ordinary Resume workflow before taking substantive action.
- **List:** read the directory. There is no index to maintain and nothing to keep in sync.
- A completed parked file is a closure candidate, not permission to delete state. Deletion still
  requires explicit confirmation for the named file.
- **Review:** inspect `parked/*.md` during every continuity review. Apply the finished-state
  invariant and report files with no unfinished sections as closure candidates. Ask for confirmation
  before deleting each candidate, and never delete one automatically. During cleanup or an explicit
  parked-task listing, also treat entries whose `Parked` timestamp is more than 14 days old as
  stale candidates, report their paths and timestamps, and never delete them automatically. A
  missing or invalid timestamp has unknown age and should be reported as such.
- **Close:** delete the file when its task is done. Parked state is not an archive, and a finished task leaves nothing behind here — Git history and the pull request are where a decision's reasoning belongs.

Park when the user turns to something substantial while unfinished state is still useful, and say that you did. Do not park to avoid asking: if the new request is small, answer it and leave `state.md` alone. If the old task is genuinely abandoned, replace it rather than parking it, so the directory does not fill with work nobody will return to. When a parked task is complete, leave its unfinished sections empty and let the completion gate report it as a named closure candidate; do not add cleanup as a placeholder next action.

The Git exclude entry is `/.project-continuity/`, so it already covers `parked/`. The lifecycle
reporter checks parked files for completed-state closure candidates but never deletes them; the
skill still requires confirmation before cleanup.

## Checkpoint

Checkpoint when the cost of losing what is not yet recorded becomes material. Favor what cannot be cheaply reconstructed from the repository: undocumented API or backend behavior, a user decision that constrains the implementation, a rejected approach and why, a surprising test or debug finding, a change of architectural direction, a hidden dependency, the cause of a blocker. Execution state also qualifies when rebuilding it would be expensive.

Before the first substantive action of a turn, checkpoint when the current user instruction materially changes the objective, requirements, decisions, blockers or next action. Record normalized task state, not prompt text. During a long-running turn, checkpoint again at meaningful phase boundaries when losing the new state would be materially expensive.

Treat a verified feature-completion boundary and the transition to the next feature as explicit
checkpoint opportunities. After a delivery action such as a commit, push, request creation,
merge, rebase, manual-test result, or user decision to pause publishing, reconcile the actual
delivery state before ending the response. Before ending a response while unfinished work remains,
checkpoint enough for another client to identify the first unfinished action. These are semantic
checkpoints, not a requirement to rewrite state after every commit.

At each checkpoint and before ending a response with unfinished work, apply this resumability test:
if this session ended now, could another supported client identify the objective, current phase,
first unfinished action, blockers, required external materials, and unverified assumptions without
guessing? If not, update continuity. Skip the update when every fact needed to resume is already
durable in the repository or current state.

Required external materials include deliverables and durable context that the repository cannot
recover. If that context is too large to inline, put it in a companion file under
`~/Documents/handoff/{repo}/YYYY-MM-DD/{HH-mm}-{slug}.md`, record its `Created`, `Last updated`,
timezone or UTC offset, and commit or state pin, and link it from `state.md`. Keep `state.md` as the entry point for
the objective, decisions, blockers, and next action; do not create competing copies of those facts.

Do not checkpoint when nothing meaningful changed, when the information is already obvious in code or tests, when the update would repeat conversation text, or when the change is trivial and cheap to redo.

When checkpointing:

1. Re-read the file immediately before writing and compare it with what was loaded earlier. Merge automatically when changes are clearly non-conflicting; ask only on a real contradiction. Never overwrite a version that was not just re-read.
2. Reconcile against current repository and Git state.
3. **Write the file whole. Never patch a section in place.** A targeted edit updates the part you were thinking about and silently leaves every other section asserting what it asserted before, which is how a state file ends up contradicting itself: one section still calling work outstanding that a later section records as done, a superseded conclusion nobody removed, a `not verified` line the user has since falsified. Rewriting forces you to re-affirm every claim, and the file is capped at about 120 lines precisely so that stays cheap. Never append a diary entry either.
   **Whole means every section of the task this file already tracks — never this task in place of another's.** Replacing one task's state with a different task's is the separate failure the Resume gate exists to stop, and you only reach this step once that gate has answered yes. Step 1 above is also what makes writing whole safe when another client shares the working tree: a whole-file write clobbers more than a targeted one, so the re-read immediately before writing is not optional here.
4. Remove stale, resolved, duplicated, or superseded entries.
5. Keep it under about 120 lines; compact it by dropping resolved history and detail the repository already holds.
6. If the work is complete and nothing continuity-worthy remains, do not invent a next action — say continuity looks unnecessary and offer cleanup.

## Deferred follow-ups and completion

When implementation differs from an approved mockup, specification, or other artifact, classify
the difference before treating the feature as complete:

- **Accepted scope difference:** the omission is intentional and needs no follow-up; preserve the
  rationale in the appropriate project record or commit when it matters.
- **Deferred dependency:** the implementation cannot match the artifact until another dependency
  changes, such as an API or schema. It remains open and needs a durable follow-up record.
- **Unresolved decision:** the expected behavior or scope still needs a PM, product, or owner
  decision. It remains open and needs a durable follow-up record.

For a deferred dependency or unresolved decision, keep the complete record in the PM/BE handoff or
issue tracker, not in continuity state. It must identify the source artifact and version, missing or
mismatched fields, exact reason and current limitation, owner, verified ticket or link (or explicitly
`unverified`), reopening trigger, required implementation follow-up, acceptance criteria, and
originating commit. Do not invent a ticket. Put only a concise pointer, status, owner, ticket state,
and trigger in `TODO / deferred` or `Next actions`.

Before declaring a feature **fully closed**, surface each active deferred follow-up and confirm that
it is classified, owned, and linked to durable tracking. “Implementation complete” may coexist with
an open deferred follow-up; “fully closed” may not. On resume, re-check the durable pointer and the
Git evidence rather than copying the implementation history into `state.md`.

## Handoff

Only when the user says they are stopping, switching client, or asks for one: checkpoint fully,
apply the resumability test, make the next action concrete and executable, label blockers and
unverified assumptions, record branch and HEAD, and report a short summary rather than the whole
file. A handoff does not imply cleanup.

## Session-export decision

At an explicit handoff, client switch, or resume after conversation loss, decide whether the
receiving client needs the source client's transcript in addition to `state.md`. Do not ask for an
export on every turn, and do not use an export request instead of a focused clarification when one
missing fact is enough to continue.

Use exactly one of these labels in the user-facing response:

- **Session export: not needed** — `state.md`, Git, and the named repository materials identify the
  objective, current phase, first unfinished action, blockers, decisions still in force, and
  verification without guessing. Important conversation-only reasoning has already been reduced
  into the state file.
- **Session export: recommended** — the state is actionable, but the conversation contains useful
  details that would be expensive to reconstruct, such as multiple pivots or rejected approaches,
  detailed UI behavior, screenshots, external research, or a long debugging trail. Explain why and
  ask the user to provide the source client's export if preserving that detail matters; continue
  when the state and repository make the next action safe.
- **Session export: required** — the state and repository do not provide enough information for a
  safe, unambiguous next action, and the missing context is broad or conversation-only. Stop before
  substantive work and request the source client's export or an equivalent transcript/summary. If
  one focused user answer would resolve the gap, ask that question instead of requiring a full
  export.

**Artifact URLs are not guaranteed cross-client handoff inputs.** A person or a client may be able
to open a Claude Artifact when it has the required access and browser path, but the receiving client
must verify that; the URL alone is not evidence that the content was opened. Record an Artifact URL
for the source client's convenience, but put any fact or deliverable a receiving client needs in
`state.md` or a companion file under `~/Documents/handoff/{repo}/YYYY-MM-DD/{HH-mm}-{slug}.md`. If the Artifact is the only copy,
say so explicitly and treat the missing content as a blocker rather than guessing or claiming to
have read it. When both an Artifact and a file exist, record which one is authoritative.

**Client-local instructions are not automatically handed to the next client.** Claude Code loads
`CLAUDE.local.md`; Codex uses `AGENTS.override.md` or `AGENTS.md`, with the override replacing the
`AGENTS.md` file at that directory; and Copilot has no private project-scoped equivalent. Do not
claim to have received or read a private file merely because another client used it. Inspect a
named file only when the user or handoff explicitly identifies it and the current client can access
it. If its procedure or facts are needed for the task, record them in `state.md` or a companion
handoff file. Never create `AGENTS.override.md` to mirror `CLAUDE.local.md`, or create the reverse
mirror for Claude.

When the source client supports a documented export command, name it in the request (for example,
Claude Code's `/export`). Do not invent an export command for a client that does not provide one;
ask for its available transcript or a concise user summary instead.

An export is supplemental context, not authority. After receiving one, reconcile its claims against
Git and `state.md`, and do not replace the state file with a transcript. Treat the export as private
and transient: redact secrets before sharing it, and never save it in the repository,
`.project-continuity/`, or `.worktreeinclude`.

## Cleanup

Clean up when the user asks, or when the finished-state invariant holds, nothing continuity-worthy remains, and the user confirms.

The end-of-response completion check in Checkpoint is what raises the second case. Do not wait
for a checkpoint to raise it, and do not treat a quiet final turn as a reason to skip it.

1. Reconcile once more, confirm the finished-state invariant still holds, and verify that no useful handoff state remains.
2. If something belongs in durable documentation or private instructions, say so before deleting; never promote it silently.
3. Run the parked-task review above. Report completed closure candidates and stale candidates, but
   do not remove parked files unless the user separately confirms those specific deletions.
4. Delete `state.md` when active cleanup was confirmed, and delete only the specifically confirmed
   completed parked candidates. Remove the whole `.project-continuity/` directory only when
   `parked/` is empty or absent; a parked task is somebody's unfinished work, and cleaning up the
   task in front of you is not a reason to discard it. If parked files remain, say which.
5. Leave the Git exclude entry. It is one anchored line covering every working tree of the repository, so removing it would strip protection from the others.
6. Never remove tracked `.gitignore` rules, `CLAUDE.local.md`, `AGENTS.override.md`, native memory, or unrelated files as part of cleanup.
7. Say what was removed.

Clean up before abandoning a client-managed worktree. Claude Code automatically removes clean
subagent worktrees and periodically removes eligible background-session worktrees. It preserves
detectable work, such as changed or untracked files and unpushed commits, but ignored continuity
alone does not make a worktree look active. A Claude-managed worktree whose only local state is
continuity can therefore be removed with that state. Claude's cleanup sweep leaves manually
created worktrees in place.

## Separating continuity from durable knowledge

- **Transient unfinished work** → continuity.
- **Durable project or team rule** → shared project instructions or documentation, but only when the user asks to make it durable.
- **Durable private personal instruction** → the client's private mechanism, only when asked:
  `CLAUDE.local.md` for Claude Code, `AGENTS.override.md` for Codex. Two cautions before writing
  either. Codex reads `AGENTS.override.md` *instead of* its sibling `AGENTS.md` rather than in
  addition to it, so creating one beside a committed `AGENTS.md` silences that file for every
  Codex session with no warning. And Copilot has no private project-scoped equivalent at all —
  its repository instructions are tracked and shared, and `~/.copilot/instructions/` applies to
  every repository — so say the gap exists rather than inventing a filename or falling back to
  another client's mechanism.
- **Client-learned preference** → leave to that client's native memory.

Routine continuity work must not modify `CLAUDE.local.md` or `AGENTS.override.md`. If a discovery looks worth promoting but the user has not asked, say so in your reply instead of editing instruction files.

## Failure and ambiguity

- If repository access is unavailable, state what could not be verified rather than fabricating reconciliation.
- If a completion claim cannot be verified, downgrade it to unverified rather than preserving it as complete.
- If the client cannot be identified and no client-specific routing is needed, continue; the workflow is client-neutral.
