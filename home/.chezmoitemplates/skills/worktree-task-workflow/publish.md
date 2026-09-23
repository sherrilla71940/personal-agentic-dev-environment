# Push and open the request

Read this only after `git-commit-action` has created commits. In `mode=draft`, show the commit plan
and stop; nothing is pushed.

The publish contract depends on the resolved route:

- `worktree` publishes the task branch against its recorded `base` branch after the exact-base
  freshness and integration gate below.
- `in-place` publishes the current branch only when the user requested publication. It does not
  create or switch a branch, and it has no recorded worktree starting commit to integrate. Require
  an explicit request target before opening a pull or merge request; do not infer one from the
  current branch, its upstream, or the forge default.

## Integrate the current base before publishing

Run this section for the `worktree` route. For `in-place`, verify the current branch and explicit
request target, then continue to [Detect the forge](#detect-the-forge).

The task starts from a recorded base commit, but the named base branch may advance while the task is
in progress. Before pushing or opening a pull or merge request, run this freshness and integration
gate from the task worktree:

1. Re-read both `git remote get-url origin` and `git remote get-url --push origin`. Compare their
   redacted identities with the invocation checkpoint. Stop if either identity changed.
2. Fetch the remote with `git fetch origin --prune`. Resolve `origin/<base>^{commit}` and stop if
   the named base branch no longer exists.
3. If the current base commit equals the recorded checkpoint, continue to [Detect the forge](#detect-the-forge).
4. If the base advanced, stop before any push or request creation. Report the recorded base commit,
   the current base commit, and that the task needs integration. Do not use ambiguous `git pull`,
   and do not choose merge or rebase silently.
5. After the user chooses an integration strategy, require a clean task worktree and no existing
   merge or rebase operation. Check whether `git ls-remote --exit-code --heads origin <branch>`
   finds an already-published task branch. Do not stash, reset, or discard changes automatically.
6. For a merge, run `git merge --no-edit origin/<base>`. For a rebase, run `git rebase origin/<base>`.
   If the task branch already exists on the remote, a rebase rewrites published history: require
   separate explicit approval and use `git push --force-with-lease`, never plain force-push. Prefer
   a merge for a branch that has already been published.
7. If Git reports conflicts, stop and preserve the worktree and conflict markers. Do not resolve,
   abort, or reset automatically. The agent may help inspect and resolve the conflicts after the
   user asks it to continue. Record the conflicting paths and the next operation in continuity.
   Resume with `git add` plus `git rebase --continue` or `git merge --continue`; use
   `git rebase --abort` or `git merge --abort` only when the user explicitly abandons that update.
8. After a successful merge or rebase, rerun applicable automated verification. Because integration
   can change behavior after the earlier manual test, return to the manual-test gate and request a
   fresh passing result before publishing.
9. Immediately before the eventual push, recheck the origin identities and `origin/<base>` again.
   A new base advance requires another integration cycle; never silently retarget the request.

The final push and request steps below assume this gate passed. Run Git commands from the active
worktree. In an isolated Claude session, do not use `git -C` to redirect operations to the main
checkout.

## Detect the forge

After the integration gate passes, re-read both `git remote get-url origin` and `git remote get-url
--push origin` and compare their redacted identities with the remote-base checkpoint recorded during
invocation. If either identity changed, stop and ask the user to re-resolve the workflow; do not
assume that the name `origin` still points at the same repository. Also verify that the invocation's
named base branch still exists on that remote. Never show or record embedded credentials.

| Origin host | Push | Open request |
| --- | --- | --- |
| GitHub or GitHub Enterprise | plain push | `gh pr create` |
| GitLab with an available MCP request tool | plain push | that MCP tool |
| GitLab without an MCP request tool | GitLab merge-request push options | the push |

Check before using optional CLIs. Do not assume `glab` is installed.

## Compose the request

Follow the repository's pull- or merge-request template when present.

- Use the primary commit's Conventional Commit subject as the title.
- Describe what changed, why, the covered scope, and anything deliberately excluded.
- When the invocation omits `lang`, use the active context default `{{ .langDefault }}`; an explicit `en` or `zhtw` value remains authoritative.
- Use the resolved `lang`; load `natural-zhtw` before Traditional Chinese request text.
- For a description longer than a few sentences, load `technical-writing` for structure. On a
  Traditional Chinese description load both: `natural-zhtw` wins where they overlap, because it
  carries the zh-TW heading conventions and warns against overcorrecting into compression.
- Attribute verification accurately: name the agent-run checks and separately state that the user
  performed the manual test and reported it passing.
- Do not describe reading as execution, or claim review, approval, deployment, or agreement that
  did not happen.

Write the description to a temporary file rather than building multiline shell quoting.

## Push

```bash
git push -u origin HEAD
```

Never force-push without the separate explicit approval required by the integration gate. Stop when
the remote task branch moved unexpectedly or authentication fails.

For GitLab without an available request tool, create the request on the first push that updates
the branch:

```bash
git push -u origin HEAD -o merge_request.create -o merge_request.target=<base> -o merge_request.title="<title>"
```

Capture the request URL from the push output.

## Open the request

For GitHub:

```bash
gh pr create --base "<base>" --head "<branch>" --title "<title>" --body-file <file>
```

For GitLab with an available MCP tool, pass the project, source branch, original target base,
title, and description using that tool's schema. Target the invocation's base, not the default
branch or forge preselection.

Stop after creating the request. Do not merge, approve, enable auto-merge, or opt into deleting
the source branch beyond the project's existing defaults.

## Report

```text
Branch:  fix/example/frontend
Commits: <sha> <subject>
Target:  feat/example-base
Request: <url>
```

List every commit. If publishing is incomplete, identify the failed step and give the exact safe
command or URL the user can use to finish it.
