#!/usr/bin/env bash
# Render and check the eight accepted machine-local AI profile combinations without touching live
# targets. Native continuity on/off has the same effective lifecycle behavior because continuity is
# a managed-mode option, but both inputs remain accepted and the stored preference is preserved.
#
# No JSONC parser is installed on the host, so the VS Code checks carry a small string-aware one:
# comments and trailing commas are removed outside string literals and the result is parsed as
# JSON. That keeps the managed settings file JSONC -- its comments label the active commit-message
# block -- while still catching structural errors that balanced delimiters alone would miss.
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
chezmoi_bin="$(command -v chezmoi || true)"
if [[ -z "$chezmoi_bin" ]]; then
  printf 'profile tests: chezmoi is required\n' >&2
  exit 1
fi

if ! command -v cat >/dev/null 2>&1 && [[ -n "${LOCALAPPDATA:-}" ]]; then
  local_app_data="$LOCALAPPDATA"
  if command -v cygpath >/dev/null 2>&1; then
    local_app_data="$(cygpath -u "$local_app_data")"
  fi
  for candidate in "$local_app_data"/Programs/Git/usr/bin "$local_app_data"/Git/usr/bin; do
    if [[ -x "$candidate/cat.exe" ]]; then
      PATH="$candidate:$PATH"
      export PATH
      break
    fi
  done
fi
command -v cat >/dev/null 2>&1 || { printf 'profile tests: cat is required\n' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'profile tests: jq is required\n' >&2; exit 1; }

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
config_file="$work_directory/chezmoi.toml"
printf '[data]\n' > "$config_file"

fail() {
  printf 'profile tests: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "'$needle' not found in $file"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "unexpected '$needle' in $file"
}

# Parse the rendered VS Code settings as JSONC instead of only balancing delimiters. The file is
# deliberately JSONC: its comments label which commit-message block is active, and dozens of string
# values carry "//" inside URLs, so a strict JSON parse and a naive comment strip both report false
# failures. Tokenise with string awareness, drop comments and trailing commas, then parse -- which
# catches structural errors that balanced brackets cannot -- and confirm both contexts ship the same
# number of commit-message instructions.
assert_jsonc_structure() {
  local file="$1" expected_instructions="$2"
  python - "$file" "$expected_instructions" <<'PY'
import json
import sys

path, expected = sys.argv[1], int(sys.argv[2])
text = open(path, encoding="utf-8").read()
backslash = chr(92)
newline = chr(10)


def copy_string(source, index, sink):
    sink.append(source[index])
    index += 1
    while index < len(source):
        sink.append(source[index])
        if source[index] == backslash:
            sink.append(source[index + 1])
            index += 2
            continue
        if source[index] == '"':
            return index + 1
        index += 1
    raise SystemExit("unterminated string in %s" % path)


stripped = []
i = 0
while i < len(text):
    char = text[i]
    following = text[i + 1] if i + 1 < len(text) else ""
    if char == '"':
        i = copy_string(text, i, stripped)
        continue
    if char == "/" and following == "/":
        while i < len(text) and text[i] != newline:
            i += 1
        continue
    if char == "/" and following == "*":
        i += 2
        while i + 1 < len(text) and not (text[i] == "*" and text[i + 1] == "/"):
            i += 1
        i += 2
        continue
    stripped.append(char)
    i += 1

source = "".join(stripped)
cleaned = []
i = 0
while i < len(source):
    if source[i] == '"':
        i = copy_string(source, i, cleaned)
        continue
    if source[i] == ",":
        j = i + 1
        while j < len(source) and source[j].isspace():
            j += 1
        if j < len(source) and source[j] in "}]":
            i += 1
            continue
    cleaned.append(source[i])
    i += 1

try:
    data = json.loads("".join(cleaned))
except ValueError as error:
    raise SystemExit("invalid JSONC in %s: %s" % (path, error))

key = "github.copilot.chat.commitMessageGeneration.instructions"
if key not in data:
    raise SystemExit("missing %s in %s" % (key, path))
if len(data[key]) != expected:
    raise SystemExit(
        "expected %d commit-message instructions in %s, found %d"
        % (expected, path, len(data[key]))
    )
PY
}

assert_json() {
  python - "$@" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as stream:
        json.load(stream)
PY
}

# Check what the rendered continuity helper does, not what it says. Text assertions cannot show
# that a disabled hook stays silent and leaves the working tree alone, and those two properties are
# the whole point of continuity off: the client must see no output, the tracked state file must not
# change, and .git/info/exclude must not gain the private-state entry the enabled helper adds.
assert_hook_behavior() {
  local continuity="$1" harness="$2" hook="$3"
  local fixture state exclude payload output
  local state_before exclude_before state_after exclude_after

  fixture="$(mktemp -d)"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.com
  git -C "$fixture" config user.name test
  git -C "$fixture" config core.autocrlf false
  printf 'fixture\n' > "$fixture/tracked.txt"
  git -C "$fixture" add tracked.txt
  git -C "$fixture" commit -qm initial

  mkdir -p "$fixture/.project-continuity"
  state="$fixture/.project-continuity/state.md"
  printf '# Project Continuity\n\n## Objective\n\nKeep the fixture task open.\n\n## Next actions\n\n1. Keep the task open.\n' > "$state"
  exclude="$(git -C "$fixture" rev-parse --path-format=absolute --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"

  state_before="$(cksum < "$state")"
  exclude_before="$(cksum < "$exclude")"
  payload="$(jq -cn --arg cwd "$fixture" '{session_id:"profile-test",cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}')"
  output="$(printf '%s' "$payload" | bash "$hook" 2>&1 || true)"
  state_after="$(cksum < "$state")"
  exclude_after="$(cksum < "$exclude")"
  rm -rf "$fixture"

  [[ "$state_before" == "$state_after" ]] ||
    fail "continuity $continuity: hook rewrote continuity state"

  if [[ "$continuity" == off || "$harness" == native ]]; then
    [[ -z "$output" ]] || fail "continuity hook was not quiet ($continuity/$harness)"
    [[ "$exclude_before" == "$exclude_after" ]] ||
      fail "continuity hook changed .git/info/exclude ($continuity/$harness)"
  else
    [[ -n "$output" ]] || fail 'managed continuity on: hook reported nothing for tracked state'
  fi
}

render_profile() {
  local context="$1" continuity="$2" harness="$3" destination="$4"
  local override="$work_directory/$context-$continuity-$harness.yaml"
  printf 'ai_context: %s\nai_continuity: %s\nai_harness: %s\n' \
    "$context" "$continuity" "$harness" > "$override"
  mkdir -p "$destination"
  "$chezmoi_bin" apply \
    --config="$config_file" \
    --source="$repository_root" \
    --destination="$destination" \
    --exclude=scripts \
    --override-data-file="$override" \
    --no-tty \
    --force >/dev/null
}

check_profile() {
  local context="$1" continuity="$2" harness="$3" destination="$4"
  local claude="$destination/.claude/CLAUDE.md"
  local codex="$destination/.codex/AGENTS.md"
  local copilot="$destination/.copilot/instructions/core.instructions.md"
  local commit_skill="$destination/.agents/skills/git-commit-action/SKILL.md"
  local lifecycle_hook="$destination/.local/share/maintain-project-continuity.sh"
  local project_continuity="$destination/.agents/skills/project-continuity/SKILL.md"
  local workflow="$destination/.agents/skills/worktree-task-workflow/SKILL.md"
  local invocation="$destination/.agents/skills/worktree-task-workflow/references/invocation.md"
  local publishing="$destination/.agents/skills/worktree-task-workflow/references/publish.md"
  local settings

  assert_file "$claude"
  assert_file "$codex"
  assert_file "$copilot"
  assert_file "$commit_skill"
  assert_file "$project_continuity"
  assert_file "$workflow"
  assert_file "$invocation"
  assert_file "$publishing"
  [[ "$(head -n 1 "$codex")" != '---' ]] ||
    fail "Codex adapter unexpectedly rendered frontmatter ($context/$continuity)"

  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
    settings="$destination/AppData/Roaming/Code/User/settings.json"
  else
    settings="$destination/Library/Application Support/Code/User/settings.json"
  fi
  assert_file "$settings"

  assert_contains "$claude" "Edit source-of-truth files"
  assert_contains "$claude" "The active context is \`$context\`."
  if [[ "$context" == company ]]; then
    assert_not_contains "$claude" 'The active context is `personal`.'
    assert_contains "$claude" "Traditional Chinese comments by default"
    assert_not_contains "$claude" "use English comments by default"
    assert_contains "$commit_skill" '| **Language** | `en` · `zhtw`      | `zhtw`'
    assert_contains "$invocation" 'commit and request text only | `zhtw`'
    assert_contains "$publishing" 'active context default `zhtw`'
    assert_contains "$settings" 'Use zh-TW for summary and for scope when present.'
    assert_not_contains "$settings" 'Use English for summary and for scope when present.'
  else
    assert_not_contains "$claude" 'The active context is `company`.'
    assert_contains "$claude" "use English comments by default"
    assert_not_contains "$claude" "Traditional Chinese comments by default"
    assert_contains "$commit_skill" '| **Language** | `en` · `zhtw`      | `en`'
    assert_contains "$invocation" 'commit and request text only | `en`'
    assert_contains "$publishing" 'active context default `en`'
    assert_contains "$settings" 'Use English for summary and for scope when present.'
    assert_not_contains "$settings" 'Use zh-TW for summary and for scope when present.'
  fi

  assert_contains "$claude" 'comments are written in English unconditionally'
  assert_contains "$project_continuity" 'State language is independent of conversation language.'
  assert_contains "$project_continuity" 'Session export: required'
  assert_contains "$workflow" 'recorded base commit'
  assert_contains "$invocation" 'remote-base checkpoint'
  assert_contains "$publishing" 'redacted identities'
  assert_contains "$publishing" 'Integrate the current base before publishing'
  assert_contains "$publishing" 'git fetch origin --prune'
  assert_contains "$publishing" 'Do not use ambiguous `git pull`'
  assert_contains "$publishing" 'git rebase --continue'
  assert_contains "$publishing" 'return to the manual-test gate'
  assert_not_contains "$commit_skill" '{{'
  assert_not_contains "$invocation" '{{'
  assert_not_contains "$publishing" '{{'
  assert_contains "$commit_skill" 'explicit `en` or `zhtw` argument overrides'
  # Both language values stay documented whichever one the context selects. Templating the value
  # into the bullet label once produced two zhtw bullets and no en bullet at all.
  assert_contains "$commit_skill" '- `en` — aliases `eng`, `english`.'
  assert_contains "$commit_skill" '- `zhtw` — aliases `zh-tw`, `chinese`'
  assert_contains "$invocation" 'explicit `en` or `zhtw` value for `lang` overrides'
  assert_jsonc_structure "$settings" 4
  assert_json "$destination/.claude/settings.json" "$destination/.codex/hooks.json"
  assert_contains "$destination/.claude/settings.json" 'statusLine'
  assert_contains "$destination/.agents/skills/project-continuity/SKILL.md" 'disable-model-invocation: true'
  assert_contains "$destination/.agents/skills/worktree-manifest/SKILL.md" 'disable-model-invocation: true'
  assert_contains "$destination/.agents/skills/worktree-task-workflow/agents/openai.yaml" 'allow_implicit_invocation: false'
  assert_contains "$destination/.agents/skills/project-continuity/agents/openai.yaml" 'allow_implicit_invocation: false'
  assert_contains "$destination/.agents/skills/worktree-manifest/agents/openai.yaml" 'allow_implicit_invocation: false'

  if [[ "$harness" == managed ]]; then
    assert_contains "$destination/.claude/settings.json" 'show-agent-notification'
    assert_contains "$destination/.claude/settings.json" 'check-worktree-launch'
    assert_contains "$destination/.codex/hooks.json" 'show-agent-notification'
    if [[ "$continuity" == on ]]; then
      assert_contains "$destination/.claude/settings.json" 'maintain-project-continuity.sh'
      assert_contains "$destination/.codex/hooks.json" 'maintain-project-continuity.sh'
    else
      assert_not_contains "$destination/.claude/settings.json" 'maintain-project-continuity.sh'
      assert_not_contains "$destination/.codex/hooks.json" 'maintain-project-continuity.sh'
    fi
  else
    assert_contains "$destination/.claude/settings.json" 'show-agent-notification'
    assert_not_contains "$destination/.claude/settings.json" 'check-worktree-launch'
    assert_not_contains "$destination/.claude/settings.json" 'maintain-project-continuity.sh'
    assert_contains "$destination/.codex/hooks.json" 'show-agent-notification'
    assert_not_contains "$destination/.codex/hooks.json" 'maintain-project-continuity.sh'
  fi

  if [[ "$continuity" == on && "$harness" == managed ]]; then
    assert_contains "$claude" '## Project continuity'
    assert_contains "$codex" '## Project continuity'
    assert_contains "$copilot" '## Project continuity'
  else
    assert_not_contains "$claude" '## Project continuity'
    assert_not_contains "$codex" '## Project continuity'
    assert_not_contains "$copilot" '## Project continuity'
    assert_contains "$lifecycle_hook" 'deliberate no-op'
  fi
  if [[ "$harness" == native || "$continuity" == off ]]; then
    assert_contains "$lifecycle_hook" 'deliberate no-op'
  else
    assert_not_contains "$lifecycle_hook" 'deliberate no-op'
  fi
  assert_hook_behavior "$continuity" "$harness" "$lifecycle_hook"

  local source_count rendered_count
  source_count="$(find "$repository_root/home/dot_agents/skills" -type f ! -name '.*' | wc -l | tr -d ' ')"
  rendered_count="$(find "$destination/.agents/skills" -type f | wc -l | tr -d ' ')"
  [[ "$source_count" == "$rendered_count" ]] ||
    fail "skill file count changed: source=$source_count rendered=$rendered_count ($context/$continuity/$harness)"
}

for context in personal company; do
  for continuity in on off; do
    for harness in managed native; do
      destination="$work_directory/render-$context-$continuity-$harness"
      render_profile "$context" "$continuity" "$harness" "$destination"
      check_profile "$context" "$continuity" "$harness" "$destination"
      printf 'profile tests: %s + continuity %s + harness %s OK\n' \
        "$context" "$continuity" "$harness"
    done
  done
done

# Verify missing-key defaults against an empty machine-local config, independent of the selectors
# configured on the machine running this test.
default_destination="$work_directory/render-defaults"
mkdir -p "$default_destination"
"$chezmoi_bin" apply \
  --config="$config_file" \
  --source="$repository_root" \
  --destination="$default_destination" \
  --exclude=scripts \
  --no-tty \
  --force >/dev/null
assert_contains "$default_destination/.claude/CLAUDE.md" 'The active context is `personal`.'
assert_not_contains "$default_destination/.claude/CLAUDE.md" 'The active context is `company`.'
assert_contains "$default_destination/.agents/skills/git-commit-action/SKILL.md" '| **Language** | `en` · `zhtw`      | `en`'
assert_contains "$default_destination/.agents/skills/worktree-task-workflow/references/invocation.md" 'commit and request text only | `en`'
assert_contains "$repository_root/AGENTS.md" 'this repository always uses the'
assert_contains "$repository_root/AGENTS.md" '`personal` context while work is performed here'
assert_contains "$default_destination/.claude/CLAUDE.md" '## Project continuity'
printf 'profile tests: missing-key defaults OK\n'

# The documented work-machine workflow sets ai_context only and leaves the other selectors at their
# defaults. Cover that shape explicitly: the combination loop always writes all three keys, so it
# cannot show that unset continuity and harness values resolve to on and managed.
company_only="$work_directory/company-only.yaml"
printf 'ai_context: company\n' > "$company_only"
company_only_destination="$work_directory/render-company-only"
mkdir -p "$company_only_destination"
"$chezmoi_bin" apply \
  --config="$config_file" \
  --source="$repository_root" \
  --destination="$company_only_destination" \
  --exclude=scripts \
  --override-data-file="$company_only" \
  --no-tty \
  --force >/dev/null
assert_contains "$company_only_destination/.claude/CLAUDE.md" 'The active context is `company`.'
assert_contains "$company_only_destination/.agents/skills/git-commit-action/SKILL.md" '| **Language** | `en` · `zhtw`      | `zhtw`'
assert_contains "$company_only_destination/.claude/CLAUDE.md" '## Project continuity'
printf 'profile tests: explicit company with default continuity OK\n'

# A native render must remove only repository-owned hook commands from an existing Claude settings
# file. Application-owned or user-added hooks and unrelated keys survive the modify template.
hook_merge_destination="$work_directory/render-hook-merge"
mkdir -p "$hook_merge_destination/.claude"
printf '%s\n' '{
  "customSetting": "preserve",
  "hooks": {
    "Notification": [{"hooks": [
      {"type": "command", "command": "bash $HOME/.local/share/show-agent-notification-macos.sh"},
      {"type": "command", "command": "bash $HOME/custom-notification.sh"}
    ]}],
    "SessionStart": [{"hooks": [
      {"type": "command", "command": "bash $HOME/.claude/hooks/check-worktree-launch.sh"},
      {"type": "command", "command": "bash $HOME/.local/share/maintain-project-continuity.sh"},
      {"type": "command", "command": "bash $HOME/custom-session-start.sh"}
    ]}]
  }
}' > "$hook_merge_destination/.claude/settings.json"
native_override="$work_directory/native-merge.yaml"
printf 'ai_context: personal\nai_continuity: on\nai_harness: native\n' > "$native_override"
"$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
  --destination="$hook_merge_destination" --exclude=scripts \
  --override-data-file="$native_override" --no-tty --force >/dev/null
assert_json "$hook_merge_destination/.claude/settings.json"
assert_contains "$hook_merge_destination/.claude/settings.json" '"customSetting": "preserve"'
assert_contains "$hook_merge_destination/.claude/settings.json" 'custom-notification.sh'
assert_contains "$hook_merge_destination/.claude/settings.json" 'custom-session-start.sh'
assert_contains "$hook_merge_destination/.claude/settings.json" 'show-agent-notification'
assert_not_contains "$hook_merge_destination/.claude/settings.json" 'check-worktree-launch'
assert_not_contains "$hook_merge_destination/.claude/settings.json" 'maintain-project-continuity.sh'
printf 'profile tests: native hook merge preserves unrelated settings OK\n'

invalid_context="$work_directory/invalid-context.yaml"
printf 'ai_context: unsupported\nai_continuity: on\n' > "$invalid_context"
if "$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
    --destination="$work_directory/invalid-context" --exclude=scripts \
    --override-data-file="$invalid_context" --no-tty --force >/dev/null 2>&1; then
  fail 'unsupported ai_context rendered successfully'
fi

invalid_continuity="$work_directory/invalid-continuity.yaml"
printf 'ai_context: personal\nai_continuity: unsupported\n' > "$invalid_continuity"
if "$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
    --destination="$work_directory/invalid-continuity" --exclude=scripts \
    --override-data-file="$invalid_continuity" --no-tty --force >/dev/null 2>&1; then
  fail 'unsupported ai_continuity rendered successfully'
fi
invalid_harness="$work_directory/invalid-harness.yaml"
printf 'ai_context: personal\nai_continuity: on\nai_harness: unsupported\n' > "$invalid_harness"
if "$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
    --destination="$work_directory/invalid-harness" --exclude=scripts \
    --override-data-file="$invalid_harness" --no-tty --force >/dev/null 2>&1; then
  fail 'unsupported ai_harness rendered successfully'
fi
legacy_harness="$work_directory/legacy-harness.yaml"
printf 'ai_context: personal\nai_continuity: on\nai_workflow: native\n' > "$legacy_harness"
legacy_destination="$work_directory/render-legacy-harness"
mkdir -p "$legacy_destination"
"$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
  --destination="$legacy_destination" --exclude=scripts \
  --override-data-file="$legacy_harness" --no-tty --force >/dev/null
assert_contains "$legacy_destination/.claude/CLAUDE.md" 'Edit source-of-truth files'
assert_not_contains "$legacy_destination/.claude/CLAUDE.md" '## Project continuity'
printf 'profile tests: legacy ai_workflow compatibility OK\n'
conflicting_harness="$work_directory/conflicting-harness.yaml"
printf 'ai_harness: native\nai_workflow: managed\n' > "$conflicting_harness"
if "$chezmoi_bin" apply --config="$config_file" --source="$repository_root" \
    --destination="$work_directory/conflicting-harness" --exclude=scripts \
    --override-data-file="$conflicting_harness" --no-tty --force >/dev/null 2>&1; then
  fail 'conflicting ai_harness and ai_workflow rendered successfully'
fi
printf 'profile tests: invalid selector rejection OK\n'

# Render the other operating system's branch. .chezmoiignore drops the wrong VS Code tree and the
# wrong worktree helper per OS, so on one machine half of those templates are never exercised and
# the host-specific assertions above are dead code for the other half. Overriding .chezmoi.os
# renders both branches from either host, which is the only way this repository sees its macOS VS
# Code body validated on Windows, or its Windows body validated on a Mac.
assert_absent() {
  [[ ! -e "$1" ]] || fail "$2"
}

check_os_branch() {
  local os_name="$1" destination="$work_directory/render-os-$1"
  local override="$work_directory/os-$1.yaml"
  printf 'ai_context: personal\nai_continuity: "on"\nai_harness: managed\nchezmoi:\n  os: %s\n' "$os_name" > "$override"
  mkdir -p "$destination"
  "$chezmoi_bin" apply \
    --config="$config_file" \
    --source="$repository_root" \
    --destination="$destination" \
    --exclude=scripts \
    --override-data-file="$override" \
    --no-tty \
    --force >/dev/null

  local settings
  if [[ "$os_name" == darwin ]]; then
    settings="$destination/Library/Application Support/Code/User/settings.json"
    assert_absent "$destination/AppData" "darwin render produced a Windows AppData tree"
    assert_file "$destination/.local/share/worktree-runtime.py"
    assert_file "$destination/.local/share/git-worktree-provision.sh"
    assert_absent "$destination/.local/share/git-worktree-provision.ps1" \
      "darwin render kept the PowerShell worktree helper"
  else
    settings="$destination/AppData/Roaming/Code/User/settings.json"
    assert_absent "$destination/Library" "windows render produced a macOS Library tree"
    assert_file "$destination/.local/share/worktree-runtime.py"
    assert_file "$destination/.local/share/git-worktree-provision.ps1"
    assert_absent "$destination/.local/share/git-worktree-provision.sh" \
      "windows render kept the POSIX worktree helper"
  fi

  assert_file "$settings"
  assert_jsonc_structure "$settings" 4
  assert_contains "$settings" 'Use English for summary and for scope when present.'
  assert_file "$destination/.claude/CLAUDE.md"
  assert_contains "$destination/.claude/CLAUDE.md" 'The active context is `personal`.'
}

check_os_branch darwin
check_os_branch windows
printf 'profile tests: cross-platform render branches OK\n'

printf 'profile tests: all checks passed\n'
