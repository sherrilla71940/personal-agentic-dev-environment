# Push and open the request

Read this only after `git-commit-action` has created commits. In `mode=draft`, show the commit plan
and stop; nothing is pushed.

## Detect the forge

Before pushing, re-read both `git remote get-url origin` and `git remote get-url --push origin` and
compare their redacted identities with the remote-base checkpoint recorded during invocation. If
either identity changed, stop and ask the user to re-resolve the workflow; do not assume that the
name `origin` still points at the same repository. Also verify that the invocation's named base
branch still exists on that remote. Never show or record embedded credentials.

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

Never force-push. Stop when the remote branch moved or authentication fails.

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
