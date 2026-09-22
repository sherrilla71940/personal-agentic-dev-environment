---
name: worktree-manifest
description: "Author or extend a repository's .worktreeinclude, the tracked manifest consumed by Claude-created Git worktrees, Codex desktop local managed worktrees, and the repository's provisioning fallback to copy approved ignored files. Use when provisioning reports 'manifest not found in source worktree', when a fresh worktree cannot run the app because a local config file is missing, when a repository moves configuration into ignored files so that every worktree created afterwards will need them - externalized secrets, configSource or include targets, a new .env or *.local.* file - or when the user asks which ignored files a worktree should carry."
argument-hint: "[repo path] optional; defaults to the current repository"
disable-model-invocation: true
---

# Worktree manifest

A Git worktree receives tracked files and nothing else. Ignored local configuration —
`connections.config`, `appsettings.secret.config`, or a local environment file — stays behind, so
a fresh worktree can compile and still not run. `.worktreeinclude` is the tracked, repository-root
manifest that authorizes copying those files. It holds repository-relative gitignore patterns,
never file contents.

Claude Code consumes it when Claude creates a Git worktree, and Codex consumes it for local
desktop-managed worktrees. `git wt-add` and `git wt-copy` implement the same allowlist for
terminal-created or already-created worktrees. Do not imply that the manifest is processed by
Codex remote/CLI/IDE paths or by a Claude `WorktreeCreate` hook: those paths need their own
provisioning route. VS Code uses the separate user-level `git.worktreeIncludeFiles` setting, so a
repository manifest does not change what VS Code copies. Say so rather than implying one file
covers everything.

Codex desktop local managed worktrees have a native exception: Codex automatically copies an
ignored `AGENTS.override.md` even when it is not listed in `.worktreeinclude`. This is client-owned
behavior, not generic manifest approval, and does not apply to Codex CLI/IDE or the terminal
fallback. Tell the user when that native path will carry the override; keep it explicit-only for
generic manifest decisions.

This skill produces one commit in the target repository. It never copies a file itself; `git
wt-add` and `git wt-copy` do that.

## 1. Establish the repository and whether a manifest is warranted

Work in the repository's main checkout, from a branch you are allowed to open a request from.

```bash
git rev-parse --show-toplevel
git log --oneline -1 -- .worktreeinclude
```

An existing manifest means this is an extension, not an authoring task: read it first and
propose only additions.

Then find out what the repository actually keeps locally. This is the step that decides whether
there is anything to do. Use the repository's read-only classifier first:

```bash
git wt-check --source <repository-root>
```

The check distinguishes no manifest, an empty tracked manifest, eligible ignored files outside
the manifest, invalid manifest entries, and explicitly missing required local files. It also
reports tracked `CLAUDE.md` and `AGENTS.md` as files already supplied by Git, private agent
overrides and client-local settings as explicit-only, and explicit `configSource` and
`appSettings file` references from tracked configuration files. Those reference results are
readiness evidence, not manifest approval: inspect the source and target paths without printing
values, then classify only ignored files for the manifest. It never creates a manifest or copies a
file. Use `git status --ignored --porcelain | grep '^!!'` only as a supporting inventory when you
need to inspect a candidate's provenance.

**Most repositories need no manifest.** A repository whose ignored entries are only build output,
dependencies, agent state and data directories has nothing eligible, and the honest answer is
that its provisioning skip was harmless. Report that and stop. Do not author a one-line manifest
to make a warning go away.

## 2. Classify each candidate

Two conditions must both hold before a path can be copied: `.worktreeinclude` matches its
repository-relative path, and Git classifies it as ignored. Tracked files already arrive through
Git and must never be listed. If a manifest pattern matches a tracked path, provisioning rejects
that manifest entry; it does not copy the tracked file from another worktree or branch.

The manifest is limited to explicitly approved ignored files. A modified tracked configuration
file is never a manifest candidate. If a provisioning command is asked to
copy one, it reports that the file is application-owned and requires project-specific manual setup
or an explicit repository contract. Use
`git wt-readiness --source <source-worktree> --target <target-worktree>` to report that it was
not copied, then review the source and target manually if the local override is required.

Eligible — local development configuration that another worktree of the same repository needs:

- local connection strings, developer settings, and non-production environment files;
- a client-neutral repository configuration file whose contents are safe to share.

Explicit-only on generic manifest and fallback paths — do not suggest these as ordinary
configuration candidates:

- private agent overrides such as `CLAUDE.local.md`, `AGENTS.override.md`, or a project-specific
  alternate override name; they can change agent behavior and require an explicit manifest entry;
- client-local settings such as `.claude/settings.local.json` or a project-specific settings file;
  they can change permissions or tool behavior and require an explicit manifest entry.

Tracked `CLAUDE.md` and `AGENTS.md` already arrive through Git. They are not copy candidates, and
alternate instruction names are not recognized as active client instructions unless the client or
repository explicitly configures them.

Never eligible, whatever the user asks:

- authentication files, production environment files, private keys, certificates;
- agent history, memory, caches, `.project-continuity/**`, Codex local state;
- dependencies and build output — `node_modules`, `packages`, `bin`, `obj`, `dist`, `coverage`;
- database files, backups, and upload or temp directories holding real data.

An external secrets folder or another directory outside this repository is never an implicit
source. Provisioning accepts only the selected source worktree of the same Git repository. If a
project needs external setup, its repository must provide an explicit, user-approved contract or
setup command; this skill does not guess or execute one.

The optional tracked `.worktree-provision` contract is a report-only pointer to a repository-relative
setup script and documentation. It does not expand `.worktreeinclude`, authorize a copy, or permit
the generic helper to execute project setup; review and run it only through the consuming repository's
explicit process.

For an approved project-specific mapping that is not representable by `.worktreeinclude`, use the
generic helper's two-step protocol: run `git wt-provision --dry-run`, show the sanitized report and
approval ID, obtain the user's affirmative approval for that exact source, destination, operation,
and target worktree, then rerun with `--approve <approval-id>`. The helper fingerprints the source
and target HEAD, refuses tracked files and existing targets, and does not infer section merges or replace whole
Web.config or `.env` files. A changed source or destination requires a new approval.

The last one is the trap worth naming to the user: a data directory can look like configuration
and can hold client-confidential material, and neither its size nor its contents is obvious from
the path.

## 3. Confirm the entries with the user

Present the classified candidates and ask which to include, offering the eligible list as the
default and naming what you excluded and why. Do not write the file on your own judgment: the
user knows which local files carry client data, and an over-broad manifest silently copies that
into every future worktree.

For a file whose usefulness is genuinely marginal, say so and let them drop it. Fewer permission
prompts is a weaker reason to share a file than an application that will not start.

## 4. Write, verify, and commit

Write the approved patterns to `.worktreeinclude` at the repository root, one per line, with a
short comment for any entry whose purpose is not evident. Match the repository's existing line
endings.

Verify before committing, because a manifest that matches nothing is a valid but often unnecessary
choice:

```bash
git check-ignore -v <each listed path>
git wt-check --source <repository-root>
git wt-add --dry-run -- <throwaway path> HEAD
```

`wt-check` is the read-only classification gate. `--dry-run` runs that same gate and additionally
validates the native `git worktree add` arguments without creating a worktree. An entry that does
not appear is either tracked already or not ignored, and belongs in neither the manifest nor the
commit. Never create a manifest automatically to clear an unlisted-file warning; confirm its
purpose with the user first.

Commit the manifest alone, with a `chore` or `build` type. It is repository infrastructure, so its
own branch off the base is the default — this matters most when the gap was found during another
task, because the branch in hand then belongs to that task. But the default is not a prohibition:
when the user has been offered the choice and asked for it to ride along, commit it on the branch
in hand and make sure the request description says the manifest is included and why. Never fold it
in silently, and never on your own judgement.

Tell the user that the manifest only takes effect for worktrees created after it is merged, and
that `git wt-copy` provisions worktrees that already exist.
