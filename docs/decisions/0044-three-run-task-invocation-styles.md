# ADR-0044: Support three run-task-end-to-end invocation styles

- Status: Accepted
- Date: 2026-09-24

## Context

`run-task-end-to-end` is used from Claude Code and Codex, but its current contract is optimized for
named arguments and a natural-language prompt. A user who invokes the skill without arguments still
needs a guided setup path that exposes the major choices without weakening the existing workspace,
base, verification, continuity, phase, and publishing boundaries.

Claude Code documents a native `AskUserQuestion` surface with bounded multiple-choice questions and
free-text support. Codex surfaces may expose a `request_user_input` capability, but the public OpenAI
Responses documentation describes application-defined input tools rather than a built-in tool with
that name. The shared workflow therefore cannot depend on either client’s presentation API.

## Decision

The workflow supports three first-class invocation styles:

1. **Guided no-argument:** no arguments enters guided intake and explicitly asks for the task,
   workspace, base, verification, continuity, and any context-specific required value. It shows
   `agent` and `auto` as defaults without silently choosing workspace or base.
2. **Prompted natural language:** text after the skill name is parsed conservatively. Clear values are
   marked `prompt`; ambiguous values remain unresolved and require a question.
3. **Explicit structured:** named or positional arguments are authoritative and marked `argument`.
   Missing values may be resolved by safe prompt parsing, defaults, or confirmation without asking
   again for values already supplied.

The shared invocation template owns allowed values, defaults, resolution order, ambiguity handling,
and the no-state-mutation boundary. Client adapters own presentation:

- Claude Code uses `AskUserQuestion` when available and falls back to concise text.
- Codex uses `request_user_input` only when the current surface exposes it and otherwise falls back
  to concise text.
- Other hosts use the same text fallback.

All guided answers use confirmation provenance. Verification and continuity defaults remain silent in
prompted and explicit/partial modes unless the user overrides them or the contract requires a choice.
Plan-only requests remain read-only, and unresolved required inputs prevent branch, worktree,
continuity, material, and application state changes.

## Alternatives considered

- **Make guided mode a fourth workflow axis.** Rejected; intake presentation must not alter lifecycle
  semantics.
- **Put Claude’s picker schema in the shared workflow.** Rejected; client presentation APIs evolve
  independently and the shared contract must remain portable.
- **Require every host to implement structured input.** Rejected; a concise text fallback keeps the
  workflow usable when a host or mode lacks the capability.
- **Apply defaults silently in no-argument mode.** Rejected; the no-argument invocation intentionally
  requests an interactive setup and should expose the major choices.
- **Infer workspace or base from task size, branch names, or remote defaults.** Rejected; this would
  bypass the existing provenance and exact-base safety contract.

## Consequences

Users can start with a short, discoverable command while power users retain deterministic structured
arguments. Claude and Codex can present native questions without duplicating the workflow contract.
Tests must cover both the shared semantic contract and each adapter’s fallback behavior. Host
capability names and question limits remain version-sensitive and require periodic documentation
checks.

## Reconsider when

Revisit this decision if supported clients expose a stable shared question protocol, if Codex makes
`request_user_input` a documented portable capability, or if the workflow gains a real parser whose
behavior should move out of instruction text and into executable tests.

## Related files and verification

- [`home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md`](../../home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md)
- [`home/dot_agents/skills/run-task-end-to-end/SKILL.md`](../../home/dot_agents/skills/run-task-end-to-end/SKILL.md)
- [`home/dot_claude/skills/run-task-end-to-end/SKILL.md`](../../home/dot_claude/skills/run-task-end-to-end/SKILL.md)
- [`scripts/tests/test-run-task-invocation.sh`](../../scripts/tests/test-run-task-invocation.sh)
- [Claude Code user input](https://code.claude.com/docs/en/agent-sdk/user-input)
- [OpenAI async tool calling](https://developers.openai.com/api/docs/guides/async-tool-calling)

Verify with the invocation contract test, the task-route contract test, `git diff --check`, and the
repository pre-commit hook.
