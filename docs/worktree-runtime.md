# Per-worktree runtime isolation

Git worktrees isolate tracked files, branches, and continuity state. They do not isolate TCP
ports, database instances, queues, caches, service processes, or external services. Two worktrees
can therefore contain different code while one development server still owns the only configured
port.

The `worktree-task-workflow` skill provides an opt-in V1 for this boundary. It supports one HTTP
development process with a project-defined port range, port injection, and health URL. It does not
make every task use a server, and it does not claim to isolate resources the project has not
described.

## When to use it

Add `runtime=auto` to the explicit workflow invocation when the task includes an application that
supports the runtime descriptor:

```text
/worktree-task-workflow develop "review the form" runtime=auto
$worktree-task-workflow develop "review the form" runtime=auto
```

The equivalent `port=<number>` option requests a particular port within the descriptor's range:

```text
/worktree-task-workflow develop "review the form" runtime=auto port=43125
```

Runtime isolation is not the default. A small or non-UI task can omit it. `runtime=off` leaves
startup to the project's ordinary procedure and means the workflow did not provide a per-worktree
port guarantee.

This preserves the harness boundary: strong runtime guarantees apply when the workflow is
explicitly chosen, without forcing every task or every project into a rigid harness.

## Project descriptor

The consuming project owns a tracked `.worktree-runtime.json` at its repository root. It is
authoritative for the V1 runtime contract. Automatic framework detection must not override it.

Minimal example:

```json
{
  "schemaVersion": 1,
  "name": "frontend development server",
  "startCommand": [
    "npm",
    "run",
    "dev",
    "--",
    "--host",
    "127.0.0.1",
    "--port",
    "{port}"
  ],
  "portRange": [43100, 43199],
  "healthUrl": "http://127.0.0.1:{port}/",
  "healthTimeoutSeconds": 30
}
```

An application that accepts an environment variable can use that instead of a command token:

```json
{
  "schemaVersion": 1,
  "name": "API development server",
  "startCommand": ["npm", "run", "dev"],
  "portRange": [43200, 43299],
  "portEnvironmentVariable": "PORT",
  "healthUrl": "http://127.0.0.1:{port}/health"
}
```

The helper starts an argument-array command without a shell. A descriptor must provide either a
`{port}` token in `startCommand`, a `portEnvironmentVariable`, or both. `workingDirectory`, when
present, is a relative path inside the worktree. `healthUrl` must be an HTTP or HTTPS URL containing
`{port}` and must not contain credentials.

Optional resources make future expansion visible without implementing it in V1:

```json
{
  "resources": [
    {"name": "database", "isolation": "unsupported", "note": "shared SQL Server"},
    {"name": "cache", "isolation": "shared-safe"}
  ]
}
```

Use one of these classifications:

| Classification | Meaning in V1 |
| --- | --- |
| `per-worktree` | The project already gives this worktree its own resource. The helper reports it but does not create it. |
| `shared-safe` | The project has confirmed that concurrent tests can share it safely. The helper reports it but does not configure it. |
| `unsupported` | Concurrent isolation is not available; the workflow reports the limitation. |

Do not put secrets, production configuration, database copies, dependencies, build output, or
runtime allocation state in the descriptor or `.worktreeinclude`.

## Allocation and launch behavior

The user-level helper is rendered to `~/.local/share/worktree-runtime.py`. From the worktree root:

```text
python "$HOME/.local/share/worktree-runtime.py" inspect
python "$HOME/.local/share/worktree-runtime.py" start
python "$HOME/.local/share/worktree-runtime.py" start --port 43125
```

The helper:

1. Reads and validates the tracked descriptor.
2. Reuses the saved port for the physical worktree when it remains inside the configured range.
3. Otherwise chooses a stable candidate from the worktree identity and configured range.
4. Acquires a user-level inter-process lease before launching the server.
5. Checks that the port can bind and retries a bounded number of collisions.
6. Injects the selected port into the command and/or environment.
7. Waits for the health URL and verifies that the launched process owns the listening port.
8. Persists the successful assignment in the user cache, outside the worktree and Git state.

The saved assignment is a preference, not a reservation. Another process may already own it when
the worktree resumes. An automatic selection can move to another candidate; an explicitly requested
occupied port fails instead of silently changing the user's request. The lease is held while the
helper's server process runs and is released when it exits.

If the project uses a fixed port and cannot accept the injected value, source/worktree isolation
still works, but concurrent runtime execution is unsupported. The workflow must report that fact
and must not claim that the URL represents the current worktree.

## Boundaries and future work

Port isolation does not automatically make a database, Redis instance, queue, Docker service, or
third-party API independent. Project-specific setup is required for those resources. Future
descriptor versions may add setup and teardown contracts, but V1 deliberately does not clone
databases, create namespaces, manage containers, proxy traffic, or infer framework behavior.

The runtime helper is independent of `ai_harness`, `ai_context`, and `ai_continuity`. Both native
and managed modes keep the skill available, and the workflow remains explicit-only. Managed mode
can provide continuity and lifecycle reporting around the task; it does not implicitly start a
server or allocate a port.

## Verification

Run the focused helper tests from the developer-environment repository:

```text
python scripts/tests/test-worktree-runtime.py -v
```

The test suite covers descriptor validation, stable assignment, exclusive leases, health-checked
launch, Windows path spelling, and explicit occupied-port rejection.
