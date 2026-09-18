# Developer environment setup

This guide covers first-time installation on Windows or macOS. Recurring edits, additions,
removals, and applies belong in [the chezmoi workflow](./chezmoi-workflow.md).

The repository manages durable shell, Git, VS Code, Claude Code, Codex, and GitHub Copilot
configuration. Credentials, sessions, caches, logs, memory, and workspace state stay local.

Chezmoi calls the desired files in its repository clone the **source state**. It renders
those files into live **targets** under your home directory when you run `chezmoi apply`.
For example, the source `home/dot_bashrc` renders to the target `~/.bashrc`.

## New machine, in order

The steps below are the whole path. Each links to its own section, and the order matters:
a later step assumes an earlier one, and two of them are easy to discover too late.

1. [Install Git and chezmoi](#install-git-and-chezmoi), and on Windows
   [enable symlink creation](#enable-windows-symlink-creation). Both are needed before cloning.
2. Decide where the Git working tree lives, **before** cloning, because both setup paths below
   clone for you: see [Working tree at `~/dotfiles`](#working-tree-at-dotfiles). To use
   `~/dotfiles`, `git clone` there yourself rather than letting `chezmoi init` choose.
3. Pick a path: [empty machine](#empty-machine) for a machine with nothing to preserve, or
   [existing configuration](#existing-configuration) when any current setting should survive.
   When unsure, choose the second — it changes no live file until you say so.
4. Run the [bootstrap helper](#bootstrap-helper). It links the default source directory and
   enables the validation hook, then installs whatever supporting tools it can.
5. Install the applications themselves and log in to each, which nothing here can do for you:
   see the table under
   [Application installation and login](#application-installation-and-login), then supply the
   [MCP server credentials](#mcp-server-credentials) that no script can set.
6. Run the [bootstrap helper](#bootstrap-helper) again. Its plugin, extension and MCP steps are
   each gated on a CLI that step 5 installs, so on a genuinely new machine the first run skips
   them. The second run is not optional.
7. [Verify](#verification).

## Choose a setup path

Choose based on the configuration already in the home directory:

| Machine state | Setup path |
| --- | --- |
| No shell, editor, or AI-client settings need to be preserved | [Empty machine](#empty-machine) |
| Any existing settings should survive, or you are unsure | [Existing configuration](#existing-configuration) |

A new computer can already have existing configuration if you used an application before
installing this developer environment. When unsure, use the existing-configuration path. It initializes
the repository without changing live files.

Both paths clone into the default chezmoi source directory. Where the Git working tree lives is
a separate choice, and it is cheapest to make now rather than after cloning: see
[Working tree at `~/dotfiles`](#working-tree-at-dotfiles).

## Common prerequisites

### Install Git and chezmoi

macOS with Homebrew:

```bash
brew install git chezmoi
```

Chezmoi's standalone installer is also available when Homebrew is not desired:

This downloads and executes a remote installer. Use it only after deciding that you trust the
source and have reviewed the URL/script policy for the machine.

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)"
```

Windows PowerShell:

```powershell
winget install --id Git.Git --exact
winget install --id twpayne.chezmoi --exact
```

Restart the shell after Winget installation. The managed `.bashrc` adds Winget's command
shim directory to Git Bash after the first apply; use PowerShell for initial setup if Git
Bash cannot find `chezmoi` yet.

### Enable Windows symlink creation

Skip this step on macOS. Portable skills render as symbolic links under `~/.claude/skills`.
On Windows, enable **Developer Mode** before the first apply, or run the apply from an account
with `SeCreateSymbolicLinkPrivilege`. Without one of those, chezmoi cannot create the skill
links. See [chezmoi's Windows guidance](https://www.chezmoi.io/user-guide/machines/windows/#create-symlinks).

## Empty machine

Use this path only when no existing configuration needs to be preserved. On macOS or Git
Bash, the standalone installer can install chezmoi and apply the repository in one command:

This command downloads and executes a remote installer; use it only after deciding that you trust
the source and have reviewed the URL/script policy for the machine.

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply sherrilla71940
```

If chezmoi is already installed, run:

```bash
chezmoi init --apply sherrilla71940
chezmoi source-path
chezmoi status
```

The source path should normally end in `~/.local/share/chezmoi/home`. Empty status output
means the managed targets match the source state.

## Existing configuration

Use this path to inspect and preserve existing settings before chezmoi writes any targets.

### 1. Initialize without applying

```bash
chezmoi init sherrilla71940
```

If you use a fork, replace `sherrilla71940` with the fork's URL or GitHub shorthand. Chezmoi
places the clone in its default source directory.

Immediately confirm that chezmoi is reading the expected clone:

```bash
chezmoi source-path
```

The result must identify this repository, either directly or through a symlink or Windows
junction. A displayed path ending in `~/.local/share/chezmoi/home` is valid when its resolved
target belongs to this repository. Compare filesystem or Git identity instead of displayed
path strings alone. If it identifies a different clone, stop and reconcile the source
directories before continuing.

### 2. Preview every target change

```bash
chezmoi diff
```

Every removed line is live configuration that apply would replace. Do not apply yet.

Useful safer variants:

| Command or flag | Behavior |
| --- | --- |
| `chezmoi apply --dry-run --verbose` | Show operations without writing |
| `chezmoi apply --interactive` | Prompt for every operation during the eventual apply |
| `chezmoi apply --less-interactive` | Prompt for changed or pre-existing targets during the eventual apply |

### 3. Adopt the settings you want to keep

Handle each changed target according to the desired result:

| Desired result | Action before applying |
| --- | --- |
| Use the repository version | Make no source change; the preview already shows what apply will replace |
| Preserve an entire plain file | Confirm the source filename is a bare `dot_` name, with no `.tmpl` suffix and no `create_`, `modify_`, or `symlink_` prefix, then run `chezmoi re-add <target>` |
| Preserve values from a `create_` or `modify_` source | Edit the source by hand; `re-add` skips these silently, and `chezmoi add` would destroy the source entry |
| Preserve selected values | Open the live target and its source side by side, then copy only portable values into the source |
| Preserve values from a templated target | Edit the source template or shared body; `re-add` deliberately skips templates |

For example, to preserve an entire live `.bashrc`:

```bash
chezmoi source-path ~/.bashrc
chezmoi re-add ~/.bashrc
chezmoi git -- diff
```

To preserve selected VS Code settings, compare the live `settings.json` with
`home/.chezmoitemplates/vscode/settings.json` and copy only the settings that should follow
every machine. Do not copy credentials, caches, machine paths, or application-owned state.

`chezmoi merge <target>` can perform a three-way merge when a merge tool is configured.
Manual source editing is safer for this repository's templates because one rendered target
can combine a thin wrapper with a shared body.

After adopting settings, review both kinds of change:

```bash
chezmoi git -- diff   # changes you made to the repository source
chezmoi diff          # changes the next apply will make to live targets
```

Back up any irreplaceable live file outside its managed target path before continuing.

### 4. Apply and verify

```bash
chezmoi apply -v
chezmoi status
```

Empty status output means the managed targets match the source. Restart applications so they
reload their configuration.

If adoption changed the source, review and commit those portable changes so they follow the
other machines. Do not commit machine-specific values or credentials.

## Select the machine-local AI profile

After initialization, choose the two independent profile inputs and the managed-mode continuity
option with `chezmoi edit-config`.
The values, defaults, validation behavior, language mapping, and repository-level override are
documented in [the machine-local selector guide](./chezmoi-workflow.md#machine-local-ai-profile-selectors).

Preview the selected result with `chezmoi diff` before applying. These values are machine-local,
not synchronized in the repository, and machine-wide in v1. Start new Claude Code, Codex, or VS
Code sessions after applying; already-running sessions retain their startup context. Worktree
workflow and manifest skills remain independently available in every combination. A profile CLI
and broad Copilot integration are intentionally deferred.

## Application installation and login

Chezmoi can write configuration before an application exists. Each application discovers its
files when it is installed and started later.

| Product surface | Installed separately? | Local follow-up |
| --- | --- | --- |
| VS Code with GitHub Copilot | Yes | Enable Copilot, sign in to GitHub, then install other desired extensions from the repository manifest |
| Claude Code CLI or IDE integration | Yes | Log in, authenticate connectors with `/mcp`, and install Claude in Chrome if desired |
| Claude Desktop | Optional | Its Code tab shares Claude Code configuration; desktop chat, Cowork, and chat-app MCP configuration remain separate |
| Codex CLI, IDE extension, or ChatGPT desktop app | Yes; install the surfaces you use | Log in and authenticate enabled connectors or plugins; local surfaces share `~/.codex/` configuration |
| GitHub Copilot command-line interface (CLI) | Yes | Install and log in separately; the CLI has its own settings and MCP configuration |
| Node Version Manager (NVM) and Node.js | Yes | The shell supports lazy-loaded NVM but does not install NVM or Node.js |

### MCP server credentials

The bootstrap helper installs the MCP server *declarations*, but never a credential. Two of
them need a local step before their tools work, and neither announces itself: the server is
simply listed and fails to connect.

| Server | Local step |
| --- | --- |
| GitLab | None beyond authenticating once. Run `/mcp` in Claude Code, select `gitlab`, and choose **Authenticate**. The instance supports OAuth dynamic client registration, so no token is involved. |
| GitHub | Set a `GITHUB_MCP_TOKEN` user environment variable to a personal access token scoped to `repo`, adding `read:org` only for organization repositories. GitHub publishes no registration endpoint, so OAuth is unavailable and Claude Code rejects the server without a token. |

Set the variable before starting the client, not after: a process inherits its environment at
start, and on Windows an editor's integrated terminal inherits the editor's, so a terminal
opened inside an editor that was already running still will not see it. Restart the editor
itself, then confirm with `echo ${#GITHUB_MCP_TOKEN}` before assuming the token is wrong.

An unexpanded variable is not reported as a missing credential. The literal `${GITHUB_MCP_TOKEN}`
is sent as the header and the server answers `HTTP 400`, which reads as a broken server rather
than an unset variable.

### Bootstrap helper

The post-clone bootstrap helper wires the clone up and installs the supporting tools this
repository expects. It points chezmoi's default source directory at this working tree, sets
`core.hooksPath` so the validation hook runs, then installs `jq` for the Claude Model
Context Protocol (MCP) installer, the TypeScript language server that the `typescript-lsp`
plugin needs but does not install itself, the Claude Code plugins, the VS Code extensions
from the manifest, and the user MCP servers. It installs none of the applications above,
and it never replaces an existing source directory:

```bash
bash scripts/bootstrap/bootstrap-macos.sh
```

```powershell
powershell -File scripts/bootstrap/bootstrap-windows.ps1
```

### VS Code extensions

The bootstrap helper installs these when the `code` CLI is on `PATH`. The manifest stays out
of routine apply, so run it directly to reinstall or to pick up manifest changes later:

```bash
grep -v '^#' scripts/manifests/vscode-extensions.txt | grep . | xargs -I{} code --install-extension {} --force
```

```powershell
Get-Content scripts/manifests/vscode-extensions.txt | Where-Object { $_ -and -not $_.StartsWith("#") } |
  ForEach-Object { code --install-extension $_ --force }
```

### Claude user MCP servers

The bootstrap helper runs this when the `claude` CLI is on `PATH`. Run it directly if Claude
Code was installed afterwards, or to pick up manifest changes:

```bash
bash scripts/install/install-claude-mcp.sh
```

```powershell
powershell -File scripts/install/install-claude-mcp.ps1
```

The shell installer requires `jq`; the PowerShell installer does not. It leaves existing
server names unchanged because `~/.claude.json` also contains application-owned state. The
[MCP customization guide](./customization-support.md#add-an-mcp-server) explains what belongs
in the manifest and what remains owned by plugins, accounts, or browser integrations.

### Plugins

The repository carries portable plugin declarations for Codex and Copilot, and installs
Claude Code's plugins from `scripts/bootstrap/bootstrap-*` instead, so enabling and disabling them stays
local. It never carries downloaded caches or authentication. Follow the
[plugin customization guide](./customization-support.md#add-a-marketplace-plugin) for the
client-specific source and Codex's create-once behavior.

## Enable repository validation

The bootstrap helper does this. Run it by hand in a clone that has not been bootstrapped:

```bash
git config core.hooksPath scripts/git-hooks
```

From the repository root, run `bash scripts/dev-env doctor` when diagnosing a machine. It reports
the chezmoi source identity, resolved profile values, unapplied drift, Claude shared-skill links,
and required tool versions without changing any target.

On Windows, run the repository's Bash-based suites through the PowerShell wrapper so they use
Windows Git Bash rather than a `bash` command that may resolve to WSL:

```powershell
.\scripts\tests\run-git-bash-tests.ps1
```

Pass one or more relative `.sh` paths to run only selected suites. The wrapper does not modify
`PATH` or install anything; it resolves and validates the Git for Windows `bash.exe` before
running each script.

The pre-commit hook, in order (the script's own numbering starts at the render step):

- confirms the default chezmoi source resolves inside this repository,
- materializes and renders the staged Git snapshot,
- checks skill file-count parity, shared Claude skill links, and Codex-targeted host gates,
- compares rendered Claude and Copilot rule bodies with cross-platform tools,
- rejects YAML frontmatter in Codex's rendered `AGENTS.md`,
- when a status line script is staged, renders both copies and compares their output, which
  needs `jq` and PowerShell on `PATH`, and
- when any markdown is staged, resolves every link carrying a `#fragment` — into another file
  or within the same one — against the headings that actually exist.

The hook renders only into a temporary directory, using the same `--exclude=scripts` flag
described in [the workflow guide](./chezmoi-workflow.md#source-filename-rules).

Before those checks it also warns, without rejecting the commit, when more than one
interactive Claude Code session is running inside this working tree. Such sessions share one
index, and `git commit` takes the whole index rather than the paths a session meant to stage,
so the warning lists every staged file and how to unstage one. The launch-time equivalent is
the `SessionStart` hook in `home/dot_claude/hooks/check-worktree-launch.*`. Decline that
offer in this repository and stage explicit paths instead: `chezmoi source-path` resolves to
the main checkout wherever the session runs, so a worktree edit is not the source chezmoi
reads. See the worktree constraint in [`AGENTS.md`](../AGENTS.md#constraints). The concurrent
session check needs `claude` and `jq` on `PATH` and is skipped without them.

That hook is Claude-only, because it shells out to `claude agents --json` and speaks in terms of
`EnterWorktree`. Project-continuity reporting used to live in it too and no longer does; it is
described next.

When `ai_continuity` is `on` and `ai_harness` is `managed`, the script rendered from
`home/dot_local/share/maintain-project-continuity.sh.tmpl` adds the
deterministic reporting that the skill cannot do for itself. On `SessionStart` it reports whether
continuity exists and, when it does, names the objective it tracks, so the decision about whether
this is the same task is made
against a shown fact rather than from recall; it also ensures `.project-continuity/` is excluded
from Git. On `Stop` it compares the recorded branch and HEAD against the checkout, offers cleanup
when the active tracking sections are empty, and reports parked files with no unfinished sections
as closure candidates. It never deletes parked state; the skill requires confirmation for each
named file. HEAD is reported two ways. A
recorded commit that has left the history - rebased, reset, or belonging to another line of work
- means the recorded starting point cannot be trusted. A recorded commit that is still an
ancestor but more than one commit behind means a checkpoint opportunity passed without the file
being rewritten; one commit behind is work in flight and stays silent, because a notice after
every commit is one readers learn to ignore. The script never reads or copies the transcript.

With `ai_continuity = "off"`, the continuity guidance and continuity lifecycle hook are absent, but
managed notifications and Claude's worktree-launch check remain. With `ai_harness = "native"`,
continuity guidance and continuity/worktree lifecycle hooks are absent; the statusline, lightweight
notifications, shared instructions, reusable skills, wrappers, and private-file protections remain.
The stored continuity preference is not changed, so returning to managed mode with continuity on
restores the automatic behavior. The `project-continuity` skill remains installed for explicit
continuity requests. Codex records trust by hook path and content hash, so switching harness modes
can require a new `/hooks` approval.

It lives in `~/.local/share` rather than under `~/.claude` because **both Claude Code and Codex
run it**. They share hook event names, stdin fields (`cwd`, `hook_event_name`, `session_id`,
`source`) and output contract (`systemMessage`, `hookSpecificOutput.additionalContext`), so one
script serves both: Claude through
[`settings-durable.json`](../home/.chezmoitemplates/claude/settings-durable.json), Codex through
[`hooks.json`](../home/dot_codex/hooks.json.tmpl). Codex records hook trust separately, in
`config.toml` under `[hooks.state]`, so each entry needs one `/hooks` approval per machine.
Anything naming one client's machinery stays in that client's own hook, which is why
`check-worktree-launch.sh` keeps only its concurrent-session and worktree-container checks.

Neither `PreCompact` nor `PostCompact` is wired in either client: neither can inject context into
the model, so a backstop built on them could only write state, never ask for it to be reconciled.
In managed mode, the ordinary `SessionStart` report covers the post-compaction case instead. On Windows the hook
uses Git Bash to avoid paying PowerShell startup cost after every response.

Claude Code, Codex and Copilot can all resume the resulting `.project-continuity/state.md` when
started in the same physical working tree. In managed mode with continuity enabled, Claude and
Codex additionally get the hook reporting above; native mode leaves that protocol available only
through explicit instructions and skills. Copilot has no hook system, so its entry path is the
global instructions and shared skill alone.

## Working tree at `~/dotfiles`

This repository is developed in, not only applied: decision records, bootstrap scripts, a
pre-commit hook and a test-render workflow are all edited and committed regularly. Its Git
working tree therefore lives at `~/dotfiles`, and chezmoi's default source directory is a
link to it. This is a deliberate layout, not a workaround, and it changes nothing about the
source state — only where the checkout you edit lives. See
[ADR-0006](./decisions/0006-keep-the-working-tree-at-dotfiles.md).

`chezmoi init` clones straight into the default source directory, so a machine set up that
way needs no link and the repository sits under `~/.local/share/chezmoi`. Both layouts work.
To use `~/dotfiles`, clone there and point the default source directory at it. Do this only
when `~/.local/share/chezmoi` does not already contain changes you need.

The bootstrap helper creates the link when the path is free, reports it when it already
points here, names a broken one, and refuses to touch an unrelated directory. The commands
below are what it runs, for a machine being set up by hand.

macOS or Git Bash with symlink permission. Remove any existing clone first: `ln -s` onto an
existing directory silently creates `~/.local/share/chezmoi/dotfiles` inside it and exits 0,
after which chezmoi keeps using the old clone and nothing you edit in `~/dotfiles` ever
applies.

```bash
[ -e ~/.local/share/chezmoi ] && echo "remove or move this first" && ls ~/.local/share/chezmoi
mkdir -p ~/.local/share
ln -s ~/dotfiles ~/.local/share/chezmoi
```

Windows PowerShell can use a directory junction without elevated symlink permission:

```powershell
New-Item -ItemType Directory -Force "$HOME\.local\share" | Out-Null
New-Item -ItemType Junction -Path "$HOME\.local\share\chezmoi" -Target "$HOME\dotfiles"
```

Then verify. Every command reports the link path rather than the working tree, so compare Git
identity instead of the displayed string:

```bash
chezmoi source-path                                        # ends in .local/share/chezmoi/home
git -C "$(chezmoi source-path)" rev-parse --show-toplevel  # must be the working tree
```

The link is not part of the source state, so `chezmoi apply` neither creates nor repairs it.
A machine missing the link silently uses whatever `~/.local/share/chezmoi` contains, which is
why this check belongs immediately after cloning.

## Verification

```bash
chezmoi source-path  # this repository, directly or through a link
chezmoi status       # empty after apply
chezmoi doctor       # environment sanity
```

Then restart each AI client and inspect the customization relevant to the change. Detailed
client paths and verification steps live in [customization-support.md](./customization-support.md).

## Secrets and ownership boundaries

Never commit credentials. `${input:figma-api-key}` in VS Code's `mcp.json` is a prompt
definition, not a stored value. If a template eventually needs a real secret, use a chezmoi
secret source or an environment variable rather than committing it.

Chezmoi deliberately does not own complete application data directories, plugin caches,
sessions, authentication tokens, logs, VS Code workspace storage, Copilot runtime state, or
Codex's existing mixed-state `config.toml`. See
[ownership and app-written settings](./chezmoi-workflow.md#applications-that-write-their-own-configuration)
before importing a live application file.

## Version-sensitive references

| Item | Why it can drift | Verify |
| --- | --- | --- |
| Chezmoi source attributes and special files | Filename transformations affect rendered names | [Source attributes](https://www.chezmoi.io/reference/source-state-attributes/) and [special files](https://www.chezmoi.io/reference/special-files/) |
| Claude rules, skills, agents, and settings | Discovery paths and accepted fields evolve | [Claude Code documentation](https://code.claude.com/docs/en/overview) |
| Claude Code worktree creation and cleanup | Sweep eligibility, ignored-file provisioning, and entry rules change by patch release, and `worktree-task-workflow` depends on all three | [Worktrees](https://code.claude.com/docs/en/worktrees) and [worktree provisioning](./worktree-provisioning.md) |
| Codex prompts, agents, config, and skills | Customization surfaces and deprecations evolve | [Codex customization](https://learn.chatgpt.com/docs/agent-configuration/agents-md) |
| Codex lifecycle hooks | Event names, payload fields and the trust model are newer than the rest of this setup, and `maintain-project-continuity.sh` assumes they stay aligned with Claude's | [Codex hooks](https://learn.chatgpt.com/docs/hooks) |
| VS Code and Copilot customization | User folders and instruction discovery evolve | [VS Code agent customization](https://code.visualstudio.com/docs/agent-customization/overview) and [Copilot customization](https://docs.github.com/en/copilot/customizing-copilot) |
| Codex app managed worktrees | `project-continuity` records that the app keeps them under `$CODEX_HOME/worktrees` on a detached HEAD, and that archiving a chat can delete one; that behavior is observed rather than documented, so re-check it in the app | [Codex config](https://learn.chatgpt.com/docs/config-file/config-basic) and direct observation |
| Copilot instruction reach and memory scope | `project-continuity` depends on `~/.copilot/instructions/**/*.instructions.md` reaching CLI and Agent Host sessions, and on Copilot Memory being repository-scoped and shared rather than machine-local like Claude's and Codex's | [Copilot CLI config dir](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference) and [repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions) |
