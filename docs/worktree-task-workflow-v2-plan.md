# Worktree task workflow v2 plan

- Status: Proposed
- Date: 2026-09-23
- Scope: W6 design only

## Purpose

The current `worktree-task-workflow` contract is intentionally worktree-first. That contract is
appropriate for parallel or isolation-sensitive work, but it is verbose for a small change that
can safely remain in the current checkout. W6 proposes a future command and routing model that can
handle both cases without weakening the existing worktree safeguards.

This document is a design proposal, not an implementation. The current command name, invocation
rules, and worktree-only behavior remain unchanged until this plan is approved.

## Goals

The future design should:

- preserve the current exact-base, material, provisioning, verification, manual-test, and publish
  gates for worktree tasks;
- make the chosen route visible before any state-changing action;
- support an explicitly approved in-place route for work that does not need a new checkout;
- avoid guessing from vague labels such as “small” or “quick”; and
- retain compatibility with existing `$worktree-task-workflow` invocations during migration.

The design should not make in-place work appear isolated. A task running in the current checkout
must report that fact and must not claim a separate branch, directory, runtime port, or continuity
scope.

## Proposed interface

Introduce a future short command only after the routing contract is approved:

```text
$task-workflow [base=<branch>] [task="<task>"] [materials...] [isolation=<mode>]
```

Use these isolation values:

| Value | Meaning |
| --- | --- |
| `worktree` | Use the current worktree-task workflow. Create or resume the isolated task worktree and task branch. |
| `in-place` | Work in the current checkout. Do not create a worktree, switch branches, or copy ignored files. |
| `auto` | Resolve the route from explicit request signals and current checkout safety. Stop when the signals conflict or are insufficient. |

Keep `$worktree-task-workflow` as a compatibility entry point. During migration, it should retain
its current worktree behavior unless the user explicitly supplies the future routing option and the
implementation has been approved.

## Deterministic route resolution

`auto` must not infer isolation from the estimated size of a task. Resolve it in this order:

1. Honor an explicit `isolation=` value.
2. Resolve plan-only requests without creating either route.
3. If the request explicitly names parallel work, a new worktree, branch isolation, or a separate
   runtime, select `worktree`.
4. If the current checkout is already the matching task worktree, continue there.
5. If the current checkout is dirty, or the requested base differs from the current branch, stop
   and ask for an explicit route or a safe checkout decision. Never switch or discard changes.
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
- Require the current branch to be the resolved base, or stop for an explicit user decision. Do
  not switch branches automatically.
- Refuse an in-place route when unrelated uncommitted changes would be mixed with the task. The
  workflow may continue only after the user classifies the existing changes and accepts the scope.
- Reconcile an existing matching continuity state. If the state belongs to another unfinished task,
  apply the existing parking or cleanup rules before starting this task.
- Do not run ignored-file provisioning. The current checkout already owns its local files, and the
  in-place route must not copy or replace tracked configuration.
- Treat `runtime=auto` as unsupported unless the project descriptor explicitly defines a safe
  current-checkout lease. A worktree-specific port guarantee cannot be claimed in place.
- Keep the same automated verification, manual-test approval, current-base integration, and
  publish gates. Publishing must identify the current branch and target explicitly.
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

W3 remains coupled to this route decision. Do not add a second implementation path or rename the
workflow until the route resolution and in-place safeguards are accepted.

## Migration sequence

Implement the future change in separate, reviewable steps:

1. Approve this route and safety contract.
2. Add parser coverage for `isolation=auto|worktree|in-place`, the future short command, and
   ambiguity rejection. Keep the tests failing until the parser and resolved echo exist.
3. Add an in-place planning and execution adapter without changing the existing worktree helper.
4. Add end-to-end scratch-repository tests for clean in-place work, dirty-checkout refusal, branch
   mismatch refusal, matching continuity, wrong-task continuity, and unchanged worktree behavior.
5. Add the future short command as an alias or wrapper, then document the compatibility behavior.
6. Re-run the existing Bash, PowerShell, continuity, profile, runtime, link, and pre-commit checks.
7. Deprecate or rename the long command only after usage and migration guidance are available.

## Approval boundary

This plan needs explicit approval before implementation. Until then:

- W6 is a documented proposal only;
- W3 is declined for the current pass because it depends on W6;
- the existing worktree-only command remains authoritative; and
- no in-place route, command rename, or compatibility alias is active.

