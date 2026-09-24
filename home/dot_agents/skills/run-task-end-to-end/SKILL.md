---
name: run-task-end-to-end
description: "Start or continue one implementation task through guided no-argument intake, a natural-language task prompt, or explicit checkout/worktree arguments, carrying it through policy-driven verification and optional publishing."
disable-model-invocation: true
---

# Task workflow

If the current host is GitHub Copilot, stop: this adapter depends on Codex worktree behavior and
must not be translated into Copilot operations.

Start or continue one task through the resolved workspace and policy:

```text
validate -> read materials -> resolve workspace/policy -> prepare workspace -> task branch
         -> plan -> implement -> review -> verify/fix/retest
         -> publish authorization -> refresh base -> commit/push/request -> handoff/cleanup
```

This skill orchestrates existing global and project instructions. Use the dedicated document
skills for supplied containers, `task-continuity` for resumable state, `git-commit-action` for
commits, `git-commit-reference` for message conventions, and `natural-zhtw` for Traditional
Chinese publishing text.

This is an explicit opt-in workflow for tasks whose branch, verification, continuity, or publishing
state benefits from a recorded lifecycle. Use `workspace=checkout` for a sequential task that can
use the current physical checkout and `workspace=worktree` for parallel work, separate runtime
processes, or independent uncommitted changes. A no-argument invocation enters guided intake and
asks for the workspace; a natural-language prompt may clearly resolve it; explicit arguments remain
authoritative. Otherwise ask before switching or creating a branch or worktree. Report the workspace
resolution source (`argument`, `prompt`, or `user-confirmation`) in the resolved echo. The workflow
never chooses from task size, current checkout state, or the word `small` alone.

The default verification policy is `verification=agent`: perform the maximum feasible automated,
runtime, browser, and interactive verification, then ask the user only for genuinely user-only
checks. `verification=balanced` adds mandatory user acceptance, while `verification=user` leaves
browser/manual verification to the user. Verification never grants publish authorization.
## 1. Resolve the invocation

Read [references/invocation.md](references/invocation.md) and follow it through the resolved echo.
This skill has three first-class invocation styles:

```text
$run-task-end-to-end
$run-task-end-to-end Use a worktree from feat/water-fee and implement the frontend changes from the attached specification.
$run-task-end-to-end workspace=worktree base=feat/water-fee task="Implement the water-fee frontend changes from the attached specification"
```

The first form is true guided mode. Expose the task, workspace, base, verification, continuity, and
any context-specific required input, including choices whose defaults are `agent` and `auto`.
The second form is natural-language intake: parse only clear values and ask for the rest. The third
form is explicit structured intake: supplied values are authoritative and bypass redundant questions.
Partial structured input keeps the same explicit style and asks only for unresolved required values.

## Codex question presentation

The shared invocation reference owns the question semantics and provenance. When this Codex surface
exposes `request_user_input`, use it for unresolved closed-set guided choices, keeping the interaction
small and preserving the allowed values and default labels from the shared contract. Use explicit
confirmation provenance for answers returned by that interaction.

If `request_user_input` is unavailable in the current Codex mode, fall back to concise numbered or
plain-text questions with the same semantics. Do not fail the workflow, silently choose a workspace
or base, or force a verification/continuity question outside true no-argument guided mode merely
because structured input is unavailable.

Invoke this skill as either:

```text
$run-task-end-to-end
$run-task-end-to-end <base-branch> "<task>" [materials...] [options...]
$run-task-end-to-end <base-branch> --infer-task <materials...> [options...]
$run-task-end-to-end "<prompt>"
$run-task-end-to-end workspace=checkout base=<base-branch> task="<task>"
$run-task-end-to-end workspace=worktree base=<base-branch> flow=<flow-number> task="<task>"
```

The positional compatibility forms may omit `workspace`, but that omission does not select a
workspace. Resolve `checkout` or `worktree` from clear prompt intent or user confirmation before
any branch switch, branch creation, or worktree creation.

For an application task that starts a server for browser or runtime testing in an isolated
worktree, `runtime=auto` is required. Use the consuming project's tracked
`.worktree-runtime.json` descriptor; an explicit `port=<number>` may override its preferred
allocation. If `runtime=auto` is not selected, report that no per-worktree port guarantee exists
before starting the server, and do not claim that browser/runtime results came from this worktree.
Leave runtime at its default `off` for tasks that do not need an application server; this workflow
is not a mandatory runtime harness.

After invocation resolution, a new `checkout` or `worktree` task requires a resolved `base` unless
repository instructions provide a stricter local override. Both modes establish the task branch from
that base before implementation. Prompt-only intake may resolve a base from an explicit branch, a
verified MR/PR target, or provider/host metadata; it must stop when that target is ambiguous.
Task identity requires exactly one explicit task, material inference, or natural-language prompt.
Prompt wording that asks for an assessment or recommendation resolves to `phase=plan`; an explicit
request to proceed or implement resolves to `phase=execute`. Ambiguous wording stops for confirmation.
A plan phase does not create a worktree, branch, continuity state, or project change.
Run the shared read-only repository identity preflight before reading materials; do not create or
change task-worktree state until the preflight and resolved echo pass.

When the resolved phase is `plan`, follow the plan-phase boundary in the invocation reference and
stop after reporting the recommendation and the exact execution invocation. Do not continue into
worktree provisioning or implementation in the same turn.

## 2. Prepare the working-tree entry point

If the resolved workspace is `checkout`, remain in the current physical checkout. Verify its Git
root, branch, status, and continuity state before establishing the task branch from the recorded
base. Do not run ignored-file provisioning or claim a separate worktree runtime. A matching unfinished
task may resume with its continuity state; a different unfinished task requires an explicit finish,
park, or abandon decision.

Inspect the current root and worktree registry without changing them:

```bash
git rev-parse --show-toplevel
git rev-parse --git-common-dir
git worktree list --porcelain
git status --porcelain
```

For the `worktree` workspace, the current root may be the repository's primary checkout or a linked
worktree. It must be clean apart from ignored files provisioned for that worktree. A new task must
never edit, branch, or stage changes in the primary checkout; if the current root is primary,
continue through the resolved echo and remote-base validation, then use section 4 to enter or
provision a worktree.

There are two Codex entry paths:

- In the Codex desktop app, a Local chat should use the chat header's Handoff control to move to
  Worktree after the resolved echo. Select the requested `<base-branch>`. Codex creates the
  local managed detached worktree, copies the repository's `.worktreeinclude` entries, and keeps the
  chat associated with that worktree. Codex also automatically copies an ignored `AGENTS.override.md`
  on this native path even when it is not listed in `.worktreeinclude`; that is client-owned behavior,
  not generic manifest approval. If `open-code=true` was requested, use Codex's native Open control
  after Handoff; do not create a second terminal worktree for this path.
- In the Codex CLI or IDE extension, the adapter can provision the worktree, but a shell command
  cannot move the current chat's workspace. It therefore creates a detached worktree, reports
  its exact path, and stops. Start Codex in that path and invoke the same resolved workflow again,
  passing the resolved `branch=` value so branch naming cannot drift. If `open-code=true` was
  requested, open that path in a new VS Code window as a convenience; this does not move the
  existing Codex chat.

  If this is an interactive terminal-fallback run and `open-code` was omitted, ask once before
  creation whether to open the exact worktree path in a new VS Code window; recommend yes when the
  user is working from an editor. Do not ask for Codex desktop's native Open control or for
  non-interactive automation. External creation is intentionally different from native creation:
  the current chat or transcript may remain associated with the launch directory, and session
  picker/history behavior may not follow the new path. Report the exact path, branch, base commit,
  and entry action, and stop if the client cannot enter the created path rather than continuing in
  the wrong checkout.

Stop if repository instructions forbid worktrees or branch switching. Follow the repository's
project-specific checkout/worktree rule, report it in the resolved echo, and do not silently apply
the generic workspace contract. This developer environment repository is identifiable by its root
`.chezmoiroot` and keeps work in its primary checkout.

## 3. Establish names and the remote base branch

Unless supplied, derive:

- `type` from the `git-commit-reference` type table;
- an ASCII two-to-four-word kebab-case `slug` from the task's meaning;
- `branch` as `{type}/{slug}/{suffix}`.

Resolve the effective branch policy before deriving the branch. Effective `company` context uses
`branch_policy=company-flow` and requires `flow=<digits>` for any execution task that creates a
branch. Validate `flow` as `^[0-9]{1,9}$` and derive `flow/<flow>-<ascii-description>` from the task;
if `branch=` is supplied, validate it as
`^flow/[0-9]{1,9}(?:-[A-Za-z0-9_-]+)?$` and require the number to match `flow=`. Effective
`personal` context keeps the existing repository-standard naming. An applicable repository
instruction may explicitly declare `branch_policy=project-exception`, an allowed pattern, and its
source; that exception requires an explicit `branch=` and is never inferred from a `feat/...` name.
The resolved echo must show `branch_policy`, `flow`, and the complete task branch. Record the same
policy and flow ID in continuity when effective continuity is enabled.

Then establish the remote identity and fetch the user-provided base branch:

```bash
git remote get-url origin
git remote get-url --push origin
git fetch origin --prune
git rev-parse --verify --quiet "refs/remotes/origin/<base>^{commit}"
git rev-parse --verify --quiet "refs/heads/<branch>"
```

Record the redacted fetch URL, push URL, base branch, and full commit ID resolved from
`origin/<base>`. Show that remote-base checkpoint after the resolved invocation echo. Show near
remote matches and stop when `origin/<base>` is absent. The task branch must not exist for a new
task; a resume may find its existing task branch and must validate it in section 5. Do not switch
branches until the current checkout has passed through section 4; this allows a primary checkout
to reach its safe Handoff or provisioning path without branching there.

Immediately before provisioning, re-read both origin URLs and the base commit. If either remote
identity changed, or `origin/<base>` now resolves to a different commit, stop and re-resolve the
plan. Use the recorded base commit as the worktree start point so a moving remote-tracking ref
cannot silently change the task's starting point. Never show or record embedded credentials.

## 4. Prepare the resolved workspace

If the resolved workspace is `checkout`, remain in the current physical checkout, verify that the
working tree is safe for a new task, and continue to section 5. Do not provision ignored files or
run worktree-native entry controls. A repository-specific policy may require staying on the current
branch; if so, report that override and do not switch branches.

If the current root is already a linked worktree, continue to section 5.

If the current root is the primary checkout, use the entry path that matches the current Codex
surface:

- For a Codex desktop Local chat, use Handoff to Worktree and select `<base-branch>`. After Codex moves
  the chat, use its Open control if `open-code=true`, then resume this workflow in the associated
  worktree. Do not use a shell `cd` as a substitute; it does not move the chat's workspace.
- For Codex CLI or the IDE extension, create a detached worktree from the recorded remote base:

  ```bash
  # Add --open-code only when open-code=true was requested.
  git wt-add --open-code -- --detach "<repo-parent>/<repo-name>.worktrees/<slug>" "<recorded-base-commit>"
  ```

  Without the option, run the same command without `--open-code`.

  Include `--open-code` only when the resolved invocation contains `open-code=true`. The wrapper
  opens a separate VS Code window after creation; it never changes the current Codex chat's
  workspace. If the wrapper cannot find VS Code, keep the worktree, report the exact path, and ask
  the user to open it manually.

  The path is a sibling of the repository, so it does not add an ignored nested directory to the
  primary checkout. `git wt-add` runs a read-only provisioning check before Git creates anything.
  If the report finds eligible ignored files outside the tracked manifest, review it and either
  add `--allow-unprovisioned` to the wrapper command or stop to author the manifest through the
  `worktree-manifest` skill. The override creates the worktree but does not copy the unlisted
  files. If the alias is unavailable, run `git wt-check --source "<repo-root>"` first, then use
  `git worktree add --detach` with the same path and start point. After creation, run
  `git wt-check --source "<repo-root>" --target "<exact-worktree-path>"` and state that raw Git
  did not provision files. If `open-code=true` was requested on this fallback, run
  `code --new-window "<exact-worktree-path>"` when the `code` command is available; otherwise
  report that the user must open the path manually.

  When the source worktree may have a local configuration override, also run
  `git wt-readiness --source "<repo-root>" --target "<exact-worktree-path>"`. The report includes
  explicit `configSource` and `appSettings file` references and classifies expected, present,
  missing, and unmapped paths without printing values. Tracked `CLAUDE.md` and `AGENTS.md` are
  reported as already supplied by Git. Private agent overrides and client-local settings are
  explicit-only and are not suggested as ordinary candidates. A `[tracked-config]` warning is
  advisory and must not block creation; never add a tracked application configuration file to
  `.worktreeinclude` or copy it automatically. If a manifest pattern matches a tracked file,
  provisioning rejects that entry and reports that application-owned configuration requires
  project-specific manual setup or an explicit repository contract. If a project provides setup,
  use its explicit `.worktree-provision` contract or user-approved command rather than guessing
  from filenames. The contract is report-only: the generic helper never executes its script or
  prints its contents. An external secrets folder is never an implicit source. Readiness does not
  prove a fresh build, a running application server, an authenticated browser session, or valid
  application credentials.

  If a required local file is outside the ordinary manifest, use `git wt-provision --dry-run` with
  one exact source path, target worktree, destination, and operation. Present its sanitized report
  and approval ID to the user and ask for approval of that exact mapping. Only after an affirmative
  answer may you repeat it with `--approve <approval-id>`; the helper recomputes the source fingerprint
  and target HEAD and refuses changed mappings, target commits, existing targets, and tracked sources.
  The ID proves mapping integrity, not that a human approved it. Copy operations
  are limited to one explicitly named ignored or external non-tracked file. Section merges and
  whole-file Web.config or `.env` replacement remain report-only refusals. A successful copy is
  still `runtime-unverified` until the separate runtime descriptor health check passes.

  Stop after creation. Report the exact path, the provisioning result, and the continuation
  command with the resolved `branch=`. The user must start Codex in that directory, or attach the
  existing CLI/IDE session to it if the surface supports that operation. Never continue by
  issuing commands against the new path from the primary checkout.

After Handoff or terminal provisioning, verify that the current root is the intended linked
worktree, that the worktree is detached for a new task, and that its HEAD equals the recorded
base commit. If native Handoff selected a different starting commit, stop without
resetting it and use the explicit CLI/IDE provisioning path instead.

## 5. Establish the task branch

For a new task, establish the branch directly from the recorded remote commit. In a `worktree`
workspace the current root must be a linked worktree with detached HEAD. In a `checkout` workspace,
the current checkout must be clean and named, unless repository instructions provide a visible
override:

```bash
git symbolic-ref --quiet --short HEAD   # must fail for a new worktree task
git switch -c <branch> <recorded-base-commit>
```

If already on `<branch>`, treat it only as a resume: first use branch-aware parked-state discovery
when no active state exists, then reconcile `task-continuity` and verify that the selected state's
Task, objective, base commit, and starting point match. A unique exact-branch candidate with the
required metadata may be restored; branch-only, legacy, ambiguous, detached, or conflicting matches
require explicit selection or confirmation. Stop on any other checked-out branch or on an existing
task branch with no matching continuity; never silently reuse, reset, or relocate it. A checkout
task branch remains in the current physical checkout after publishing; only a worktree workspace
has a separate directory to clean up.

On resume, re-read the recorded redacted origin identities and base branch from continuity before
publishing. If the current origin identity differs, stop and re-resolve the workflow rather than
silently changing the request target. A task may continue from its recorded base commit even when
the named base branch has advanced; that later movement does not rewrite the task's starting point.

## 6. Verify the workspace

After branch creation or resume, verify:

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git status --porcelain
```

For a new task, HEAD must equal the recorded base commit and the branch must be the resolved task
branch, unless a repository-specific checkout override was reported. Keep every file operation and
command rooted in the resolved workspace. For a `worktree` workspace, do not reach back into the
primary checkout with absolute paths, `git -C`, `--git-dir`, or `GIT_DIR`.

Report the resolved workspace path, workspace mode, branch, origin identities, and base commit in
the response, not only in a tool call. For a worktree, the chat's workspace may not be where the
user's editor is working; for checkout, identify the current physical checkout explicitly.

For a `worktree` workspace, also report what ignored local configuration it actually has. Private
agent overrides
and client-local settings should be reported as explicit-only, not as ordinary eligible files.
Codex desktop local managed worktrees process `.worktreeinclude` and may additionally carry the
ignored `AGENTS.override.md` native exception described above; Codex remote, CLI, and IDE paths do
not get that native guarantee. The terminal fallback reports its read-only decision before creation, and
the post-creation `wt-check --target` report identifies copy candidates and conflicts. Do not
infer application necessity from a filename; use `--required` for a known required file and build
or start the app for the remaining application-specific check.

## 7. Implement through publishing

Read [references/lifecycle.md](references/lifecycle.md) and follow it through the selected
verification policy and publish-authorization boundary. Do not commit, push, or open a request until
the workflow has explicit publish authorization.

## 8. Leave worktree deletion to Codex

The skill never deletes its active Codex worktree. A `checkout` workspace remains in the current
directory and keeps its task branch; only the worktree workspace has client-owned directory cleanup.
The task branch and request always survive.

With `cleanup=keep`, retain any active continuity state and report the workspace path. With `cleanup=ask`, after
publishing ask whether the worktree should remain available for review. Recommend keeping it for
non-trivial review.

Only mark it ready for disposal when all are true:

- the selected verification policy passed, including any required user-only check;
- publish authorization was granted;
- `git status --porcelain` is empty;
- `git rev-parse HEAD` equals `git rev-parse origin/<branch>`;
- the request exists and its URL is recorded;
- this task left no stash.

When the user chooses disposal and all checks pass, explain that the user can archive the Codex-managed
chat or use Handoff according to the app's worktree controls. Do not run `git worktree remove`, delete
a branch, archive a chat, or claim the worktree was removed. Continuity cleanup is separate: before
every final response after continuity was enabled or touched, run the `task-continuity` completion
gate; publishing is only one exit path. Ask before deleting the active state or any completed parked
state; never treat a clean branch or removed worktree as permission to delete continuity state.

The completion gate is a required final-response step, not a reminder to handle later. Reconcile
the actual delivery state and review parked state candidates in the same response on every exit path,
including plan-only completion, manual-gate pauses, local commit without publish, publish deferral,
and successful publish. If a stale HEAD or branch warning appears, reconcile it and then repeat the
finished-state check instead of ending with the warning alone. If the user declines a named cleanup,
record `Cleanup: declined` in that file's Verification block and do not ask again for that task. The
final response must state whether cleanup was completed, declined and recorded, or remains pending
with the named state files. Keep worktree and branch retention separate from continuity cleanup.

## Resume

Resume in the same physical Codex worktree. In the app, return or hand the chat back to its
associated worktree. In CLI or the IDE extension, start Codex in that exact directory and invoke
the same resolved workflow with its recorded `branch=` value, then continue from
`task-continuity`.
