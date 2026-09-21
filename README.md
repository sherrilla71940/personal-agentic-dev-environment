# Personal Cross-Platform Developer Environment for Agentic Workflows

[English](README.md) · [繁體中文](README.zh-TW.md)

This repository is a cross-platform developer environment and agentic workflow system, with managed
dotfile configuration and client-native integrations for Claude Code, Codex, and GitHub Copilot. That
client list can evolve as the repository changes. The explicit workflow handles isolated tasks,
local automated verification, a separate user manual-test gate, and cross-session project
continuity.

[Chezmoi](https://www.chezmoi.io/) renders managed source state into native targets while Git remains
authoritative for tracked source state, branches, and commits. Verification results and the user's
manual approval still determine whether the task is actually complete. Project continuity preserves
the context that Git cannot: what a task means, where a session stopped, and what the next session
must do.

**Jump to:**

- [System at a glance](#system-at-a-glance)
- [Project continuity](#project-continuity)
- [Task lifecycle and isolated worktrees](#task-lifecycle-and-isolated-worktrees)
- [Profiles and AI harness modes](#profiles-and-ai-harness-modes)
- [Repository layout](#repository-layout)

> ⚠️ **Personal configuration:** This repository contains my preferences, not a neutral default.
> On an existing machine, review `chezmoi diff` and apply only the targets you intend to change.
> Apply the repository broadly only where replacing these personal values is acceptable.

## What this gives you

| Pillar | Result |
| --- | --- |
| One source, native targets | Shared AI instructions and reusable AI skills have one source body. Thin wrappers preserve each client's native discovery and scope rules. |
| Profiles without duplicated trees | Machine-local selectors compose personal or company context with a managed or native AI harness, plus an independent continuity preference. |
| Continuity across sessions and clients | One `.project-continuity/state.md` stays with one physical worktree so another supported session can resume from the same objective, decisions, blockers, materials, verification state, and next action. |
| Isolated, reviewable tasks | An explicit workflow pins the base, creates a task worktree and branch, provisions only approved ignored local files, runs local automated checks, then asks the user for a separate manual test before publishing without deleting the branch. |

Ownership boundaries and validation support all four pillars; they are guarantees across the system,
not a separate fifth pillar.

The repository also keeps application-owned preferences local, supports Windows and macOS paths,
and records architectural trade-offs in [decision records](./docs/decisions/README.md).

## System at a glance

`home/` is the chezmoi source state for this repository's dotfiles and AI configuration. The
home-directory files are native targets that applications read. `scripts/` and `docs/` support both
the configuration and workflow planes with bootstrap, diagnostics, installers, tests, and decision
records.

```mermaid
flowchart TB
    subgraph configuration["Configuration plane"]
        aiSources["Managed AI sources<br/>home/ · shared instructions · portable skills<br/>client-specific instructions<br/>skills · agents · commands · config"]:::source
        compose["Chezmoi composition<br/>source files · .chezmoitemplates<br/>profile selectors"]:::process
        adapt["Native delivery<br/>wrappers · links/symlinks<br/>client metadata · discovery"]:::process
        targets["Native targets<br/>Claude Code · Codex · GitHub Copilot<br/>VS Code · managed dotfiles"]:::target
        aiSources --> compose
        compose --> adapt --> targets
    end

    subgraph workflow["Task workflow plane"]
        task["Explicit task workflow<br/>base · worktree · approved files"]:::process
        state["Isolated worktree ↔ continuity state<br/>.project-continuity/state.md"]:::state
        verify["Local checks → user approval"]:::check
        authority["Git authority<br/>code · branch · commits<br/>completion still needs verification"]:::authority
        task --> state --> verify --> authority
    end

    aiSources -. workflow skills .-> task
    state -. reconcile .-> authority

    classDef source fill:#dbeafe,stroke:#2563eb,color:#111827
    classDef process fill:#f3e8ff,stroke:#9333ea,color:#111827
    classDef target fill:#dcfce7,stroke:#16a34a,color:#111827
    classDef state fill:#fef3c7,stroke:#d97706,color:#111827
    classDef check fill:#f3e8ff,stroke:#9333ea,color:#111827
    classDef authority fill:#f3f4f6,stroke:#4b5563,color:#111827

    style configuration fill:transparent,stroke:#4b5563,stroke-width:1px
    style workflow fill:transparent,stroke:#4b5563,stroke-width:1px
```

`home/` contains both plain chezmoi source files and templates. Reusable bodies in
`.chezmoitemplates/` feed thin client wrappers; portable skills remain a shared source and use
links or symlinks when a client needs a native discovery location. Client-specific sources stay in
their native directories.

The workflow uses client-native capabilities when they satisfy the contract. Repository-owned
fallbacks cover the remaining invariants: an exact `origin/<base>` contract, portable state,
approved ignored-file provisioning, focused verification, manual approval, optional runtime
isolation, and explicit workflow archives. See [native-first worktree delegation](./docs/worktree-provisioning.md#native-first-delegation)
for the client-specific details.

## Start here

- Set up a new or existing machine with the [setup guide](./docs/setup.md). Review `chezmoi diff`
  before applying changes to an existing home directory.
- Learn the source-versus-target boundary and daily commands in the
  [chezmoi workflow](./docs/chezmoi-workflow.md).
- For a substantial or isolation-sensitive task, read the
  [worktree provisioning guide](./docs/worktree-provisioning.md).

## Profiles and AI harness modes

Three machine-local selectors change the rendered client configuration and behavior. The selectors
are not committed.

~~~toml
[data]
ai_context = "company"        # personal or company
ai_continuity = "on"          # on or off
ai_harness = "managed"        # managed or native
~~~

```mermaid
flowchart TB
    baseline["Shared baseline"]:::base
    context["ai_context<br/>personal | company"]:::choice
    harness["AI harness<br/>managed | native"]:::choice
    continuity["ai_continuity<br/>on | off"]:::choice
    compose["Compose rendered profile"]:::process
    effective{"Effective combination"}:::check
    managedOn["managed + on<br/>automatic continuity guidance and reporting"]:::result
    managedOff["managed + off<br/>no automatic continuity; managed notifications and launch check remain"]:::result
    native["native + on/off<br/>continuity skill remains explicit"]:::result

    baseline --> compose
    context --> compose
    harness --> compose
    continuity --> compose
    compose --> effective
    effective -->|"managed + on"| managedOn
    effective -->|"managed + off"| managedOff
    effective -->|"native + on/off"| native

    classDef base fill:#dbeafe,stroke:#2563eb,color:#111827
    classDef choice fill:#f3e8ff,stroke:#9333ea,color:#111827
    classDef process fill:#f3e8ff,stroke:#9333ea,color:#111827
    classDef check fill:#f3f4f6,stroke:#4b5563,color:#111827
    classDef result fill:#dcfce7,stroke:#16a34a,color:#111827
    class baseline base
    class context,harness,continuity choice
    class compose process
    class effective check
    class managedOn,managedOff,native result
```

| Selector | Controls | Default and boundary |
| --- | --- | --- |
| `ai_context` | Personal or company context, artifact-language default, and the default comment language for application and project repositories. | Missing means `personal`; other values fail rendering. |
| `ai_continuity` | The managed-mode continuity preference. | Missing means `on`; `off` removes automatic continuity guidance and reporting. Native mode suppresses the effective behavior but preserves the value. |
| `ai_harness` | The complete managed AI harness or the lower-opinionated native AI harness. | Missing means `managed`; other values fail rendering. `ai_workflow` remains a legacy alias only when `ai_harness` is absent. |

An **AI harness** is the repository's instruction, skill, lifecycle, and delivery layer around an AI
client. It is not a hosted model or model runtime. Managed mode adds repository-owned lifecycle
guidance and reporting; native mode keeps the shared AI content and client-native delivery surfaces
while leaving those workflow actions explicit.

The rendered composition is `shared baseline + context + AI harness behavior + effective continuity`.
Managed AI harness mode also adds lifecycle reporting, notifications, and Claude's worktree-launch
check. Native AI harness mode keeps shared instructions, skills, statusline, lightweight
notifications, delivery wrappers, and private-file protection, but leaves continuity and worktree
lifecycle actions explicit. Neither mode starts a state-changing workflow implicitly.

Selector changes affect newly rendered configuration and newly started sessions. This repository's
root `AGENTS.md` requires the effective `personal` context while work happens here, even on a
machine whose selector is `company`. The artifact-language default affects commit and worktree
request text and selected Copilot guidance; it does not translate branch names, paths, commands,
user-level dotfiles, or this README.

Read the [AI profile section of the chezmoi workflow](./docs/chezmoi-workflow.md#machine-local-ai-profile-selectors)
and the [customization support guide](./docs/customization-support.md#ai-profile-dimensions) for
the full composition rules.

## Project continuity

Continuity belongs to one physical working tree. It is a local handoff record, not project
documentation and not proof that work is complete. Each physical worktree has at most one active
`.project-continuity/state.md`; a newly created worktree starts without another worktree's continuity
state.

```mermaid
flowchart TD
    stop["One session or client stops"]:::handoff
    persist["The same physical worktree keeps<br/>.project-continuity/state.md<br/><br/>objective · decisions · blockers<br/>verification · materials · next action"]:::state
    resume["Another supported session or client<br/>opens the same worktree and resumes"]:::handoff
    reconcile["Reconcile the state with the current task<br/>and the worktree's Git status"]:::check
    git["Git remains authoritative<br/>for code · branch · commits<br/>completion still needs verification"]:::authority
    continue["Continue, verify, or close the task<br/>and checkpoint the next handoff"]:::work
    durable["Durable handoff / reference / issue record<br/>when information must outlive local state"]:::handoff

    stop --> persist --> resume --> reconcile --> git --> continue --> persist
    persist -. "outlives local state" .-> durable
    durable -. "pointer in state.md" .-> persist

    classDef handoff fill:#dbeafe,stroke:#2563eb,color:#111827
    classDef state fill:#fef3c7,stroke:#d97706,color:#111827
    classDef check fill:#f3e8ff,stroke:#9333ea,color:#111827
    classDef authority fill:#f3f4f6,stroke:#4b5563,color:#111827
    classDef work fill:#dcfce7,stroke:#16a34a,color:#111827
```

Local continuity state is the working-session record. When information must outlive that state—or a
decision is deferred or unresolved—the workflow uses a durable handoff, reference, or issue record
and keeps its pointer in `state.md`.

The state records the objective, phase, decisions, assumptions, blockers, verification state,
material references and provenance, and the next action. Claude Code and Codex report lifecycle
events automatically in managed mode when continuity is enabled. Copilot can follow the same
protocol without an automatic lifecycle hook, and native mode keeps the continuity skill
available for explicit use.

Git remains the authority when state and the checkout disagree. Continuity never replaces a
commit, branch check, test result, or user approval. If implementation differs from an approved
artifact, classify the difference as accepted scope, a deferred dependency, or an unresolved
decision; the latter two need a durable handoff or issue record, with only its pointer kept in
`state.md`.

The state is Git-ignored for privacy and convenience. It is not encrypted and must not contain
credentials. When a different unfinished task starts in the same physical directory, the existing
state is parked under `.project-continuity/parked/` instead of being overwritten. See the
[worktree continuity boundary](./docs/worktree-provisioning.md#how-each-worktree-receives-ignored-files)
and the [continuity skill](./home/dot_agents/skills/project-continuity/SKILL.md).

## Source state and native targets

Chezmoi treats the files under `home/` as **source state**: the configuration this repository
edits and commits. The files written into the home directory are **targets**: the files tools and
applications read. The root `.chezmoiroot` selects `home/`; applying the repository does not create
a `~/home/` directory.

When changing a managed setting, edit the source under `home/`, preview the rendered result with
`chezmoi diff`, and apply only after reviewing the target changes. Leave application-owned values in
the target unless you intentionally promote them into repository ownership.

Source filenames carry behavior. `dot_` becomes a leading `.`, `.tmpl` enables rendering, and
prefixes such as `create_`, `modify_`, and `symlink_` control target handling. Read the
[source-state rules](./docs/chezmoi-workflow.md#source-filename-rules) before adding or renaming a
source file.

The repository keeps shared content shared without pretending that clients are interchangeable:

| Content | Source and delivery |
| --- | --- |
| Shared AI instructions | One body is inlined into Claude, Codex, and Copilot native files. Thin wrappers add only the metadata each client supports. Codex receives no imports or path-scoped rules. |
| Portable skills | One real skill under `home/dot_agents/skills/` renders to `~/.agents/skills`. Claude reaches portable skills through individual symlinks; host-gated metadata prevents a Codex-targeted skill from automatic invocation by the wrong host. |
| Client-specific skills, agents, commands, and MCP | Native files remain under the relevant client source directory. The repository does not create a misleading tool-neutral copy. |
| OS-specific files | Shared bodies use wrappers for Windows and macOS target paths. |

The [AI customization support table](./docs/customization-support.md#what-the-support-table-answers)
maps each capability to its source path and every client surface that reads it. It also documents
the full adapter matrix, current discovery paths, and the rule for adding a Codex-targeted skill.

The main workflow skills stay focused: [worktree-task-workflow](./home/dot_agents/skills/worktree-task-workflow/SKILL.md)
coordinates the lifecycle, [project-continuity](./home/dot_agents/skills/project-continuity/SKILL.md)
owns the handoff state, and [worktree-manifest](./home/dot_agents/skills/worktree-manifest/SKILL.md)
reviews or creates the approved ignored-file allowlist. Runtime isolation remains a separate
project-provided descriptor and [focused guide](./docs/worktree-runtime.md).

## Task lifecycle and isolated worktrees

The task workflow is an explicit opt-in for substantial, parallel, or isolation-sensitive work. A
small self-contained edit can remain in the current valid worktree. The user may clarify the request,
provide materials, or give feedback at any point; the manual-test loop below is the explicit
pre-publish gate.

```mermaid
sequenceDiagram
    participant W as Workflow
    participant G as Git / worktree
    participant C as Continuity state
    participant U as User

    Note over W: Receive request and supplied materials
    Note over W,G: <base> branch = task start + PR/MR target
    Note over W: Fetch and resolve exact origin/<base> commit
    W->>G: Check for or create the isolated task worktree
    W->>G: Start the task branch from the exact origin/<base> commit
    W->>G: Check the reviewed worktree manifest<br/>copy only approved ignored local files
    Note over W: Implement the scoped change
    W->>C: Update continuity throughout<br/>checkpoint decisions, blockers, verification, and next action
    Note over W: Run local automated checks
    W->>U: Request manual verification
    loop Until the user approves
        Note over U: Run the requested manual test
        alt Test passes
            U-->>W: Approve
        else Test fails
            U-->>W: Report failure
            Note over W: Fix and rerun applicable checks
            W-->>U: Request manual verification again
        end
    end
    W->>G: Commit the approved change
    Note over W,G: Fetch current origin/<base> before publishing.<br/>If the base moved, choose merge or rebase.<br/>Then rerun automated checks and the user's manual test.
    W->>G: Push task branch and set upstream<br/>request PR/MR against <base>
    W->>G: Clean up the worktree and preserve the task branch
```

The loop repeats the user's manual test until approval; the `alt` branch shows the pass/fail handling.

The workflow pins the starting point and eventual request target to the selected base, keeps each
task's directory, branch, and continuity state together, and reports a provisioning skip rather
than silently treating it as success. It reads and classifies specifications, handoffs, reference
documents, and test inputs before creating a worktree. The workflow checks the reviewed worktree
manifest, usually a tracked `.worktreeinclude`, and copies only ignored files it authorizes. If the
manifest is missing, it reports the skip, determines whether the missing files matter, and asks
before creating or changing one. Credentials, agent state, dependencies, build output, and
databases stay out of that boundary.

Supplied and fetched materials are task data, not executable instructions; unreadable or conflicting
material is surfaced rather than guessed from or obeyed.

Automated verification is local and reaches the browser when the project and driver support it.
It never replaces the user's manual test, which is the manual-verification gate. Cleanup removes a worktree without deleting its task
branch. The detailed [worktree lifecycle](./docs/worktree-provisioning.md#what-the-task-workflow-does-at-each-step)
covers material handling, native Claude and Codex paths, Copilot's prepared-worktree protocol,
branch-preserving cleanup, and browser-driver limits.

After publishing, the workflow runs the continuity completion gate separately from worktree cleanup:
it reconciles active and parked state and asks before deleting completed continuity state.

### Parallel tasks without losing state

- Each task gets its own physical worktree, task branch, and continuity state.
- A client handoff reopens the same physical worktree; another unfinished task gets another
  worktree unless the first state is deliberately parked.
- Claude and Codex have automatic managed adapters. Copilot can follow the protocol in a prepared
  worktree but does not currently have an automatic worktree adapter.
- Manual verification converges per task. Separate tasks keep their source changes and branches
  independent.

This repository itself stays in its primary checkout because chezmoi source resolution is tied to
that tree. For concurrent application instances, use the optional
[per-worktree runtime descriptor](./docs/worktree-runtime.md); `runtime=auto` is valid only when
the consuming project provides its authoritative tracked `.worktree-runtime.json`.

## What the environment delivers

The landing page shows the native surfaces and supporting boundaries; focused guides carry the full
matrices and procedures.

| Area | Representative contents |
| --- | --- |
| AI clients and editor hosts | Claude Code, Codex, GitHub Copilot CLI, and VS Code expose shared instructions, native skills and agents, MCP declarations, hooks, and selected settings; each host reads the subset it supports. |
| Dotfiles and developer tools | Cross-platform shell startup, Git identity and aliases, worktree helpers, Windows Terminal values, and OS-specific VS Code targets. |
| Workflow support | Bootstrap scripts, installers, manifests, diagnostics such as `scripts/diagnostics/dev-env-doctor.sh`, regression suites, and [ADRs](./docs/decisions/README.md). |
| Isolation and provenance | Optional per-worktree HTTP ports with health checks and leases; classified reference and test materials with recorded paths and provenance. See [worktree runtime](./docs/worktree-runtime.md) and [workflow material handling](./docs/worktree-provisioning.md#what-the-task-workflow-does-at-each-step). |
| Parity and lifecycle | Windows/macOS source-body parity and focused checks. Archives act on explicit tracked source inventories; generated targets use chezmoi removal, while continuity, secrets, and application state stay outside. See [workflow archives](./docs/workflow-archives.md). |

The developer-experience layer includes a cross-platform Claude status line:

![Three status-line rows: model and effort level with the session name; the working directory and
Git branch with a dirty-file count; and the context used alongside both rate-limit windows with
their reset times.](./docs/images/statusline.png)

The status line shows the model and effort level, session name, working directory, Git branch and
file status, context usage, and the five-hour and seven-day rate-limit windows with their reset
times. Bash and PowerShell implementations are parity-checked and measure CJK and emoji width for
narrow terminals.

## Ownership and privacy boundaries

For application-owned configuration, the repository claims the narrowest useful surface: deliberate
durable keys or structures. Volatile preferences, authentication, history, caches, session/runtime
state, and future application-owned values remain local unless intentionally promoted into repository
ownership.

| Target | Repository owns | Application or user owns |
| --- | --- | --- |
| Claude `settings.json` | Durable environment, hooks, status line, and update-channel values through a deep-merge template. | Model, effort, theme, permissions, plugins, project state, and future keys. |
| Codex `config.toml` | Defaults only when the file does not exist. | Existing trust, runtime, marketplace, and session state. |
| Windows Terminal `settings.json` | Selected durable values and the complete `actions` and `keybindings` arrays. | Generated profiles and other unnamed settings. |
| VS Code user files | Tracked settings, keybindings, and MCP sources through OS-specific wrappers. | Workspace storage, authentication, extension caches, and runtime data. |
| Claude user MCP state | Non-secret declarations through an add-missing installer. | Authentication and the rest of `~/.claude.json`. |

The global Git exclude file protects private client files and continuity state from accidental
tracking:

~~~text
**/.claude/settings.local.json
**/CLAUDE.local.md
**/AGENTS.override.md
/.project-continuity/
~~~

The ignore policy does not copy files into worktrees and does not encrypt them. MCP configuration
may contain placeholders such as `\${input:figma-api-key}` or `\${GITHUB_MCP_TOKEN}`, never their
values. Authenticate clients locally and keep credentials out of `home/`.

## Validation and regression coverage

The repository uses local automated suites and an explicit user manual-test gate. No repository CI
workflow is configured, so a passing local suite is not a claim that CI ran.

The pre-commit hook renders staged source into a temporary directory, never into the home directory,
and checks:

- source identity and every staged path, which matters because this checkout's Git index is shared;
- filename-attribute safety and skill file-count parity;
- Claude skill links and Codex host gates;
- byte-identical shared rule bodies between Claude and Copilot;
- no YAML frontmatter in Codex's rendered `AGENTS.md`;
- Bash and PowerShell status-line parity when either implementation changes; and
- relative Markdown links and heading fragments.

Run the focused suites by hand when the protected behavior changes:

| Behavior | Local check |
| --- | --- |
| Windows worktree provisioning | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-git-worktree-provision.ps1` |
| macOS worktree provisioning | `bash scripts/tests/test-git-worktree-provision.sh` |
| Continuity lifecycle and recovery | `bash scripts/tests/test-project-continuity-hook.sh` |
| AI profile composition and selectors | `bash scripts/tests/test-ai-configuration-profiles.sh` |
| Workflow archive, restore, and deletion | `bash scripts/tests/test-workflow-archive.sh` |
| Runtime descriptor, allocation, and port lease | `python scripts/tests/test-worktree-runtime.py -v` |

On Windows PowerShell, run Bash-based suites through
`.\scripts\tests\run-git-bash-tests.ps1`; it resolves Windows Git Bash explicitly. The continuity
fixtures under `scripts/tests/continuity-fixtures/` are manual model-behavior probes, not live
automated agent tests. They use throwaway repositories and deliberately fabricated `state.md`
files; never treat a fixture state as the real working tree state.

## Repository layout

~~~text
home/                              chezmoi source state
  .chezmoidata.yaml                shared rule globs
  .chezmoitemplates/               shared bodies and OS-neutral data
  dot_agents/skills/               portable and host-gated skills
  dot_claude/                      Claude Code files and adapters
  dot_codex/                       Codex files and create-once config
  dot_copilot/                     Copilot CLI files, agents, and skills
  AppData/ · Library/              Windows and macOS VS Code targets
  dot_bashrc · dot_zshrc.tmpl      shell startup files
  dot_gitconfig.tmpl               Git identity and global excludes link
  dot_config/git/ignore             private AI and continuity excludes
  dot_local/share/                 worktree, runtime, and notification helpers

scripts/bootstrap/                 manual new-machine setup
scripts/install/                   Claude MCP installers
scripts/manifests/                 MCP, VS Code extension, and workflow declarations
scripts/workflows/                 archive and deletion tooling
scripts/diagnostics/               doctor, usage, and drift reports
scripts/tests/                     profile, continuity, worktree, and runtime suites
scripts/git-hooks/                 pre-commit and Markdown link validation
archives/workflows/                tracked reusable workflow archives
docs/                              setup, workflow, customization, and ADR guides
~~~

## Where to go next

| I want to… | Read |
| --- | --- |
| Set up or update the machine | [docs/setup.md](./docs/setup.md) |
| Add, change, or remove a managed file | [docs/chezmoi-workflow.md](./docs/chezmoi-workflow.md) |
| Add an instruction, skill, agent, prompt, MCP server, or plugin | [docs/customization-support.md](./docs/customization-support.md) |
| Find which client surface reads a customization | [the support table](./docs/customization-support.md#what-the-support-table-answers) |
| Run an isolated task or provision ignored local files | [docs/worktree-provisioning.md](./docs/worktree-provisioning.md) |
| Run parallel application instances | [docs/worktree-runtime.md](./docs/worktree-runtime.md) |
| Archive, restore, or delete a reusable workflow | [docs/workflow-archives.md](./docs/workflow-archives.md) |
| Understand why the repository uses this structure | [docs/decisions/README.md](./docs/decisions/README.md) |
| Understand why a rule exists before removing it | [docs/rule-rationale.md](./docs/rule-rationale.md) |
| Let a coding assistant work safely in this repository | [AGENTS.md](./AGENTS.md) |

Every structural choice has a written reason. Read the relevant ADR before changing a
repository-wide mechanism, ownership boundary, or client integration. Discovery paths,
frontmatter keys, hook payloads, and worktree behavior change with upstream releases; verify
version-sensitive details against the current [chezmoi](https://www.chezmoi.io/reference/source-state-attributes/),
[Claude Code](https://code.claude.com/docs/en/overview),
[Codex](https://learn.chatgpt.com/docs/agent-configuration/agents-md), and
[VS Code agent customization](https://code.visualstudio.com/docs/agent-customization/overview)
documentation before changing a client-specific path or key.
