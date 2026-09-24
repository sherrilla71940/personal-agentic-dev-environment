# ADR-0022: Define native and managed AI harness modes

- Status: Accepted
- Date: 2026-09-17

## Context

The first native-mode implementation treated the mode as a continuity-only switch. That did not
match the intended boundary. The repository needs a low-opinionated mode for machines that want
the shared instruction and skill library, statusline, and delivery wrappers without repository
specific lifecycle automation. It also needs to retain the current complete automation as an
opt-in managed mode.

The boundary must not remove useful general developer configuration or make explicit workflow
skills unusable. It must also preserve application-owned settings when a machine changes modes.

## Decision

Use `ai_harness` as the public machine-local selector:

| Selector | Supported values | Missing-key default |
| --- | --- | --- |
| `ai_context` | `personal`, `company` | `personal` |
| `ai_continuity` | `on`, `off` | `on` |
| `ai_harness` | `managed`, `native` | `managed` |

`ai_workflow` is accepted only as a backward-compatible alias when `ai_harness` is absent. If
both are present, rendering fails. New configuration and documentation use `ai_harness`.

The effective composition is:

```text
shared baseline + selected context
managed harness behavior when `ai_harness=managed`
continuity guidance and lifecycle reporting when managed + `ai_continuity=on`
```

The modes have these boundaries:

- **Managed:** preserves the complete repository harness. With `ai_continuity=on`, it loads
  continuity guidance and registers Claude and Codex lifecycle reporting. It also registers
  managed notifications and Claude's automatic worktree-launch check. With continuity off, it
  omits only continuity guidance and continuity hooks; the other managed hooks remain.
- **Native:** keeps shared instructions and context, reusable skills, the statusline, lightweight
  notifications, required client delivery wrappers and symlinks, and private-file protections. It
does not load continuity guidance or register repository-owned continuity or automatic
worktree-launch lifecycle hooks. The `task-continuity`, worktree, workflow-deletion, and task
workflow skills remain explicitly invokable; native mode does not automatically run them.

`ai_context` and `ai_harness` are independent inputs. `ai_continuity` remains stored as a
managed-mode option. Native mode suppresses its effective guidance and automation without changing
the preference, so returning to managed mode with continuity on restores that behavior. General
shell, Git, VS Code, and Windows Terminal configuration remains outside `ai_harness` and is not
removed when native mode is selected.

The harness boundary does not change skill invocation policy. State-changing skills such as
task continuity, worktree provisioning, workflow deletion, and the task workflow remain
explicit-only in every mode. Managed hooks can report lifecycle events, but they do not implicitly
start a workflow or alter source state.

Claude's settings modify template filters only the repository's known hook commands when a mode
removes them, preserving unrelated application or user hooks. Codex retains its lightweight
notification hook in native mode, omits continuity lifecycle entries there, and may require a new
`/hooks` approval when switching modes because Codex trusts each entry by path and content hash.
The Claude statusline remains managed in every mode.

## Alternatives considered

### Keep native mode as continuity-off only

Rejected because it leaves automatic worktree safety active, which violates the low-opinionated
native boundary. Notifications are intentionally retained as lightweight feedback.

### Remove all skills and wrappers in native mode

Rejected because native mode is a lower-automation harness, not an empty client installation.
Shared instructions, reusable skills, statusline delivery, and cross-client wrappers are useful
without lifecycle automation.

### Use a separate native source tree

Rejected because it duplicates shared instructions, skills, and client adapters and would drift.
One resolver and small conditional branches preserve one source of truth.

### Let the harness selector control shell, Git, editor, and terminal settings

Rejected because those are general developer-environment capabilities, not AI harness behavior.
Changing harness mode should not unexpectedly change a font, editor preference, or Git setting.

### Keep all lifecycle hook entries permanently registered and make only the helpers no-op

Rejected because native mode should not register its continuity and worktree lifecycle hooks. The
lightweight notification hook is intentionally registered in both modes. The resulting Codex trust
reapproval cost for switching lifecycle hooks is documented and accepted.

## Consequences

The machine has eight selector combinations, but their effective automation is explicit: native
always disables automatic harness behavior, while managed still respects `ai_continuity`. Switching
profiles changes newly rendered files and newly started sessions; it does not alter the stored
selector values of another machine, change a running session, or run `chezmoi apply` automatically.

The profile resolver exposes derived values for continuity guidance, continuity automation,
notifications, the worktree guard, and statusline so diagnostics and the profile skill can report
the effective result rather than infer it. Notifications are on in both modes; the worktree guard
is on only in managed mode.

The source still ships dormant hook scripts in native mode because they are repository-managed
targets and may be needed when the machine returns to managed mode. Only registration is gated.
Workflow deletion remains a separate source-management workflow and never switches profiles or
applies generated targets. Git history provides recovery for tracked source after deletion.

## Reconsider when

- a client changes its hook trust or discovery contract;
- another automatic harness component needs a native/managed boundary;
- users need per-session rather than machine-wide harness selection; or
- general developer settings become intentionally profile-specific.

## Related files and verification

- `home/.chezmoitemplates/ai-profile.yaml` resolves the selectors and derived behavior.
- `home/.chezmoitemplates/continuity.md` gates always-loaded continuity guidance.
- `home/.chezmoitemplates/claude/settings-durable.json` and `home/dot_codex/hooks.json.tmpl`
  gate client hook registration while retaining the Claude statusline.
- `home/dot_claude/modify_settings.json` removes only known repository hook commands from live
  Claude settings when required.
- `home/dot_agents/skills/ai-profile/SKILL.md`, the setup and customization guides, and both
  READMEs document selection and mode boundaries.
- `scripts/tests/test-ai-configuration-profiles.sh` covers the selector matrix, defaults,
  invalid values, legacy compatibility, hook behavior, continuity helper behavior, and both OS
  render branches.
- Run that profile suite, the continuity and workflow deletion suites, `python -m py_compile
  scripts/workflows/workflow-delete.py`, and the repository pre-commit hook.
