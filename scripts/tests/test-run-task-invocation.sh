#!/usr/bin/env bash
# Verify the shared invocation semantics and the Claude/Codex presentation adapters.
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
shared="$repository_root/home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md"
codex="$repository_root/home/dot_agents/skills/run-task-end-to-end/SKILL.md"
claude="$repository_root/home/dot_claude/skills/run-task-end-to-end/SKILL.md"
readme="$repository_root/README.md"
readme_zh="$repository_root/README.zh-TW.md"
adr="$repository_root/docs/decisions/0044-three-run-task-invocation-styles.md"

fail() {
  printf 'run-task invocation tests: %s\n' "$1" >&2
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

for mode in 'input=guided' 'input=prompt' 'input=explicit'; do
  assert_contains "$shared" "$mode"
done

for value in \
  'Guided no-argument resolution' \
  'What should this task accomplish?' \
  'Where should the task run?' \
  'Which branch is the task based on and targeting?' \
  'agent` (default)' \
  'auto` (default)' \
  'Other` or manual-entry route' \
  'source=confirmation' \
  'source=prompt' \
  'source=argument' \
  'Explicit values preserve `source=argument` and bypass redundant questions' \
  'Prompted and explicit/partial modes keep the existing default behavior' \
  'required answer is dismissed or remains ambiguous' \
  'stop before any branch' \
  'Keep a plan-only request read-only' \
  'company-flow' \
  'Do not use a task-size, checkout-state, or' \
  'Unavailable structured input is never an error' \
  'stop before any branch, worktree, continuity,' \
  'material, or application state changes' \
  'A partial' \
  'structured request such as' \
  'workspace=worktree Use a worktree from feat/water-fee' \
  'branch names'; do
  assert_contains "$shared" "$value"
done

for value in \
  'agent` and `auto`' \
  'Partial structured input' \
  '$run-task-end-to-end Use a worktree from feat/water-fee'; do
  assert_contains "$codex" "$value"
done
assert_contains "$codex" 'request_user_input'
assert_contains "$codex" 'plain-text questions'
assert_contains "$codex" '$run-task-end-to-end'

for value in \
  'agent` and `auto`' \
  'AskUserQuestion' \
  'Other` or free-text' \
  'plain-text questions' \
  '/run-task-end-to-end Use a worktree from feat/water-fee'; do
  assert_contains "$claude" "$value"
done

assert_contains "$readme" '/run-task-end-to-end'
assert_contains "$readme" '$run-task-end-to-end'
assert_contains "$readme" 'No-argument mode asks for the task, workspace, base'
assert_contains "$readme" 'Partial structured input is also supported'
assert_contains "$readme" '$task-workflow'
assert_contains "$readme" '$worktree-task-workflow'
assert_contains "$readme_zh" '無參數模式會詢問任務、workspace、base'
assert_contains "$readme_zh" '也可以只提供部分結構化參數'

assert_contains "$adr" 'three first-class invocation styles'
assert_contains "$adr" 'AskUserQuestion'
assert_contains "$adr" 'request_user_input'
assert_contains "$adr" 'Plan-only requests remain read-only'
assert_not_contains "$shared" 'workspace=inferred'

printf 'run-task invocation tests: guided, prompted, explicit, and adapter contracts OK\n'
