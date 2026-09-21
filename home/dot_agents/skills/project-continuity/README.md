# Project continuity — what it is

Notes for the human. Agents read [SKILL.md](SKILL.md); nothing loads this file.

One markdown file, `.project-continuity/state.md`, private to one working directory. Claude Code,
Codex and Copilot can each read it and carry on.

Think of it as a write-through cache of unrecoverable task context and reasoning. Git already knows which files
changed and the tests already know what passes, so the file holds only what neither can answer:
why an approach was rejected, what a backend did that nobody expected, which behavior you chose,
what is blocking, and what to do next. That is also why it has no `Completed` section — there is
no point caching what the authoritative store can already tell you.

The machine-local `ai_continuity` selector controls whether continuity is preferred, not this
skill's availability. Automatic startup/stop reporting and state handling require
`ai_continuity = "on"` together with `ai_harness = "managed"`; native harness mode suppresses
them without changing the stored continuity preference. An explicit request to start, resume,
checkpoint, hand off, or clean up continuity can still invoke the skill in every harness mode.

It is designed for one core move: a task crosses a session or client boundary, and the next client
resumes in the same directory without being re-briefed from scratch.

```bash
git worktree list        # find the directory again
cd <that directory>      # then start codex, claude, or code .
```

**The one rule:** same interrupted task, reopen the same directory. Opening a different directory
gives you a different working tree — without this one's uncommitted changes, untracked files, or
continuity. You do not need worktrees for any of this; the ordinary checkout is a working tree.
Worktrees only matter when you want two independent tasks side by side.

In managed mode, the receiving client detects the state on its first task turn, reconciles it
against Git, and resumes. In native mode, invoke continuity explicitly. Say "continue from project
continuity" only to force that, or if the global bootstrap did not load.

### When to export the session

At a client switch or handoff, the agent reports one of three labels:

- `Session export: not needed` — continuity and Git are enough.
- `Session export: recommended` — the task can continue, but the conversation contains useful
  details such as rejected approaches, UI behavior, screenshots, external research, or a long
  debugging trail. Paste the source client's export if you want to preserve those details.
- `Session export: required` — the receiving agent cannot safely determine the next action. Provide
  the source client's export or answer the focused clarification it requests.

For Claude Code, the source-client command is `/export`. Other clients may require an equivalent
transcript or a summary. Treat exports as private, redact secrets, and paste them only as
supplemental context; Git and `state.md` remain authoritative. Do not put exports in the repository
or `.project-continuity/`.

If you need to work on something else before finishing, the unfinished task is parked rather
than overwritten — it moves to `.project-continuity/parked/<slug>.md` and moves back when you
return. `ls .project-continuity/parked/` lists all parked tasks. A worktree is still the
answer when the two tasks also need separate uncommitted changes.
A parked task is not active: move it back to `state.md` and resume it before continuing work on
that task. Every continuity review checks parked files for the finished-state invariant. A
completed parked file is reported as a closure candidate, but deletion requires confirmation for
that named file.

Two cautions. Every client's own memory is separate, invisible to the others, and may hold stale
claims about the task — continuity reconciled against Git is what establishes where things stand.
And a client-managed worktree can be deleted with its session: Claude sweeps eligible worktrees
whose only local state is ignored files, and archiving a Codex chat can remove its worktree, so
hand off or clean up before archiving.
