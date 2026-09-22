# ADR-0034: Require explicit runtime isolation for isolated browser tests

- Status: Accepted
- Date: 2026-09-22

## Context

Git worktrees isolate source and Git state, but they do not isolate a development server's TCP
port. Starting a project's ordinary server from an isolated worktree can therefore leave the
browser pointed at another worktree's process. The repository already provides a descriptor-driven
runtime helper with a bounded port range, leases, health checks, process-ownership checks, and
automatic collision fallback, but the workflow contract did not require that path for browser or
runtime testing and lacked regression coverage for fallback from an occupied preferred port.

## Decision

Browser or runtime testing from an isolated worktree requires `runtime=auto` before starting the
server. The consuming project must provide the tracked `.worktree-runtime.json` descriptor. If
runtime isolation is not selected or the descriptor is unavailable, the workflow reports that no
per-worktree port guarantee exists and does not claim that runtime results represent the current
worktree. Tasks that do not need a server may continue with runtime disabled.

The allocator keeps its bounded automatic fallback: an occupied preferred candidate advances to
the next candidate in the descriptor range, while an explicitly requested occupied port remains an
error. Fixed-port projects remain unsupported for concurrent runtime testing unless their tracked
descriptor explains how to inject a port.

## Alternatives considered

- Start the ordinary project server and warn afterward: rejected because the browser may already
  have tested another worktree's process.
- Add generic free-port discovery without a tracked descriptor: rejected because the application,
  browser URL, and server may disagree about the selected port.
- Make runtime isolation mandatory for every task: rejected because non-UI tasks need no server.

## Consequences

The workflow has a clear safety gate before isolated browser/runtime testing. Projects must provide
a descriptor to receive the guarantee, and fixed-port projects must remain explicit about being
unsupported for concurrent runtime execution. Port selection remains user-cache state outside Git,
and automatic collision fallback is bounded and test-covered.

## Verification

- `python scripts/tests/test-worktree-runtime.py -v`
- `scripts/tests/run-pre-commit.ps1`

## Related

- [0023: Optional per-worktree runtime isolation](./0023-optional-per-worktree-runtime-isolation.md)
- [Per-worktree runtime guide](../worktree-runtime.md)
