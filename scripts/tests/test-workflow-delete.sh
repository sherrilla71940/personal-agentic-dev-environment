#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
delete_tool="$repository_root/scripts/workflows/workflow-delete.py"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

fail() {
  printf 'workflow deletion tests: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_not_file() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "'$2' not found in $1"
}

expect_failure() {
  local log="$work_directory/failure.log"
  if "$@" >"$log" 2>&1; then
    cat "$log" >&2
    fail "command unexpectedly succeeded: $*"
  fi
}

fixture="$work_directory/source-repository"
mkdir -p "$fixture/home/dot_agents/skills/demo" "$fixture/scripts/manifests/workflows" "$fixture/scripts"
git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config user.name test
git -C "$fixture" config core.autocrlf false
printf '# Demo workflow\n' > "$fixture/home/dot_agents/skills/demo/SKILL.md"
printf 'helper\n' > "$fixture/scripts/helper.txt"
printf 'shared\n' > "$fixture/scripts/shared.txt"
printf '%s\n' \
  '{' \
  '  "schemaVersion": 1,' \
  '  "name": "demo",' \
  '  "description": "A test workflow",' \
  '  "dependencies": ["git"],' \
  '  "profileAssumptions": ["uses test profile"],' \
  '  "sharedFiles": ["scripts/shared.txt"],' \
  '  "targets": [".agents/skills/demo", ".claude/skills/demo"],' \
  '  "files": [' \
  '    "home/dot_agents/skills/demo/SKILL.md",' \
  '    "scripts/helper.txt"' \
  '  ]' \
  '}' > "$fixture/scripts/manifests/workflows/demo.json"
printf '%s\n' \
  '{' \
  '  "schemaVersion": 1,' \
  '  "name": "bad",' \
  '  "files": [".claude/CLAUDE.md"]' \
  '}' > "$fixture/scripts/manifests/workflows/bad.json"
git -C "$fixture" add .
git -C "$fixture" commit -qm initial

expect_failure python "$delete_tool" --repo "$fixture" --definition scripts/manifests/workflows/bad.json

python "$delete_tool" --repo "$fixture" \
  --definition scripts/manifests/workflows/demo.json > "$work_directory/dry-run.log"
assert_file "$fixture/home/dot_agents/skills/demo/SKILL.md"
assert_file "$fixture/scripts/helper.txt"
assert_not_file "$fixture/home/.chezmoiremove"
assert_contains "$work_directory/dry-run.log" 'would delete: home/dot_agents/skills/demo/SKILL.md'
assert_contains "$work_directory/dry-run.log" 'would queue for removal: .agents/skills/demo'
assert_contains "$work_directory/dry-run.log" 'no archive or restore copy is created'

python "$delete_tool" --repo "$fixture" \
  --definition scripts/manifests/workflows/demo.json --apply > "$work_directory/delete.log"
assert_not_file "$fixture/home/dot_agents/skills/demo/SKILL.md"
assert_not_file "$fixture/scripts/helper.txt"
assert_file "$fixture/scripts/shared.txt"
assert_file "$fixture/scripts/manifests/workflows/demo.json"
assert_file "$fixture/home/.chezmoiremove"
assert_contains "$fixture/home/.chezmoiremove" '.agents/skills/demo'
assert_contains "$fixture/home/.chezmoiremove" '.claude/skills/demo'
assert_contains "$work_directory/delete.log" 'delete complete: 2 source file(s) deleted'
assert_not_file "$fixture/archives"

dirty_repo="$work_directory/dirty-repository"
git clone -q "$fixture" "$dirty_repo"
git -C "$dirty_repo" config user.email test@example.com
git -C "$dirty_repo" config user.name test
printf 'tracked edit\n' >> "$dirty_repo/scripts/shared.txt"
expect_failure python "$delete_tool" --repo "$dirty_repo" \
  --definition scripts/manifests/workflows/demo.json

printf 'workflow deletion tests: passed\n'
