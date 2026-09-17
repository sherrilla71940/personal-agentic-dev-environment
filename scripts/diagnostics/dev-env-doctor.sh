#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/../.." && pwd -P)"
failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

same_path() {
  local left right
  left="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  right="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  [[ "$left" == "$right" ]]
}

printf 'developer environment doctor\n'
printf 'repository: %s\n\n' "$repository_root"

source_path="$(chezmoi source-path 2>/dev/null || true)"
if [[ -z "$source_path" ]]; then
  fail 'chezmoi source-path could not be resolved'
else
  printf 'chezmoi source: %s\n' "$source_path"
  source_repository="$(git -C "$source_path" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$source_repository" ]]; then
    fail 'the resolved chezmoi source is not a Git checkout'
  else
    source_repository="$(canonical_dir "$source_repository")"
    if same_path "$source_repository" "$repository_root"; then
      pass 'chezmoi source identity matches this repository'
    else
      fail "chezmoi source identity is $source_repository, expected $repository_root"
    fi
  fi
fi

if [[ -n "${source_path:-}" && -f "$source_path/.chezmoitemplates/ai-profile.yaml" ]]; then
  profile_output="$(chezmoi execute-template --file "$source_path/.chezmoitemplates/ai-profile.yaml" 2>&1 || true)"
  profile_context="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^ai_context: "\(.*\)"$/\1/p')"
  profile_continuity="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^ai_continuity: "\(.*\)"$/\1/p')"
  profile_harness="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^ai_harness: "\(.*\)"$/\1/p')"
  profile_guidance="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^continuity_guidance: "\(.*\)"$/\1/p')"
  profile_automation="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^continuity_automation: "\(.*\)"$/\1/p')"
  profile_notifications="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^notifications: "\(.*\)"$/\1/p')"
  profile_worktree_guard="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^worktree_guard: "\(.*\)"$/\1/p')"
  profile_statusline="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^statusline: "\(.*\)"$/\1/p')"
  profile_language="$(printf '%s\n' "$profile_output" | tr -d '\r' | sed -n 's/^artifact_language: "\(.*\)"$/\1/p')"
  if [[ -n "$profile_context" && -n "$profile_continuity" && -n "$profile_harness" &&
        -n "$profile_guidance" && -n "$profile_automation" && -n "$profile_notifications" &&
        -n "$profile_worktree_guard" && -n "$profile_statusline" && -n "$profile_language" ]]; then
    printf 'machine selectors: ai_context=%s, ai_continuity=%s, ai_harness=%s, artifact_language=%s\n' \
      "$profile_context" "$profile_continuity" "$profile_harness" "$profile_language"
    printf 'derived behavior: continuity_guidance=%s, continuity_automation=%s, notifications=%s, worktree_guard=%s, statusline=%s\n' \
      "$profile_guidance" "$profile_automation" "$profile_notifications" "$profile_worktree_guard" "$profile_statusline"
    pass 'machine-local profile values render successfully'
  else
    fail "machine-local profile could not be rendered: $profile_output"
  fi
else
  fail 'the ai-profile template is not available through the resolved source'
fi

printf 'repository override: personal (AGENTS.md has priority while working in this repository)\n'

status_output="$(chezmoi status 2>&1 || true)"
if [[ -z "$(printf '%s\n' "$status_output" | sed '/^[[:space:]]*$/d')" ]]; then
  pass 'chezmoi status is clean'
else
  warn 'chezmoi has unapplied target drift:'
  printf '%s\n' "$status_output"
fi

link_count=0
link_failures=0
for source_link in "$repository_root"/home/dot_claude/skills/symlink_*.tmpl; do
  [[ -e "$source_link" ]] || continue
  skill_name="$(basename "$source_link" .tmpl)"
  skill_name="${skill_name#symlink_}"
  live_link="$HOME/.claude/skills/$skill_name"
  expected_target="$HOME/.agents/skills/$skill_name"
  link_count=$((link_count + 1))
  if [[ ! -L "$live_link" || ! -d "$expected_target" ]]; then
    link_failures=$((link_failures + 1))
    printf '  FAIL: %s is not a symlink to %s\n' "$live_link" "$expected_target"
    continue
  fi
  actual_target="$(canonical_dir "$live_link" || true)"
  expected_target="$(canonical_dir "$expected_target" || true)"
  if ! same_path "$actual_target" "$expected_target"; then
    link_failures=$((link_failures + 1))
    printf '  FAIL: %s resolves to %s, expected %s\n' "$live_link" "$actual_target" "$expected_target"
  fi
done
if [[ "$link_failures" -eq 0 ]]; then
  pass "Claude shared-skill links are healthy ($link_count checked)"
else
  fail "$link_failures Claude shared-skill link(s) are unhealthy"
fi

report_version() {
  local label command_name version
  label="$1"
  command_name="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "$label is not available on PATH"
    return
  fi
  version="$($command_name --version 2>&1 | sed -n '1p')"
  printf '%s: %s\n' "$label" "$version"
}

printf '\nversions\n'
report_version chezmoi chezmoi
report_version git git
report_version node node
if command -v python >/dev/null 2>&1; then
  report_version python python
else
  report_version python python3
fi

if [[ "$failures" -eq 0 ]]; then
  printf '\nDoctor found no blocking issues.\n'
else
  printf '\nDoctor found %s blocking issue(s).\n' "$failures" >&2
fi
exit "$failures"
