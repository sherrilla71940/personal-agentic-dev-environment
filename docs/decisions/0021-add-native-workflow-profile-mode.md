# ADR-0021: Add a native workflow profile mode

- Status: Superseded by ADR-0022
- Date: 2026-09-17

> This decision records the first, narrower native-mode implementation. ADR-0022 replaces its
> public selector name with `ai_harness` and broadens native mode to disable the automatic harness
> hooks while preserving the statusline and shared capabilities.

## Context

ADR-0014 introduced independent machine-local context and continuity selectors. The repository
also contains an automatic lifecycle harness: Claude Code and Codex hooks report continuity state,
detect recorded Git drift, and surface cleanup candidates. Some machines need the shared
instructions, rules, and reusable skills without that repository-specific orchestration. They
should be able to keep the knowledge layer while using the clients' native behavior by default.

Coupling workflow mode to `ai_continuity` would remove a useful independent choice. Removing the
hook entries would also break Claude's unrelated worktree launch check and invalidate Codex's
per-entry hook trust. The mode therefore needs to change the helper's behavior without changing
hook registration or deleting any skill.

## Decision

Extend the machine-local profile schema with this independent selector:

| Selector | Supported values | Missing-key default |
| --- | --- | --- |
| `ai_workflow` | `managed`, `native` | `managed` |

The three selectors compose as follows:

```text
shared baseline + personal OR company context
continuity guidance when ai_continuity=on
automatic lifecycle reporting when ai_continuity=on and ai_workflow=managed
```

The modes mean:

- `managed` preserves the existing automatic continuity lifecycle behavior when
  `ai_continuity=on`.
- `native` keeps shared instructions, rules, and reusable skills, but makes continuity manual and
  renders the shared lifecycle helper as a no-op. When `ai_continuity=on`, the rendered guidance
  tells the client to use continuity only for an explicit user request.
- `ai_continuity=off` still removes the always-loaded continuity guidance regardless of workflow
  mode. The continuity skill remains installed for explicit requests in every combination.
- The worktree-task and worktree-manifest skills remain explicit opt-ins in every combination.
  Selecting `native` does not prevent a user from explicitly invoking one of those workflows.

Hook entries remain registered in every mode. This preserves Claude's independent worktree launch
check and Codex's hook trust, while the shared helper decides whether automatic continuity behavior
is active. Context and workflow mode never change one another, and profile selection never changes
automatically during archive or restore operations.

## Alternatives considered

### Couple native mode to continuity off

Rejected because a user may want continuity guidance available for explicit manual use while
disabling automatic lifecycle reporting. Independent selectors make that choice visible rather
than hiding one setting's effect inside another.

### Remove or conditionally register hook entries

Rejected because Claude's hook array also carries the worktree launch check, and Codex trusts hook
entries by path and content hash. Re-registering a different hook set would remove an unrelated
warning or require a new trust decision after a mode change.

### Remove workflow and continuity skills in native mode

Rejected because native mode changes automatic orchestration, not the available capabilities. A
user can still explicitly opt into a repository workflow when needed.

### Add a separate configuration tree for native mode

Rejected because it would duplicate shared instructions and skills. The existing template
composition can express the behavior through one resolver and a small mode-specific branch.

## Consequences

There are eight valid combinations across context, continuity, and workflow mode. Missing keys
remain backward-compatible: an existing machine that has only `ai_context` and `ai_continuity`
continues to use managed workflow behavior. Invalid workflow values fail during rendering rather
than producing a partial configuration.

Native mode does not make the repository disappear. It still renders shared instructions, rules,
skills, client adapters, and normal application configuration. It only removes automatic
continuity lifecycle reporting; explicit skills and client-native behavior remain available.

Changing a selector affects newly rendered configuration and newly started sessions. It does not
modify repository source, switch profiles inside a running session, or automatically apply live
configuration. Users still preview with `chezmoi diff`, review it, and apply separately.

## Reconsider when

- a client adds a native workflow mode that conflicts with this repository's manual behavior;
- another automatic harness component needs the same mode gate;
- users need per-session workflow modes instead of one machine-wide choice; or
- explicit workflow skills can no longer safely opt into managed orchestration from native mode.

## Related files and verification

- `home/.chezmoitemplates/ai-profile.yaml` resolves and validates `ai_workflow`.
- `home/.chezmoitemplates/continuity.md` keeps continuity guidance independent while making native
  mode manual.
- `home/dot_local/share/maintain-project-continuity.sh.tmpl` makes automatic lifecycle reporting a
  no-op for native mode without changing hook registration.
- `docs/chezmoi-workflow.md`, `docs/customization-support.md`, and both READMEs document the
  selector and its combinations.
- `home/dot_agents/skills/ai-profile/SKILL.md` routes selection and schema extension using the
  current resolver contract.
- `scripts/tests/test-ai-configuration-profiles.sh` covers all eight combinations, defaults,
  invalid values, hook behavior, and both operating-system render branches.
- Run `bash scripts/tests/test-ai-configuration-profiles.sh`, the repository pre-commit hook, and
  the skill validator for the updated skill metadata.
