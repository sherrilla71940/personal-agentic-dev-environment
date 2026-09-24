---
name: ai-profile
description: "Inspect or change this machine's AI profile, or extend the repository's profile schema. Use for profile selectors, context layers, dimensions, or composition rules."
argument-hint: "[show|select|extend] [selector=value ...]"
---

# AI profile

Manage the repository's AI profile without editing generated client files or duplicating profile
trees. The profile resolver and its documentation define the current machine-local inputs. The
current schema exposes two independent inputs and one managed-mode option:

```text
ai_context    = personal | company
ai_harness    = managed | native
ai_continuity = on | off   # managed-mode option
```

The rendered result is:

```text
shared baseline + selected context
managed harness behavior when ai_harness=managed
continuity guidance and lifecycle reporting when managed + ai_continuity=on
```

In the current schema, `personal` is the default context and uses English for applicable artifact
text. `company` uses Traditional Chinese for Taiwan (`zhtw` where an interface uses that value).
`on` is the default continuity preference. `managed` is the default harness and enables the
opinionated automation layer. `native` keeps shared instructions, reusable skills, the statusline,
required delivery wrappers, private-file protections, and lightweight notification feedback, but
does not render continuity guidance or register continuity and automatic worktree safety hooks.
Workflow skills remain available for explicit invocation. General shell, Git, VS Code, and Windows
Terminal configuration is outside the harness selector. Invalid values must fail rendering rather
than produce a partial profile. If the resolver changes, treat its keys, allowed values, defaults,
and derived fields as authoritative and update this summary with the schema change.

## Route the request

- **Show:** Report the raw machine-local values from `chezmoi data`, then report defaults and
  derived values from the resolver with `chezmoi execute-template --file <source>/.chezmoitemplates/ai-profile.yaml`.
  Do not infer a selector from the current client or conversation language. If the current schema
  is unclear, read the resolver and its documentation before reporting it.
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
  `ai_context=company`, `ai_harness=managed`, and `ai_continuity=on`.
- **Harness mode:** Choose `managed` for the complete automation layer or `native` for the
  lower-opinionated layer. Native mode suppresses continuity regardless of the stored preference.
- **Managed-mode option:** Choose `ai_continuity=on|off` when managed mode should include or omit
  continuity guidance and lifecycle reporting. The stored value is preserved while native is active.
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
/ai-profile select ai_context=company ai_continuity=on ai_harness=managed
/ai-profile select ai_harness=native
/ai-profile extend: add a review context layer
/ai-profile extend: add a review-mode selector
```

In Codex CLI or the IDE extension, mention the skill with `$`:

```text
$ai-profile show
$ai-profile select ai_context=company ai_continuity=on ai_harness=native
$ai-profile select ai_harness=managed ai_continuity=off
$ai-profile extend: add a review context layer
$ai-profile extend: add a review-mode selector
```

In Codex, `/skills` lists available skills; it does not invoke this skill. These examples are
prompts, not terminal commands. For Copilot or another host without a documented direct syntax,
use its skill picker when available or use natural language:

```text
Show me the current AI profile.
Switch this machine to company context and use the native harness.
Switch this machine to the managed harness with continuity enabled.
Add a review context layer.
Add a review-mode selector to the profile schema.
```

The first two examples in each client-specific block inspect or select an existing profile. The
last two request repository extension work. The natural-language examples express the same
distinction. Automatic skill selection may load this skill for matching requests, but loading it
does not change configuration; selection and extension still require the confirmations described
below. State-changing workflow skills remain explicit-only in every harness mode; managed lifecycle
hooks do not implicitly start them.

## Shared safety rules

1. Confirm chezmoi's source identity before reviewing or applying rendered configuration:
   `chezmoi source-path` must resolve into this repository checkout. Compare Git repository roots,
   not display strings, because Windows links and junctions can disguise the path.
2. Never edit `.claude/`, `.codex/`, `.copilot/`, VS Code profile files, or other generated home
   targets directly. Edit the source under `home/` and render it.
3. Keep `ai_context` and `ai_harness` independent. Treat `ai_continuity` as a managed-mode option:
   native mode suppresses its effective behavior but does not rewrite the stored value. Do not
   create copied profile trees or make one selector mutate another. Use the resolver as the source
   of truth for the current selector names and values.
4. Show the proposed selector or source change before mutation. Ask for confirmation immediately
   before changing machine-local configuration or repository profile sources, and ask separately
   before `chezmoi apply` because apply can replace live configuration.
5. Preserve application-owned settings. A profile change may alter only the targets shown by the
   reviewed `chezmoi diff`; stop if unrelated drift appears.
6. A selector change affects newly rendered configuration and newly started sessions. Tell the
   user which clients need restarting. A running session keeps its startup context.

## Select an existing profile

Use the supported chezmoi workflow:

1. Run `chezmoi data` for the machine-local input, then render the resolver template to confirm
   defaults and derived behavior. `chezmoi data` alone does not evaluate this repository's
   resolver template, so do not report missing raw keys as missing effective selectors.
2. Show the requested values and their consequences. Explain that the values are machine-local,
   are not committed, and do not synchronize through this repository.
3. After confirmation, use `chezmoi edit-config` to set the values under `[data]`:

   For the current schema, the selector block is:

   ```toml
   [data]
   ai_context = "personal"        # personal or company
   ai_continuity = "on"            # on or off
   ai_harness = "managed"          # managed or native
   ```

   Do not copy this example blindly if the resolver has changed. Preserve unrelated machine-local
   configuration. Do not guess a config path or write it with an ad hoc parser;
   `chezmoi edit-config` is the portable entry point.
4. Run `chezmoi data` and the resolver render again to confirm the requested values and derived
   behavior. Then run `chezmoi diff` and summarize only the expected rendered changes.
5. Ask for confirmation before applying. Run `chezmoi apply` only after the source identity and
   diff checks pass, then run `chezmoi status` and report any remaining drift.
6. Tell the user to restart Claude Code, Codex, and VS Code sessions that should receive the new
   profile. Native mode keeps the statusline, shared instructions, wrappers, protections, and
   explicit workflow skills, and lightweight notifications; it suppresses continuity guidance and
   continuity/worktree lifecycle hooks. General shell, Git, VS Code, and Windows Terminal settings
   are unaffected by this selector.

If the user requests a value the current resolver rejects, stop and report the allowed values from
that resolver. Do not repair an unrelated configuration problem as part of profile selection.

## Extend the profile system

Read the relevant sections before editing:

- [Machine-local AI profile selectors in the chezmoi workflow](../../../../docs/chezmoi-workflow.md)
- [AI profile dimensions in the customization guide](../../../../docs/customization-support.md)
- [ADR-0014](../../../../docs/decisions/0014-machine-local-ai-configuration-profiles.md)
- [ADR-0022](../../../../docs/decisions/0022-define-native-and-managed-ai-harness-modes.md)

Then:

1. Identify whether the request changes an existing value or layer, adds a new context layer,
   adds a new independent selector, or changes how layers compose. The current composition is
   hierarchical: `ai_harness` selects the complete managed harness or the lower-opinionated native
   harness, while `ai_continuity` is a managed-mode option. Native mode suppresses continuity
   without changing the stored preference, and managed mode uses that preference. A new named
   bundle is a schema decision, not a routine selector edit. The legacy `ai_workflow` key is
   accepted only for backward compatibility when `ai_harness` is absent; do not add it to new
   configuration.
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

Keep workflow deletion out of this skill. Git history is the recovery mechanism for tracked
workflow source; this profile skill does not archive or restore workflow definitions.
