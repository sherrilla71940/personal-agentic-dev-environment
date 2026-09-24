#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
session_start_hook="$repository_root/home/dot_claude/hooks/check-worktree-launch.sh"
fixture="$(mktemp -d)"
rendered_hook_directory="$(mktemp -d)"

# The lifecycle helper became a chezmoi template when continuity gained an off switch, so these
# cases run the rendered script rather than the source. They describe the enabled helper's
# reporting behaviour, so render it with continuity on regardless of this machine's selector; the
# profile suite owns the disabled no-op. The rendered copy lives outside the fixture repository so
# it cannot appear as an untracked file in the working tree under test.
command -v chezmoi >/dev/null 2>&1 || { printf 'continuity hook tests: chezmoi is required\n' >&2; exit 1; }
lifecycle_hook="$rendered_hook_directory/maintain-task-continuity.sh"
printf 'ai_context: personal\nai_continuity: "on"\n' > "$rendered_hook_directory/profile.yaml"
chezmoi execute-template --source="$repository_root" \
  --override-data-file="$rendered_hook_directory/profile.yaml" \
  --file "$repository_root/home/dot_local/share/maintain-task-continuity.sh.tmpl" \
  > "$lifecycle_hook"

cleanup() {
  case "$fixture" in
    "${TMPDIR:-/tmp}"/*) rm -rf -- "$fixture" ;;
    *) printf 'Refusing to remove unexpected fixture path: %s\n' "$fixture" >&2 ;;
  esac
  case "$rendered_hook_directory" in
    "${TMPDIR:-/tmp}"/*) rm -rf -- "$rendered_hook_directory" ;;
    *) printf 'Refusing to remove unexpected rendered hook path: %s\n' "$rendered_hook_directory" >&2 ;;
  esac
}
trap cleanup EXIT

git -C "$fixture" init -q
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config core.autocrlf false
printf 'fixture\n' > "$fixture/tracked.txt"
git -C "$fixture" add tracked.txt
git -C "$fixture" commit -qm initial

session_id="continuity-hook-test-$$"
state_file="$fixture/.task-continuity/state.md"

# SessionStart reporting lives in the lifecycle hook, not in any one client's launch hook, so
# that Codex gets it too. It must name the tracked objective: the same-task decision is what
# stops an unrelated request overwriting an unfinished task's handoff state.
mkdir -p "$fixture/.task-continuity"
printf '# Task Continuity\n\n## Objective\n\nRepair the invoice export so totals match\nthe ledger for partial refunds.\n\n## Next actions\n\n1. Keep the task open.\n' > "$state_file"
session_start() {
  jq -cn --arg sid "$session_id" --arg cwd "$fixture" --arg src "$1" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"SessionStart",source:$src}' \
    | bash "$lifecycle_hook" | jq -r '.hookSpecificOutput.additionalContext // ""'
}
session_start_raw() {
  jq -cn --arg sid "$session_id" --arg cwd "$fixture" --arg src "$1" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"SessionStart",source:$src}' \
    | bash "$lifecycle_hook"
}

active_output="$(session_start compact)"
case "$active_output" in
  *"Task continuity is active"*) ;;
  *) printf 'expected the active notice, got: %s\n' "$active_output" >&2; exit 1 ;;
esac
# The whole first paragraph, joined onto one line - not just its first line.
case "$active_output" in
  *"Repair the invoice export so totals match the ledger for partial refunds."*) ;;
  *) printf 'the objective must be named in full, got: %s\n' "$active_output" >&2; exit 1 ;;
esac
# Continuity existing is what makes the exclude entry appear.
git -C "$fixture" check-ignore -q .task-continuity/state.md

# A legacy-only state remains readable during the one-time migration window, but the report-only
# hook must not move, rewrite, or delete it. The task-continuity procedure owns the explicit move.
legacy_state_file="$fixture/.project-continuity/state.md"
mv "$fixture/.task-continuity" "$fixture/.project-continuity"
legacy_before="$(cat "$legacy_state_file")"
legacy_output="$(session_start_raw startup)"
case "$legacy_output" in
  *"Task continuity is active"*) ;;
  *) printf 'expected the legacy continuity state to remain readable, got: %s\n' "$legacy_output" >&2; exit 1 ;;
esac
[[ ! -d "$fixture/.task-continuity" ]] || { printf 'legacy-only hook must not create a canonical state directory\n' >&2; exit 1; }
[[ "$(cat "$legacy_state_file")" == "$legacy_before" ]] || { printf 'legacy state changed during report-only inspection\n' >&2; exit 1; }
mv "$fixture/.project-continuity" "$fixture/.task-continuity"

# A partial rename must not let the hook choose one state directory silently. The migration is a
# controlled operation owned by the task-continuity skill, so both lifecycle events surface the
# collision and stop before reading either state file.
mkdir -p "$fixture/.project-continuity"
collision_session_output="$(session_start_raw startup)"
case "$(printf '%s' "$collision_session_output" | jq -r '.systemMessage // ""')" in
  *"both .task-continuity/ and legacy .project-continuity/"*) ;;
  *) printf 'expected the continuity directory collision notice, got: %s\n' "$collision_session_output" >&2; exit 1 ;;
esac
collision_stop_output="$(jq -cn --arg sid "$session_id" --arg cwd "$fixture" \
  '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false}' \
  | bash "$lifecycle_hook")"
case "$(printf '%s' "$collision_stop_output" | jq -r '.systemMessage // ""')" in
  *"both .task-continuity/ and legacy .project-continuity/"*) ;;
  *) printf 'expected the Stop collision notice, got: %s\n' "$collision_stop_output" >&2; exit 1 ;;
esac
rmdir "$fixture/.project-continuity"

# With no Objective section there is nothing to name, so the plain notice is used.
printf '# Task Continuity\n\n## Next actions\n\n1. Keep the task open.\n' > "$state_file"
case "$(session_start startup)" in
  *"tracks this objective"*) printf 'must not claim an objective when there is none\n' >&2; exit 1 ;;
  *"Task continuity is active"*) ;;
  *) printf 'expected the plain active notice\n' >&2; exit 1 ;;
esac

# No continuity at all: the activation reminder, and a distinct one after compaction.
rm -f "$state_file"
case "$(session_start startup)" in
  *"Task continuity is not active"*) ;;
  *) printf 'expected the activation reminder\n' >&2; exit 1 ;;
esac
case "$(session_start compact)" in
  *"compacted without active task continuity"*) ;;
  *) printf 'expected the post-compaction reminder\n' >&2; exit 1 ;;
esac

# The Claude-only launch hook must no longer say anything about continuity.
launch_output="$(jq -cn --arg sid "$session_id" --arg cwd "$fixture" \
  '{session_id:$sid,cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}' \
  | bash "$session_start_hook" || true)"
case "$launch_output" in
  *continuity*) printf 'continuity reporting must not be in the launch hook: %s\n' "$launch_output" >&2; exit 1 ;;
esac

printf '# Task Continuity\n\n## Next actions\n\n1. Keep the task open.\n' > "$state_file"

# Nothing blocks a Stop any more; the hook only ever reports.
stop_output="$(jq -cn --arg sid "$session_id" --arg cwd "$fixture" \
  '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false}' \
  | bash "$lifecycle_hook")"
if printf '%s' "$stop_output" | jq -e 'has("decision")' >/dev/null 2>&1; then
  printf 'Stop must never block\n' >&2
  exit 1
fi

printf 'task continuity hook lifecycle OK\n'

# --- Drift notices and the cleanup offer -------------------------------------------------------
# Stop only ever reports; these exercise drift, active cleanup, and parked closure notices.
fixture_branch="$(git -C "$fixture" branch --show-current)"
fixture_head="$(git -C "$fixture" rev-parse --short HEAD)"

write_state() {
  # write_state <branch> <head> <trailing-verification-lines...>
  local branch="$1" head="$2"
  shift 2
  mkdir -p "$fixture/.task-continuity"
  {
    printf '# Task Continuity\n\n## Objective\n\nExercise the Stop notices.\n\n'
    printf '## Verification\n\n'
    printf -- '- Branch: `%s`\n' "$branch"
    printf -- '- HEAD: `%s`\n' "$head"
    local line
    for line in "$@"; do
      printf -- '%s\n' "$line"
    done
  } > "$state_file"
}

append_section() {
  printf '\n## %s\n\n%s\n' "$1" "$2" >> "$state_file"
}

stop_notice() {
  jq -cn --arg sid "$session_id" --arg cwd "$fixture" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false}' \
    | bash "$lifecycle_hook"
}

notice_message() {
  printf '%s' "$1" | jq -r '.systemMessage // ""'
}

# A recorded commit that has left this history is real drift - rebased, reset, or state belonging
# to another line of work - and the recorded starting point can no longer be trusted.
write_state "$fixture_branch" deadbee
append_section 'Next actions' '1. Keep the task open.'
head_message="$(notice_message "$(stop_notice)")"
case "$head_message" in
  *"is out of date"*"no longer in this history"*) ;;
  *) printf 'expected HEAD-drift notice, got: %s\n' "$head_message" >&2; exit 1 ;;
esac
case "$head_message" in
  *"not by itself a new task"*)
    printf 'HEAD drift must not emit the branch-switch warning\n' >&2; exit 1 ;;
esac

# One commit ahead of the last checkpoint is work in flight, so the notice stays silent -
# otherwise it fires after every commit and the reader learns to ignore it.
one_behind_head="$(git -C "$fixture" rev-parse --short HEAD)"
printf 'advance\n' >> "$fixture/tracked.txt"
git -C "$fixture" add tracked.txt
git -C "$fixture" commit -qm 'advance HEAD once'
write_state "$fixture_branch" "$one_behind_head"
append_section 'Next actions' '1. Keep the task open.'
if [[ -n "$(stop_notice)" ]]; then
  printf 'one commit ahead is work in flight, not drift: %s\n' "$(notice_message "$(stop_notice)")" >&2
  exit 1
fi

# Two or more means a checkpoint opportunity passed without the file being rewritten, which is
# when its claims start being overtaken. That is worth saying, and it says rewrite rather than
# patch, because the claims that go stale are the ones nobody was thinking about.
printf 'advance\n' >> "$fixture/tracked.txt"
git -C "$fixture" add tracked.txt
git -C "$fixture" commit -qm 'advance HEAD twice'
fixture_head="$(git -C "$fixture" rev-parse --short HEAD)"
write_state "$fixture_branch" "$one_behind_head"
append_section 'Next actions' '1. Keep the task open.'
behind_message="$(notice_message "$(stop_notice)")"
case "$behind_message" in
  *"behind the work"*"last reconciled 2 commits ago"*"Rewrite"*"whole"*) ;;
  *) printf 'expected the behind-the-work notice, got: %s\n' "$behind_message" >&2; exit 1 ;;
esac
case "$behind_message" in
  *"no longer in this history"*)
    printf 'a commit that is still an ancestor must not read as lost history\n' >&2; exit 1 ;;
esac

# A different branch may mean a different task, so the notice must warn against merging rather
# than ask for reconciliation - that is the case that used to corrupt the previous task's state.
write_state some-other-branch "$fixture_head"
append_section 'Next actions' '1. Keep the task open.'
branch_message="$(notice_message "$(stop_notice)")"
case "$branch_message" in
  *"not by itself a new task"*"park it instead"*) ;;
  *) printf 'expected branch-switch warning, got: %s\n' "$branch_message" >&2; exit 1 ;;
esac
case "$branch_message" in
  *"is out of date"*)
    printf 'branch drift must not reuse the stale-HEAD reconcile wording\n' >&2; exit 1 ;;
esac

# Both drifting reports the branch warning first and mentions the stale commit separately.
write_state some-other-branch deadbee
append_section 'Next actions' '1. Keep the task open.'
both_message="$(notice_message "$(stop_notice)")"
case "$both_message" in
  *"not by itself a new task"*"Separately, continuity records HEAD deadbee"*) ;;
  *) printf 'expected combined branch-then-HEAD notice, got: %s\n' "$both_message" >&2; exit 1 ;;
esac

# A Verification line may carry code spans of its own after the value. Reading the last span
# rather than the first reported a branch the file never recorded, and the hook then cried drift
# on every response of a session that had done nothing wrong. Found by a fixture run.
{
  printf '# Task Continuity\n\n## Objective\n\nExercise the Stop notices.\n\n'
  printf '## Verification\n\n'
  printf -- '- Branch: `%s` (created off `master`; repo has no `main`)\n' "$fixture_branch"
  printf -- '- HEAD: `%s`\n' "$fixture_head"
} > "$state_file"
append_section 'Next actions' '1. Keep the task open.'
annotated_message="$(notice_message "$(stop_notice)")"
if [[ -n "$annotated_message" ]]; then
  printf 'an annotated Branch line must not read as drift, got: %s\n' "$annotated_message" >&2
  exit 1
fi

# An explicit feature checkpoint can expose a contradiction that Git alone cannot answer. The
# lifecycle reporter stays conservative: it only checks the documented structured form and leaves
# broader reconciliation to the task-continuity skill.
{
  printf '# Task Continuity\n\n## Objective\n\nExercise the progress guard.\n\n'
  printf '## Current phase\n\n- Feature: `FE-03` - complete\n\n'
  printf '## Verification\n\n'
  printf -- '- Branch: `%s`\n' "$fixture_branch"
  printf -- '- HEAD: `%s`\n' "$fixture_head"
  printf -- '- Feature: `FE-03` - browser verification pending\n'
} > "$state_file"
contradiction_message="$(notice_message "$(stop_notice)")"
case "$contradiction_message" in
  *"progress/verification contradiction"*"FE-03"*"pending"*) ;;
  *) printf 'expected a structured progress/verification contradiction notice, got: %s\n' \
    "$contradiction_message" >&2; exit 1 ;;
esac


# A detached HEAD has no branch name, which is how the Codex app runs its managed worktrees. It
# must not read as branch drift.
git -C "$fixture" checkout -q --detach HEAD
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Keep the task open.'
test -z "$(stop_notice)"
git -C "$fixture" checkout -q "$fixture_branch"

# A state file with no unfinished work anywhere should raise the cleanup offer.
write_state "$fixture_branch" "$fixture_head"
append_section 'Decisions still in force' '- A decision that still binds.'
cleanup_message="$(notice_message "$(stop_notice)")"
case "$cleanup_message" in
  *"TASK CONTINUITY COMPLETION GATE REQUIRED"*"records no unfinished work"*"confirm"*) ;;
  *) printf 'expected cleanup offer, got: %s\n' "$cleanup_message" >&2; exit 1 ;;
esac
test -f "$state_file"

# A completed parked state must be reported even though the active-state cleanup offer does not
# inspect parked files. The report is a candidate only; deletion still needs confirmation.
parked_directory="$fixture/.task-continuity/parked"
parked_candidate="$parked_directory/completed-task.md"
mkdir -p "$parked_directory"
{
  printf '# Task Continuity\n\n## Objective\n\nCompleted parked task.\n\n'
  printf '## Verification\n\n- Parked: `2026-09-16T10:00:00+08:00`\n'
} > "$parked_candidate"
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Keep the active task open.'
parked_message="$(notice_message "$(stop_notice)")"
case "$parked_message" in
  *"Completed parked continuity files are closure candidates"*"parked/completed-task.md"*"confirm"*) ;;
  *) printf 'expected completed parked closure candidate, got: %s\n' "$parked_message" >&2; exit 1 ;;
esac

# A parked file without the required timestamp must not disappear from age-based review. Report
# the unknown age so the continuity skill can reconcile it without trusting file-system metadata.
parked_metadata_candidate="$parked_directory/missing-timestamp.md"
{
  printf '# Task Continuity\n\n## Objective\n\nParked task with incomplete metadata.\n\n'
  printf '## Next actions\n\n1. Keep the parked task open.\n'
} > "$parked_metadata_candidate"
metadata_message="$(notice_message "$(stop_notice)")"
case "$metadata_message" in
  *"Parked continuity metadata is incomplete"*"age is unknown"*"parked/missing-timestamp.md"*) ;;
  *) printf 'expected unknown parked age notice, got: %s\n' "$metadata_message" >&2; exit 1 ;;
esac
rm -f "$parked_metadata_candidate"

# A unique exact-branch candidate with task and start-commit metadata is discoverable, but the hook
# remains report-only. The task-continuity skill performs the request comparison and restoration.
parked_branch_candidate="$parked_directory/branch-resumable-task.md"
parked_branch_base="$(git -C "$fixture" rev-list --max-parents=0 HEAD)"
{
  printf '# Task Continuity\n\n## Objective\n\nResume the branch-aware task.\n\n'
  printf '## Next actions\n\n1. Resume and reconcile the parked task.\n\n## Verification\n\n'
  printf -- '- Task: `branch-resumable-task`\n'
  printf -- '- Branch: `%s`\n' "$fixture_branch"
  printf -- '- HEAD: `%s`\n' "$fixture_head"
  printf -- '- Base commit: `%s`\n' "$parked_branch_base"
  printf -- '- Started from: `%s`\n' "$parked_branch_base"
  printf -- '- Parked: `2026-09-24T10:00:00+08:00`\n'
} > "$parked_branch_candidate"
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Keep the active task open.'
unique_branch_message="$(notice_message "$(stop_notice)")"
case "$unique_branch_message" in
  *"PARKED CONTINUITY MATCH"*"branch-resumable-task.md"*"only parked state"*"Task and reachable Base commit"*) ;;
  *) printf 'expected unique parked branch candidate, got: %s\n' "$unique_branch_message" >&2; exit 1 ;;
esac

# Two strong candidates on the same branch are not deterministic. The hook must require explicit
# disambiguation instead of restoring the first directory entry returned by the shell.
second_parked_branch_candidate="$parked_directory/second-branch-resumable-task.md"
sed 's/branch-resumable-task/second-branch-resumable-task/g' "$parked_branch_candidate" > "$second_parked_branch_candidate"
ambiguous_branch_message="$(notice_message "$(stop_notice)")"
case "$ambiguous_branch_message" in
  *"PARKED CONTINUITY MATCHES REQUIRE DISAMBIGUATION"*"branch-resumable-task.md"*"second-branch-resumable-task.md"*) ;;
  *) printf 'expected ambiguous parked branch candidates, got: %s\n' "$ambiguous_branch_message" >&2; exit 1 ;;
esac
case "$ambiguous_branch_message" in
  *"only parked state"*)
    printf 'ambiguous parked candidates must not be reported as unique\n' >&2
    exit 1
    ;;
esac

# A branch-only legacy record is not a strong match, even when it is the only candidate.
rm -f "$second_parked_branch_candidate"
{
  printf '# Task Continuity\n\n## Objective\n\nLegacy branch-only task.\n\n'
  printf '## Next actions\n\n1. Keep the legacy task open.\n\n## Verification\n\n'
  printf -- '- Branch: `%s`\n' "$fixture_branch"
  printf -- '- Parked: `2026-09-24T10:00:00+08:00`\n'
} > "$parked_branch_candidate"
legacy_branch_message="$(notice_message "$(stop_notice)")"
case "$legacy_branch_message" in
  *"PARKED CONTINUITY MATCHES REQUIRE DISAMBIGUATION"*"Legacy or incomplete candidates"*"branch-resumable-task.md"*) ;;
  *) printf 'expected legacy parked branch review, got: %s\n' "$legacy_branch_message" >&2; exit 1 ;;
esac
rm -f "$parked_branch_candidate"

# The parked candidate is reported even when there is no active state file.
rm -f "$state_file"
no_active_parked_message="$(notice_message "$(stop_notice)")"
case "$no_active_parked_message" in
  *"Completed parked continuity files are closure candidates"*"parked/completed-task.md"*) ;;
  *) printf 'expected parked candidate without active state, got: %s\n' "$no_active_parked_message" >&2; exit 1 ;;
esac

# A declined parked cleanup offer must stay quiet on later reviews.
{
  printf '# Task Continuity\n\n## Objective\n\nCompleted parked task.\n\n'
  printf '## Verification\n\n- Cleanup: `declined`\n'
} > "$parked_candidate"
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Keep the active task open.'
if notice_message "$(stop_notice)" | grep -q 'Completed parked continuity files'; then
  printf 'a declined parked cleanup candidate must stay quiet\n' >&2
  exit 1
fi

# Test fixtures must not let this candidate affect the remaining active-state cases.
rm -f "$parked_candidate"
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Keep the active task open.'

# Present-but-empty tracking sections count as finished too.
write_state "$fixture_branch" "$fixture_head"
append_section 'In progress' ''
append_section 'Next actions' ''
append_section 'Blockers' ''
append_section 'TODO / deferred' ''
notice_message "$(stop_notice)" | grep -q 'records no unfinished work'

# A cleanup reminder accidentally left in Next actions must not suppress the completion gate. The
# hook reports the placeholder so the skill can reconcile it out of the unfinished sections.
write_state "$fixture_branch" "$fixture_head"
append_section 'Next actions' '1. Offer cleanup of this active continuity state; delete it only after the user confirms.'
cleanup_placeholder_message="$(notice_message "$(stop_notice)")"
case "$cleanup_placeholder_message" in
  *"records no unfinished work"*"cleanup wording appears in unfinished-task sections"*) ;;
  *) printf 'expected cleanup placeholder and completion notices, got: %s\n' \
    "$cleanup_placeholder_message" >&2; exit 1 ;;
esac

# One open item in any tracking section is enough to keep the offer silent.
for open_section in 'In progress' 'Next actions' 'Blockers' 'TODO / deferred'; do
  write_state "$fixture_branch" "$fixture_head"
  append_section "$open_section" '- Still outstanding.'
  if [[ -n "$(stop_notice)" ]]; then
    printf 'an open item in %s must suppress the cleanup offer\n' "$open_section" >&2
    exit 1
  fi
done

# A declined offer is not raised again for the rest of the task.
write_state "$fixture_branch" "$fixture_head" '- Cleanup: `declined`'
append_section 'Decisions still in force' '- A decision that still binds.'
test -z "$(stop_notice)"

# Drift outranks the cleanup offer, because one response carries one system message and wrong
# recorded state misleads the next reader more than an unretired file does. The completion gate is
# still present when the stale state has no open tracking items.
write_state "$fixture_branch" deadbee
append_section 'Decisions still in force' '- A decision that still binds.'
notice_message "$(stop_notice)" | grep -q 'is out of date'

write_state "$fixture_branch" deadbee
cleanup_with_drift_message="$(notice_message "$(stop_notice)")"
case "$cleanup_with_drift_message" in
  *"is out of date"*"TASK CONTINUITY COMPLETION GATE REQUIRED"*) ;;
  *) printf 'stale-state notice must not hide the completion gate, got: %s\n' \
    "$cleanup_with_drift_message" >&2; exit 1 ;;
esac

# With no Verification block there is nothing to compare against, so drift stays silent -
# but the file still records no unfinished work, so the cleanup offer is the right notice.
printf '# Task Continuity\n\n## Objective\n\nNo verification block.\n' > "$state_file"
notice_message "$(stop_notice)" | grep -q 'records no unfinished work'

printf 'task continuity drift and cleanup notices OK\n'
