# Working in this repository with chezmoi

Use this guide for recurring additions, edits, removals, and applies. For first-time
installation, including preserving existing configuration, use [the setup guide](./setup.md).

## Source state and live targets

This repository contains `home/dot_bashrc`. Chezmoi interprets `dot_` as a leading dot, so
the source represents the live `~/.bashrc` file:

```text
repository source                     live target
home/dot_bashrc  --chezmoi apply-->   ~/.bashrc
```

The **source state** is the desired configuration stored under `home/`. Edit and commit the
source state. A **target** is the live file in the home directory that an application reads.
Run `chezmoi apply` to make targets match the source state.

The repository-root `.chezmoiroot` file contains `home`. This setting makes `home/` the top
of the source state without creating a `~/home/` directory. Repository-only files such as
`README.md`, `docs/`, and `scripts/` remain outside the managed home tree.

Use these rules to choose a command:

- **Changed a source file under `home/`:** Run `chezmoi diff`, then `chezmoi apply`.
- **Changed a plain live target:** Run `chezmoi re-add <target>` to copy it into the source.
- **Changed a templated live target:** Edit its source template; `re-add` skips templates.
- **Changed a target whose source carries an attribute** (`create_`, `modify_`, `symlink_`):
  Edit the source. `re-add` silently skips these, so it looks like it worked and changes
  nothing. Never run `chezmoi add` on one — see the warning below.
- **Created a new live file:** Run `chezmoi add <target>` to start managing it.

## Machine-local AI profile selectors

The AI profile is selected in chezmoi's machine-local config, not in this repository's source
state. Run `chezmoi edit-config` and set these values under `[data]` when needed:

```toml
[data]
ai_context = "company"        # personal or company; default: personal
ai_continuity = "on"           # on or off; default: on
ai_harness = "managed"         # managed or native; default: managed
```

`ai_context` and `ai_harness` are independent choices; `ai_continuity` is an option within managed
mode. The raw selector inputs have eight supported combinations, but the two native combinations
have the same effective continuity behavior because native suppresses continuity. Missing
`ai_context` uses `personal`, missing `ai_continuity` uses `on`, and missing `ai_harness` uses
`managed`. For backward compatibility, `ai_workflow` is accepted as a legacy alias only when
`ai_harness` is absent; new configuration should use `ai_harness`. Any other value fails clearly
during rendering. Personal context resolves the applicable artifact-language default to English
(`en`); company resolves it to Traditional Chinese (`zh-TW`, represented as `zhtw` where an
existing interface uses that value). Explicit user or repository instructions and explicit language
arguments take precedence.

The selectors compose one baseline with either the personal or company context. `ai_continuity`
stores the managed-mode continuity preference; its guidance and automatic lifecycle reporting are
effective only when it is `on` and `ai_harness = "managed"`. Managed mode also registers
notifications and the Claude worktree-launch hook. Native mode keeps shared instructions, reusable
skills, the statusline, lightweight notifications, delivery wrappers, and private-file protections,
but does not load continuity guidance or register continuity/worktree lifecycle hooks. The stored
continuity preference is unchanged, so returning to managed mode can re-enable it. General shell,
Git, VS Code, and Windows Terminal settings are outside this selector. Workflow skills remain
available as explicit opt-ins in either mode. State-changing workflow skills never start implicitly;
managed lifecycle hooks report events without starting a worktree or changing source state. The selectors affect newly rendered configuration
and newly started sessions; an already-running session keeps its startup context. The values are
local to the machine and are not committed or synchronized by this repository. When working in
this repository, root `AGENTS.md` overrides the machine context and requires the effective context
to be `personal`.

The worktree task workflow is an opt-in for substantial or isolation-sensitive work, not a mandatory
entry point for every task. Small, self-contained edits that do not need parallel isolation may stay
in the current valid worktree; use the workflow when isolation, cross-session handoff, controlled
verification, or publishing matters.

After editing the config, use `chezmoi diff` to preview the selected render. Review it before
`chezmoi apply`, then restart the affected client sessions. A dedicated profile CLI is deferred;
the worktree skills remain installed and independently invokable in every selector combination.

## Archive, restore, or delete reusable workflows

Workflow archives are tracked repository data under `archives/workflows/`, not chezmoi source and
not client-discovery directories. Use the `workflow-archive`, `workflow-restore`, and
`workflow-delete` skills. They accept a workflow name or description, perform bounded discovery,
and use a reviewed explicit inventory under the shared engine
`scripts/workflows/workflow-archive.py`.

Archive creates a recoverable copy and then deletes only confirmed canonical source files in the
same operation. It queues generated-target deletion through `home/.chezmoiremove` but does not
delete live targets directly. Delete removes confirmed source files without creating a new archive.
Restore defaults to a dry run, refuses collisions, writes only missing canonical files after
explicit confirmation, and leaves profile selection and `chezmoi apply` to their separate
workflows. Read the [workflow archive guide](./workflow-archives.md) before changing the definition
or archive layout.

From the repository root, `bash scripts/dev-env doctor` reports source identity, the resolved
profile, unapplied target drift, Claude shared-skill link health, and required tool versions. It is
repository tooling because it checks this checkout and live chezmoi state; it is not rendered into
the home directory as a machine command.

Check which case applies by reading the whole source filename, not only its suffix:

```bash
basename "$(chezmoi source-path ~/.some-config)"
```

A plain target has a bare `dot_` name. Anything else — a `.tmpl` suffix, or a `create_`,
`modify_`, or `symlink_` prefix — means `re-add` is the wrong command.

`chezmoi add` takes a target path, never a source path. Use `chezmoi add ~/.bashrc`, not
`chezmoi add home/dot_bashrc`.

## Add a new file

When the desired live file does not exist yet, create it and add its target path:

```bash
chezmoi add ~/.new-config
chezmoi source-path ~/.new-config
chezmoi diff
```

Chezmoi encodes the live name in the source filename. For example, it stores `~/.new-config`
as `home/dot_new-config`.

If the source already exists under `home/`, edit it directly. Do not run `chezmoi add` again.
For instructions, skills, agents, prompts, Model Context Protocol (MCP) servers, or plugins,
follow the [AI customization guide](./customization-support.md) before choosing a path.

## Change a managed file

Editing a target changes only the live file. A later apply can restore the source version and
erase the live-only edit. Preserve the edit in the source before applying again.

First, identify its source:

```bash
chezmoi source-path ~/.bashrc
```

The suffix alone does not classify a source: `modify_settings.json` has no `.tmpl` and is
not a plain file. Read the whole filename, then use the matching workflow:

| Source type | Preserve a live edit | Preferred direct edit |
| --- | --- | --- |
| Plain file (`dot_name`) | `chezmoi re-add <target>` | `chezmoi edit <target>` |
| Template (`.tmpl`) | Copy the desired values into the source; `re-add` skips it | `chezmoi edit <target>` |
| Modify template (`modify_`) | Copy the value into the body the script includes; `re-add` skips it silently | Edit the body, not the script |
| Create-once (`create_`) | Merge only the missing durable declarations; the application owns the rest | Edit the source directly |

`chezmoi add` is the destructive command here, not `re-add`. On a template it asks first
(`adding … would remove template attribute, continue?`). On a `modify_` or `create_` source it
does **not** ask: it deletes the source entry and writes a plain file holding the live
contents. Running `chezmoi add ~/.claude/settings.json` therefore destroys
`home/dot_claude/modify_settings.json`, unmanages the durable keys, and commits the
application-owned ones. Never run `add` against a target that is already managed; if the
source exists, edit it.

After changing the source, review and apply:

```bash
chezmoi git -- diff   # source changes to commit
chezmoi diff          # live changes the next apply will make
chezmoi apply -v
chezmoi status
```

### Applications that write their own configuration

Applications can update files that also contain portable preferences. Preserve those changes
according to the file's ownership policy:

| Live file | Ownership policy | Preserve a UI or CLI change |
| --- | --- | --- |
| VS Code `settings.json` | Managed template | Edit `home/.chezmoitemplates/vscode/settings.json` |
| Claude `~/.claude/settings.json` | Partially managed modify template | Edit `home/.chezmoitemplates/claude/settings-durable.json` for durable keys; use `/config`, `/model` or `/effort` for app-owned choices |
| Copilot `~/.copilot/settings.json` | Plain managed file | Run `chezmoi re-add ~/.copilot/settings.json`, then review the source diff |
| Codex `~/.codex/config.toml` | Create-once mixed state | Merge only missing durable declarations; never replace the complete live file |
| Windows Terminal `settings.json` | Partially managed modify template | Edit `home/.chezmoitemplates/windows-terminal/settings-durable.json` for durable keys and for any keybinding; use its settings UI for everything else |

Windows Terminal is the one entry where the repository owns arrays rather than single
keys. It supplies `actions` and `keybindings` in full, so a keybinding added through the
Actions page of the settings UI is reverted on the next apply; add it to the durable file
instead. `profiles.list` stays with the application, because its GUIDs are generated per
machine. See [ADR-0009](./decisions/0009-own-windows-terminal-actions-and-keybindings.md).

The repository owns `env`, `hooks`, `statusLine`, and `autoUpdatesChannel`. Claude Code and
project settings own everything else, including `model`, `effortLevel`, `theme`, `verbose`,
`tui`, `permissions`, `enabledPlugins`, and unknown future keys, so those survive
`chezmoi apply` without entering Git.

Expect `~/.claude/settings.json` to sit at `MM` in `chezmoi status` more or less permanently,
and do not read that as the repository threatening an app-owned key. The modify template writes
the merged file with its keys normalized, while Claude Code appends each new key wherever it
lands, so choosing a model or an effort level leaves the same values in a different order. One
command separates a reordering from a real change:

```bash
diff <(chezmoi cat ~/.claude/settings.json | jq -S .) <(jq -S . ~/.claude/settings.json)
```

No output means every value already agrees and only the ordering differs, so the apply is safe
and changes nothing you chose in the app. Output names the keys that genuinely differ; check
those against the ownership table above before applying.

Releasing `theme` releases the *choice*, not the palette. Custom theme definitions are
separate files in `~/.claude/themes/`, and those are managed: `home/dot_claude/themes/` holds
one JSON file per theme, named for its slug, so every machine offers the same palettes in
`/theme`. Selecting one writes `theme: "custom:<slug>"` into the live settings, which the
repository does not own, so each machine can pick a different one.

A key earns a place in the durable set by being needed on every machine, stable enough that
you would not change it mid-session, and not written by the application. `permissions` fails
the second test: which rules are worth having changes with the workflow. A project's own
`.claude/settings.json` outranks the user file, so a guardrail that must hold belongs there
instead. A fresh machine therefore starts with no `ask` rules.

`enabledPlugins` fails it too, and the merge cannot express a disable, so pinning a plugin
made turning it off locally impossible. Plugins are installed software rather than
configuration, so `scripts/bootstrap/bootstrap-*` installs them the way it installs any other tool.
Which plugins are enabled after that is yours.

The durable keys live as readable JSON in
`home/.chezmoitemplates/claude/settings-durable.json`. `home/dot_claude/modify_settings.json`
only deep-merges that file over the live one, so a value the repository does not name is
never removed, and a key added locally under a name the repository does own is kept
alongside it. See
[ADR-0005](./decisions/0005-merge-durable-claude-settings-as-json.md).

`/statusline` writes `statusLine`, which the repository owns, so its change is reverted on
the next apply and the script it generates never reaches the repository. Edit the managed
statusline scripts instead. That key has to stay owned: the repository ships both scripts, so
releasing the setting would leave a fresh machine rendering scripts that nothing references.
`/plugin` is now unconstrained: it writes `enabledPlugins`, which the repository no longer
owns.

### Promote a local Claude setting into the repository

`chezmoi diff ~/.claude/settings.json` reports only repository-owned keys, so a setting you
changed locally and now want on every machine does not appear there. List the candidates:

```bash
./scripts/diagnostics/claude-settings-drift.sh
```

Most of what it lists is meant to stay local. Before promoting a key, check it against the
admission criterion in
[ADR-0005](./decisions/0005-merge-durable-claude-settings-as-json.md): needed on every machine,
stable enough not to change mid-session, and not written by the application. `theme`,
`verbose`, `tui`, `permissions`, and `enabledPlugins` were released deliberately, so re-pinning
one reverses that decision. Plugins do not belong in the settings at all — add them to the
`claude plugin install` list in `scripts/bootstrap/bootstrap-*`.

For a key that does qualify, copy the value into
`home/.chezmoitemplates/claude/settings-durable.json`, then apply and commit:

```bash
chezmoi diff ~/.claude/settings.json   # confirm only the promoted key changes
chezmoi apply
git commit --only -m "<message>" -- home/.chezmoitemplates/claude/settings-durable.json
```

Promotion stays manual on purpose. `chezmoi re-add` is not an option here: it skips modify
templates silently, so it reports success and changes nothing. Capturing the live file
automatically would also sweep up machine-local state and overwrite the template expressions
that render per-machine paths.

## Remove a managed file

Deleting only a source entry stops managing its target but usually leaves the live file on
disk. Choose the intended behavior:

| Goal | Action |
| --- | --- |
| Stop managing it and keep the live file | `chezmoi forget <target>` |
| Remove it from the source and this machine | `chezmoi destroy <target>` |
| Remove it from every machine on next apply | Delete its source and add the target path to `home/.chezmoiremove` |

Keep `.chezmoiremove` entries until every managed machine has pulled and applied the change.
Then remove the cleanup entries in a later commit.

### Example: retire a shared skill

A shared skill named `<name>` has two source entries:

| Source file | Purpose |
| --- | --- |
| `home/dot_agents/skills/<name>/` | The skill itself, which Codex and Copilot read directly |
| `home/dot_claude/skills/symlink_<name>.tmpl` | The link that lets Claude Code find it |

Delete both together. The pre-commit hook iterates over source skills, so an orphaned symlink
template passes its checks and then renders a link to a directory that no longer exists.

Deleting the source only stops the skill being managed. It does not remove the skill from a
machine that already applied it, because chezmoi does not delete a target merely because its
source entry is gone. Naming the live targets in `home/.chezmoiremove` is what removes them:

```text
.agents/skills/<name>
.claude/skills/<name>
```

To retire the skill everywhere:

1. Move anything worth keeping into a rule body or another skill **before** deleting, and check
   that it is not already there.
2. Delete the skill directory and its symlink template.
3. Add both target paths to `home/.chezmoiremove`.
4. Run `chezmoi diff` and confirm that the deletions listed are the intended ones and nothing
   else.
5. Run `chezmoi apply -v`, then confirm that `chezmoi status` is empty.
6. Compare file counts against a test render, as under
   [Source filename rules](#source-filename-rules).
7. Commit the source deletions together with the `.chezmoiremove` change.
8. Remove the cleanup entries once every machine has applied them, and delete
   `home/.chezmoiremove` if it is then empty.

`.chezmoiremove` is a template, so an entry can be wrapped in a conditional when the target
exists on only one operating system.

### Example: retire a shared instruction

1. Delete `home/.chezmoitemplates/rules/<name>.md` and both client wrappers.
2. Delete the rule's entry from `home/.chezmoidata.yaml`.
3. Add `.claude/rules/<name>.md` and
   `.copilot/instructions/<name>.instructions.md` to `home/.chezmoiremove`.
4. Apply the change, then remove the cleanup entries after every machine has applied them.

## Daily commands

Before `chezmoi apply`, run the identity check in
[`AGENTS.md`](../AGENTS.md#before-you-finish). Every chezmoi command reports its configured
source directory, which may reach this repository through a symlink or Windows junction, so
the displayed path is not proof.

```bash
chezmoi source-path                 # identify the source behind a live target
chezmoi edit ~/.bashrc              # edit a source by target path
chezmoi diff                        # preview live changes
chezmoi apply -v                    # write reviewed changes
chezmoi re-add ~/.bashrc            # preserve a plain live edit
chezmoi update -v                   # pull and apply on another machine
chezmoi cd                          # launch a shell in the working tree; exit to leave
chezmoi status                      # empty means fully applied
```

Because chezmoi copies rather than links, editing a live file does not appear in `git status`.
Use `chezmoi edit`, or run `chezmoi re-add` afterward for a plain file.

## Source filename rules

Chezmoi reads attributes from the start of source filenames. These names are significant:

| Situation | Source name | Consequence if missed |
| --- | --- | --- |
| Target starts with `.` | `dot_zshrc` | The target becomes `zshrc` instead of `.zshrc` |
| Real name starts with an attribute-like prefix | `literal_create_validation_image.py` | Chezmoi consumes `create_` as an attribute |
| Empty file must exist | `empty___init__.py` | Chezmoi omits an ordinary empty file |
| Application owns an existing file | `create_config.toml.tmpl` | Removing `create_` can overwrite application state |
| File needs template rendering | `name.tmpl` | Removing `.tmpl` writes template syntax literally |
| Target directory also holds unmanaged files | `dot_config`, never `exact_config` | Adding `exact_` makes apply delete every entry in the directory that the source does not contain |

Files beginning with `.` in the source state are ignored. This behavior keeps
`home/.README.md` as repository documentation instead of deploying it.

After a bulk move, test-render and compare file counts because filename transformations can
silently omit files:

```bash
chezmoi apply --destination="$(mktemp -d)" --exclude=scripts
# compare rendered counts with the corresponding source tree
```

Always use `--exclude=scripts` for a test render. The flag excludes chezmoi script entry
types, not the repository's top-level `scripts/` directory.

## Operating-system differences

The source supports operating-system differences in three ways:

1. Use `{{ if eq .chezmoi.os "windows" }}` inside a template.
2. Use `home/.chezmoiignore` to exclude the other operating system's VS Code profile tree.
3. Render a template as empty when the target should not exist on the current system.

Derive home paths from `{{ .chezmoi.homeDir }}` inside templates. Never hardcode a user
directory.

### Line endings

[`.gitattributes`](../.gitattributes) pins every file to LF with `* text=auto eol=lf`, and keeps
explicit `text eol=lf` lines for shell scripts and shell profiles so binary misdetection cannot
leave CRLF in an interpreter line.

That rule exists because chezmoi copies source bytes verbatim. A CRLF working copy renders CRLF
targets, and `chezmoi diff` then reports whole-file differences that contain no changed words.
Before the rule, 215 of 327 tracked files were checked out CRLF by `core.autocrlf`, and that
noise hid a real two-line change inside a 118-line diff. [ADR-0010](./decisions/0010-normalize-the-working-tree-to-lf.md)
records the decision and the alternatives.

`chezmoi diff` should now show only hunks that change content. Treat an EOL-only hunk as a
symptom, not as background churn: it means some file reached the working tree with CRLF.

**Check endings with Git, not with `grep`.** Two obvious checks silently report clean on a CRLF
file, and both have produced a wrong answer here. Git Bash strips CR from text-mode input before
`grep` sees it, and `\r` in a POSIX basic regular expression matches a literal `r`. Use:

```bash
git ls-files --eol | awk '{print $2}' | sort | uniq -c   # whole repository
tr -cd '\r' < path/to/file | wc -c                       # one file, 0 when clean
```

If a file does come back CRLF, restore it from the index rather than editing endings by hand.
`git checkout-index -a -f` alone will not do it, because it honors the stat cache and leaves
existing files in place:

```bash
git status --porcelain                    # must be empty first
git ls-files -z | xargs -0 rm -f
git checkout-index -a -f
git add --renormalize .                   # refresh index stat entries; stages no content
```

Git reports every restored file as modified until that last command runs. `git diff --stat`
stays empty throughout, which is how you tell a stat-cache artifact from a real change.
