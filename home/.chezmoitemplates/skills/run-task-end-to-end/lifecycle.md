# Implementation and verification lifecycle

## Understand before editing

Use the materials and the existing implementation to summarize the required change and give a
short plan naming likely files. Resolve genuine contradictions, missing assets, or correctness
risks before implementing the affected part. Otherwise proceed without a separate plan approval.

Apply the resolved workspace and continuity policy before implementation:

- For `worktree`, enter or resume the isolated task worktree and keep the existing provisioning and
  runtime gates. For `checkout`, stay in the current physical checkout and do not provision ignored
  files or claim worktree runtime isolation.
- Establish the task branch from the recorded base before implementation unless repository
  instructions provide a visible project-specific override.
- Apply the resolved branch policy before establishing that branch. Under effective `company` context,
  `branch_policy=company-flow` requires a `flow` value matching `^[0-9]{1,9}$` and uses the branch
  shape `flow/<flow>-<ascii-description>`. A project exception must be explicitly declared by
  repository instructions and must name the allowed pattern; a `feat/...` branch alone is never an
  exception. Record `branch_policy`, `flow`, and the resolved task branch in continuity when state
  is enabled.
- When effective `continuity` is `on`, initialize or resume `task-continuity` and record each
  material because a later session may need it again. Before initializing a different task, apply
  the continuity transition: resume the same task; stop for a different unfinished task until it is
  finished, parked, or abandoned; and for a different completed task, reconcile the completion
  invariant and move the old active state to `.task-continuity/parked/` with a non-colliding name.
  Do not pause for active-state deletion confirmation during this transition. Never park by
  overwriting an existing record. Initialize a fresh state for the new task when continuity is
  enabled; deletion of the parked completed record is a separate confirmation-gated cleanup. When
  effective `continuity` is `off`,
  do not initialize or update state for this task; cleanup, parking, and deletion remain separate
  decisions. When it is `auto`, use the active profile's `ai_continuity` value directly.

Continuity is scoped to the physical checkout for both workspace modes. One checkout has at most one
active task state. Parking preserves a sequential handoff; it does not make two simultaneous tasks
safe in the same directory.

## Implement and verify

Install dependencies according to the lockfile when the fresh worktree needs them. Keep the
implementation within the resolved task.

Work from the resolved workspace using repository-relative paths. For `worktree`, re-anchoring each
command with `cd` and the absolute worktree path defeats the isolation check, because such a command succeeds
identically whether or not the session actually moved, so a failed switch stays invisible for the
rest of the task. A relative path fails loudly instead, and it keeps the transcript evidence that
the work happened in the worktree.

Never let a command's working directory resolve outside the worktree, read-only commands
included. Absolute re-anchoring is what makes that reachable: once every call carries its own
`cd`, one wrong anchor relocates the shell for good, and a search or a listing is as capable of
doing that as an edit. Reaching outside for something genuinely outside — a reference document,
another worktree — is what the file-reading and search tools are for, since they take an absolute
path without moving the shell.

For every supported repository-provided non-native worktree creation path, run the read-only
provisioning check before creating anything:

```bash
git wt-check --source <source-worktree>
```

The check reports manifest status, manifest matches, eligible ignored files that are not listed,
private agent overrides and client-local settings as explicit-only, tracked `CLAUDE.md` and
`AGENTS.md` as files already supplied by Git, missing manifest patterns, existing target conflicts
when a target is supplied, explicitly named required local files, and explicit `configSource` or
`appSettings file` references from tracked configuration candidates. It writes nothing and never creates `.worktreeinclude`. A result of
`no-manifest-needed` or `manifest-present-no-matches` is different from
`eligible-ignored-files-unlisted`; the latter requires an explicit decision before creation.
Use `git wt-add --allow-unprovisioned` only after reviewing that report, or author a tracked
manifest through the `worktree-manifest` skill. The override permits creation but does not copy
the unlisted files.

When the application has a known required local file, pass it explicitly with
`--required <repo-relative-path>`. Otherwise, report the requirement as unknown and settle it by
building or starting the app. The configuration reference report classifies expected, present,
missing, and unmapped paths without printing values. After a raw `git worktree add`, run the check
again with `--target <worktree>` and use `git wt-copy` only for approved ignored manifest entries.
If a manifest pattern matches a tracked file, the command rejects it; tracked application
configuration requires project-specific manual setup or an explicit repository contract. A tracked
`.worktree-provision` contract may name a repository-relative setup script and documentation for
manual review; the generic helper reports it but never executes it or prints its contents. Native
Claude, Codex, and VS Code provisioning remains a separate path; do not route it through the
terminal fallback or claim that its native copy result exists without checking the client result.

This workflow deliberately creates the task worktree through the repository wrapper before entering
it. The wrapper is required because the task is pinned to a named `origin/<base>` commit and the
native client creation paths do not all accept an arbitrary base ref. After creation, enter the
reported absolute path with the client appropriate to the current surface. External creation has a
client-visible consequence: the conversation or transcript may remain associated with the launch
directory rather than following the new worktree, and native worktree history or picker behavior
may differ. Report the worktree path, branch, base commit, and client entry action explicitly; do
not imply that external creation has the same session discoverability as a client-created
worktree. If the client cannot enter the created path, stop and hand the exact path to the user
rather than continuing in the wrong checkout.

Settle which of those it is rather than passing the warning along. Inspect the source worktree or
main checkout before entering Claude's isolated worktree whenever possible: that tree has been
used and so holds the ignored files, while the same command in the freshly created worktree lists
nothing by construction and reads as evidence it has not earned. After Claude enters isolation,
run Git commands only from the current worktree; Claude rejects even a read-only `git -C` redirect
to the main checkout. If the inventory was missed, call `ExitWorktree` with `action: "keep"`,
inspect the main checkout there, then re-enter the preserved task worktree and continue this
provisioning gate.

Keep Bash and Monitor calls inside isolation plain and separate. Claude may reject a compound
command such as `A && B`, a dynamically shaped pipeline, or a heredoc when it cannot verify that
every Git operation stays inside the worktree. Use one plain command per call or the Write tool;
do not bypass the guard with a redirect to the main checkout.

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

After creation, run `git wt-readiness --source <source-worktree> --target <worktree>` when the
source worktree may contain local configuration overrides. Treat `[tracked-config]`, `[rejected]`
tracked manifest entries, `[missing]`, and `[unmapped]` results as advisory: never add a tracked
file to `.worktreeinclude` or copy it automatically, and do not block `git wt-add` because a
tracked change may be intentional. If the project owns a setup command, invoke it only through an
explicit repository contract or user-approved step; do not infer or execute one from a filename.
Provisioning readiness does not prove a fresh build, a running application server, an authenticated
browser session, or valid application credentials.

An external secrets folder or another directory outside the repository is never an implicit source.
Only the selected worktree of the same Git repository may supply files to `git wt-copy`.

If a project needs a file outside the ordinary manifest, use `git wt-provision --dry-run` with one
exact source path, target worktree, destination, and operation. Show the sanitized report and its
approval ID to the user, then ask for approval of that exact mapping. Only after an affirmative
answer may the command be repeated with `--approve <approval-id>`; the helper recomputes the source
fingerprint and target HEAD and refuses changed paths, contents, destinations, operations, target
commits, existing targets, and
tracked sources. The approval ID verifies mapping integrity, but cannot prove that a human approved
the report; the client must obtain that affirmative approval separately. `copy-ignored-file` and
`copy-external-file` are copy-only operations. Section
merges and whole-file Web.config or `.env` replacement are report-only refusals. A dry run or
successful copy still leaves the runtime state `runtime-unverified` until the separate descriptor
health check passes.

When browser or runtime verification needs a running app, start it and request one real route before writing
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

For browser or runtime testing from an isolated worktree, `runtime=auto` is required. When the
invocation selects `runtime=auto`, use the consuming repository's tracked
`.worktree-runtime.json` descriptor and the rendered user-level helper:

```text
python "$HOME/.local/share/worktree-runtime.py" inspect
python "$HOME/.local/share/worktree-runtime.py" start [--port <explicit-port>]
```

The helper keeps the preferred port assignment outside the worktree, keyed to the physical
worktree, acquires an inter-process lease before starting the server, retries bounded collisions,
and verifies both the health URL and the listening process. Keep it running in a dedicated terminal
for the selected verification run. If `runtime=auto` was not selected, report that no per-worktree port guarantee
was provided before starting the server. If the descriptor is absent, report that runtime isolation
is unconfigured;
source and Git isolation remain valid, but concurrent runtime testing is not guaranteed. If the
descriptor cannot inject a port, report parallel runtime execution as unsupported rather than
silently testing another worktree's server. `runtime=off` uses the project's ordinary startup
procedure only for tasks that do not require isolated browser/runtime testing, and must state that
no per-worktree port guarantee was provided.

The descriptor may classify databases, caches, queues, Docker services, and external services as
`per-worktree`, `shared-safe`, or `unsupported`. V1 reports those classifications but does not
clone databases, create namespaces, manage containers, or copy runtime state.

## Verification policy

Every mode runs the cheap baseline checks needed to avoid knowingly handing back broken syntax or a
seconds-long broken build. The selected policy then determines the interactive verification boundary:

- `verification=agent` is the default. Run maximum feasible agent-verifiable coverage first:
  typecheck, lint, focused tests, a meaningful build, runtime checks, and browser flows when
  available. Keep iterating through review, test, fix, and retest until the agent-verifiable
  acceptance criteria pass. Ask the user only for genuinely user-only checks that remain, and never
  claim an untested behavior passed.
- `verification=balanced` performs the same maximum feasible agent-verifiable coverage, then requires
  explicit user acceptance before the verification gate is complete.
- `verification=user` runs non-interactive automated checks only. Do not drive browser or manual
  flows; provide exact steps and wait for the user's result.

The deprecated `agent-test=true|false` alias maps to `verification=agent|user` only when the new
option is absent. Do not expose both policies in a resolved invocation.

In every mode:

- review the complete diff for unintended changes;
- list commands actually run and their outcomes;
- separate execution evidence from conclusions reached by reading;
- never call a UI flow, integration, or runtime behavior tested unless a tool drove it;
- state what could not be run and why;
- keep verification separate from publish authorization.

Passing verification never authorizes a push or pull/merge request. When the selected policy leaves
a user-only check unresolved, stop at that check; otherwise stop at the separate publish-authorization
boundary unless publication was explicitly authorized by the workflow request.

## Stop at the applicable verification gate

For `balanced` or `user`, give exact manual steps. For `worktree`, open with the absolute task-
worktree path and say plainly that the user's editor, terminal, and running dev server may still be
in another checkout. For `checkout`, identify the current Git root and task branch instead. Include
the startup command, route or screen, preconditions and test data, ordered actions, and expected
results, then stop and wait. For `agent`, request user input only for a named user-only blocker.

Do not commit, push, or open a pull or merge request until the workflow has publish authorization.
Balanced/user acceptance, plan approval, approval of a diff, or green automated checks do not by
themselves authorize publication. If the user discusses something else meanwhile, leave the
applicable gate closed.

When a verification or user test fails, investigate the actual cause, make the scoped correction,
rerun the relevant verification, checkpoint the useful finding, and return to the applicable gate
with updated steps.

## Publish only after the gate opens

Load and follow `git-commit-action` with the resolved `mode`, `group`, and `lang`. In `draft` mode,
stop after the commit plan because there are no commits to push. Otherwise follow
[publish.md](publish.md) and report the branch, every commit SHA and subject, the target base, and
the request URL.

For both `checkout` and `worktree`, the publish stage first checks whether the recorded base commit
is still current. If the base advanced, it pauses for an explicit merge-or-rebase choice. A
repository-specific checkout override may have no recorded starting commit; in that case follow the
override and require an explicit request target. After integration changes either workspace, rerun
the selected verification policy before publishing.

Never merge the pull or merge request, enable auto-merge, approve the request, force-push without
the explicit integration approval, switch a checkout workspace to another branch outside the
resolved task-branch transition, or delete a local or remote branch. A worktree task branch must
outlive its worktree for review and CI.

## Finalize continuity on every workflow exit

Run the `task-continuity` completion gate before every final response after continuity was
enabled or touched. A successful publish is only one terminal path. Reconcile the active state with
the actual checkout, delivery decision, request state, and verification, then classify the exit:

| Workflow exit | State action | Final response |
| --- | --- | --- |
| Plan-only prompt | Do not create or modify continuity state. | Say continuity was not needed for planning. |
| Manual gate waiting or failed verification | Keep the active state with the blocker or first concrete next action. | Say continuity is retained and name what happens next. |
| Implementation complete with an uncommitted diff | Record `Delivery: commit pending` and keep review/commit as the next action. | Do not offer continuity cleanup before the durable Git checkpoint. |
| Local commit without publish | Record `Delivery: local-only complete` or `Delivery: publish pending`. | State whether publication remains requested and whether continuity cleanup is offered. |
| Publish declined or deferred | Record the delivery decision and a next action only if work remains. | Keep branch/worktree retention separate from continuity cleanup. |
| Publish, merge, or rebase complete | Reconcile HEAD, branch, status, request state, and checks, then apply the completion gate. | Report active cleanup and parked candidates separately. |

`Next actions` is reserved for unfinished task work. Do not put “offer cleanup” or “ask before
deleting state” there; a completed state must leave the unfinished sections empty so the completion
gate can report it deterministically.

Worktree cleanup and continuity cleanup are separate decisions. If the active continuity state is
finished, ask the user whether to delete `.task-continuity/state.md`. Ask separately before
deleting each completed parked candidate. Never delete continuity state automatically; if the user
declines, record `Cleanup: declined` in that file's Verification block and do not ask again for that
task.
