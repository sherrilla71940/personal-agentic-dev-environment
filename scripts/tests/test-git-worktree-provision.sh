#!/usr/bin/env bash
# Run the macOS worktree helper against disposable repositories containing non-secret
# fixtures. The suite is Bash 3.2 compatible and can also run under Git Bash on Windows.

set -u

repository_root=$(cd "$(dirname "$0")/../.." && pwd -P)
tool_path="$repository_root/home/dot_local/share/git-worktree-provision.sh"
temporary_parent=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$temporary_parent/git-worktree-provision-tests.XXXXXX") || exit 1
passed=0
failed=0
skipped=0
result_output=""
result_status=0

cleanup() {
    case "$test_root" in
        "$temporary_parent"/git-worktree-provision-tests.*)
            [[ -d "$test_root" ]] && rm -rf -- "$test_root"
            ;;
        *)
            printf 'Refusing to remove unexpected test path: %s\n' "$test_root" >&2
            ;;
    esac
}
trap cleanup EXIT

write_fixture() {
    local path=$1
    local content=$2
    mkdir -p "${path%/*}"
    printf '%s' "$content" >"$path"
}

run_git() {
    local directory=$1
    shift
    result_output=$(cd "$directory" && git "$@" 2>&1)
    result_status=$?
}

git_checked() {
    local directory=$1
    shift
    run_git "$directory" "$@"
    if [[ $result_status -ne 0 ]]; then
        printf 'git %s failed:\n%s\n' "$*" "$result_output" >&2
        return 1
    fi
}

new_repository() {
    local name=$1
    local path="$test_root/$name"
    mkdir -p "$path"
    git_checked "$path" init --quiet --initial-branch=main || return 1
    git_checked "$path" config user.name 'Worktree Fixture' || return 1
    git_checked "$path" config user.email fixture@example.invalid || return 1
    git_checked "$path" config alias.wt-add "!bash \"$tool_path\" add" || return 1
    git_checked "$path" config alias.wt-copy "!bash \"$tool_path\" copy" || return 1
    git_checked "$path" config alias.wt-check "!bash \"$tool_path\" check" || return 1
    git_checked "$path" config alias.wt-readiness "!bash \"$tool_path\" readiness" || return 1
    git_checked "$path" config alias.wt-provision "!bash \"$tool_path\" provision" || return 1
    write_fixture "$path/README.md" $'fixture\n'
    git_checked "$path" add README.md || return 1
    git_checked "$path" commit --quiet -m fixture || return 1
    fixture_repository=$path
}

add_manifest() {
    local repository=$1
    local ignore_content=$2
    local manifest_content=$3
    write_fixture "$repository/.gitignore" "$ignore_content"
    write_fixture "$repository/.worktreeinclude" "$manifest_content"
    git_checked "$repository" add .gitignore .worktreeinclude || return 1
    git_checked "$repository" commit --quiet -m 'add worktree manifest'
}

assert_true() {
    local message=$1
    shift
    "$@" || {
        printf '%s\n' "$message" >&2
        return 1
    }
}

assert_status() {
    local expected=$1
    local message=$2
    if [[ $result_status -ne $expected ]]; then
        printf '%s Expected %s, got %s. Output:\n%s\n' \
            "$message" "$expected" "$result_status" "$result_output" >&2
        return 1
    fi
}

assert_output_contains() {
    local expected=$1
    local message=$2
    if [[ "$result_output" != *"$expected"* ]]; then
        printf '%s Output:\n%s\n' "$message" "$result_output" >&2
        return 1
    fi
}

run_case() {
    local name=$1
    local function_name=$2
    if [[ -n "${WORKTREE_PROVISION_TEST_FILTER-}" && "$name" != *"$WORKTREE_PROVISION_TEST_FILTER"* ]]; then
        return
    fi
    if "$function_name"; then
        passed=$((passed + 1))
        printf 'PASS %s\n' "$name"
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n' "$name"
    fi
}

case_no_manifest() {
    new_repository no-manifest || return 1
    local repository=$fixture_repository target="$test_root/no-manifest-target"
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 0 'Creation without a manifest should succeed.' || return 1
    assert_output_contains '[skipped] .worktreeinclude' 'The missing manifest should be reported.' || return 1
    [[ -f "$target/.git" ]]
}

case_unlisted_blocked() {
    new_repository unlisted-blocked || return 1
    local repository=$fixture_repository target="$test_root/unlisted-blocked-target"
    write_fixture "$repository/.gitignore" $'.env.local\n'
    write_fixture "$repository/.env.local" $'local\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add ignore rule' || return 1
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 3 'Unlisted ignored configuration should require an explicit override.' || return 1
    assert_output_contains 'Decision: eligible-ignored-files-unlisted' 'The unlisted decision should be reported.' || return 1
    [[ ! -e "$target" ]]
}

case_check_unlisted() {
    new_repository check-unlisted || return 1
    local repository=$fixture_repository target="$test_root/check-unlisted-target"
    write_fixture "$repository/.gitignore" $'.env.local\n'
    write_fixture "$repository/.env.local" $'local\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add ignore rule' || return 1
    run_git "$repository" wt-check --target "$target"
    assert_status 3 'The check should require a decision for an unlisted ignored file.' || return 1
    assert_output_contains '[unlisted] .env.local' 'The unlisted file should be reported.' || return 1
    assert_output_contains 'Writes: none' 'The check should declare its read-only behavior.' || return 1
    [[ ! -e "$target" ]]
}

case_redaction() {
    new_repository redaction || return 1
    local repository=$fixture_repository target="$test_root/redaction-target"
    write_fixture "$repository/.gitignore" $'password=DO-NOT-PRINT\n'
    write_fixture "$repository/password=DO-NOT-PRINT" $'secret-content\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add redaction fixture' || return 1
    run_git "$repository" wt-check
    assert_status 3 'An unlisted sensitive-looking path should remain advisory.' || return 1
    assert_output_contains '[unlisted] password=[REDACTED]' 'The sensitive path should be redacted in preflight.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    run_git "$repository" wt-add --allow-unprovisioned -- --detach "$target" HEAD
    assert_status 0 'Allowing an unprovisioned worktree should succeed.' || return 1
    assert_output_contains '[unlisted] password=[REDACTED]' 'The sensitive path should be redacted in provisioning output.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    run_git "$repository" 'wt-provision' '--bad=password=DO-NOT-PRINT'
    assert_status 2 'An invalid provisioning option should fail.' || return 1
    assert_output_contains 'password=[REDACTED]' 'The provisioning error should redact sensitive text.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]]
}

case_python_cache() {
    new_repository python-cache || return 1
    local repository=$fixture_repository
    write_fixture "$repository/.gitignore" $'__pycache__/\n*.pyc\n'
    write_fixture "$repository/__pycache__/module.pyc" $'cache\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add cache ignore rule' || return 1
    run_git "$repository" wt-check
    assert_status 0 'Python cache artifacts should not require provisioning.' || return 1
    assert_output_contains 'Decision: no-manifest-needed' 'The cache-only decision should be reported.' || return 1
    [[ "$result_output" != *'[unlisted]'* ]]
}

case_check_empty_manifest() {
    new_repository check-empty-manifest || return 1
    local repository=$fixture_repository
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    run_git "$repository" wt-check
    assert_status 0 'An empty manifest should be reportable without failing.' || return 1
    assert_output_contains 'Manifest: tracked' 'The tracked manifest should be reported.' || return 1
    assert_output_contains 'Decision: manifest-present-no-matches' 'The empty-manifest decision should be reported.'
}

case_check_raw() {
    new_repository check-raw || return 1
    local repository=$fixture_repository target="$test_root/check-raw-target"
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$repository/.env.local" $'source\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-check --source "$repository" --target "$target"
    assert_status 0 'A raw worktree check should succeed.' || return 1
    assert_output_contains '[would-copy] .env.local' 'The omitted file should be reported as a copy candidate.' || return 1
    [[ ! -e "$target/.env.local" ]] || return 1
    write_fixture "$target/.env.local" $'existing\n'
    run_git "$target" wt-check --source "$repository" --target "$target"
    assert_output_contains '[conflict] .env.local' 'The existing target conflict should be reported.'
}

case_check_required() {
    new_repository check-required || return 1
    local repository=$fixture_repository
    run_git "$repository" wt-check --required .env.local
    assert_status 2 'A missing required file should fail the check.' || return 1
    assert_output_contains '[required-missing] .env.local' 'The required missing file should be reported.' || return 1
    assert_output_contains 'Decision: required-local-config-missing' 'The required-config decision should be reported.'
}

case_readiness_tracked_config() {
    new_repository readiness-tracked-config || return 1
    local repository=$fixture_repository target="$test_root/readiness-tracked-config-target"
    write_fixture "$repository/Web.config" $'branch-config\n'
    git_checked "$repository" add Web.config || return 1
    git_checked "$repository" commit --quiet -m 'add tracked configuration' || return 1
    add_manifest "$repository" $'*.local\n' $'approved.local\n' || return 1
    write_fixture "$repository/approved.local" $'approved\n'
    write_fixture "$repository/other.local" $'unlisted\n'
    write_fixture "$repository/Web.config" $'connectionString=DO-NOT-PRINT\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-readiness --source "$repository" --target "$target"
    assert_status 0 'Tracked configuration readiness must be advisory.' || return 1
    assert_output_contains "Source worktree: $repository" 'The exact source worktree should be reported.' || return 1
    assert_output_contains 'Source branch: main' 'The source branch should be reported.' || return 1
    assert_output_contains "Target worktree: $target" 'The exact target worktree should be reported.' || return 1
    assert_output_contains 'Target branch: (detached)' 'The target branch should be reported.' || return 1
    assert_output_contains '[authorized] approved.local' 'The authorized ignored file should be reported.' || return 1
    assert_output_contains '[unlisted] other.local' 'The unauthorized ignored file should be reported.' || return 1
    assert_output_contains '[tracked-config] Web.config: modified tracked configuration was not copied; review only if this worktree requires the local override.' 'The tracked configuration warning should be reported.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    [[ $(<"$target/Web.config") == branch-config ]] || return 1
}

case_readiness_clean() {
    new_repository readiness-clean || return 1
    run_git "$fixture_repository" wt-readiness
    assert_status 0 'A clean readiness check should succeed.' || return 1
    assert_output_contains '[configuration] no local configuration differences' 'The clean readiness state should be reported.'
}

case_readiness_references() {
    new_repository readiness-references || return 1
    local repository=$fixture_repository target="$test_root/readiness-references-target"
    write_fixture "$repository/Web.config" $'<configuration>\n  <appSettings\n      file="config/appsettings.local.config">\n    <add key="private-key" value="DO-NOT-PRINT" />\n  </appSettings>\n  <connectionStrings configSource="config/connections.config" />\n  <customSection configSource="config/unmapped.config" />\n  <otherSection configSource="config/missing.config" />\n  <system.web />\n</configuration>\n'
    git_checked "$repository" add Web.config || return 1
    git_checked "$repository" commit --quiet -m 'add configuration references' || return 1
    add_manifest "$repository" $'config/appsettings.local.config\nconfig/connections.config\n' $'config/appsettings.local.config\nconfig/connections.config\n' || return 1
    write_fixture "$repository/config/appsettings.local.config" $'local settings\n'
    write_fixture "$repository/config/connections.config" $'connection settings\n'
    write_fixture "$repository/config/unmapped.config" $'unmapped settings\n'
    write_fixture "$repository/Web.config" "$(<"$repository/Web.config")<!-- local override DO-NOT-PRINT: <commentedSection configSource=\"config/comment-only.config\" /> -->\n"

    run_git "$repository" wt-check --target "$target"
    assert_status 0 'Configuration references must not block provisioning preflight.' || return 1
    assert_output_contains '[expected] Web.config -> config/appsettings.local.config' 'The appSettings reference should be reported by preflight.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1

    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-readiness --source "$repository" --target "$target"
    assert_status 0 'Configuration readiness must be advisory.' || return 1
    assert_output_contains '[expected] Web.config -> config/appsettings.local.config: explicit appSettings file reference' 'The appSettings reference should be reported.' || return 1
    assert_output_contains '[present] Web.config -> config/appsettings.local.config: referenced configuration file is present in the source worktree (ignored)' 'The present ignored reference should be reported.' || return 1
    assert_output_contains '[missing] Web.config -> config/appsettings.local.config: target worktree is missing the referenced configuration file' 'The missing target reference should be reported.' || return 1
    assert_output_contains '[expected] Web.config -> config/connections.config: explicit configSource reference' 'The configSource reference should be reported.' || return 1
    assert_output_contains '[expected] Web.config -> config/missing.config: explicit configSource reference' 'The missing source reference should be reported.' || return 1
    assert_output_contains '[missing] Web.config -> config/missing.config: referenced configuration file is missing from the source worktree' 'The missing source reference status should be reported.' || return 1
    assert_output_contains '[present] Web.config -> config/unmapped.config: referenced configuration file is present in the source worktree (unmapped)' 'The unmapped reference should be reported as present.' || return 1
    assert_output_contains '[unmapped] Web.config -> config/unmapped.config: referenced configuration file is present but is neither tracked nor ignored' 'The unmapped reference status should be reported.' || return 1
    [[ "$result_output" != *'comment-only.config'* ]] || return 1
    assert_output_contains '[tracked-config] Web.config: modified tracked configuration was not copied; review only if this worktree requires the local override.' 'The tracked configuration warning should be reported.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    [[ ! -e "$target/config/appsettings.local.config" ]]
}

case_setup_contract() {
    new_repository setup-contract || return 1
    local repository=$fixture_repository
    write_fixture "$repository/.worktree-provision" $'schemaVersion=1\nscript=scripts/setup-worktree.sh\ndocumentation=docs/setup-worktree.md\n'
    write_fixture "$repository/scripts/setup-worktree.sh" $'printf "DO-NOT-EXECUTE\\n"\n'
    write_fixture "$repository/docs/setup-worktree.md" $'Manual setup documentation\n'
    git_checked "$repository" add .worktree-provision scripts/setup-worktree.sh docs/setup-worktree.md || return 1
    git_checked "$repository" commit --quiet -m 'add setup contract' || return 1
    run_git "$repository" wt-check
    assert_status 0 'A valid setup contract should be advisory.' || return 1
    assert_output_contains '[setup-contract] .worktree-provision: tracked setup contract declares scripts/setup-worktree.sh; not executed; review docs/setup-worktree.md' 'The setup contract should be reported.' || return 1
    [[ "$result_output" != *'DO-NOT-EXECUTE'* ]]
}

case_matching() {
    new_repository matching || return 1
    local repository=$fixture_repository target="$test_root/matching-target"
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$repository/.env.local" $'fixture-value\n'
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 0 'Provisioning should succeed.' || return 1
    [[ $(<"$target/.env.local") == fixture-value ]]
}

case_reject_tracked_manifest_file() {
    new_repository eligibility || return 1
    local repository=$fixture_repository target="$test_root/eligibility-target"
    add_manifest "$repository" $'*.local\n' $'approved.local\nlocal.txt\nREADME.md\n' || return 1
    write_fixture "$repository/approved.local" $'approved\n'
    write_fixture "$repository/other.local" $'not approved\n'
    write_fixture "$repository/local.txt" $'not ignored\n'
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 2 'A tracked manifest file must block provisioning.' || return 1
    [[ ! -e "$target" ]] || return 1
    assert_output_contains '[missing] local.txt' 'The unignored manifest entry should be reported.'
    assert_output_contains '[rejected] README.md: tracked files already arrive through Git and cannot be copied from another worktree' 'The tracked manifest entry was not explicitly rejected.'
    assert_output_contains '[unlisted] other.local' 'The unlisted ignored file should be reported.'
    assert_output_contains 'Decision: invalid-manifest' 'The tracked manifest entry did not invalidate the manifest.'
}

case_private_client_files() {
    new_repository private-client-files || return 1
    local repository=$fixture_repository
    write_fixture "$repository/CLAUDE.md" $'tracked Claude instructions\n'
    write_fixture "$repository/AGENTS.md" $'tracked Codex instructions\n'
    git_checked "$repository" add CLAUDE.md AGENTS.md || return 1
    git_checked "$repository" commit --quiet -m 'add tracked instructions' || return 1
    write_fixture "$repository/.gitignore" $'CLAUDE.local.md\nAGENTS.override.md\n.claude/settings.local.json\n'
    write_fixture "$repository/CLAUDE.local.md" $'private override\n'
    write_fixture "$repository/AGENTS.override.md" $'private override\n'
    write_fixture "$repository/.claude/settings.local.json" $'{"permissions":[]}\n'
    run_git "$repository" wt-check
    assert_status 0 'Private client files should be advisory and not ordinary candidates.' || return 1
    assert_output_contains '[agent-override] CLAUDE.local.md: private agent override affects agent behavior; not suggested as ordinary configuration' 'The Claude private override was not classified explicitly.'
    assert_output_contains '[agent-override] AGENTS.override.md: private agent override affects agent behavior; not suggested as ordinary configuration' 'The Codex private override was not classified explicitly.'
    assert_output_contains '[client-settings] .claude/settings.local.json: client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration' 'The client-local settings file was not classified separately.'
    assert_output_contains '[tracked-instructions] CLAUDE.md: tracked instructions arrive through Git; not copied' 'Tracked Claude instructions were not identified.'
    assert_output_contains '[tracked-instructions] AGENTS.md: tracked instructions arrive through Git; not copied' 'Tracked Codex instructions were not identified.'
    [[ "$result_output" != *'[unlisted] CLAUDE.local.md'* ]] || return 1
    [[ "$result_output" != *'[unlisted] AGENTS.override.md'* ]] || return 1
    [[ "$result_output" != *'[unlisted] .claude/settings.local.json'* ]] || return 1
}

case_tracked_config_copy_rejection() {
    new_repository tracked-config-copy-rejection || return 1
    local repository=$fixture_repository target="$test_root/tracked-config-copy-rejection-target"
    write_fixture "$repository/Web.config" $'branch-config\n'
    write_fixture "$repository/Other.config" $'unrelated-config\n'
    git_checked "$repository" add Web.config Other.config || return 1
    git_checked "$repository" commit --quiet -m 'add tracked application configuration' || return 1
    add_manifest "$repository" $'approved.local\nOther.config\n' $'approved.local\nWeb.config\n' || return 1
    write_fixture "$repository/approved.local" $'approved\n'

    local preflight_target="$test_root/tracked-config-copy-rejection-preflight"
    run_git "$repository" wt-add -- --detach "$preflight_target" HEAD
    assert_status 2 'A tracked configuration manifest entry must block new worktree creation.' || return 1
    assert_output_contains '[rejected] Web.config: tracked application-owned configuration cannot be copied from another worktree' 'The tracked configuration was not rejected during preflight.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    [[ "$result_output" != *'[rejected] Other.config'* ]] || return 1
    [[ ! -e "$preflight_target" ]] || return 1

    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-copy --source "$repository"
    assert_status 2 'Copy should reject the tracked file while reporting the approved ignored file.' || return 1
    assert_output_contains '[rejected] Web.config: tracked application-owned configuration cannot be copied from another worktree' 'The tracked configuration was not rejected by wt-copy.' || return 1
    [[ "$result_output" != *'[rejected] Other.config'* ]] || return 1
    assert_output_contains '[copied] approved.local' 'The approved ignored file was not provisioned.' || return 1
    [[ -f "$target/approved.local" ]] || return 1
    [[ $(<"$target/Web.config") == branch-config ]] || return 1
}

case_external_source_rejection() {
    new_repository external-source-target || return 1
    local repository=$fixture_repository target="$test_root/external-source-target-worktree"
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$repository/.env.local" $'target-source\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1

    new_repository external-source-repository || return 1
    local external=$fixture_repository
    add_manifest "$external" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$external/.env.local" $'EXTERNAL-SECRET-MUST-NOT-COPY\n'
    run_git "$target" wt-copy --source "$external"
    assert_status 2 'An external source repository must be rejected.' || return 1
    assert_output_contains 'not worktrees of the same Git repository' 'The external source rejection should be reported.' || return 1
    [[ ! -e "$target/.env.local" ]] || return 1
    [[ "$result_output" != *'EXTERNAL-SECRET-MUST-NOT-COPY'* ]]
}

case_nested_unicode() {
    new_repository unicode || return 1
    local repository=$fixture_repository target="$test_root/target space 測試"
    local relative='config space/測試.local'
    add_manifest "$repository" $'config space/\n' $'config space/\n' || return 1
    write_fixture "$repository/$relative" $'unicode\n'
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 0 'Unicode provisioning should succeed.' || return 1
    [[ -f "$target/$relative" ]]
}

case_conflict() {
    new_repository conflict || return 1
    local repository=$fixture_repository target="$test_root/conflict-target"
    add_manifest "$repository" $'.env\n' $'.env\n' || return 1
    git_checked "$repository" checkout --quiet -b target-with-file || return 1
    write_fixture "$repository/.env" $'tracked-target\n'
    git_checked "$repository" add --force .env || return 1
    git_checked "$repository" commit --quiet -m 'track target file' || return 1
    git_checked "$repository" checkout --quiet main || return 1
    write_fixture "$repository/.env" $'ignored-source\n'
    run_git "$repository" wt-add -- "$target" target-with-file
    assert_status 0 'A target conflict should be skipped without failing.' || return 1
    assert_output_contains '[conflict] .env' 'The conflict should be reported.' || return 1
    [[ $(<"$target/.env") == tracked-target ]]
}

case_native_failure() {
    new_repository native-failure || return 1
    local repository=$fixture_repository
    run_git "$repository" wt-add -- --detach
    [[ $result_status -ne 0 && "$result_output" != *'[copied]'* ]]
}

case_blocked_file() {
    new_repository blocked || return 1
    local repository=$fixture_repository target="$test_root/blocked-target"
    add_manifest "$repository" $'.project-continuity/\n' $'.project-continuity/\n' || return 1
    write_fixture "$repository/.project-continuity/state.md" $'fixture state\n'
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 2 'A blocked source should fail provisioning.' || return 1
    assert_output_contains '[rejected] .project-continuity/state.md' 'The blocked file should be reported.' || return 1
    [[ -f "$target/.git" ]]
}

case_traversal() {
    new_repository traversal || return 1
    local repository=$fixture_repository target="$test_root/traversal-target"
    add_manifest "$repository" $'*.env\n' $'../outside.env\n' || return 1
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 2 'A traversal manifest should fail provisioning.' || return 1
    assert_output_contains 'parent-directory traversal' 'The traversal reason should be reported.'
}

case_source_symlink() {
    if [[ $(uname -s) != Darwin ]]; then
        skipped=$((skipped + 1))
        printf 'SKIP source symlink (requires native macOS filesystem semantics)\n'
        return 0
    fi
    new_repository source-symlink || return 1
    local repository=$fixture_repository target="$test_root/source-symlink-target"
    local external="$test_root/source-symlink-external"
    add_manifest "$repository" $'linked.env\n' $'linked.env\n' || return 1
    mkdir -p "$external"
    write_fixture "$external/local.env" $'outside\n'
    ln -s "$external/local.env" "$repository/linked.env" || return 1
    run_git "$repository" wt-add -- --detach "$target" HEAD
    assert_status 2 'A source symlink should fail provisioning.' || return 1
    assert_output_contains 'source path traverses a symbolic link' 'The source symlink should be reported.'
}

case_repair_primary() {
    new_repository repair-primary || return 1
    local repository=$fixture_repository target="$test_root/repair-primary-target"
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$repository/.env.local" $'repair\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-copy
    assert_status 0 'Automatic repair should succeed.' || return 1
    assert_output_contains 'Source worktree:' 'The selected source should be reported.' || return 1
    [[ -f "$target/.env.local" ]]
}

case_repair_explicit() {
    new_repository repair-explicit || return 1
    local repository=$fixture_repository target="$test_root/repair-explicit-target"
    add_manifest "$repository" $'.env.test\n' $'.env.test\n' || return 1
    write_fixture "$repository/.env.test" $'explicit\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-copy --source "$repository"
    assert_status 0 'Explicit repair should succeed.' || return 1
    [[ -f "$target/.env.test" ]]
}

case_branch_forwarding() {
    new_repository forwarding || return 1
    local repository=$fixture_repository target="$test_root/forwarding-target"
    git_checked "$repository" checkout --quiet -b develop || return 1
    write_fixture "$repository/develop.txt" $'develop\n'
    git_checked "$repository" add develop.txt || return 1
    git_checked "$repository" commit --quiet -m 'develop marker' || return 1
    git_checked "$repository" checkout --quiet main || return 1
    run_git "$repository" wt-add -- -b feat/from-develop "$target" develop
    assert_status 0 'Native branch and start-point arguments should succeed.' || return 1
    assert_output_contains 'Handoff reminder: continuity and uncommitted changes stay in this worktree.' 'The handoff reminder should be printed.' || return 1
    assert_output_contains 'Open this exact path in Claude Code, Codex, or Copilot:' 'The exact-path instruction should be printed.' || return 1
    assert_output_contains 'Then say: Continue from project continuity.' 'The continuation prompt should be printed.' || return 1
    assert_output_contains 'Use a separate worktree for another unfinished task.' 'The task-isolation reminder should be printed.' || return 1
    git_checked "$target" branch --show-current || return 1
    [[ "$result_output" == feat/from-develop && -f "$target/develop.txt" ]]
}

case_dry_run() {
    new_repository dry-run || return 1
    local repository=$fixture_repository target="$test_root/dry-run-target"
    add_manifest "$repository" $'.env.local\n' $'.env.local\n' || return 1
    write_fixture "$repository/.env.local" $'dry\n'
    run_git "$repository" wt-add --dry-run -- --detach "$target" HEAD
    assert_status 0 'Dry run should succeed.' || return 1
    assert_output_contains '[matched] .env.local' 'Dry run should report the manifest match.' || return 1
    [[ ! -e "$target" ]]
}

case_mapping_approval() {
    new_repository mapping-approval || return 1
    local repository=$fixture_repository target="$test_root/mapping-approval-target" destination='config/local/.env.local' approval fresh_approval
    write_fixture "$repository/.gitignore" $'.env.local\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add ignore rule' || return 1
    write_fixture "$repository/.env.local" $'first-value\n'
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-provision --dry-run --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination"
    assert_status 0 'A valid mapping dry run should succeed.' || return 1
    assert_output_contains "[approval-required] $destination" 'The dry run should require approval.' || return 1
    assert_output_contains 'Source branch: main' 'The source branch should be reported.' || return 1
    assert_output_contains 'Target branch: (detached)' 'The target branch should be reported.' || return 1
    assert_output_contains 'Target HEAD: ' 'The target HEAD should be reported.' || return 1
    assert_output_contains 'Runtime state: runtime-unverified' 'The runtime state should be reported.' || return 1
    approval=$(printf '%s\n' "$result_output" | sed -n 's/^Approval id: //p' | head -n 1)
    [[ "$approval" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ ! -e "$target/$destination" ]] || return 1

    write_fixture "$target/approval-scope-marker.txt" $'target-head-changed\n'
    git_checked "$target" add approval-scope-marker.txt || return 1
    git_checked "$target" commit --quiet -m 'advance target head' || return 1
    run_git "$target" wt-provision --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination" --approve "$approval"
    assert_status 3 'A changed target HEAD must invalidate the previous approval.' || return 1
    assert_output_contains "[approval-rejected] $destination" 'The changed target HEAD should be rejected.' || return 1
    [[ ! -e "$target/$destination" ]] || return 1

    write_fixture "$repository/.env.local" $'changed-value\n'
    run_git "$target" wt-provision --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination" --approve "$approval"
    assert_status 3 'A changed source should invalidate the previous approval.' || return 1
    assert_output_contains "[approval-rejected] $destination" 'The changed source should be rejected.' || return 1
    [[ ! -e "$target/$destination" ]] || return 1

    run_git "$target" wt-provision --dry-run --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination"
    fresh_approval=$(printf '%s\n' "$result_output" | sed -n 's/^Approval id: //p' | head -n 1)
    [[ "$fresh_approval" =~ ^[0-9a-f]{64}$ && "$fresh_approval" != "$approval" ]] || return 1
    run_git "$target" wt-provision --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination" --approve "$fresh_approval"
    assert_status 0 'An approved exact mapping should copy once.' || return 1
    [[ $(<"$target/$destination") == changed-value ]] || return 1
    run_git "$target" wt-provision --operation copy-ignored-file --source-file "$repository/.env.local" --target "$target" --destination "$destination" --approve "$fresh_approval"
    assert_status 2 'An existing target should block a second copy.' || return 1
    assert_output_contains "[conflict] $destination" 'The existing target conflict should be reported.'
}

case_mapping_rejections() {
    new_repository mapping-rejections || return 1
    local repository=$fixture_repository target="$test_root/mapping-rejections-target" operation
    write_fixture "$repository/Web.config" $'connectionString=DO-NOT-PRINT\n'
    git_checked "$repository" add Web.config || return 1
    git_checked "$repository" commit --quiet -m 'add tracked config' || return 1
    write_fixture "$repository/.gitignore" $'Web.config\nlocal.config\n'
    git_checked "$repository" add .gitignore || return 1
    git_checked "$repository" commit --quiet -m 'add config ignore rules' || return 1
    git_checked "$repository" worktree add --quiet --detach "$target" HEAD || return 1
    run_git "$target" wt-provision --dry-run --operation copy-external-file --source-file "$repository/Web.config" --target "$target" --destination local.config
    assert_status 2 'A tracked application configuration source should be rejected.' || return 1
    assert_output_contains 'tracked files, including application configuration, cannot be copied' 'The tracked source rejection should be reported.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]] || return 1
    [[ ! -e "$target/local.config" ]] || return 1
    for operation in merge-named-section replace-file; do
        run_git "$target" wt-provision --dry-run --operation "$operation" --source-file "$repository/Web.config" --target "$target" --destination local.config
        assert_status 2 "The $operation operation should be report-only." || return 1
        assert_output_contains 'does not perform section merges or whole-file replacement' "The $operation refusal should be reported." || return 1
    done
}

case_ecosystem_evidence() {
    new_repository ecosystem-evidence || return 1
    local repository=$fixture_repository
    write_fixture "$repository/package.json" $'{"scripts":{"dev":"vite"},"private":true}\n'
    write_fixture "$repository/vite.config.js" $'export default {}\n'
    write_fixture "$repository/next.config.js" $'module.exports = {}\n'
    write_fixture "$repository/.env.example" $'API_TOKEN=DO-NOT-PRINT\n'
    git_checked "$repository" add package.json vite.config.js next.config.js .env.example || return 1
    git_checked "$repository" commit --quiet -m 'add ecosystem markers' || return 1
    run_git "$repository" wt-readiness
    assert_status 0 'Framework evidence should be advisory.' || return 1
    assert_output_contains '[ecosystem] package.json: Node.js script-evidence' 'Node evidence should be reported.' || return 1
    assert_output_contains '[ecosystem] vite.config.js: React/Vite framework-marker' 'Vite evidence should be reported.' || return 1
    assert_output_contains '[ecosystem] next.config.js: Next.js framework-marker' 'Next.js evidence should be reported.' || return 1
    assert_output_contains 'Runtime state: runtime-unverified' 'The runtime-unverified state should be reported.' || return 1
    [[ "$result_output" != *'DO-NOT-PRINT'* ]]
}

run_case 'create without manifest' case_no_manifest
run_case 'block unlisted ignored files without explicit override' case_unlisted_blocked
run_case 'read-only check reports unlisted ignored files' case_check_unlisted
run_case 'redact sensitive values from provisioning records' case_redaction
run_case 'ignore Python cache artifacts' case_python_cache
run_case 'read-only check distinguishes an empty manifest' case_check_empty_manifest
run_case 'read-only check reports raw worktree omission and conflict' case_check_raw
run_case 'read-only check reports required local configuration' case_check_required
run_case 'readiness reports modified tracked configuration without copying it' case_readiness_tracked_config
run_case 'readiness reports no local configuration differences' case_readiness_clean
run_case 'readiness reports explicit configuration references without values' case_readiness_references
run_case 'report tracked setup contract without executing it' case_setup_contract
run_case 'copy matching ignored file' case_matching
run_case 'reject tracked manifest file' case_reject_tracked_manifest_file
run_case 'classify private agent files and client settings separately' case_private_client_files
run_case 'reject tracked configuration but copy approved ignored file' case_tracked_config_copy_rejection
run_case 'reject an external source repository' case_external_source_rejection
run_case 'copy nested Unicode path' case_nested_unicode
run_case 'preserve existing target file' case_conflict
run_case 'preserve native Git failure' case_native_failure
run_case 'leave worktree after provisioning rejection' case_blocked_file
run_case 'reject traversal pattern' case_traversal
run_case 'reject source symlink' case_source_symlink
run_case 'repair from discovered primary' case_repair_primary
run_case 'repair from explicit source' case_repair_explicit
run_case 'forward branch and start-point arguments' case_branch_forwarding
run_case 'dry run creates nothing' case_dry_run
run_case 'approve an exact ignored-file mapping without overwriting' case_mapping_approval
run_case 'reject tracked and section-mapping operations' case_mapping_rejections
run_case 'report framework evidence without claiming runtime readiness' case_ecosystem_evidence

printf 'Worktree tool tests: passed=%s failed=%s skipped=%s\n' "$passed" "$failed" "$skipped"
[[ $failed -eq 0 ]]
