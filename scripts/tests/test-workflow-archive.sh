#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
archive_tool="$repository_root/scripts/workflows/workflow-archive.py"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

fail() {
  printf 'workflow archive/delete tests: %s\n' "$1" >&2
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
  '  "files": [' \
  '    ".claude/CLAUDE.md",' \
  '    "scripts/manifests/workflows/bad.json"' \
  '  ]' \
  '}' > "$fixture/scripts/manifests/workflows/bad.json"
mkdir -p "$fixture/.claude"
printf 'generated target\n' > "$fixture/.claude/CLAUDE.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm initial

delete_repo="$work_directory/delete-repository"
git clone -q "$fixture" "$delete_repo"
git -C "$delete_repo" config user.email test@example.com
git -C "$delete_repo" config user.name test

expect_failure python "$archive_tool" archive --repo "$fixture" \
  --definition scripts/manifests/workflows/bad.json --id v1-bad

python "$archive_tool" archive --repo "$fixture" \
  --definition scripts/manifests/workflows/demo.json \
  --id v1 --reason "test archive" > "$work_directory/archive-dry-run.log"
archive_directory="$fixture/archives/workflows/demo/v1"
assert_not_file "$archive_directory"
assert_file "$fixture/home/dot_agents/skills/demo/SKILL.md"
assert_file "$fixture/scripts/helper.txt"
assert_not_file "$fixture/home/.chezmoiremove"
assert_contains "$work_directory/archive-dry-run.log" 'would archive and delete: home/dot_agents/skills/demo/SKILL.md'
assert_contains "$work_directory/archive-dry-run.log" 'would queue for removal: .agents/skills/demo'

python "$archive_tool" archive --repo "$fixture" \
  --definition scripts/manifests/workflows/demo.json \
  --id v1 --reason "test archive" --apply > "$work_directory/archive.log"
assert_file "$archive_directory/manifest.json"
assert_file "$archive_directory/source/home/dot_agents/skills/demo/SKILL.md"
assert_file "$archive_directory/source/scripts/helper.txt"
assert_not_file "$archive_directory/source/scripts/manifests/workflows/demo.json"
assert_not_file "$fixture/home/dot_agents/skills/demo/SKILL.md"
assert_not_file "$fixture/scripts/helper.txt"
assert_file "$fixture/scripts/shared.txt"
assert_file "$fixture/scripts/manifests/workflows/demo.json"
assert_file "$fixture/home/.chezmoiremove"
assert_contains "$archive_directory/manifest.json" '"sourceCommit"'
assert_contains "$archive_directory/manifest.json" '"reason": "test archive"'
assert_contains "$archive_directory/manifest.json" '"targets"'
assert_contains "$fixture/home/.chezmoiremove" '.agents/skills/demo'
assert_contains "$fixture/home/.chezmoiremove" '.claude/skills/demo'
assert_contains "$work_directory/archive.log" 'archive created: archives/workflows/demo/v1'
assert_contains "$work_directory/archive.log" 'source files deleted: 2'

definition_archive_repo="$work_directory/definition-archive-repository"
git clone -q "$fixture" "$definition_archive_repo"
git -C "$definition_archive_repo" config user.email test@example.com
git -C "$definition_archive_repo" config user.name test
python "$archive_tool" archive --repo "$definition_archive_repo" \
  --definition scripts/manifests/workflows/demo.json \
  --id with-definition --delete-definition --apply > "$work_directory/archive-with-definition.log"
definition_archive_directory="$definition_archive_repo/archives/workflows/demo/with-definition"
assert_file "$definition_archive_directory/source/scripts/manifests/workflows/demo.json"
assert_contains "$definition_archive_directory/manifest.json" '"scripts/manifests/workflows/demo.json"'
assert_not_file "$definition_archive_repo/scripts/manifests/workflows/demo.json"

printf 'tracked edit\n' >> "$delete_repo/scripts/helper.txt"
expect_failure python "$archive_tool" archive --repo "$delete_repo" \
  --definition scripts/manifests/workflows/demo.json --id dirty
expect_failure python "$archive_tool" delete --repo "$delete_repo" \
  --definition scripts/manifests/workflows/demo.json
git -C "$delete_repo" checkout-index -f -- scripts/helper.txt

restore_repo="$work_directory/restore-repository"
git -C "$work_directory" init -q "$restore_repo"
git -C "$restore_repo" config user.email test@example.com
git -C "$restore_repo" config user.name test
mkdir -p "$restore_repo/archives/workflows/demo"
cp -R "$archive_directory" "$restore_repo/archives/workflows/demo/v1"

python "$archive_tool" restore --repo "$restore_repo" \
  archives/workflows/demo/v1 > "$work_directory/restore-dry-run.log"
assert_not_file "$restore_repo/home/dot_agents/skills/demo/SKILL.md"
assert_contains "$work_directory/restore-dry-run.log" 'dry-run: 2 file(s) would be restored'
assert_contains "$work_directory/restore-dry-run.log" 'profile assumptions: uses test profile'

python "$archive_tool" restore --repo "$restore_repo" \
  archives/workflows/demo/v1 --apply > "$work_directory/restore.log"
assert_file "$restore_repo/home/dot_agents/skills/demo/SKILL.md"
assert_file "$restore_repo/scripts/helper.txt"
assert_not_file "$restore_repo/scripts/manifests/workflows/demo.json"

mkdir -p "$delete_repo/archives/workflows/demo"
cp -R "$archive_directory" "$delete_repo/archives/workflows/demo/v1"
printf '%s\n' \
  '{{ if eq .chezmoi.os "windows" }}' \
  '.existing/target' \
  '{{ end }}' > "$delete_repo/home/.chezmoiremove"
python "$archive_tool" delete --repo "$delete_repo" \
  --definition scripts/manifests/workflows/demo.json > "$work_directory/delete-dry-run.log"
assert_file "$delete_repo/home/dot_agents/skills/demo/SKILL.md"
assert_file "$delete_repo/scripts/manifests/workflows/demo.json"
assert_file "$delete_repo/archives/workflows/demo/v1/manifest.json"
assert_contains "$work_directory/delete-dry-run.log" 'shared canonical dependencies (kept):'
assert_contains "$work_directory/delete-dry-run.log" 'would queue for removal: .agents/skills/demo'
assert_contains "$work_directory/delete-dry-run.log" 'no archive created by this operation'
assert_contains "$work_directory/delete-dry-run.log" 'existing archives (unchanged): archives/workflows/demo/'
assert_contains "$work_directory/delete-dry-run.log" 'continuity state (kept): .project-continuity/'
python "$archive_tool" delete --repo "$delete_repo" \
  --definition scripts/manifests/workflows/demo.json --apply --delete-definition \
  > "$work_directory/delete.log"
assert_not_file "$delete_repo/home/dot_agents/skills/demo/SKILL.md"
assert_not_file "$delete_repo/scripts/helper.txt"
assert_file "$delete_repo/scripts/shared.txt"
assert_not_file "$delete_repo/scripts/manifests/workflows/demo.json"
assert_file "$delete_repo/home/.chezmoiremove"
assert_contains "$delete_repo/home/.chezmoiremove" '.agents/skills/demo'
assert_contains "$delete_repo/home/.chezmoiremove" '.claude/skills/demo'
assert_contains "$delete_repo/home/.chezmoiremove" '{{ if eq .chezmoi.os "windows" }}'
assert_contains "$delete_repo/home/.chezmoiremove" '.existing/target'
assert_file "$delete_repo/archives/workflows/demo/v1/manifest.json"

collision_repo="$work_directory/collision-repository"
git -C "$work_directory" init -q "$collision_repo"
git -C "$collision_repo" config user.email test@example.com
git -C "$collision_repo" config user.name test
mkdir -p "$collision_repo/archives/workflows/demo" "$collision_repo/home/dot_agents/skills/demo"
cp -R "$archive_directory" "$collision_repo/archives/workflows/demo/v1"
printf 'different\n' > "$collision_repo/home/dot_agents/skills/demo/SKILL.md"
expect_failure python "$archive_tool" restore --repo "$collision_repo" \
  archives/workflows/demo/v1 --apply
assert_contains "$collision_repo/home/dot_agents/skills/demo/SKILL.md" 'different'

tampered_repo="$work_directory/tampered-repository"
git -C "$work_directory" init -q "$tampered_repo"
git -C "$tampered_repo" config user.email test@example.com
git -C "$tampered_repo" config user.name test
mkdir -p "$tampered_repo/archives/workflows/demo"
cp -R "$archive_directory" "$tampered_repo/archives/workflows/demo/v1"
printf 'unlisted top level\n' > "$tampered_repo/archives/workflows/demo/v1/unlisted.txt"
expect_failure python "$archive_tool" restore --repo "$tampered_repo" \
  archives/workflows/demo/v1
rm -f "$tampered_repo/archives/workflows/demo/v1/unlisted.txt"
printf 'unlisted\n' > "$tampered_repo/archives/workflows/demo/v1/source/unlisted.txt"
expect_failure python "$archive_tool" restore --repo "$tampered_repo" \
  archives/workflows/demo/v1

python "$archive_tool" delete-archive --repo "$fixture" \
  archives/workflows/demo/v1 > "$work_directory/delete-archive-dry-run.log"
assert_file "$archive_directory/manifest.json"
assert_contains "$work_directory/delete-archive-dry-run.log" 'dry-run: archive directory would be deleted'
python "$archive_tool" delete-archive --repo "$fixture" \
  archives/workflows/demo/v1 --apply > "$work_directory/delete-archive.log"
assert_not_file "$archive_directory"

printf 'workflow archive/delete tests: passed\n'
