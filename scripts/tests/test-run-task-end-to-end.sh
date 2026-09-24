#!/usr/bin/env bash
# Verify the shared run-task-end-to-end workspace and policy contract without touching live targets or Git state.
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"

fail() {
  printf 'task workflow policy tests: %s\n' "$1" >&2
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

assert_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "unexpected compatibility path remains: $path"
}

assert_valid_flow() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{1,9}$ ]] || fail "expected valid flow value: $value"
}

assert_invalid_flow() {
  local value="$1"
  [[ ! "$value" =~ ^[0-9]{1,9}$ ]] || fail "expected invalid flow value: $value"
}

assert_valid_flow_branch() {
  local flow="$1" branch="$2" branch_flow
  [[ "$branch" =~ ^flow/[0-9]{1,9}(-[A-Za-z0-9_-]+)?$ ]] ||
    fail "expected valid company-flow branch: $branch"
  branch_flow="${branch#flow/}"
  branch_flow="${branch_flow%%-*}"
  [[ "$branch_flow" == "$flow" ]] ||
    fail "flow and branch disagree: flow=$flow branch=$branch"
}

assert_invalid_flow_branch() {
  local branch="$1"
  [[ ! "$branch" =~ ^flow/[0-9]{1,9}(-[A-Za-z0-9_-]+)?$ ]] ||
    fail "expected invalid company-flow branch: $branch"
}

invocation="$repository_root/home/.chezmoitemplates/skills/run-task-end-to-end/invocation.md"
lifecycle="$repository_root/home/.chezmoitemplates/skills/run-task-end-to-end/lifecycle.md"
continuity_template="$repository_root/home/.chezmoitemplates/continuity.md"
state_format="$repository_root/home/dot_agents/skills/task-continuity/references/state-format.md"
continuity_skill="$repository_root/home/dot_agents/skills/task-continuity/SKILL.md"
codex_skill="$repository_root/home/dot_agents/skills/run-task-end-to-end/SKILL.md"
claude_skill="$repository_root/home/dot_claude/skills/run-task-end-to-end/SKILL.md"
legacy_codex_skill="$repository_root/home/dot_agents/skills/worktree-task-workflow/SKILL.md"
legacy_claude_skill="$repository_root/home/dot_claude/skills/worktree-task-workflow/SKILL.md"
task_codex_skill="$repository_root/home/dot_agents/skills/task-workflow/SKILL.md"
task_claude_skill="$repository_root/home/dot_claude/skills/task-workflow/SKILL.md"
removed_continuity_skill="$repository_root/home/dot_agents/skills/project-continuity/SKILL.md"
canonical_hook="$repository_root/home/dot_local/share/maintain-task-continuity.sh.tmpl"
canonical_symlink="$repository_root/home/dot_claude/skills/symlink_task-continuity.tmpl"
removed_hook="$repository_root/home/dot_local/share/maintain-project-continuity.sh.tmpl"
removed_symlink="$repository_root/home/dot_claude/skills/symlink_project-continuity.tmpl"
provisioning="$repository_root/docs/worktree-provisioning.md"
runtime="$repository_root/docs/worktree-runtime.md"
plan="$repository_root/docs/worktree-task-workflow-v2-plan.md"
adr="$repository_root/docs/decisions/0038-generalize-task-workspace-and-verification-policy.md"
completed_adr="$repository_root/docs/decisions/0042-preserve-completed-continuity-by-parking.md"
parked_identity_adr="$repository_root/docs/decisions/0043-restore-parked-continuity-by-git-identity.md"
flow_adr="$repository_root/docs/decisions/0040-require-company-flow-branch-identifiers.md"
readme="$repository_root/README.md"
readme_zh="$repository_root/README.zh-TW.md"
completed_fixture="$repository_root/scripts/tests/continuity-fixtures/16-completed-state-to-new-task/expected.md"
parked_identity_fixture="$repository_root/scripts/tests/continuity-fixtures/17-branch-aware-parked-resume/expected.md"

for token in '`workspace`' '`checkout`' '`worktree`' '`verification`' '`agent`' '`balanced`' '`user`' '`continuity`' '`auto`' '`on`' '`off`'; do
  assert_contains "$invocation" "$token"
done
assert_contains "$invocation" '| `flow` | one to nine ASCII digits'
assert_contains "$invocation" 'branch_policy=company-flow'
assert_contains "$invocation" 'branch_policy=project-exception'
assert_contains "$invocation" 'flow/<flow>-<ascii-description>'
assert_contains "$invocation" 'company-flow execution without `flow=`'
assert_contains "$invocation" 'flow=<digits>'
assert_contains "$invocation" 'effective branch policy'
assert_contains "$invocation" 'flow=15927 task="Continue sewer layer editing"'
assert_contains "$invocation" 'active profile'
assert_contains "$invocation" 'source: argument | prompt | user-confirmation'
assert_contains "$invocation" 'ask before any branch switch'
assert_contains "$invocation" 'phase      execute'
assert_contains "$invocation" 'base branch'
assert_contains "$invocation" 'task branch'
assert_contains "$invocation" 'publish authorization'
assert_contains "$invocation" 'task override as the source'
assert_contains "$invocation" 'effective_continuity'
assert_contains "$invocation" '| `verification` | `agent`, `balanced`, or `user` | `agent` |'
assert_contains "$invocation" 'continuity requested auto'
assert_contains "$invocation" 'different completed task runs the completed-state transition'
assert_contains "$invocation" '`isolation=worktree|in-place|auto`'
assert_contains "$invocation" 'deprecated alias'
assert_contains "$invocation" 'isolation=auto` value cannot select a workspace'
assert_contains "$invocation" 'does not run a second task-size'
assert_contains "$lifecycle" 'verification=agent'
assert_contains "$lifecycle" 'verification=balanced'
assert_contains "$lifecycle" 'verification=user'
assert_contains "$lifecycle" 'active profile'
assert_contains "$lifecycle" 'publish authorization'
assert_contains "$lifecycle" 'move the old active state to `.task-continuity/parked/`'
assert_contains "$lifecycle" 'confirmation-gated cleanup'
assert_contains "$continuity_template" 'continuity=auto'
assert_contains "$continuity_template" 'ai_continuity'
assert_contains "$continuity_template" 'Do not apply a second task-size heuristic'
assert_contains "$continuity_template" 'completed-state transition'
assert_contains "$continuity_template" 'non-colliding objective-derived name'
assert_contains "$continuity_template" 'does not require deletion confirmation'
assert_contains "$continuity_template" 'Branch policy'
assert_contains "$state_format" 'Branch policy:'
assert_contains "$state_format" 'Flow:'
assert_contains "$state_format" 'Task:'
assert_contains "$state_format" 'Base commit:'
assert_contains "$state_format" 'branch alone never selects a parked state'
assert_contains "$state_format" "executing environment's current clock"
assert_contains "$state_format" 'Never estimate it'
assert_contains "$continuity_skill" 'one active task'
assert_contains "$continuity_skill" 'Completed active state to a new task'
assert_contains "$continuity_skill" 'A finished-state'
assert_contains "$continuity_skill" 'Never overwrite an existing parked file'
assert_contains "$continuity_skill" 'does not require deletion confirmation'
assert_contains "$continuity_skill" 'do not offer active-state deletion before parking'
assert_contains "$continuity_skill" 'Branch-aware parked-state discovery'
assert_contains "$continuity_skill" 'strong unique'
assert_contains "$continuity_skill" '`Parked` marker'
assert_contains "$continuity_skill" 'git check-ignore -v -- .task-continuity/state.md'
assert_contains "$continuity_skill" '.git/info/exclude` match is not a global-ignore claim'
assert_contains "$continuity_skill" 'Never estimate it'
assert_not_contains "$continuity_skill" 'only after the old one is explicitly'
assert_not_contains "$invocation" 'only after cleanup is confirmed'
assert_not_contains "$invocation" 'either continue with effective `continuity=off` or stop'
assert_contains "$codex_skill" 'workspace=checkout'
assert_contains "$codex_skill" 'workspace=worktree'
assert_contains "$codex_skill" '$run-task-end-to-end'
assert_not_contains "$codex_skill" '$worktree-task-workflow'
assert_contains "$codex_skill" 'branch_policy=company-flow'
assert_contains "$codex_skill" 'flow/<flow>-<ascii-description>'
assert_contains "$claude_skill" 'branch_policy=company-flow'
assert_contains "$claude_skill" 'flow/<flow>-<ascii-description>'
assert_contains "$claude_skill" 'workspace'
assert_contains "$codex_skill" 'name: run-task-end-to-end'
assert_contains "$claude_skill" 'name: run-task-end-to-end'
assert_contains "$legacy_codex_skill" 'name: worktree-task-workflow'
assert_contains "$legacy_codex_skill" '../run-task-end-to-end/SKILL.md'
assert_not_contains "$legacy_codex_skill" 'workspace=checkout'
assert_contains "$legacy_claude_skill" 'name: worktree-task-workflow'
assert_contains "$legacy_claude_skill" '../run-task-end-to-end/SKILL.md'
assert_not_contains "$legacy_claude_skill" 'workspace=checkout'
assert_contains "$task_codex_skill" 'name: task-workflow'
assert_contains "$task_codex_skill" '../run-task-end-to-end/SKILL.md'
assert_contains "$task_claude_skill" 'name: task-workflow'
assert_contains "$task_claude_skill" '../run-task-end-to-end/SKILL.md'
assert_absent "$removed_continuity_skill"
assert_contains "$canonical_hook" '#!/usr/bin/env bash'
assert_contains "$canonical_hook" '.task-continuity'
assert_contains "$canonical_hook" '.project-continuity'
assert_contains "$canonical_hook" 'report_parked_branch_candidates'
assert_contains "$canonical_hook" 'PARKED CONTINUITY MATCHES REQUIRE DISAMBIGUATION'
assert_contains "$canonical_symlink" '.agents/skills/task-continuity'
assert_absent "$removed_hook"
assert_absent "$removed_symlink"
assert_contains "$provisioning" 'workspace=checkout'
assert_contains "$provisioning" 'verification=agent|balanced|user'
assert_contains "$provisioning" 'continuity=auto|on|off'
assert_contains "$provisioning" 'Company flow branch policy'
assert_contains "$provisioning" 'branch_policy=company-flow'
assert_contains "$provisioning" 'project-exception'
assert_contains "$provisioning" '0038-generalize-task-workspace-and-verification-policy.md'
assert_contains "$runtime" 'workspace=checkout'
assert_contains "$plan" 'Superseded by ADR-0038'
assert_contains "$adr" 'workspace=checkout|worktree'
assert_contains "$adr" 'verification=agent|balanced|user'
assert_contains "$adr" 'continuity=auto|on|off'
assert_contains "$completed_adr" 'Preserve completed continuity by parking'
assert_contains "$completed_adr" 'confirmation-gated deletion'
assert_contains "$parked_identity_adr" 'unique exact-branch match'
assert_contains "$parked_identity_adr" 'branch-only restoration'
assert_contains "$provisioning" 'non-colliding name'
assert_contains "$readme" 'moves it to `.task-continuity/parked/` with a non-colliding name'
assert_contains "$readme" 'no deletion confirmation or'
assert_contains "$readme_zh" '不需要先確認刪除'
assert_contains "$completed_fixture" 'preserved by parking'
assert_contains "$completed_fixture" 'no cleanup confirmation or `continuity=off` workaround'
assert_contains "$parked_identity_fixture" 'unique parked record'
assert_contains "$parked_identity_fixture" 'branch or filename alone'
assert_contains "$adr" 'Workspace has no implicit default'
assert_contains "$flow_adr" 'flow=<digits>'
assert_contains "$flow_adr" 'company-flow'
assert_contains "$flow_adr" 'project-exception'
assert_contains "$readme" 'workspace=checkout'
assert_contains "$readme" 'verification=agent` is the default'
assert_contains "$readme" 'publish authorization'
assert_contains "$readme_zh" 'workspace=checkout'
assert_contains "$readme_zh" 'verification=agent` 是預設值'
assert_contains "$readme_zh" '發布核准'
assert_contains "$readme" 'Completed state is never silently'
assert_contains "$readme_zh" '已完成'

assert_contains "$readme" 'flow=15927'
assert_contains "$readme" 'flow/15927-sewer-layer-editing'
assert_contains "$readme_zh" 'flow=15927'
assert_contains "$readme_zh" 'flow/15927-sewer-layer-editing'
assert_contains "$readme" 'same working directory'
assert_contains "$readme_zh" '同一個工作目錄'
assert_valid_flow 15927
assert_valid_flow 123456789
assert_invalid_flow 1234567890
assert_invalid_flow abc
assert_valid_flow_branch 15927 'flow/15927-sewer-layer-editing'
assert_valid_flow_branch 15927 'flow/15927'
assert_invalid_flow_branch 'feat/15927-sewer-layer-editing'
if [[ 'flow/15928-sewer-layer-editing' =~ ^flow/[0-9]{1,9}(-[A-Za-z0-9_-]+)?$ ]]; then
  branch_flow='15928'
  [[ "$branch_flow" != 15927 ]] || fail 'mismatched flow branch was accepted'
fi

# The old proposal-only or contradictory visible contract must not survive.
assert_not_contains "$provisioning" 'The route changes what the workflow is allowed to isolate;'
assert_not_contains "$plan" 'Status: Implemented'
assert_not_contains "$readme" 'The in-place route keeps the current checkout and branch;'
assert_not_contains "$readme" 'Both routes keep automated checks and explicit manual approval'
assert_not_contains "$readme_zh" 'In-place route 則留在目前分支'
assert_not_contains "$invocation" 'workspace=inferred'
assert_not_contains "$adr" 'workspace=checkout|worktree|inferred'
assert_not_contains "$readme" 'workspace=inferred'
assert_not_contains "$readme_zh" 'workspace=inferred'

printf 'task workflow policy tests: workspace and policy contract OK\n'
