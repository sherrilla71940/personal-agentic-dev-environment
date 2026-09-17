# Implementation and manual-test lifecycle

## Understand before editing

Use the materials and the existing implementation to summarize the required change and give a
short plan naming likely files. Resolve genuine contradictions, missing assets, or correctness
risks before implementing the affected part. Otherwise proceed without a separate plan approval.

Enable `project-continuity` in the task worktree. Record each material — a path because it may
live outside the worktree, a URL because a later session has to fetch it again — since the
manual-test gate can span sessions. Enable it whatever the change's size: a
general exemption for small self-contained edits does not reach this workflow, because what has
to survive is the gate and the worktree path rather than the diff.

## Implement and verify

Install dependencies according to the lockfile when the fresh worktree needs them. Keep the
implementation within the resolved task.

Work from the worktree using repository-relative paths. Re-anchoring each command with `cd` and
the absolute worktree path defeats the isolation check, because such a command succeeds
identically whether or not the session actually moved, so a failed switch stays invisible for the
rest of the task. A relative path fails loudly instead, and it keeps the transcript evidence that
the work happened in the worktree.

Never let a command's working directory resolve outside the worktree, read-only commands
included. Absolute re-anchoring is what makes that reachable: once every call carries its own
`cd`, one wrong anchor relocates the shell for good, and a search or a listing is as capable of
doing that as an edit. Reaching outside for something genuinely outside — a reference document,
another worktree — is what the file-reading and search tools are for, since they take an absolute
path without moving the shell.

Confirm the ignored local configuration this app needs to run is actually present in the
worktree, because a fresh checkout carries no ignored file. Provisioning can report a skip such
as `[skipped] .worktreeinclude: manifest not found in source worktree`, which means nothing was
copied. Do not treat a skip as harmless: say which files were expected, and whether the missing
ones are needed to run the manual test. Resolve a real gap with `git wt-copy` from a worktree
that has them, or name exactly what the user must place and where. A skip that genuinely does
not matter, because the settings the app reads are tracked, is worth one sentence saying so.

Settle which of those it is rather than passing the warning along, and run `git status --ignored`
in the source worktree or main checkout to do it — that tree has been used and so holds the ignored
files, while the same command in the freshly created worktree lists nothing by construction and
reads as evidence it has not earned.

What that listing shows answers only one of two questions. Whether anything needs provisioning for
the app to build and run here is settled by building and running it, not by classifying filenames:
a dependency directory is regenerable in principle yet still required in practice, as a
`packages.config` .NET project's ignored `packages/` is when no restore path exists to rebuild it.
Resolve that with a dependency restore where one works, otherwise by copying the directory from the
source worktree. Whether anything belongs in the tracked `.worktreeinclude` is the separate
question — regenerable dependency and build output does not, local configuration that cannot be
regenerated does.

When a manifest is warranted, do not decide alone where it lands. `.worktreeinclude` is tracked at
the repository root, so folding it in carries an unrelated root-level file into this task's
request; but that is a disclosure problem rather than a prohibition, and the user may reasonably
prefer one review to two. Offer the choice at the moment it arises — fold it into this branch and
say so in the request description, author it on a separate branch off the base, or defer it to a
later task and only report the gap. Authoring itself belongs to the `worktree-manifest` skill
whichever they pick. The rule this replaces is silent scope creep, not an explicit instruction, so
the same offer fits any repository-infrastructure work this workflow turns up mid-task.

When the manual test needs a running app, start it and request one real route before writing
the steps. A fresh worktree can fail at startup for reasons the build output does not reveal:
a first build that restores dependencies but never runs their copy targets is the common one,
and it leaves a tree that compiles cleanly and serves nothing. Treat a redirect to the app's
own error page as failure rather than success, because a custom error page can return 200 and
can state a status code that contradicts the real one. Report the request made and what came
back. When the app cannot be started at all, say so and label the handed-over steps unverified
instead of implying the app ran.

When that request fails, rule out two causes that recur in compiled web projects before
debugging the change itself. A first build in a fresh worktree can restore dependencies without
running the targets that copy them into place, leaving a tree that compiles cleanly and serves
nothing; building a second time settles it. And a development server port is usually pinned per
project rather than per worktree, so another worktree of the same repository may already hold the
port and be serving a different build under the URL being tested. Establish which directory the
running server was started from before trusting what it returns.

When the invocation selects `runtime=auto`, use the consuming repository's tracked
`.worktree-runtime.json` descriptor and the rendered user-level helper:

```text
python "$HOME/.local/share/worktree-runtime.py" inspect
python "$HOME/.local/share/worktree-runtime.py" start [--port <explicit-port>]
```

The helper keeps the preferred port assignment outside the worktree, keyed to the physical
worktree, acquires an inter-process lease before starting the server, retries bounded collisions,
and verifies both the health URL and the listening process. Keep it running in a dedicated terminal
for the manual test. If the descriptor is absent, report that runtime isolation is unconfigured;
source and Git isolation remain valid, but concurrent runtime testing is not guaranteed. If the
descriptor cannot inject a port, report parallel runtime execution as unsupported rather than
silently testing another worktree's server. `runtime=off` uses the project's ordinary startup
procedure and must state that no per-worktree port guarantee was provided.

The descriptor may classify databases, caches, queues, Docker services, and external services as
`per-worktree`, `shared-safe`, or `unsupported`. V1 reports those classifications but does not
clone databases, create namespaces, manage containers, or copy runtime state.

`agent-test=true` requests proportionate checks that can catch defects in this change: typecheck,
lint, focused tests, a meaningful build, and a targeted browser or runtime pass for visual work
when available. `agent-test=false` skips optional verification, but still requires cheap minimum
checks that avoid knowingly handing back broken syntax or a seconds-long broken build.

In either mode:

- review the complete diff for unintended changes;
- list commands actually run and their outcomes;
- separate execution evidence from conclusions reached by reading;
- never call a UI flow, integration, or runtime behavior tested unless a tool drove it;
- state what could not be run and why.

Agent verification never replaces the user's manual test.

## Stop at the manual-test gate

Give exact manual steps when user-facing behavior remains. Open with the absolute path of the
task worktree and say plainly that the user's editor, terminal and running dev server are
probably still in the main checkout on the previous branch, so the change is invisible until
they open that directory. Repeat the path here even though isolation already reported it; this
gate can span sessions. Then give the startup command, route or screen, preconditions and test
data, ordered actions, and expected results. Then stop and wait.

Do not commit, push, or open a pull or merge request until the user explicitly reports that the
manual test passed. Plan approval, approval of a diff, or green automated checks do not open this
gate. If the user discusses something else meanwhile, leave it closed.

When the manual test fails, investigate the actual cause, make the scoped correction, rerun the
relevant verification, checkpoint the useful finding, and return to the gate with updated steps.

## Publish only after the gate opens

Load and follow `git-commit-action` with the resolved `mode`, `group`, and `lang`. In `draft` mode,
stop after the commit plan because there are no commits to push. Otherwise follow
[publish.md](publish.md) and report the branch, every commit SHA and subject, the target base, and
the request URL.

Never merge, enable auto-merge, approve the request, force-push, or delete either the local or
remote task branch. The branch must outlive the worktree for review and CI.
