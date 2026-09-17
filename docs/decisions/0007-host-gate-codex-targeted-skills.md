# ADR-0007: Host-gate Codex-targeted skills

- Status: Accepted
- Date: 2026-08-25
- Amended: 2026-09-17

## Context

[ADR-0002](./0002-share-cross-tool-configuration-with-thin-wrappers.md) established that a
shared body is rendered into a per-tool wrapper, and left one case open: "Codex personal skills
normally live in `~/.agents/skills`, which Copilot also scans. Treat them as portable shared
skills. If one must be Codex-only, verify the current supported isolation options rather than
assuming a plugin is required."

One case is path-scoped guidance. Codex cannot path-scope an instruction, so a rule that Claude
receives as `~/.claude/rules/<name>.md` with `paths:` and Copilot as an `.instructions.md` with
`applyTo:` has no Codex equivalent. The remaining way to give Codex the same guidance on demand
is a skill. But `~/.agents/skills` is a shared discovery path: Codex, Copilot CLI and VS Code all
read it natively, so a skill placed there for Codex alone is visible to Copilot too, which already
has the path-scoped version. Directory placement cannot isolate it.

A second case is a workflow whose contract is shared but whose execution adapter is inherently
host-specific. Claude Code and Codex can each support `worktree-task-workflow`, but Claude uses
`EnterWorktree` and `ExitWorktree` while Codex uses an already-associated worktree and app-owned
Handoff and retention. One supposedly portable skill would either contain misleading tool names
or make every host load instructions for the other. Copilot does not support this workflow here.

Since ADR-0002 the isolation options were checked. No supported per-tool skill root exists, and
no plugin is required.

## Decision

Keep such a skill in `~/.agents/skills` and isolate it by host gates rather than by location.
A Codex-targeted skill carries all five:

1. An empty source-only marker at `home/dot_agents/skills/<name>/.codex-only`. Chezmoi ignores
   the dotfile; the pre-commit hook reads it to tell the skill apart from a portable one.
2. No `home/dot_claude/skills/symlink_<name>.tmpl`, so Claude Code never discovers it.
3. `disable-model-invocation: true` in `SKILL.md`, so Copilot discovers it but does not choose
   it.
4. `agents/openai.yaml` with an explicit `allow_implicit_invocation` policy. Use `false` for a
   state-changing or side-effectful skill, and use `true` only when implicit Codex invocation is
   safe and deliberate.
5. A host guard at the top of the body telling GitHub Copilot to stop. It states whether
   equivalent native instructions are already active or the workflow is unsupported there. This
   covers an explicit Copilot invocation, which gate 3 does not prevent.

Gates 3 and 4 independently declare how each host may invoke the skill. They do not imply that a
Codex-targeted skill should always be implicitly invokable.

The pre-commit hook enforces the set, so a skill cannot be marked `.codex-only` and then lose a
gate silently.

## Alternatives considered

- **A separate Codex-only skill directory:** no supported per-tool skill root exists. Copilot
  scans `~/.agents/skills` natively and offers no setting to exclude a path.
- **Distribute the skill as a Codex plugin:** heavier than the problem, and ADR-0002 already
  cautioned against assuming a plugin is required before checking.
- **Let Copilot invoke it:** rejected. Depending on the use case, Copilot would either hold a
  second route to guidance it already receives or attempt a workflow built on another host's
  lifecycle.
- **Give Codex nothing:** rejected. Codex would silently lack guidance the other two receive,
  and the gap would be invisible rather than declared.

## Consequences

Isolation depends on five separate conditions rather than a directory, so it is easy to get
partly right. That is why the hook checks it and why the procedure is written out in
[docs/customization-support.md](../customization-support.md#add-a-codex-targeted-skill).

`worktree-task-workflow` is the first skill gated this way; it was named
`frontend-task-workflow` until 2026-09-02, when it was renamed because nothing in it is
frontend-specific and the worktree precondition is what both adapters actually share.
Its Codex adapter lives under `home/dot_agents/skills/`, while its Claude adapter remains
under `home/dot_claude/skills/`.
Their invocation, implementation, manual-test and publishing rules come from shared template
bodies; their worktree entry and cleanup mechanics remain host-specific.

`worktree-task-workflow` is state-changing, so its Codex policy is explicit-only. The portable
`project-continuity` and `worktree-manifest` skills use the same explicit-only policy because they
can create or change working-tree state. Managed lifecycle hooks remain independent: they can
report continuity automatically without implicitly starting any of these workflows.

`project-continuity` was the earlier near miss, carrying a Copilot guard while being symlinked to
Claude. That guard was removed once Copilot CLI was verified to load
`~/.copilot/instructions/**/*.instructions.md` and to read and write the continuity state, so the
skill supports all three clients and is gated for none.

A gated skill is still visible in Copilot's skill list. Gates 3 and 5 stop it being used, not
being seen.

## Reconsider when

- Copilot stops scanning `~/.agents/skills`, or gains a setting to exclude a path, which would
  make a plain directory sufficient.
- Codex gains path-scoped instructions, which would remove the reason for the skill entirely.
- A per-tool skill root appears in any of the three clients.
- `disable-model-invocation` or `allow_implicit_invocation` changes meaning, since the explicit
  invocation safety boundary depends on both hosts honoring those policies.

## Related files and verification

- [`AGENTS.md`](../../AGENTS.md) — the always-on constraint
- [`docs/customization-support.md`](../customization-support.md#add-a-codex-targeted-skill) —
  the procedure
- [`scripts/git-hooks/pre-commit`](../../scripts/git-hooks/pre-commit) — the check, keyed on
  the `.codex-only` marker

Stage a skill with a `.codex-only` marker and one gate missing; the pre-commit hook must
reject the commit.
