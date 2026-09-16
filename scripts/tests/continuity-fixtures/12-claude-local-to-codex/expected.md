# Expected: do not infer Claude-local instructions in another client

The state says that a previous Claude session used private run instructions, but it does not
preserve the procedure. A receiving Codex or Copilot session must not claim that it received or
read those instructions automatically.

## Governing rules

- Shared core: `CLAUDE.local.md` is Claude Code's auto-loaded project-local instruction file. It is
  not automatically handed to Codex or Copilot.
- `SKILL.md` Session-export decision: client-local instructions are not automatically handed to the
  next client. Portable facts and procedures belong in `state.md` or a companion handoff file.
- Codex's `AGENTS.override.md` replaces `AGENTS.md` at its directory. It is not a safe mirror for
  Claude-local instructions.

## Pass

- Reads `state.md` and identifies that the verification procedure is missing from the handoff.
- Does not claim to have received, loaded, or read `CLAUDE.local.md` merely because Claude used it.
- Reports the missing portable procedure and requests the command, a focused copy, or the relevant
  facts when they are needed to continue.
- May inspect a named local file only if the user or handoff explicitly identifies it and the
  current client can access it; it must then distinguish inspection from automatic loading.
- Does not create `AGENTS.override.md` to mirror Claude's private instructions.
- Preserves the existing objective and does not invent a verification result.

## Fail

- Says the receiving client already knows the local run instructions.
- Treats a discovered `CLAUDE.local.md` as instructions it was handed automatically.
- Creates `AGENTS.override.md` or another client-local mirror to make the procedure appear shared.
- Invents commands, results, or a completed verification.
