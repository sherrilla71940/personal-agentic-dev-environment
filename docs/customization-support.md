# AI client customization support

This repository manages personal configuration for several local coding-agent clients. A
**surface** is one way to run a client, such as a terminal CLI, an IDE extension, or a
desktop app. Each surface can share some configuration with the others while keeping other
state separate.

The **Model Context Protocol (MCP)** connects a client to external tools and data sources.

## What the support table answers

The table answers: **If this repository manages a customization, which local surface reads
it?** It describes this repository's implementation, not every feature that each product
natively supports.

Paths beginning with `~/` in the table are live **targets** that applications read. Make
durable changes in the corresponding source files under this repository's `home/` directory;
the procedures below identify those source paths.

The columns group surfaces only when they read the same personal configuration:

- **Claude Code local:** Claude Code CLI, its IDE integrations, and the Code tab in Claude
  Desktop. These surfaces share Claude Code configuration under `~/.claude/` and
  `~/.claude.json`.
- **Codex local:** Codex CLI, the Codex IDE extension, and Codex in the ChatGPT desktop app.
  These surfaces share configuration under `~/.codex/`.
- **Copilot CLI** and **VS Code with Copilot:** These surfaces share personal instructions,
  skills, and agents under `~/.copilot/` but keep separate settings, prompts, and MCP files.

| Capability | Claude Code local | Codex local | Copilot CLI | VS Code with Copilot |
| --- | --- | --- | --- | --- |
| Always-on personal instructions | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.copilot/instructions/core.instructions.md` with `applyTo: "**"` | the same personal `*.instructions.md` file |
| Instructions for this repository | root `CLAUDE.md` imports root `AGENTS.md` | root `AGENTS.md` | root `AGENTS.md` | root `AGENTS.md`, enabled by `chat.useAgentsMdFile` |
| Path-scoped instructions | `~/.claude/rules/` | not supported by Codex | `~/.copilot/instructions/*.instructions.md` | the same personal files, selected by `applyTo` |
| Portable shared skills | linked from `~/.agents/skills` | native `~/.agents/skills` discovery | native `~/.agents/skills` discovery | native `~/.agents/skills` discovery |
| `run-task-end-to-end` invocation | Claude adapter presents guided questions through its native structured question surface when available, then falls back to text | Codex adapter uses `request_user_input` when exposed by the current surface, then falls back to text | unsupported; use the documented compatibility boundaries | unsupported; use the documented compatibility boundaries |
| Workflow deletion skill | linked from `~/.agents/skills` | native `~/.agents/skills` discovery | native `~/.agents/skills` discovery | native `~/.agents/skills` discovery |
| Client-only skills | `~/.claude/skills/<name>` | host-gated under `~/.agents/skills/<name>`; Copilot discovers the metadata but cannot invoke it automatically | `~/.copilot/skills/<name>` | `~/.copilot/skills/<name>` |
| Agent definitions | custom subagents under `~/.claude/agents/` | custom agents under `~/.codex/agents/` | custom agents under `~/.copilot/agents/` | the same personal Copilot agents |
| Prompts or commands | `~/.claude/commands/` | standalone custom prompts are deprecated; use a skill | no dedicated Copilot CLI command; compatible Claude commands may also be discovered | prompt files in the VS Code user profile |
| Marketplace plugins | installed by `scripts/bootstrap/bootstrap-*`; enablement stays local | defaults in create-once `config.toml` | declarative `enabledPlugins` with automatic installation | discovers enabled Copilot plugins when `chat.plugins.enabled` is true |
| User MCP servers | manifest plus hand-run installer protects app-owned `~/.claude.json` | defaults in create-once `config.toml` | `~/.copilot/mcp-config.json` | `mcp.json` in the VS Code user profile |
| General settings | partially managed `settings.json`; only env, hooks, status line and update channel are repository-owned | create-once app-owned `config.toml` | managed `~/.copilot/settings.json` | managed VS Code user `settings.json` |

Add an agent or client-only skill only when it has a concrete purpose. Empty prepared
directories exist only where a client requires the directory before a session starts.
Current client-only examples include Claude's `project-orientation` command and Copilot's
`remember` skill. These features stay in their native client sources because their behavior is not
portable across all supported clients.

VS Code lists every shared skill twice. Claude Code reads personal skills only from
`~/.claude/skills`, so this repository links each shared skill there, and VS Code scans both
that directory and `~/.agents/skills`. Both entries resolve to the same file, so the effect is
cosmetic. It cannot be configured away: `home/.chezmoitemplates/vscode/settings.json` suppresses
the same duplication for rules with `chat.instructionsFilesLocations`, and VS Code exposes
`chat.promptFilesLocations` for prompt files, but there is no equivalent setting for skills.

## AI profile dimensions

The repository exposes two independent machine-local inputs plus one managed-mode option:
`ai_context` (`personal` or `company`), `ai_harness` (`managed` or `native`), and
`ai_continuity` (`on` or `off`). Claude Code and Codex use all three inputs for their instruction
and hook outputs. The managed VS Code Copilot commit-message instruction uses the context-derived
artifact language. Missing values default to `personal`, `managed`, and `on`; unsupported values
fail during rendering. `ai_workflow` remains a legacy alias for `ai_harness` when the new key is
absent. The rendered configuration is the shared baseline plus one context layer. Continuity
guidance and automatic lifecycle reporting are effective only when `ai_continuity=on` and
`ai_harness=managed`.

Managed mode is the complete opinionated harness: it registers continuity reporting, notifications,
and Claude's automatic worktree-launch check when applicable. Native mode is the low-opinionated
layer: it keeps shared instructions, reusable skills, the statusline, lightweight notifications,
delivery wrappers, and private-file protections, but does not load continuity guidance or register
continuity/worktree lifecycle hooks. Workflow skills remain discoverable and explicitly invokable
in native mode. General shell, Git, VS Code, and Windows Terminal settings are not controlled by
`ai_harness`.

This repository is an explicit exception: its root `AGENTS.md` is a repository
instruction that overrides the machine default and requires the effective context to be
`personal` while work is performed here.

Personal context defaults applicable artifact language to English (`en`). Company context defaults
it to Traditional Chinese (`zh-TW`, `zhtw` in existing command interfaces), and recommends or
loads `natural-zhtw` where that language is produced. Explicit language arguments and repository
instructions take precedence. User-level configuration and customization source remains English
in both contexts; application/project comment language follows the active context unless the
repository or project says otherwise. Continuity state remains English.

Turning continuity off removes the always-loaded continuity instructions and unregisters the
continuity lifecycle hook, but managed notifications and the Claude worktree-launch check remain.
Native mode unregisters the continuity and worktree lifecycle hooks but retains lightweight
notifications. The `task-continuity` skill stays installed, so an explicit continuity request
can still invoke it; returning to managed mode with continuity on restores the automatic behavior.
Because Codex records trust for each hook entry by path and content hash, switching harness modes
may require a new `/hooks` approval. Native mode is lower-opinionated, not notification-free.
State-changing workflow skills—including task continuity, worktree provisioning, workflow deletion,
and the task workflow—are explicit-only in every client and harness mode. Git history is the
recovery mechanism for tracked workflow source; the repository no longer provides archive or restore
skills. Managed hooks may report lifecycle
events, but they never start a worktree or change source state.
Worktree workflow and worktree manifest remain independently available as explicit skills in all
selector combinations and do not toggle continuity. Broad Copilot integration—skill discovery,
repository instructions, and agent plugins—is unchanged and deferred. See [ADR-0014](./decisions/0014-machine-local-ai-configuration-profiles.md)
for the design boundaries. See [ADR-0022](./decisions/0022-define-native-and-managed-ai-harness-modes.md)
for the native-versus-managed harness decision.

### Surfaces outside this table

This repository does not manage complete product or account state:

- Claude Desktop chat and Cowork do not consume every Claude Code file listed above. In
  particular, MCP servers configured for the desktop chat app are separate from the Code
  tab.
- Claude.ai connectors, authentication, conversations, and account settings remain with the
  signed-in account.
- `~/.codex/rules/` is not instruction scoping despite the name. It stores Codex's command
  approval decisions as `prefix_rule(...)` entries, the equivalent of a permission
  allow-list, and is app-owned machine state. Codex still has no path-scoped instructions.
- Codex cloud receives repository files such as root `AGENTS.md` when the repository is
  available to the cloud task. It does not receive personal files from this machine's
  `~/.codex/` directory through chezmoi.
- Copilot cloud features can read supported files committed inside a repository. This
  this setup does not copy personal `~/.copilot/` runtime state into GitHub.

## Choose where a customization goes

Use a client directory for client-specific content and a shared directory only when multiple
clients can use the same body:

| Client or scope | Instructions | Skills | Agents | Prompts or commands |
| --- | --- | --- | --- | --- |
| Claude Code | `home/dot_claude/rules/` | `home/dot_claude/skills/` | `home/dot_claude/agents/` | `home/dot_claude/commands/` |
| Codex | `home/dot_codex/AGENTS.md.tmpl` | shared or host-gated skills | `home/dot_codex/agents/` | use a skill |
| GitHub Copilot | `home/dot_copilot/instructions/` | `home/dot_copilot/skills/` | `home/dot_copilot/agents/` | VS Code profile wrappers |
| Shared | `home/.chezmoitemplates/` | `home/dot_agents/skills/` | not shared | not shared |

Some apparently missing directories are intentional:

- Codex personal skills use `~/.agents/skills`, which Copilot also scans. A Codex-targeted
  skill therefore needs host gates rather than relying on directory isolation. Follow the
  procedure under [Add a skill](#add-a-skill).
- Codex standalone custom prompts are deprecated. Use a skill instead of creating
  `home/dot_codex/prompts/`.
- VS Code reads `*.prompt.md` from its user profile, not from `~/.copilot/prompts/`.
- Codex has no personal path-scoped rules directory.

## Add a new client directory

Do not assume that a client reads every directory under its configuration folder. Before
adding a directory:

1. Verify the directory path and file format in the client's current official documentation.
2. Confirm that the directory contains portable configuration rather than credentials,
   caches, logs, history, or other runtime state.
3. Add each file under the matching source path:

   | Live directory | Source directory |
   | --- | --- |
   | `~/.claude/<folder>/` | `home/dot_claude/<folder>/` |
   | `~/.codex/<folder>/` | `home/dot_codex/<folder>/` |
   | `~/.copilot/<folder>/` | `home/dot_copilot/<folder>/` |

4. Run `chezmoi diff`, apply the change, restart the client when required, and confirm that
   the client discovers the file.

If the file already exists in the live directory and is not managed yet, import its target
path:

```bash
chezmoi add ~/.claude/<folder>/<file>
```

Check first with `chezmoi source-path <target>`. If it resolves, the file is already managed —
edit that source instead. `chezmoi add` on a managed `modify_` or `create_` source deletes it
without asking.

If you create the file directly under this repository's `home/` source state, do not run
`chezmoi add`. A directory containing managed files is created automatically. Do not add an
empty directory unless the client explicitly requires one.

For example, Claude Code does not currently document `~/.claude/workflows/` as a discovery
directory. Represent a reusable Claude workflow as a skill instead:

- Claude-only: `home/dot_claude/skills/<name>/SKILL.md`.
- Portable across Claude, Codex, and Copilot: `home/dot_agents/skills/<name>/SKILL.md` plus
  its Claude symlink wrapper.

### Delete a reusable workflow

Workflow deletion is repository tooling, not another client customization directory. The
`workflow-delete` skill accepts a workflow name or description, performs bounded discovery, and
shows the exact source/dependency/target boundary before mutation. The shared engine under
`scripts/workflows/` deletes only confirmed canonical source files and queues generated-target
cleanup through `home/.chezmoiremove`; it never deletes live targets directly or changes
continuity state.

Git is the recovery mechanism for tracked source. Use `git log` to locate the relevant commit and
`git restore --source <commit> -- <paths>` after reviewing the diff. Read the
[workflow deletion guide](./workflow-deletion.md) for the definition fields, discovery boundary,
Git recovery, chezmoi removal behavior, and focused test suite.

## Add an instruction

### One client

Add a plain file to that client's source directory. Include the client's required
frontmatter, but do not create a shared template. For example, a Claude-only Python rule can
live at `home/dot_claude/rules/python.md`:

```markdown
---
paths:
  - "**/*.py"
---

# Python guidelines

- ...
```

The Copilot equivalent is
`home/dot_copilot/instructions/<name>.instructions.md` with `applyTo:` frontmatter. Put
Claude-only always-on content in `home/dot_claude/CLAUDE.md.tmpl` below the
`# Claude Code only` marker.

Keep an instruction client-specific when it names that client's tools or behavior. Do not
create a tool-neutral paraphrase solely to make it shareable.

### Multiple clients

When Claude and Copilot can share the same instruction body:

1. Add the body without frontmatter at `home/.chezmoitemplates/rules/<name>.md`.
2. Add its file pattern and title to `home/.chezmoidata.yaml`.
3. Add a thin `.tmpl` wrapper under both clients' instruction directories.
4. Run `chezmoi diff`, apply, and verify that the rendered bodies match.

A **thin wrapper** adds client-specific frontmatter and includes the shared body. The Copilot
JavaScript wrapper shows each template element:

```gotemplate
{{- /* Generated from .chezmoitemplates/rules/javascript.md -- edit the body there, not here. */ -}}
---
applyTo: "{{ (index .rules "javascript").glob }}"
description: '{{ (index .rules "javascript").title }} rules, shared with Claude Code.'
---

{{ includeTemplate "rules/javascript.md" -}}
```

| Syntax | Effect |
| --- | --- |
| `{{- /* ... */ -}}` | Adds an optional source comment that is removed from the target |
| YAML between `---` lines | Writes Copilot frontmatter to the target |
| `{{ (index .rules "javascript").glob }}` | Reads the file pattern from `home/.chezmoidata.yaml` |
| `{{ includeTemplate "rules/javascript.md" -}}` | Renders the shared instruction body |
| `-` beside a template delimiter | Trims adjacent whitespace |

Claude uses a separate wrapper with `paths:` frontmatter. Do not add a Codex wrapper for a
language rule: Codex cannot path-scope it, so the rule would become always-on.

## Edit the shared working agreement

The rendered `~/.claude/CLAUDE.md` combines shared and Claude-only sources:

| Change | Source | Shortcut | Clients reached |
| --- | --- | --- | --- |
| Shared working agreement | `home/.chezmoitemplates/core.md` | `dotf-core` | Claude, Codex, and Copilot |
| Claude-only addition | `home/dot_claude/CLAUDE.md.tmpl` | `dotf-claude` | Claude only |

The `dotf-*` shortcuts are aliases defined in `home/dot_bashrc` and `home/dot_zshrc.tmpl`, so
they exist in bash and zsh only. In PowerShell, run the chezmoi commands directly.

Use the shared body only when the text remains correct for all three clients.
`chezmoi edit ~/.claude/CLAUDE.md` opens the Claude wrapper, not the included shared body.
After editing, run `dotf-diff` and `dotf-apply` or the equivalent chezmoi commands.

## Add a skill

Choose the source path according to who should discover the skill:

| Scope | Source |
| --- | --- |
| Portable across all three clients | `home/dot_agents/skills/<name>/SKILL.md` plus `home/dot_claude/skills/symlink_<name>.tmpl` |
| Codex-targeted; not linked into Claude and blocked from automatic Copilot invocation | `home/dot_agents/skills/<name>/` with a `.codex-only` marker and no Claude symlink |
| Claude-only | `home/dot_claude/skills/<name>/SKILL.md` |
| Copilot-only | `home/dot_copilot/skills/<name>/SKILL.md` |

The Claude symlink template points to
`{{ .chezmoi.homeDir }}/.agents/skills/<name>`. Individual links allow shared and Claude-only
skills to coexist in `~/.claude/skills/`.

Check a portable skill for client-specific tool names before sharing it. Because these are
source-state changes, run `chezmoi diff` and `chezmoi apply`; do not run `chezmoi add`.

### Give the skill a way to be reached

A skill that nothing points at is unlikely to be used. An earlier local-session audit found that
every skill that had been invoked was named explicitly in always-on context — a rule body,
`core.md`, or the continuity bootstrap — and no skill without such a reference had run. Description
quality was not what separated them; routing was. Treat that observation as a historical finding,
not a current usage measurement.

So name a new skill from the instruction that covers its topic, the way
`home/.chezmoitemplates/rules/accessibility.md` ends by pointing at `accessibility-review`.
Without that, expect it to sit unused however good its description is, and prefer folding its
content into an existing rule to adding a skill nothing reaches.

`scripts/diagnostics/claude-config-usage.sh` reports which managed skills are actually being invoked, so this
is worth re-measuring rather than assuming. Read a zero as a lower bound: a skill marked
`user-invocable: false`, or one whose guidance was followed without a tool call, looks the same
there as one that was ignored.

### Add a Codex-targeted skill

Use this exception when Codex needs an on-demand workflow that must not become a portable skill.
Two cases qualify: Claude and Copilot already receive equivalent native configuration, such as
path-scoped instructions; or the same workflow has a separate Claude adapter because the clients'
tools and lifecycle differ, while Copilot is deliberately unsupported. Both Codex and Copilot
discover personal skills under `~/.agents/skills`, so the skill cannot rely on its directory to
stay private.

Create the skill with all of these gates:

1. Add an empty source-only marker at
   `home/dot_agents/skills/<name>/.codex-only`. Chezmoi ignores the dotfile, while the
   repository hook uses it to distinguish the skill from portable skills.
2. Do not add `home/dot_claude/skills/symlink_<name>.tmpl`; this keeps Claude from
   discovering the skill.
3. Set `disable-model-invocation: true` in `SKILL.md`. Copilot still discovers the skill in
   `~/.agents/skills`, but does not invoke it automatically.
4. Add `agents/openai.yaml` with an explicit Codex invocation policy. Use `false` for a
   state-changing or side-effectful skill, and use `true` only when implicit Codex invocation is
   safe and deliberate:

   ```yaml
   policy:
     allow_implicit_invocation: false
   ```

5. Start the skill body with a host guard that tells GitHub Copilot to stop and states whether
   equivalent native instructions are already active or the workflow is unsupported there. This
   also protects against an explicit Copilot invocation.

Validate these skills with `scripts/git-hooks/pre-commit`, not Codex's generic
`skill-creator/scripts/quick_validate.py`. The generic validator accepts only its single-host
frontmatter schema, so it rejects client-specific fields used in this repository, including
`disable-model-invocation`, `argument-hint`, and `user-invocable`. Do not remove a required field
or install PyYAML only to make that validator pass. The repository hook renders the staged source
and checks the `.codex-only` host gates.

For a portable skill that changes repository state, add the same explicit-only boundary to its
`SKILL.md` with `disable-model-invocation: true` and to its Codex metadata with
`allow_implicit_invocation: false`. Keep this policy separate from `ai_harness`: managed mode may
register lifecycle hooks, but it does not make source-changing workflows implicit.

When another host adapter shares workflow guidance, keep detailed references as thin templates
that include one existing shared body. Do not copy that body into each skill.

## Add an agent definition

- Claude Code: add `home/dot_claude/agents/<name>.md`.
- Codex: add `home/dot_codex/agents/<name>.toml`.
- Copilot: add `home/dot_copilot/agents/<name>.agent.md`.

Use each client's native schema. Agents are client-specific unless current official
documentation confirms that every field and behavior is portable.

The clients use overlapping terminology for related concepts:

- Claude Code calls files in `agents/` **custom subagents**.
- Codex calls them **custom agents** and uses them when spawning subagent sessions.
- Copilot calls them **custom agents**; its main agent can select one directly or run one as
  a **subagent** with a separate context.

## Add a prompt or command

- Claude Code commands go in `home/dot_claude/commands/`.
- VS Code prompt files have one body under `home/.chezmoitemplates/vscode/` and thin
  OS-specific wrappers in the VS Code profile trees.
- Do not create `home/dot_codex/prompts/`; Codex standalone custom prompts are deprecated.
  Create a skill for a reusable Codex workflow.

VS Code can discover instruction files from several user folders, including Claude's. This
repository disables `~/.claude/rules` in `chat.instructionsFilesLocations` and disables
`chat.useClaudeMdFile`, so Copilot receives the managed Copilot wrappers once without also
loading Claude-only instructions. Keep those exclusions when changing VS Code settings.

## Add an MCP server

### Claude Code

User-scoped MCP configuration shares `~/.claude.json` with authentication, project state,
and caches, so chezmoi must not overwrite that file. Add a non-secret definition to
`scripts/manifests/claude-user-mcp-servers.json`, then run the platform installer:

```bash
bash scripts/install/install-claude-mcp.sh
```

```powershell
powershell -File scripts/install/install-claude-mcp.ps1
```

The installer adds missing definitions with `claude mcp add-json --scope user` and leaves an
existing server of the same name unchanged for manual review. Authentication remains local.

That manifest intentionally contains only directly configured user MCP servers. Claude can
show additional MCP-backed tools from other sources, and those should stay with their owner:

| Source | This setup | How it follows machines |
| --- | --- | --- |
| Direct user MCP | Chrome DevTools, GitLab, GitHub | the manifest and hand-run installer |
| Enabled Claude plugin | Figma and Playwright MCP servers | `claude plugin install` in `scripts/bootstrap/bootstrap-*` |
| Claude.ai connector | Figma and Slack | the signed-in Claude account; authenticate through `/mcp` |
| Claude in Chrome | browser tools exposed by the Chrome extension integration | install the extension, then use `/chrome`; its onboarding and enablement state is app-owned |

Do not duplicate a plugin server, Claude.ai connector, or Claude in Chrome integration in the
user manifest merely because it appears in `/mcp`. Run `claude mcp list` or `/mcp` to inspect
the combined effective set.

### Codex

Add non-secret defaults to `home/dot_codex/create_config.toml.tmpl`. They reach a new machine
only when `~/.codex/config.toml` does not exist. For an existing live config, compare the
desired blocks and merge only what is missing; do nothing when those declarations are already
present. Never replace the complete live file, because Codex also writes marketplace metadata,
runtime paths, project trust, and other machine state there. Complete authentication locally.

### GitLab, on every client

The self-managed instance at `gitlab.dtdi.com.tw` exposes GitLab's built-in MCP server over
HTTP at `/api/v4/mcp`, so every client uses the remote endpoint and none runs a local server
process. Authentication is OAuth, so no token appears in this repository and none is needed in
the environment either: the instance publishes `registration_endpoint` in
`/.well-known/oauth-authorization-server`, meaning dynamic client registration is enabled and
each client registers itself on first connection.

The scope is `mcp`, which is an OAuth scope rather than a personal access token scope, so it
does not appear on GitLab's token page. A personal access token is the fallback if an
administrator turns dynamic client registration off; it would need `read_api` and
`ai_features`, passed as an `Authorization` header.

Complete authentication locally, once per client. In Claude Code a newly added server is not
visible until a new session starts, because MCP configuration is read at session start.
Codex's declaration reaches only a machine without `~/.codex/config.toml`; add it by hand or
with `codex mcp add` on a machine that already has one.

### GitHub, on every client

GitHub's hosted MCP server at `https://api.githubcopilot.com/mcp/` covers pull requests,
issues and reviews on github.com. It authenticates with a personal access token rather than
OAuth: its protected-resource metadata names `https://github.com/login/oauth` as the
authorization server but publishes no registration endpoint, and Claude Code rejects the
server outright with `Incompatible auth server: does not support dynamic client registration`.
This is the opposite of the GitLab instance, which does support registration and needs no
token at all.

No token is stored here. The command-line clients read `GITHUB_MCP_TOKEN` from the
environment, and VS Code prompts for `${input:github-pat}` and keeps it in its own secret
storage. Set the variable per machine with a token scoped to `repo`, adding `read:org` for
organization repositories; the server's metadata lists every scope it accepts, and the rest
are worth reading before granting more.

The `gh` command-line interface remains the simpler route for ordinary pull request work and
needs no MCP server or token at all. Prefer it when a session only has to open or review a
pull request, and keep this server for work that genuinely needs tool calls.

### GitHub Copilot

Add CLI-compatible servers to `home/dot_copilot/mcp-config.json`. Add VS Code servers to
`home/.chezmoitemplates/vscode/mcp.json` when the IDE also needs them. The schemas and input
mechanisms differ, so share a server definition only when both clients support its fields.

## Add a marketplace plugin

Here, **declarative** means the repository records which plugin should be enabled, while the
client downloads and manages the plugin files. The downloaded cache is not copied into the
developer environment repository. Claude Code is the exception: its plugins are installed by the bootstrap
scripts rather than declared, so enabling and disabling them stays a local decision.

- Claude Code: add the plugin to the `claude plugin install` list in both
  `scripts/bootstrap/bootstrap-macos.sh` and `scripts/bootstrap/bootstrap-windows.ps1`, with its marketplace
  ahead of it if that marketplace is not registered automatically. The repository installs
  Claude plugins rather than declaring them, so enabling and disabling stays local — see
  [ADR-0005](./decisions/0005-merge-durable-claude-settings-as-json.md).
- Codex: add its marketplace and plugin defaults to
  `home/dot_codex/create_config.toml.tmpl`; merge only missing declarations into an existing
  app-owned config.
- Copilot: add the plugin specification to `enabledPlugins` in
  `home/dot_copilot/settings.json`. Copilot CLI declaratively installs enabled plugins, and
  VS Code discovers the resulting installation.

Prefer editing the source declaration before installing. If Copilot CLI has already added a
plugin to the live `~/.copilot/settings.json`, preserve it before the next apply:

```bash
chezmoi diff
chezmoi re-add ~/.copilot/settings.json
```

Review the source diff before committing. This works because Copilot's settings file is a
plain managed file. Claude has no declaration to preserve, because its plugins are installed
by the bootstrap scripts instead. For Codex's create-once config, follow the client-specific
steps above instead.

Never copy plugin caches, installed-plugin directories, authentication tokens, or client
runtime state into `home/`.

## Verify after applying

- Claude Code: run `claude mcp get chrome-devtools`, then inspect `/agents`, `/skills`, and
  `/plugin` in a new session as relevant to the change.
- Codex: start a new session and inspect its agents, skills, plugins, or MCP tools. Existing
  `~/.codex/config.toml` files need the documented comparison; merge only when the desired
  declaration is missing.
- Copilot CLI: inspect `~/.copilot/settings.json` and `~/.copilot/mcp-config.json`, then start
  a new session. In VS Code, use **Chat: Open Customizations** for agents, instructions,
  prompts, and skills.

## Official references

- [Claude Code configuration directory](https://code.claude.com/docs/en/claude-directory)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Claude Code Desktop and shared configuration](https://code.claude.com/docs/en/desktop)
- [Claude Code in VS Code](https://code.claude.com/docs/en/vs-code)
- [Claude Code custom subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code MCP sources](https://code.claude.com/docs/en/mcp)
- [Claude Code with Chrome](https://code.claude.com/docs/en/chrome)
- [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex skills](https://developers.openai.com/codex/skills)
- [Codex custom agents and subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [VS Code custom instructions](https://code.visualstudio.com/docs/agent-customization/custom-instructions)
- [VS Code custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)
- [VS Code agent skills](https://code.visualstudio.com/docs/agent-customization/agent-skills)
- [Copilot CLI configuration directory](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- [GitHub Copilot agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- [GitHub Copilot CLI skill reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#skills-reference)
- [GitHub Copilot custom agents](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-custom-agents)
