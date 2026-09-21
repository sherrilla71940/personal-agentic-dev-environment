---
name: worktree-task-workflow
description: "Run one isolated implementation task through its lifecycle in a Claude Code worktree, from an explicit task or requested material inference through manual testing, publishing, and branch-preserving cleanup."
argument-hint: '<base> ("<task>" [materials...] | --infer-task <materials...>) [options...]'
disable-model-invocation: true
---

# Worktree task workflow

Run one task in its own Claude Code worktree:

```text
identity preflight -> validate -> read materials -> isolate -> plan -> implement -> verify
         -> USER MANUAL TEST -> commit -> push -> request -> worktree cleanup
```

This skill orchestrates existing global and project instructions. Use the dedicated document
skills for supplied containers, `project-continuity` for resumable state, `git-commit-action` for
commits, `git-commit-reference` for message conventions, and `natural-zhtw` for Traditional
Chinese publishing text.

## 1. Resolve the invocation

Read [references/invocation.md](references/invocation.md) and follow it through the resolved echo.
`base` is required. Task identity requires exactly one of:

- a non-empty explicit task; or
- `--infer-task` / `infer-task=true` with readable materials.

An empty `task=` is always invalid. When inference is requested, omit `task` rather than passing
an empty value. Run the shared read-only repository identity preflight before reading materials;
do not create or change Git state until the preflight and resolved echo pass.

## 2. Check repository and derive names

```bash
git rev-parse --show-toplevel
git remote get-url origin
```

Stop if repository instructions forbid worktrees. This developer environment repository does, identifiable by
its root `.chezmoiroot`; offer to run that task in place instead.

Unless supplied, derive:

- `type` from the `git-commit-reference` type table;
- an ASCII two-to-four-word kebab-case `slug` from the task's meaning;
- `branch` as `{type}/{slug}/{suffix}`;
- the worktree path as `<repo-root>/.claude/worktrees/<slug>`.

Runtime isolation is optional. When the task includes an application and the invocation selects
`runtime=auto`, use the tracked `.worktree-runtime.json` descriptor and the rendered
`~/.local/share/worktree-runtime.py` helper. Otherwise leave runtime startup to the project or
user and report that no per-worktree port guarantee was provided.

That path is deliberate, not a copy of a terminal habit. `EnterWorktree` moves the session
without an approval prompt only inside the repository's `.claude/worktrees/`, and no permission
rule suppresses the prompt elsewhere. A sibling `.worktrees/` directory would therefore add one
approval to every run. Do not relocate it to match a `git wt-add` invocation; that command has
no default path of its own. The developer environment repository's `docs/worktree-provisioning.md` carries the
full reasoning and the pre-v2.1.246 sweep caveat.

## 3. Establish the remote base

```bash
git remote get-url origin
git remote get-url --push origin
git fetch origin --prune
git rev-parse --verify --quiet "refs/remotes/origin/<base>^{commit}"
git rev-parse --verify --quiet "refs/heads/<branch>"
```

Record the redacted fetch URL, push URL, base branch, and full commit ID resolved from
`origin/<base>`, and show that remote-base checkpoint after the resolved invocation echo. Show near
remote matches and stop when `origin/<base>` does not exist. Stop and ask when the task branch
already exists; never silently reuse or reset it. A local branch named `<base>` is irrelevant and
must not be updated by this workflow.

Immediately before provisioning, re-read both origin URLs and the base commit. If either remote
identity changed, or `origin/<base>` now resolves to a different commit, stop and re-resolve the
plan. Use the recorded base commit as the worktree start point so a moving remote-tracking ref
cannot silently change the task's starting point. Never show or record embedded credentials.

## 4. Create and enter the worktree

Ensure `.claude/worktrees` is locally ignored through the repository's common `info/exclude`, then
create the branch and worktree with the managed wrapper:

```bash
# Add --open-code only when open-code=true was requested.
git wt-add --open-code -- -b <branch> "<repo-root>/.claude/worktrees/<slug>" "<recorded-base-commit>"
```

Without the option, run the same command without `--open-code`.

Include `--open-code` only when the resolved invocation contains `open-code=true`. The wrapper
opens the exact worktree in a separate VS Code window before the session enters it; it does not
switch the user's existing editor window. If VS Code is unavailable, keep the created worktree,
report the exact path, and let the user open it manually.

If `git wt-add` is unavailable, use `git worktree add -b <branch> <path> <recorded-base-commit>` and state
that `.worktreeinclude` files were not provisioned. Either way, report what provisioning actually
did. `git wt-add` can succeed while copying nothing, for example
`[skipped] .worktreeinclude: manifest not found in source worktree`, and that skip is silent
until the app fails to run. Claude Code's own `.worktreeinclude` handling does not apply here,
because the worktree is created by Git rather than by Claude Code.

Enter the created path with Claude Code's `EnterWorktree` tool using its `path` parameter.
`EnterWorktree` cannot itself select an arbitrary base, which is why Git creates the worktree
first. Never use `ExitWorktree` with `action: "remove"`; that would delete the task branch.

Read [references/lifecycle.md](references/lifecycle.md) now, before the first command inside the
worktree, rather than when step 6 refers to it again. Its working-directory rule governs every
command from here, and its provisioning check is what turns the skip reported above into a
verdict; reaching them at step 6 means reading them after the point where they applied.

## 5. Verify isolation

From inside the worktree, verify its root, branch, HEAD, and status. They must equal the created
path, task branch, recorded base commit, and a clean checkout apart from approved
provisioned files. Stop on any mismatch.

When resuming an existing task, re-read its recorded redacted origin identities and base branch
from continuity before publishing. If the current origin identity differs, stop and re-resolve the
workflow rather than silently changing the request target. A later movement of the named base
branch does not rewrite the task's recorded starting commit.

Respect Claude Code's worktree boundary. If it refuses a command that it cannot trace safely,
rewrite the command plainly rather than bypassing the guard.

One refusal has no plain rewrite, so recognize it rather than retrying. The guard reads the
shell's inherited working directory before a command runs, which means a `cd` that has already
left the worktree cannot be undone from the shell: every later call is refused, `pwd` and
`git -C "<worktree>"` among them, and so is the corrective `cd "<worktree>"`, whose only effect
would have been to satisfy the guard. The message names the worktree to re-run from while making
it unreachable.

Do not rely on the guard to keep you out of that state. Tested on 2026-09-02, it refuses a `cd`
into the main checkout before a *git* command, but permits the same `cd` before a non-git one, so
an ordinary search walks straight through. Whether the escape then sticks to the shell varied
within the same session: it stuck when the command piped its output and did not when it ran bare,
which is reason to treat every escape as capable of ending the session rather than to look for a
safe spelling. That is why the working-directory rule in
[references/lifecycle.md](references/lifecycle.md) covers read-only commands too.

Recover with `ExitWorktree` and `action: "keep"`. It returns the session to the main checkout and
drops the guard, leaving the worktree directory and the task branch on disk; address the worktree
with `git -C` afterwards, and hold the manual-test gate exactly where it was. A fresh session
started in the worktree recovers just as well. Nothing on disk is lost either way, so say what
happened and which recovery was taken instead of quietly routing around it.

Report the worktree's absolute path, branch, origin identities, and base commit in the response,
not only in a tool call. The session has moved and the user's editor has not, so an unreported path
leaves them looking at the old branch in the main checkout with no sign of the change.

Do not treat the status line as evidence either way. After `EnterWorktree` moves the session by
path, Claude Code has been observed still sending the main checkout as `workspace.current_dir`,
so a status line built on that documented field keeps showing the old directory and branch for
the rest of the session. Verify with `git rev-parse` from the worktree instead, and say so if the
user reports a contradiction.

## 6. Implement through publishing

Read [references/lifecycle.md](references/lifecycle.md) and follow it through the manual-test gate
and publishing. Do not commit, push, or open a request until the user explicitly reports that the
manual test passed.

## 7. Clean up the worktree, never the branch

Removal is allowed only when all are true:

- the user reported the manual test passed;
- `git status --porcelain` is empty;
- `git rev-parse HEAD` equals `git rev-parse origin/<branch>`;
- the request exists and its URL is recorded;
- this task left no stash;
- the user did not request `cleanup=keep`.

For `cleanup=ask`, ask once and explain that dependencies and build output in the directory are
also removed. Recommend keeping the worktree while non-trivial review is likely. For
`cleanup=auto`, the invocation supplies removal authorization, but the same safety checks remain.

When removal is authorized:

1. Clean up continuity according to `project-continuity`.
2. Call `ExitWorktree` with `action: "keep"`.
3. From the main checkout, run `git worktree remove "<path>"` without `--force`.
4. Run `git worktree prune`.
5. Confirm the worktree is absent and the local task branch still exists.

If any check or removal fails, leave everything in place and report the exact failure. Never
delete the local or remote branch.

## Resume

Resume in the same physical worktree. A new Claude Code session can enter its path with
`EnterWorktree`; continuity lives in that worktree rather than the main checkout.
