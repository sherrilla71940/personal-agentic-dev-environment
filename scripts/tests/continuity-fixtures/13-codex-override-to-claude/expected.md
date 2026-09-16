# Expected: do not infer Codex overrides in another client

The state says that a previous Codex session used private override instructions, but it does not
preserve the procedure. A receiving Claude or Copilot session must not claim that it received or
read those instructions automatically.

## Governing rules

- Shared core: `AGENTS.override.md` is Codex's client-local project instruction file. It is not
  automatically handed to Claude or Copilot.
- `SKILL.md` Session-export decision: client-local instructions are not automatically handed to the
  next client. Portable facts and procedures belong in `state.md` or a companion handoff file.
- Codex uses `AGENTS.override.md` instead of `AGENTS.md` at its directory. Creating one as a mirror
  of Claude instructions would silence the repository's Codex guidance.

## Pass

- Reads `state.md` and identifies that the verification procedure is missing from the handoff.
- Does not claim to have received, loaded, or read `AGENTS.override.md` merely because Codex used it.
- Reports the missing portable procedure and requests the command, a focused copy, or the relevant
  facts when they are needed to continue.
- May inspect a named local file only if the user or handoff explicitly identifies it and the
  current client can access it; it must then distinguish inspection from automatic loading.
- Does not create `CLAUDE.local.md` to mirror Codex's private instructions.
- Preserves the existing objective and does not invent a verification result.

## Fail

- Says the receiving client already knows the local run instructions.
- Treats a discovered `AGENTS.override.md` as instructions it was handed automatically.
- Creates `CLAUDE.local.md` or another client-local mirror to make the procedure appear shared.
- Invents commands, results, or a completed verification.
