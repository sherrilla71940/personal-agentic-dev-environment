# Worktree task workflow v2 plan

- Status: Implemented
- Date: 2026-09-23
- Scope: W6 route contract; the short-command rename remains deferred

## Purpose

The current `worktree-task-workflow` contract is worktree-first because that is the safest choice for
parallel or isolation-sensitive work, but it is verbose for a small change that can safely remain in
the current checkout. W6 adds a route-selection model that handles both cases without weakening the
existing worktree safeguards.

The existing command remains the compatibility entry point. Its worktree behavior remains the
default when `base` is supplied; `isolation=in-place` and `isolation=auto` opt into the new route
contract. The command is not renamed in this change.

## Goals

The implemented route contract must:

- preserve the current exact-base, material, provisioning, verification, manual-test, and publish
  gates for worktree tasks;
- make the chosen route visible before any state-changing action;
- support an explicitly approved in-place route for work that does not need a new checkout;
- avoid guessing from vague labels such as “small” or “quick”; and
- retain compatibility with existing `$worktree-task-workflow` invocations during migration.

The design should not make in-place work appear isolated. A task running in the current checkout
must report that fact and must not claim a separate branch, directory, runtime port, or continuity
scope.

## Interface

The implemented compatibility command accepts the route option:

```text
$worktree-task-workflow [base=<branch>] [task="<task>"] [materials...] [isolation=<mode>]
```

Use these isolation values:

| Value | Meaning |
| --- | --- |
| `worktree` | Use the current worktree-task workflow. Create or resume the isolated task worktree and task branch. |
| `in-place` | Work in the current checkout. Do not create a worktree, switch branches, or copy ignored files. |
| `auto` | Resolve the route from explicit request signals and current checkout safety. Stop when the signals conflict or are insufficient. |

The future short `$task-workflow` name remains a possible alias, but it is not required for the
route to be useful and is intentionally deferred until migration guidance and client discovery
behavior are available.

## Deterministic route resolution

`auto` must not infer isolation from the estimated size of a task. Resolve it in this order:

1. Honor an explicit `isolation=` value.
2. Resolve plan-only requests without creating either route.
3. If the request explicitly names parallel work, a new worktree, branch isolation, or a separate
   runtime, select `worktree`.
4. If the current checkout is already the matching task worktree, continue there.
5. If `auto` would otherwise select in-place but the current checkout is dirty, detached, or has
   conflicting unfinished continuity, stop and ask for an explicit route or safe checkout decision.
   A supplied base selects `worktree` under `auto`; for explicit `in-place`, a supplied base is a
   request target only and may differ from the current branch. Never switch or discard changes.
6. If the request contains no isolation signal and the current checkout is safe for the task,
   select `in-place` only when the resolved echo makes that choice explicit before execution.
7. Otherwise stop with the unresolved route and show `isolation=worktree` and `isolation=in-place`
   examples.

The resolved echo must include the route, current Git root, current branch, requested base, task
branch when applicable, continuity path, and whether runtime isolation applies. No worktree or
branch may be created before that echo and the normal execution approval boundary.

## In-place safeguards

The in-place route reuses the current directory and therefore needs a separate safety contract:

- Run the repository identity preflight before reading project files or changing anything.
- Require a named current branch and leave it unchanged. If `base` is supplied, treat it as the
  explicit pull or merge request target; do not switch branches automatically or treat that target
  as the task's starting commit.
- Refuse an in-place route when unrelated uncommitted changes would be mixed with the task. The
  workflow may continue only after the user classifies the existing changes and accepts the scope.
- Reconcile an existing matching continuity state. If the state belongs to another unfinished task,
  apply the existing parking or cleanup rules before starting this task.
- Do not run ignored-file provisioning. The current checkout already owns its local files, and the
  in-place route must not copy or replace tracked configuration.
- Treat `runtime=auto` as unsupported unless the project descriptor explicitly defines a safe
  current-checkout lease. A worktree-specific port guarantee cannot be claimed in place.
- Keep the same automated verification and manual-test approval gates, with route-specific
  integration and publication rules. Publishing must identify the current branch and target
  explicitly.
- Keep continuity cleanup separate. Completing an in-place task must still offer cleanup of its
  active state and must never delete `state.md` automatically.

## Worktree route compatibility

The worktree route should reuse the existing implementation and remain the default for the current
command. It must continue to:

- resolve and pin `origin/<base>` before creation;
- use the client-native entry path when it satisfies the contract;
- run the evidence-only provisioning preflight and report target-base manifest evidence;
- keep tracked configuration, secrets, and implicit setup execution out of provisioning;
- record materials and continuity in the task worktree; and
- stop after creation when the current client cannot enter the new path.

W3 remains coupled to this route decision. The route contract is accepted and implemented without
renaming the workflow; the existing worktree route and the new in-place route share the same
materials, verification, manual-test, and continuity boundaries.

## Implementation follow-ups

Keep the implemented route contract maintainable through separate, reviewable follow-ups:

1. Keep parser and resolved-echo coverage for `isolation=auto|worktree|in-place` and ambiguity
   rejection in the shared invocation contract.
2. Keep the in-place adapter separate from the existing worktree provisioning helper.
3. Cover clean in-place work, dirty-checkout refusal, detached-HEAD refusal, matching continuity,
   wrong-task continuity, runtime refusal, and unchanged worktree behavior through the route contract
   test and continuity fixtures.
4. Re-run the Bash, PowerShell, continuity, profile, runtime, link, and pre-commit checks when the
   protected behavior changes.
5. Consider the future short command only after usage and migration guidance are available.

## Approval boundary

The route contract is implemented and documented. W3 remains deferred: the existing command name is
retained, and no short-command rename or alias is active. Reconsider that migration only after the
client discovery surfaces and user-facing invocation guidance can be updated together.
