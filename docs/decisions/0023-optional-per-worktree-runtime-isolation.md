# ADR-0023: Add optional per-worktree runtime isolation

- Status: Accepted
- Date: 2026-09-17

## Context

Git worktrees isolate tracked files, branches, and the physical directory that carries project
continuity. They do not isolate development-server ports or other runtime resources. As a result,
two valid worktrees can still compete for one fixed HTTP port, making parallel manual testing
unreliable even though source isolation is correct.

The repository's `native` and `managed` harness modes describe the amount of user-level AI
orchestration. Runtime allocation is a project and workflow concern, not a machine profile concern.
The feature must therefore help projects that opt into it without making every task start a server
or requiring every project to adopt a runtime contract.

## Decision

Add an optional, tracked `.worktree-runtime.json` descriptor at the consuming repository root. The
descriptor is authoritative for the V1 runtime contract and declares:

- a no-shell startup command;
- an allowed HTTP port range;
- a `{port}` command token, a port environment variable, or both;
- an HTTP or HTTPS health URL containing `{port}`;
- an optional worktree-relative working directory; and
- optional classifications for resources that V1 reports but does not create.

The `worktree-task-workflow` skill accepts `runtime=auto` explicitly. Without that option, runtime
startup remains the project's ordinary responsibility. The workflow reports when the descriptor is
absent, invalid, or unable to support port injection; source/worktree isolation remains valid, but
parallel runtime execution is not claimed. A fixed-port project is therefore supported as a
source-isolated project while being explicitly unsupported for concurrent runtime testing.

A cross-platform Python helper is rendered to the user's local helper directory. It assigns a
stable preferred port to the physical worktree, acquires a user-level inter-process lease while
the server runs, retries bounded automatic collisions, injects the selected port, waits for the
declared health URL, and verifies that the launched process owns the listening port. The assignment
is stored outside the worktree and Git state; it is a preference, not a permanent reservation.
An explicit occupied port fails rather than silently changing the user's request.

This preserves the agreed harness boundary: strong runtime guarantees apply when the workflow is
explicitly chosen, without forcing every task or every project into a rigid harness.

V1 covers one HTTP development process and its port. Database, cache, queue, Docker, and external
service isolation are visible through resource classifications only; they are not automatically
created, cloned, namespaced, or torn down.

## Alternatives considered

### Keep one fixed port per project

Rejected because separate worktrees would still collide and the workflow could not honestly promise
parallel runtime testing.

### Probe for an available port without a lease

Rejected because a check-then-start race can let two worktrees choose the same port. The lease is
held for the lifetime of the helper-managed process.

### Detect frameworks and rewrite their startup commands automatically

Rejected because framework detection is heuristic and would make project ownership ambiguous. The
project descriptor is explicit and reviewable; detection can be considered only as a future
best-effort aid that never overrides it.

### Carry runtime state through `.worktreeinclude`

Rejected because allocation state is machine-local and must not become ignored project material.
The helper keeps it in a user cache, while `.worktreeinclude` remains an allowlist for approved
ignored files.

### Add a profile selector for runtime isolation

Rejected because runtime behavior is selected per task and project, not by personal/company context,
harness mode, or continuity preference. Adding a profile dimension would make unrelated concerns
coupled.

### Implement database, cache, Docker, and queue provisioning in V1

Rejected as over-broad. Those resources have project-specific setup, credentials, cleanup, and
data-isolation requirements. V1 reports their declared status and leaves implementation to a later
descriptor contract.

## Consequences

Projects with a descriptor can run one independently addressed development server per worktree and
resume with the same preferred port when it is available. The lease, health check, and process
ownership check make collisions visible before manual testing proceeds.

The feature adds a Python 3 requirement only for projects that opt into runtime startup. Projects
without a descriptor or with `runtime=off` keep their existing startup path. A port range does not
isolate any resource outside the declared HTTP process, and a fixed-port application remains
unsupported for concurrent runtime execution.

Runtime allocation is deliberately outside Git, continuity state, and application-owned settings.
Applying the developer-environment repository does not restore a project descriptor, start a
server, or reserve a port.

## Reconsider when

Review this decision when multiple projects need a common database/cache/container contract, when
the helper must manage more than one process, when a project needs setup or teardown hooks, or when
the runtime descriptor requires a backward-incompatible schema change. Also review it if projects
report that the explicit opt-in and bounded failure behavior is too burdensome for routine tasks.

## Related files and verification

- [Per-worktree runtime guide](../worktree-runtime.md)
- [Worktree provisioning guide](../worktree-provisioning.md)
- [Shared workflow lifecycle](../../home/.chezmoitemplates/skills/task-workflow/lifecycle.md)
- `home/dot_local/share/worktree-runtime.py`
- `scripts/tests/test-worktree-runtime.py`
- `scripts/manifests/workflows/worktree-task-workflow.json`

Verify with:

```bash
python scripts/tests/test-worktree-runtime.py -v
```
