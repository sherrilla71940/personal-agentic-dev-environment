---
name: worktree-task-workflow
description: "Start or continue one isolated implementation task through its lifecycle in a Codex worktree, creating the task branch from a user-provided base branch and carrying it through manual testing, publishing, and branch-preserving handoff."
disable-model-invocation: true
---

# Worktree task workflow

If the current host is GitHub Copilot, stop: this adapter depends on Codex worktree behavior and
must not be translated into Copilot operations.

Start or continue one task with a Codex-managed or provisioned worktree:

```text
validate -> read materials -> confirm isolation -> prepare/enter worktree -> branch
         -> plan -> implement -> verify
         -> USER MANUAL TEST -> commit -> push -> request -> app-owned worktree lifecycle
```

This skill orchestrates existing global and project instructions. Use the dedicated document
skills for supplied containers, `project-continuity` for resumable state, `git-commit-action` for
commits, `git-commit-reference` for message conventions, and `natural-zhtw` for Traditional
Chinese publishing text.

This is an explicit opt-in workflow for substantial or isolation-sensitive tasks. Do not invoke it
merely because an agent is making a change: a small, self-contained edit that does not need parallel
isolation may stay in the current valid worktree. Use this workflow when isolation, cross-session
handoff, controlled verification, or publishing matters.

## 1. Resolve the invocation

Read [references/invocation.md](references/invocation.md) and follow it through the resolved echo.
Invoke this skill as either:

```text
$worktree-task-workflow <base-branch> "<task>" [materials...] [options...]
$worktree-task-workflow <base-branch> --infer-task <materials...> [options...]
```

For an application task that needs concurrent runtime testing, add `runtime=auto` and use the
project's tracked `.worktree-runtime.json` descriptor. An explicit `port=<number>` may override
the descriptor's preferred allocation. Leave runtime at its default `off` for tasks that do not
need an application server; this workflow is not a mandatory runtime harness.

`base` is required and means the user-provided existing branch on `origin`. The workflow creates
the task branch from `origin/<base>` in a new worktree, and the eventual pull or merge request
targets that same base branch. Task identity requires exactly one non-empty explicit task or
requested inference from readable materials. `task=""` is invalid; omit `task` when using
inference. Run the shared read-only repository identity preflight before reading materials; do not
create or change Git state until the preflight and resolved echo pass.

## 2. Prepare the working-tree entry point

Inspect the current root and worktree registry without changing them:

```bash
git rev-parse --show-toplevel
git rev-parse --git-common-dir
git worktree list --porcelain
git status --porcelain
```

The current root may be the repository's primary checkout or a linked worktree. It must be clean
apart from ignored files provisioned for this worktree. A new task must never edit, branch, or
stage changes in the primary checkout; if the current root is primary, continue through the
resolved echo and remote-base validation, then use section 4 to enter or provision a worktree.

There are two Codex entry paths:

- In the Codex desktop app, a Local chat should use the chat header's Handoff control to move to
  Worktree after the resolved echo. Select the requested `<base-branch>`. Codex creates the
  local managed detached worktree, copies the repository's `.worktreeinclude` entries, and keeps the
  chat associated with that worktree. If `open-code=true` was requested, use Codex's native Open
  control after Handoff; do not create a second terminal worktree for this path.
- In the Codex CLI or IDE extension, the adapter can provision the worktree, but a shell command
  cannot move the current chat's workspace. It therefore creates a detached worktree, reports
  its exact path, and stops. Start Codex in that path and invoke the same resolved workflow again,
  passing the resolved `branch=` value so branch naming cannot drift. If `open-code=true` was
  requested, open that path in a new VS Code window as a convenience; this does not move the
  existing Codex chat.

Stop if repository instructions forbid worktrees. This developer environment repository does, identifiable by
its root `.chezmoiroot`; offer to run that task in place instead.

## 3. Establish names and the remote base branch

Unless supplied, derive:

- `type` from the `git-commit-reference` type table;
- an ASCII two-to-four-word kebab-case `slug` from the task's meaning;
- `branch` as `{type}/{slug}/{suffix}`.

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

## 4. Enter or provision the worktree

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
  primary checkout. `git wt-add` also provisions the tracked `.worktreeinclude` allowlist. If the
  alias is unavailable, use `git worktree add --detach` with the same path and start point, and
  state that ignored files were not provisioned. If `open-code=true` was requested on this fallback,
  run `code --new-window "<exact-worktree-path>"` when the `code` command is available; otherwise
  report that the user must open the path manually.

  Stop after creation. Report the exact path, the provisioning result, and the continuation
  command with the resolved `branch=`. The user must start Codex in that directory, or attach the
  existing CLI/IDE session to it if the surface supports that operation. Never continue by
  issuing commands against the new path from the primary checkout.

After Handoff or terminal provisioning, verify that the current root is the intended linked
worktree, that the worktree is detached for a new task, and that its HEAD equals the recorded
base commit. If native Handoff selected a different starting commit, stop without
resetting it and use the explicit CLI/IDE provisioning path instead.

## 5. Establish the task branch

For a new task, the current root must now be a linked worktree with detached HEAD. Create the
branch directly from the recorded remote commit:

```bash
git symbolic-ref --quiet --short HEAD   # must fail for a new task
git switch -c <branch> <recorded-base-commit>
```

If already on `<branch>`, treat it only as a resume: reconcile `project-continuity` and verify that
its objective and starting point match. Stop on any other checked-out branch or on an existing
task branch with no matching continuity; never silently reuse, reset, or relocate it.

On resume, re-read the recorded redacted origin identities and base branch from continuity before
publishing. If the current origin identity differs, stop and re-resolve the workflow rather than
silently changing the request target. A task may continue from its recorded base commit even when
the named base branch has advanced; that later movement does not rewrite the task's starting point.

## 6. Verify isolation

After branch creation or resume, verify:

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git status --porcelain
```

For a new task, HEAD must equal the recorded base commit and the branch must be the resolved task
branch. Keep every file operation and command rooted in this worktree. Do not reach
back into the primary checkout with absolute paths, `git -C`, `--git-dir`, or `GIT_DIR`.

Report the worktree's absolute path, branch, origin identities, and base commit in the response,
not only in a tool call. The chat's workspace is not where the user is working, so an unreported
path leaves them looking at the primary checkout with no sign of the change.

Also report what ignored local configuration this worktree actually has. Codex desktop local
managed worktrees should process `.worktreeinclude`; Codex remote, CLI, and IDE paths do not get
that native guarantee, and a fallback worktree can also lack the manifest. A provisioning skip
such as `[skipped] .worktreeinclude: manifest not found in source worktree` is silent until the
app fails to run, so inspect the actual result rather than assuming the creator copied it.

## 7. Implement through publishing

Read [references/lifecycle.md](references/lifecycle.md) and follow it through the manual-test gate
and publishing. Do not commit, push, or open a request until the user explicitly reports that the
manual test passed.

## 8. Leave worktree deletion to Codex

The skill never deletes its active Codex workspace. The task branch and request always survive.

With `cleanup=keep`, retain continuity and report the worktree path. With `cleanup=ask`, after
publishing ask whether the worktree should remain available for review. Recommend keeping it for
non-trivial review.

Only mark it ready for disposal when all are true:

- the user reported the manual test passed;
- `git status --porcelain` is empty;
- `git rev-parse HEAD` equals `git rev-parse origin/<branch>`;
- the request exists and its URL is recorded;
- this task left no stash.

When the user chooses disposal and all checks pass, clean up continuity and explain that the user
can archive the Codex-managed chat or use Handoff according to the app's worktree controls. Do not
run `git worktree remove`, delete a branch, archive a chat, or claim the worktree was removed.

## Resume

Resume in the same physical Codex worktree. In the app, return or hand the chat back to its
associated worktree. In CLI or the IDE extension, start Codex in that exact directory and invoke
the same resolved workflow with its recorded `branch=` value, then continue from
`project-continuity`.
