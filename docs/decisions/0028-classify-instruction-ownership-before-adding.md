# ADR-0028: Classify instruction ownership before adding behavior

- Status: Accepted
- Date: 2026-09-21

## Context

This repository renders one shared instruction body into Claude Code, Codex, and GitHub Copilot,
while also carrying repository-specific instructions, reusable skills, hooks, and documentation.
Adding a rule to the file that happens to be open can therefore create either unnecessary global
behavior or three divergent copies of one rule.

The repository already separated always-on constraints, operational procedures, and durable rationale
in ADR-0001. `AGENTS.md` also prohibits duplicating shared instructions, and the continuity skill
distinguishes transient state from durable project rules and private client instructions. Those rules
did not provide one short decision gate for classifying new behavior before adding it.

## Decision

Before adding an instruction, rule, hook, or skill, classify the behavior by ownership and scope:

- **User/global instruction:** a broadly applicable working principle that follows the user across
  repositories and projects. Store it in the shared core.
- **Repository/project instruction:** behavior specific to one repository's architecture, workflow,
  terminology, or source-of-truth rules. Store it in that repository's instructions.
- **Skill:** a reusable, conditional workflow with meaningful steps, arguments, state transitions, or
  explicit invocation value. Store it in the appropriate shared or client-specific skill source.
- **Documentation or ADR:** explanatory material, rationale, or reference information that does not
  need to load as an instruction.

Prefer the narrowest correct scope. Check whether an existing instruction or skill already covers the
behavior. Keep one authoritative definition and make other layers reference or specialize it. Do not
turn a simple always-applicable principle into a skill, and do not place project-specific behavior in
the global core.

Documentation-impact checking has two layers. The generic principle that a change may affect related
documentation belongs in the shared core. The list of affected surfaces belongs in project
instructions or the relevant workflow guide, such as this repository's `AGENTS.md`, customization
guide, workflow guides, ADR index, README files, rendered client outputs, and validation suites.

The shared core keeps only generic source-of-truth and partial-ownership principles. Chezmoi
commands, managed-symlink behavior, and this repository's `home/` source-tree mechanics belong in
the root `AGENTS.md` and [chezmoi workflow guide](../chezmoi-workflow.md). The root `CLAUDE.md`
imports `AGENTS.md`, so Claude, Codex, and Copilot receive the repository-specific details when
they work in this repository without loading them for unrelated repositories.

## Profile impact

The classification rule and generic source-of-truth guidance remain part of the shared core, so they
render for Claude, Codex, and Copilot in all current `ai_context`, `ai_continuity`, and `ai_harness`
combinations. Exact chezmoi mechanics are now project-local and arrive through this repository's
root instructions instead of every user's shared profile. This does not change the profile schema,
language defaults, continuity behavior, lifecycle hooks, or native-versus-managed harness
boundaries. The shared rules remain useful in native mode because they govern source ownership, not
continuity automation, and their documentation-impact guidance does not require a hook.

## Alternatives considered

- **Create a reusable ownership skill.** Rejected because the behavior is a simple always-applicable
  principle, not a conditional workflow.
- **Repeat the classifier in `AGENTS.md`, each client wrapper, and skills.** Rejected because copies
  would drift and violate the repository's one-authoritative-body boundary.
- **Keep the classifier only in documentation.** Rejected because agents need the scope decision
  before they add or modify an instruction source.
- **Add a new profile selector for documentation behavior.** Rejected because ownership and
  documentation impact are not machine-local profile dimensions.

## Consequences

Future additions receive an explicit scope decision before source placement. The shared core grows by
one small always-on rule, and the profile suite verifies that the rule reaches every client surface.
Project-specific source paths remain in project documentation instead of expanding the global rule.

## Reconsider when

Revisit this decision if the repository stops rendering shared instructions across clients, adopts a
mechanically enforced ownership registry, or gains a native client feature that provides a more
reliable scope boundary.

## Related files and verification

- [`home/.chezmoitemplates/core.md`](../../home/.chezmoitemplates/core.md) — authoritative shared rule
- [`AGENTS.md`](../../AGENTS.md) — repository-specific ownership and source rules
- [`docs/customization-support.md`](../customization-support.md) — project-specific customization surfaces
- [`docs/decisions/0001-separate-operational-guides-from-decision-records.md`](./0001-separate-operational-guides-from-decision-records.md) — documentation layers
- [`home/dot_agents/skills/task-continuity/SKILL.md`](../../home/dot_agents/skills/task-continuity/SKILL.md) — continuity promotion boundary
- [`scripts/tests/test-ai-configuration-profiles.sh`](../../scripts/tests/test-ai-configuration-profiles.sh) — cross-profile rendering coverage
