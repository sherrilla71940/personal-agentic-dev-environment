---
name: ai-profile
description: "Inspect or change this machine's AI profile, or extend the repository's profile schema. Use for profile selectors, context layers, dimensions, or composition rules."
argument-hint: "[show|select|extend] [selector=value ...]"
---

# AI profile

Manage the repository's AI profile without editing generated client files or duplicating profile
trees. The profile resolver and its documentation define the current machine-local selectors. The
current schema exposes three independent selectors:

```text
ai_context    = personal | company
ai_continuity = on | off
ai_workflow   = managed | native
```

The rendered result is:

```text
shared baseline + selected context + continuity guidance when enabled
automatic lifecycle reporting when continuity is enabled and workflow is managed
```

In the current schema, `personal` is the default context and uses English for applicable artifact
text. `company` uses Traditional Chinese for Taiwan (`zhtw` where an interface uses that value).
`on` is the default continuity state. `managed` is the default workflow mode and enables the
automatic continuity lifecycle helper. `native` keeps the shared guidance and explicit skills but
makes continuity manual and the helper a no-op. Invalid values must fail rendering rather than
produce a partial profile. If the resolver changes, treat its keys, allowed values, defaults, and
derived fields as authoritative and update this summary with the schema change.

## Route the request

- **Show:** Report the effective selectors and derived values from `chezmoi data`. Do not infer a
  selector from the current client or conversation language. If the current schema is unclear,
  read the resolver and its documentation before reporting it.
- **Select:** Change the existing machine-local selector values. This does not modify repository
  source files or commit anything.
- **Extend:** Add or change a context layer, selector dimension, or composition rule in the
  repository source. Treat this as repository architecture work, not machine profile selection.

If a request names only values already accepted by the current resolver, route it to **Select**.
Discover the accepted keys and values from the resolver or its documentation instead of assuming
that today's `personal`, `company`, `on`, and `off` values are permanent. If it asks for a new
profile, context, layer, dimension, or rendering behavior, route it to **Extend**. If the request
does not make that distinction clear and the change would alter source architecture, ask before
editing.

The current implementation does not provide a separate registry of arbitrary named profile
bundles. Treat "create a new profile" as an extension request unless the user is selecting an
existing combination of current selectors.

## Terminology

A **profile** is the complete resolved configuration produced by the current selector schema.
Use these terms to distinguish selection from schema changes:

- **Profile selection:** Choose values already accepted by the current resolver, such as
  `ai_context=company`, `ai_continuity=on`, and `ai_workflow=managed`.
- **Profile schema:** The selector keys, allowed values, defaults, derived fields, and composition
  rules that define how profiles render.
- **Preset:** A named bundle of selector values. The current implementation does not support
  presets; adding one would be an extension to the profile schema.

## Examples

Invocation syntax depends on the client. The skill behavior is shared, but the explicit
invocation marker is client-specific.

In Claude Code, invoke the skill with a slash command:

```text
/ai-profile show
/ai-profile select ai_context=company ai_continuity=on ai_workflow=managed
/ai-profile extend: add a review context layer
/ai-profile extend: add a review-mode selector
```

In Codex CLI or the IDE extension, mention the skill with `$`:

```text
$ai-profile show
$ai-profile select ai_context=company ai_continuity=on ai_workflow=native
$ai-profile extend: add a review context layer
$ai-profile extend: add a review-mode selector
```

In Codex, `/skills` lists available skills; it does not invoke this skill. These examples are
prompts, not terminal commands. For Copilot or another host without a documented direct syntax,
use its skill picker when available or use natural language:

```text
Show me the current AI profile.
Switch this machine to company context, keep continuity enabled, and use native workflow mode.
Add a review context layer.
Add a review-mode selector to the profile schema.
```

The first two examples in each client-specific block inspect or select an existing profile. The
last two request repository extension work. The natural-language examples express the same
distinction. Automatic skill selection may load this skill for matching requests, but loading it
does not change configuration; selection and extension still require the confirmations described
below.

## Shared safety rules

1. Confirm chezmoi's source identity before reviewing or applying rendered configuration:
   `chezmoi source-path` must resolve into this repository checkout. Compare Git repository roots,
   not display strings, because Windows links and junctions can disguise the path.
2. Never edit `.claude/`, `.codex/`, `.copilot/`, VS Code profile files, or other generated home
   targets directly. Edit the source under `home/` and render it.
3. Keep selector dimensions independent unless the documented architecture explicitly changes. Do
   not create copied profile trees or make one selector a side effect of another. Use the resolver
   as the source of truth for the current selector names and values.
4. Show the proposed selector or source change before mutation. Ask for confirmation immediately
   before changing machine-local configuration or repository profile sources, and ask separately
   before `chezmoi apply` because apply can replace live configuration.
5. Preserve application-owned settings. A profile change may alter only the targets shown by the
   reviewed `chezmoi diff`; stop if unrelated drift appears.
6. A selector change affects newly rendered configuration and newly started sessions. Tell the
   user which clients need restarting. A running session keeps its startup context.

## Select an existing profile

Use the supported chezmoi workflow:

1. Run `chezmoi data` and record every effective selector and derived value exposed by the current
   resolver.
2. Show the requested values and their consequences. Explain that the values are machine-local,
   are not committed, and do not synchronize through this repository.
3. After confirmation, use `chezmoi edit-config` to set the values under `[data]`:

   For the current schema, the selector block is:

   ```toml
   [data]
   ai_context = "personal"        # personal or company
   ai_continuity = "on"            # on or off
   ai_workflow = "managed"         # managed or native
   ```

   Do not copy this example blindly if the resolver has changed. Preserve unrelated machine-local
   configuration. Do not guess a config path or write it with an ad hoc parser;
   `chezmoi edit-config` is the portable entry point.
4. Run `chezmoi data` again and confirm the requested values. Then run `chezmoi diff` and summarize
   only the expected rendered changes.
5. Ask for confirmation before applying. Run `chezmoi apply` only after the source identity and
   diff checks pass, then run `chezmoi status` and report any remaining drift.
6. Tell the user to restart Claude Code, Codex, and VS Code sessions that should receive the new
   profile. The worktree and worktree-manifest skills remain available in every combination.

If the user requests a value the current resolver rejects, stop and report the allowed values from
that resolver. Do not repair an unrelated configuration problem as part of profile selection.

## Extend the profile system

Read the relevant sections before editing:

- [Machine-local AI profile selectors in the chezmoi workflow](../../../../docs/chezmoi-workflow.md)
- [AI profile dimensions in the customization guide](../../../../docs/customization-support.md)
- [ADR-0014](../../../../docs/decisions/0014-machine-local-ai-configuration-profiles.md)
- [ADR-0021](../../../../docs/decisions/0021-add-native-workflow-profile-mode.md)

Then:

1. Identify whether the request changes an existing value or layer, adds a new context layer,
   adds a new independent selector, or changes how layers compose. For example, `ai_workflow`
   selects automatic managed orchestration or manual native behavior; it does not change
   `ai_continuity`. A new named bundle is a schema decision, not a routine selector edit.
2. Keep reusable content in shared templates and use thin client wrappers. Do not copy the same
   profile body into Claude, Codex, Copilot, or VS Code outputs.
3. Update the resolver, profile layers, wrappers, and user-facing documentation together when
   their contracts change. Keep Codex's `AGENTS.md` literal and frontmatter-free.
4. Add or update an ADR when the change affects the selector schema, source ownership, rendering
   boundary, or every machine using the repository.
5. Run the profile test suite covering every supported combination, defaults, invalid values, and
   continuity-off behavior. In this repository that is
   `bash scripts/tests/test-ai-configuration-profiles.sh`. Run the repository pre-commit hook for
   cross-client rendering and link checks.
6. Preview the rendered targets with `chezmoi diff`, show the impact, and ask before applying.
7. If selector names, common values, or the invocation surface changed, update this skill's
   current-schema summary and metadata together with the resolver and documentation.

An extension is incomplete if it changes only one client wrapper, one operating system, or one
supported profile combination.

## Report the result

Use this compact report:

```text
Profile selectors: <key=value ...>
Derived values: <key=value ...>
Changed: <machine-local selectors or source files>
Rendered impact: <client surfaces>
Applied: <yes/no>
Restart required: <clients or none>
```

Keep archive/export of workflow definitions out of this skill. That is a separate explicit
workflow with its own manifest, retention, and restoration contract.
