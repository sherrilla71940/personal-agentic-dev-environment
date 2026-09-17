# ADR-0014: Compose machine-local AI configuration profiles

- Status: Accepted
- Date: 2026-09-14

This decision remains in force as the v1 baseline for the two selectors it introduced. ADR-0021
extends that schema with an independent workflow-mode choice; references below to exactly two
selectors or four combinations describe this record's original scope, not the current schema.

## Context

The developer environment repository serves personal and company machines from one cross-platform chezmoi
source tree. The existing Claude Code, Codex, Copilot, skill, hook, and worktree configuration
already provides the required behavior, but it assumes one context and always-on automatic
project continuity. The repository needs two independent machine-local choices without creating
duplicated configuration trees.

The two choices have different lifecycles. The context changes language defaults and workflow
conventions. Continuity controls automatic startup and stop handling for a working-tree-local
state file. Combining them into one selector would make valid combinations unavailable and would
make language and lifecycle changes harder to reason about.

## Decision

Keep one canonical source tree and compose three layers at render time:

```text
shared baseline + personal OR company context + continuity when enabled
```

Use these two machine-local selectors in the chezmoi configuration file's `[data]` section:
ADR-0021 adds `ai_workflow` as a third independent selector.

| Selector | Supported values | Missing-key default |
| --- | --- | --- |
| `ai_context` | `personal`, `company` | `personal` |
| `ai_continuity` | `on`, `off` | `on` |

The values do not live in the repository. Chezmoi's shared templates read them from each
machine's local config file, and a shared resolver validates them before returning the selected
context, continuity state, and artifact language. Unsupported values fail during rendering.

The context selects the default language for applicable artifacts:

- `personal` selects English (`en`).
- `company` selects Traditional Chinese for Taiwan (`zh-TW`, represented as `zhtw` where an
  existing interface uses that value).

A personal machine can omit `ai_context` entirely. A work machine opts in by setting
`ai_context = "company"` with `chezmoi edit-config`, which keeps the company choice explicit and
machine-local rather than inherited by every machine that clones this repository.

The developer environment repository is a deliberate repository-level exception either way. Its root
`AGENTS.md` treats the effective context as `personal`, so changes to this user-level
configuration remain English even on a machine explicitly set to `company`.

Explicit language arguments remain authoritative. The default applies to `git-commit-action`,
the worktree workflow's invocation and publishing guidance, and the managed VS Code Copilot
commit-message setting. Technical identifiers, filenames, branch names, commit types, user-level
configuration comments, and continuity state remain in English. Application/project comments
follow the selected context unless repository or project instructions override it.

Continuity remains independent of context. When it is `on`, Claude Code and Codex receive the
existing continuity instructions and the shared lifecycle helper reports as before. When it is
`off`, the always-loaded instructions are omitted and that helper renders as a deliberate no-op: it
drains the event payload, prints nothing, and writes nothing, so neither a tracked state file nor
`.git/info/exclude` changes. The `project-continuity` skill stays installed so an explicit user
request can still invoke it, and the existing session-export decisions remain part of that skill.

Hook wiring is identical in both states, and the guard alters no app-owned configuration.

Worktree workflow and worktree manifest capabilities remain independently available in both
contexts. The worktree workflow may use project continuity when continuity is enabled, but neither
worktree capability is a profile toggle.

Claude Code and Codex keep separate native adapters. Codex continues to receive one literal,
frontmatter-free `AGENTS.md`. The canonical `git-commit-action` skill remains one rendered skill;
only its default language is templated. The managed VS Code settings source remains JSONC with its
comments and trailing commas.

## Alternatives considered

### Four duplicated profile trees

Rejected because every skill, instruction, hook, and adapter change would need four copies. The
duplication would drift and would violate the repository's existing shared-body architecture.

### A third user-facing language selector

Rejected because language is a consequence of the selected context in v1. Explicit invocation
arguments already provide an escape hatch for an individual artifact.

### Tracked selector values

Rejected because a personal/company choice and continuity choice belong to one machine, not to the
shared repository. Tracking them would silently force one machine's context onto another.

### A profile CLI or per-session isolation

Deferred. The selectors are machine-wide in v1, so simultaneous sessions on one machine cannot
safely use different contexts. A dedicated CLI and per-session isolation need a separate lifecycle
and ownership design.

### Disabling continuity by removing hook entries

Rejected after it regressed an unrelated capability. Claude's `SessionStart` array carries both the
worktree launch check and the continuity hook, so gating the array removed the warning that another
session already occupies a working tree. Codex also records hook trust in `config.toml` keyed by
each entry's path and content hash, so rewriting an entry on every toggle invalidates that approval
and forces a fresh `/hooks` confirmation per machine. Guarding inside the shared helper keeps both
clients' hook configuration byte-identical across a toggle and leaves the worktree check active.

### Removing the continuity skill when continuity is off

Rejected because `off` disables automatic lifecycle behavior, not explicit continuity operations.
Deleting the skill would remove a supported user-requested workflow.

### Broad Copilot integration

Deferred. V1 keeps existing Copilot instruction discovery, skill discovery, agent plugins, and
repository instruction behavior unchanged. Only the managed VS Code commit-message setting follows
the context default.

## Consequences

Within this decision's original scope, newly rendered configuration was deterministic for all four
combinations. The current schema, extended by ADR-0021, is deterministic for all eight combinations.
Changing a selector does not modify tracked source files and does not automatically apply the result.
Users must preview with `chezmoi diff`, apply only after reviewing the preview, and restart Claude
Code, Codex, or VS Code so a new session reads the rendered configuration.

Already-running sessions retain the startup context they already loaded. The selectors are
machine-wide, so users who need concurrent personal and company sessions must use separate machines
or a future per-session design.

The repository must keep testing both OS-specific VS Code source branches. No JSONC parser is
installed on the host, so the portable shell test carries a small string-aware one: it removes
comments and trailing commas outside string literals and parses the result as JSON. The managed
source therefore keeps its comments, trailing commas, and strings containing URLs, and still fails
the test on a structural error that balanced delimiters alone would not catch.

## Related files and verification

- `home/.chezmoitemplates/ai-profile.yaml` resolves and validates the selectors.
- `home/.chezmoitemplates/core.md`, `profiles/`, and `continuity.md` compose the instruction layers.
- Claude, Codex, and VS Code wrappers pass the root template data explicitly.
- `home/dot_local/share/maintain-project-continuity.sh.tmpl` carries the continuity-off no-op guard.
- `scripts/tests/test-ai-configuration-profiles.sh` renders all combinations defined by the current
  schema, defaults, and invalid values without changing live targets. It asserts that the worktree
  launch check survives every continuity/workflow mode, and runs the rendered helper against a
  throwaway repository to prove that automatic lifecycle reporting is quiet when disabled.
- Run `bash scripts/tests/test-ai-configuration-profiles.sh` from Git Bash or macOS Bash, then run the
  repository pre-commit hook for staged-source rendering and cross-client structural checks.

## Revisions

- 2026-09-14: the missing-key default for `ai_context` changed from `company` to `personal`. The
  original value preserved the previous unconditional zh-TW comment rule for application
  repositories, but it also meant that a machine which had never been configured produced
  Traditional Chinese artifacts, including on a personal machine and on a fresh clone. Making
  `personal` the fallback keeps the company choice explicit and machine-local, which is the point
  of the selector. Nothing else in this record changed: the composition model, the continuity
  semantics, the worktree independence, and the rejected alternatives all still hold.
