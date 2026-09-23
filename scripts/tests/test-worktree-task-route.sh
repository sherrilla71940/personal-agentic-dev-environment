#!/usr/bin/env bash
# Verify the shared task-workflow route contract without touching live targets or Git state.
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"

fail() {
  printf 'task route tests: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "'$needle' not found in $file"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "unexpected '$needle' in $file"
}

invocation="$repository_root/home/.chezmoitemplates/skills/worktree-task-workflow/invocation.md"
lifecycle="$repository_root/home/.chezmoitemplates/skills/worktree-task-workflow/lifecycle.md"
continuity="$repository_root/home/dot_agents/skills/project-continuity/SKILL.md"
codex_skill="$repository_root/home/dot_agents/skills/worktree-task-workflow/SKILL.md"
claude_skill="$repository_root/home/dot_claude/skills/worktree-task-workflow/SKILL.md"
provisioning="$repository_root/docs/worktree-provisioning.md"
plan="$repository_root/docs/worktree-task-workflow-v2-plan.md"
readme="$repository_root/README.md"
readme_zh="$repository_root/README.zh-TW.md"

assert_contains "$invocation" '`isolation`'
assert_contains "$invocation" '`worktree`'
assert_contains "$invocation" '`in-place`'
assert_contains "$invocation" '`auto`'
assert_contains "$invocation" 'branch is required for the `worktree` route'
assert_contains "$invocation" 'current branch'
assert_contains "$invocation" 'dirty'
assert_contains "$invocation" 'route rejects `runtime=auto`'
assert_contains "$invocation" 'route'
assert_contains "$lifecycle" 'For `in-place`'
assert_contains "$lifecycle" 'Do not create a worktree'
assert_contains "$lifecycle" 'do not initialize continuity'
assert_contains "$lifecycle" 'physical checkout'
assert_contains "$lifecycle" 'runtime=auto'
assert_contains "$continuity" 'one active task'
assert_contains "$continuity" 'trivial'
assert_contains "$codex_skill" 'in-place'
assert_contains "$claude_skill" 'in-place'
assert_contains "$provisioning" 'isolation=in-place'
assert_contains "$provisioning" 'one active task'
assert_contains "$plan" 'Status: Implemented'
assert_contains "$plan" 'W3 remains deferred'
assert_contains "$plan" 'A supplied base selects `worktree` under `auto`'
assert_contains "$plan" 'request target only'
assert_contains "$readme" 'isolation=in-place'
assert_contains "$readme" 'A physical checkout has at most one active task'
assert_contains "$readme" 'per-checkout continuity record'
assert_contains "$readme_zh" 'isolation=in-place'
assert_contains "$readme_zh" '每個實體 checkout 最多只有一個作用中的任務'
assert_contains "$readme_zh" '每個 checkout 的 continuity 紀錄'

# The old proposal-only language must not survive after the route is implemented.
assert_not_contains "$provisioning" 'It is not active; the current `worktree-task-workflow` contract remains worktree-only.'
assert_not_contains "$plan" 'no in-place route, command rename, or compatibility alias is active.'
assert_not_contains "$plan" 'the requested base differs from the current branch'

printf 'task route tests: route contract OK\n'
