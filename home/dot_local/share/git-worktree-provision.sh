#!/usr/bin/env bash
# Managed by the developer environment repository. Provides the implementation behind the macOS
# `git wt-add` and `git wt-copy` aliases without requiring PowerShell.

set -u

temp_files=()
worktree_paths=()
standard_ignored=()
manifest_matched=()
pattern_matched=()
selection_files=()
selection_unlisted=()
selection_patterns=()
selection_missing=()
selection_rejected_patterns=()
selection_rejected_reasons=()
selection_tracked_manifest_files=()
selection_tracked_instructions=()
selection_explicit_only_files=()
selection_explicit_only_categories=()
selection_manifest_present=false
selection_manifest_status=absent
setup_contract_status=absent
setup_contract_script=""
setup_contract_documentation=""
setup_contract_reason=""
tracked_paths=()
rejection_reason=""
report_decision=""
required_missing_count=0
tracked_configurations=()
configuration_keys=()
configuration_sources=()
configuration_kinds=()
configuration_targets=()
configuration_valid=()
configuration_source_present=()
configuration_target_present=()
configuration_target_root_supplied=()
configuration_mappings=()
configuration_reasons=()
configuration_reference_issue_count=0
configuration_evidence_ecosystems=()
configuration_evidence_kinds=()
configuration_evidence_paths=()
configuration_evidence_details=()
mapping_source_branch='(external)'
mapping_source_path=""
mapping_source_classification=""
mapping_source_fingerprint=""
mapping_target_root=""
mapping_target_path=""
mapping_destination=""
mapping_approval_id=""
mapping_operation=""
mapping_reason=""
mapping_valid=false

# A shell Git alias exports repository-local variables from the invoking worktree. They
# must not reach nested `git -C <other-worktree>` calls because GIT_DIR wins over -C.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_DIR GIT_GRAFT_FILE
unset GIT_IMPLICIT_WORK_TREE GIT_INDEX_FILE GIT_INTERNAL_SUPER_PREFIX
unset GIT_NO_REPLACE_OBJECTS GIT_OBJECT_DIRECTORY GIT_PREFIX GIT_REPLACE_REF_BASE
unset GIT_SHALLOW_FILE GIT_WORK_TREE

cleanup() {
    local path
    for path in "${temp_files[@]}"; do
        [[ -n "$path" && -f "$path" ]] && rm -f -- "$path"
    done
}
trap cleanup EXIT

die() {
    printf 'git-worktree-provision: %s\n' "$(display_text "$*")" >&2
    return 2
}

display_text() {
    local safe
    safe=$(printf '%s' "$1" | LC_ALL=C tr '[:cntrl:]' '?')
    safe=$(printf '%s' "$safe" | sed -E \
        -e 's/((password|passwd|pwd|connectionstring|connection-string|api[_-]?key|token|secret|client[_-]?secret|access[_-]?token)[[:space:]]*[:=][[:space:]]*)"[^"]*"/\1[REDACTED]/gI' \
        -e "s/((password|passwd|pwd|connectionstring|connection-string|api[_-]?key|token|secret|client[_-]?secret|access[_-]?token)[[:space:]]*[:=][[:space:]]*)'[^']*'/\\1[REDACTED]/gI" \
        -e 's/((password|passwd|pwd|connectionstring|connection-string|api[_-]?key|token|secret|client[_-]?secret|access[_-]?token)[[:space:]]*[:=][[:space:]]*)[^[:space:];,]+/\1[REDACTED]/gI')
    printf '%s' "$safe"
}

write_record() {
    local category=$1
    local path=$2
    local detail=${3-}
    local safe_path safe_detail
    safe_path=$(display_text "$path")
    if [[ -n "$detail" ]]; then
        safe_detail=$(display_text "$detail")
        printf '[%s] %s: %s\n' "$category" "$safe_path" "$safe_detail"
    else
        printf '[%s] %s\n' "$category" "$safe_path"
    fi
}

new_temp_file() {
    local path
    path=$(mktemp "${TMPDIR:-/tmp}/git-worktree-provision.XXXXXX") || return 1
    temp_files+=("$path")
    new_temp_path=$path
}

canonical_directory() {
    (cd "$1" 2>/dev/null && pwd -P)
}

repository_root() {
    git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

common_git_directory() {
    local root=$1
    local path
    path=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
    if [[ "$path" != /* && ! "$path" =~ ^[A-Za-z]:[\\/] ]]; then
        path="$root/$path"
    fi
    canonical_directory "$path"
}

same_path() {
    local left right
    left=$(canonical_directory "$1") || return 1
    right=$(canonical_directory "$2") || return 1
    [[ "$left" == "$right" ]]
}

path_inside_root() {
    local root=${1%/}
    local path=$2
    [[ "$path" == "$root"/* ]]
}

load_worktree_paths() {
    local root=$1
    local output field
    new_temp_file || return 1
    output=$new_temp_path
    git -C "$root" worktree list --porcelain -z >"$output" || return 1
    worktree_paths=()
    while IFS= read -r -d '' field; do
        case "$field" in
            'worktree '*) worktree_paths+=("${field#worktree }") ;;
        esac
    done <"$output"
}

array_contains() {
    local needle=$1
    shift
    local value
    for value in "$@"; do
        [[ "$value" == "$needle" ]] && return 0
    done
    return 1
}

find_symlink() {
    local root=${1%/}
    local path=$2
    local include_leaf=$3
    local relative remaining segment current leaf

    found_symlink=""
    path_inside_root "$root" "$path" || {
        found_symlink=$path
        return 0
    }

    relative=${path#"$root"/}
    remaining=$relative
    current=$root
    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == */* ]]; then
            segment=${remaining%%/*}
            remaining=${remaining#*/}
            leaf=false
        else
            segment=$remaining
            remaining=""
            leaf=true
        fi

        [[ "$leaf" == true && "$include_leaf" != true ]] && break
        [[ -z "$segment" ]] && continue
        current="$current/$segment"
        if [[ -L "$current" ]]; then
            found_symlink=$current
            return 0
        fi
    done
    return 1
}

get_pattern_rejection_reason() {
    local pattern=$1
    local candidate=$pattern
    rejection_reason=""
    [[ "$candidate" == '!'* ]] && candidate=${candidate#'!'}
    [[ "$candidate" == /* ]] && candidate=${candidate#/}

    if [[ "$candidate" =~ ^[A-Za-z]:[\\/] || "$candidate" =~ ^[/\\]{2} ]]; then
        rejection_reason="absolute filesystem paths are not allowed"
    elif [[ "/$candidate/" == *'/../'* ]]; then
        rejection_reason="parent-directory traversal is not allowed"
    fi
    [[ -n "$rejection_reason" ]]
}

get_file_rejection_reason() {
    local relative_path=$1
    local normalized lower name extension segment rest
    rejection_reason=""
    normalized=${relative_path//\\//}
    normalized=${normalized#/}
    lower=$(printf '%s' "$normalized" | LC_ALL=C tr '[:upper:]' '[:lower:]')

    rest=$lower
    while :; do
        if [[ "$rest" == */* ]]; then
            segment=${rest%%/*}
            rest=${rest#*/}
        else
            segment=$rest
            rest=""
        fi
        case "$segment" in
            .git|.project-continuity|node_modules|packages|bin|obj|.vs|.cache|__pycache__|coverage|dist)
                rejection_reason="blocked directory '$segment'"
                return 0
                ;;
        esac
        [[ -z "$rest" ]] && break
    done

    case "/$lower" in
        /.claude/worktrees|/.claude/worktrees/*|/.claude/logs|/.claude/logs/*|/.claude/agent-memory-local|/.claude/agent-memory-local/*)
            rejection_reason="Claude session state is never copied"
            return 0
            ;;
        /.codex|/.codex/*)
            rejection_reason="Codex local state is never copied"
            return 0
            ;;
    esac

    name=${lower##*/}
    case "$name" in
        .env.production|.env.production.local)
            rejection_reason="production environment files are never copied"
            return 0
            ;;
        .npmrc|nuget.config|credentials.json|auth.json|id_rsa|id_ed25519)
            rejection_reason="credential or authentication files are never copied"
            return 0
            ;;
    esac

    extension=""
    [[ "$name" == *.* ]] && extension=.${name##*.}
    case "$extension" in
        .pem|.key|.pfx|.p12|.cer|.crt)
            rejection_reason="private keys and certificates are never copied"
            return 0
            ;;
        .bak|.db|.sqlite|.sqlite3|.pyc|.pyo)
            rejection_reason="database backups and local data stores are never copied"
            return 0
            ;;
    esac
    return 1
}

get_explicit_only_category() {
    local relative_path=$1 normalized name
    normalized=${relative_path//\\//}
    normalized=${normalized#/}
    normalized=$(printf '%s' "$normalized" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    name=${normalized##*/}
    case "$name" in
        claude.local.md|claude.override.md|agents.override.md|agents.local.md|codex.local.md|codex.override.md)
            explicit_only_category=agent-override
            return 0
            ;;
        claude.settings.md|claude.settings.local.md|agents.settings.md|agents.settings.local.md|codex.settings.md|codex.settings.local.md)
            explicit_only_category=client-settings
            return 0
            ;;
    esac
    case "$normalized" in
        .claude/settings.local.json|*/.claude/settings.local.json)
            explicit_only_category=client-settings
            return 0
            ;;
    esac
    explicit_only_category=""
    return 1
}

load_ignored_files() {
    local root=$1
    local mode=$2
    local value output
    new_temp_file || return 1
    output=$new_temp_path

    if [[ "$mode" == standard ]]; then
        git -C "$root" ls-files --others --ignored --exclude-standard -z -- >"$output" || return 1
        standard_ignored=()
        while IFS= read -r -d '' value; do standard_ignored+=("$value"); done <"$output"
    elif [[ "$mode" == manifest ]]; then
        git -C "$root" ls-files --others --ignored --exclude-from=.worktreeinclude -z -- >"$output" || return 1
        manifest_matched=()
        while IFS= read -r -d '' value; do manifest_matched+=("$value"); done <"$output"
    else
        git -C "$root" ls-files --others --ignored --exclude-from="$mode" -z -- >"$output" || return 1
        pattern_matched=()
        while IFS= read -r -d '' value; do pattern_matched+=("$value"); done <"$output"
    fi
}

load_tracked_paths() {
    local root=$1
    new_temp_file || return 1
    git -C "$root" ls-files -z -- >"$new_temp_path" || return 1
    tracked_paths=()
    while IFS= read -r -d '' value; do tracked_paths+=("$value"); done <"$new_temp_path"
}

valid_repository_relative_contract_path() {
    local path=${1-} normalized=${1-}
    normalized=${normalized//\\//}
    [[ -n "$normalized" ]] || return 1
    [[ "$normalized" != /* && ! "$normalized" =~ ^[A-Za-z]:/ ]] || return 1
    [[ ! "$normalized" =~ (^|/)\.\.(\/|$) ]] || return 1
    [[ ! "$normalized" =~ [$'\r\n'] ]] || return 1
    return 0
}

load_setup_contract() {
    local source_root=$1
    local contract="$source_root/.worktree-provision"
    local line key value schema_version="" script_path="" documentation_path=""
    setup_contract_status=absent
    setup_contract_script=""
    setup_contract_documentation=""
    setup_contract_reason=""

    [[ -f "$contract" ]] || return 0
    if ! array_contains '.worktree-provision' "${tracked_paths[@]}"; then
        setup_contract_status=invalid
        setup_contract_reason='setup contract exists but is not tracked'
        return 0
    fi
    if find_symlink "$source_root" "$contract" true; then
        setup_contract_status=invalid
        setup_contract_reason='setup contract is or traverses a symbolic link'
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z "$line" || "$line" == '#'* ]] && continue
        if [[ "$line" != *=* ]]; then
            setup_contract_status=invalid
            setup_contract_reason='setup contract contains an invalid entry'
            return 0
        fi
        key=${line%%=*}
        value=${line#*=}
        key=${key%"${key##*[![:space:]]}"}
        value=${value#"${value%%[![:space:]]*}"}
        case "$key" in
            schemaVersion)
                [[ -z "$schema_version" ]] || { setup_contract_status=invalid; setup_contract_reason='setup contract contains an unsupported or duplicate key'; return 0; }
                schema_version=$value
                ;;
            script)
                [[ -z "$script_path" ]] || { setup_contract_status=invalid; setup_contract_reason='setup contract contains an unsupported or duplicate key'; return 0; }
                script_path=${value//\\//}
                ;;
            documentation)
                [[ -z "$documentation_path" ]] || { setup_contract_status=invalid; setup_contract_reason='setup contract contains an unsupported or duplicate key'; return 0; }
                documentation_path=${value//\\//}
                ;;
            *)
                setup_contract_status=invalid
                setup_contract_reason='setup contract contains an unsupported or duplicate key'
                return 0
                ;;
        esac
    done <"$contract"

    if [[ "$schema_version" != 1 ]]; then
        setup_contract_status=invalid
        setup_contract_reason='setup contract schemaVersion must be 1'
        return 0
    fi
    if ! valid_repository_relative_contract_path "$script_path" ||
        ! array_contains "$script_path" "${tracked_paths[@]}" ||
        [[ ! -f "$source_root/$script_path" ]] ||
        find_symlink "$source_root" "$source_root/$script_path" true; then
        setup_contract_status=invalid
        setup_contract_reason='setup contract must declare a tracked, repository-relative setup script'
        return 0
    fi
    if [[ -n "$documentation_path" ]] && {
        ! valid_repository_relative_contract_path "$documentation_path" ||
        ! array_contains "$documentation_path" "${tracked_paths[@]}" ||
        [[ ! -f "$source_root/$documentation_path" ]] ||
        find_symlink "$source_root" "$source_root/$documentation_path" true;
    }; then
        setup_contract_status=invalid
        setup_contract_reason='setup contract documentation must be a tracked, repository-relative file'
        return 0
    fi
    setup_contract_status=valid
    setup_contract_script=$script_path
    setup_contract_documentation=$documentation_path
}

write_setup_contract_record() {
    case "$setup_contract_status" in
        absent)
            write_record setup-contract .worktree-provision 'no tracked setup contract was found'
            ;;
        valid)
            local detail="tracked setup contract declares $setup_contract_script; not executed"
            [[ -n "$setup_contract_documentation" ]] && detail="$detail; review $setup_contract_documentation"
            write_record setup-contract .worktree-provision "$detail"
            ;;
        *)
            write_record setup-contract-invalid .worktree-provision "$setup_contract_reason"
            ;;
    esac
}

load_tracked_manifest_files() {
    local root=$1 path status temporary_root temporary_parent
    selection_tracked_manifest_files=()
    temporary_parent=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || {
        die 'Git could not prepare the isolated manifest matcher.'
        return 2
    }
    temporary_root=$(mktemp -d "$temporary_parent/git-worktree-provision-manifest.XXXXXX") || {
        die 'Git could not prepare the isolated manifest matcher.'
        return 2
    }
    if ! cp "$root/.worktreeinclude" "$temporary_root/.gitignore" ||
        ! git -C "$temporary_root" init --quiet; then
        case "$temporary_root" in
            "$temporary_parent"/git-worktree-provision-manifest.*) rm -rf -- "$temporary_root" ;;
            *) die 'Refusing to remove an unexpected manifest matcher path.'; return 2 ;;
        esac
        die 'Git could not prepare the isolated manifest matcher.'
        return 2
    fi
    for path in "${tracked_paths[@]}"; do
        git -C "$temporary_root" check-ignore --no-index -- "$path" >/dev/null 2>&1
        status=$?
        if [[ $status -eq 0 ]]; then
            selection_tracked_manifest_files+=("$path")
        elif [[ $status -ne 1 ]]; then
            case "$temporary_root" in
                "$temporary_parent"/git-worktree-provision-manifest.*) rm -rf -- "$temporary_root" ;;
                *) die 'Refusing to remove an unexpected manifest matcher path.'; return 2 ;;
            esac
            die 'Git could not evaluate tracked paths against .worktreeinclude.'
            return 2
        fi
    done
    case "$temporary_root" in
        "$temporary_parent"/git-worktree-provision-manifest.*) rm -rf -- "$temporary_root" ;;
        *) die 'Refusing to remove an unexpected manifest matcher path.'; return 2 ;;
    esac
    return 0
}

load_selection() {
    local source_root=$1
    local manifest="$source_root/.worktreeinclude"
    local line pattern match pattern_file has_match source_path selected

    selection_manifest_present=false
    selection_manifest_status=absent
    selection_files=()
    selection_unlisted=()
    selection_patterns=()
    selection_missing=()
    selection_rejected_patterns=()
    selection_rejected_reasons=()
    selection_tracked_manifest_files=()
    selection_tracked_instructions=()
    selection_explicit_only_files=()
    selection_explicit_only_categories=()

    load_ignored_files "$source_root" standard || {
        die "Git could not enumerate normally ignored files."
        return 2
    }
    load_tracked_paths "$source_root" || {
        die "Git could not enumerate tracked files."
        return 2
    }
    load_setup_contract "$source_root"
    local tracked_path tracked_name
    for tracked_path in "${tracked_paths[@]}"; do
        tracked_name=${tracked_path##*/}
        tracked_name=$(printf '%s' "$tracked_name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
        case "$tracked_name" in
            claude.md|agents.md) selection_tracked_instructions+=("$tracked_path") ;;
        esac
    done

    if [[ ! -f "$manifest" ]]; then
        for match in "${standard_ignored[@]}"; do
            source_path="$source_root/$match"
            [[ -f "$source_path" ]] || continue
            get_file_rejection_reason "$match" && continue
            if get_explicit_only_category "$match"; then
                selection_explicit_only_files+=("$match")
                selection_explicit_only_categories+=("$explicit_only_category")
            else
                selection_unlisted+=("$match")
            fi
        done
        return 0
    fi
    selection_manifest_present=true
    selection_manifest_status=tracked

    if find_symlink "$source_root" "$manifest" true; then
        die ".worktreeinclude is or traverses a symbolic link."
        return 2
    fi
    if ! git -C "$source_root" ls-files --error-unmatch -- .worktreeinclude >/dev/null 2>&1; then
        selection_manifest_status=untracked
        for match in "${standard_ignored[@]}"; do
            source_path="$source_root/$match"
            [[ -f "$source_path" ]] || continue
            get_file_rejection_reason "$match" && continue
            if get_explicit_only_category "$match"; then
                selection_explicit_only_files+=("$match")
                selection_explicit_only_categories+=("$explicit_only_category")
            else
                selection_unlisted+=("$match")
            fi
        done
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == '#'* ]] && continue
        selection_patterns+=("$line")
        if get_pattern_rejection_reason "$line"; then
            selection_rejected_patterns+=("$line")
            selection_rejected_reasons+=("$rejection_reason")
        fi
    done <"$manifest"

    if [[ ${#selection_rejected_patterns[@]} -eq 0 ]]; then
        load_tracked_manifest_files "$source_root" || return 2
    fi

    load_ignored_files "$source_root" manifest || {
        die "Git could not apply .worktreeinclude."
        return 2
    }

    for match in "${manifest_matched[@]}"; do
        array_contains "$match" "${standard_ignored[@]}" && selection_files+=("$match")
    done

    for match in "${standard_ignored[@]}"; do
        selected=false
        array_contains "$match" "${selection_files[@]}" && selected=true
        [[ "$selected" == true ]] && continue
        source_path="$source_root/$match"
        [[ -f "$source_path" ]] || continue
        get_file_rejection_reason "$match" && continue
        if get_explicit_only_category "$match"; then
            selection_explicit_only_files+=("$match")
            selection_explicit_only_categories+=("$explicit_only_category")
            continue
        fi
        selection_unlisted+=("$match")
    done

    for pattern in "${selection_patterns[@]}"; do
        [[ "$pattern" == '!'* ]] && continue
        get_pattern_rejection_reason "$pattern" && continue
        new_temp_file || return 2
        pattern_file=$new_temp_path
        printf '%s\n' "$pattern" >"$pattern_file"
        load_ignored_files "$source_root" "$pattern_file" || {
            die "Git could not evaluate a .worktreeinclude pattern."
            return 2
        }
        has_match=false
        for match in "${pattern_matched[@]}"; do
            if array_contains "$match" "${standard_ignored[@]}"; then
                has_match=true
                break
            fi
        done
        [[ "$has_match" == false ]] && selection_missing+=("$pattern")
    done
    return 0
}

get_provision_decision() {
    local required_missing=${1:-0}
    if [[ "$selection_manifest_status" == untracked || ${#selection_rejected_patterns[@]} -gt 0 ||
        ${#selection_tracked_manifest_files[@]} -gt 0 ]]; then
        report_decision=invalid-manifest
    elif [[ "$required_missing" -gt 0 ]]; then
        report_decision=required-local-config-missing
    elif [[ ${#selection_unlisted[@]} -gt 0 ]]; then
        report_decision=eligible-ignored-files-unlisted
    elif [[ "$selection_manifest_present" == false ]]; then
        report_decision=no-manifest-needed
    elif [[ ${#selection_files[@]} -eq 0 ]]; then
        report_decision=manifest-present-no-matches
    else
        report_decision=manifest-ready
    fi
}

text_fingerprint() {
    local value=$1
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$value" | sha256sum | awk '{print $1}'
    else
        printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
    fi
}

file_fingerprint() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | awk '{print $1}'
    else
        shasum -a 256 -- "$1" | awk '{print $1}'
    fi
}

get_provisioning_state() {
    case "$report_decision" in
        invalid-manifest|required-local-config-missing) printf '%s' provisioning-blocked ;;
        eligible-ignored-files-unlisted) printf '%s' provisioning-review-required ;;
        *) printf '%s' provisioning-ready ;;
    esac
}

write_readiness_states() {
    printf 'Provisioning state: %s\n' "$(get_provisioning_state)"
    printf '%s\n' 'Runtime state: runtime-unverified'
}

load_configuration_evidence() {
    local source_root=$1 relative_path name source_path
    configuration_evidence_ecosystems=()
    configuration_evidence_kinds=()
    configuration_evidence_paths=()
    configuration_evidence_details=()
    for relative_path in "${tracked_paths[@]}"; do
        relative_path=${relative_path//\\//}
        name=${relative_path##*/}
        name=$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
        case "$name" in
            web.config|app.config|global.json|packages.config|*.csproj|*.fsproj|appsettings*.json|launchsettings.json)
                configuration_evidence_ecosystems+=(.NET)
                configuration_evidence_kinds+=(framework-marker)
                configuration_evidence_paths+=("$relative_path")
                configuration_evidence_details+=("tracked .NET configuration or project marker; runtime consumption is not established")
                ;;
            package.json)
                configuration_evidence_ecosystems+=(Node.js)
                configuration_evidence_kinds+=(framework-marker)
                configuration_evidence_paths+=("$relative_path")
                configuration_evidence_details+=("tracked package manifest; scripts and runtime consumption require project verification")
                source_path="$source_root/$relative_path"
                if grep -Eiq '\b(next|vite|react-scripts|webpack|node)\b' "$source_path" 2>/dev/null; then
                    configuration_evidence_ecosystems+=(Node.js)
                    configuration_evidence_kinds+=(script-evidence)
                    configuration_evidence_paths+=("$relative_path")
                    configuration_evidence_details+=("package scripts or dependencies mention a JavaScript tool; runtime consumption is not established")
                fi
                ;;
            vite.config.*)
                configuration_evidence_ecosystems+=(React/Vite)
                configuration_evidence_kinds+=(framework-marker)
                configuration_evidence_paths+=("$relative_path")
                configuration_evidence_details+=("tracked Vite configuration marker; environment consumption is not established")
                ;;
            next.config.*)
                configuration_evidence_ecosystems+=(Next.js)
                configuration_evidence_kinds+=(framework-marker)
                configuration_evidence_paths+=("$relative_path")
                configuration_evidence_details+=("tracked Next.js configuration marker; environment consumption is not established")
                ;;
            .env.example|.env.template|docker-compose*.yml|docker-compose*.yaml|compose*.yml|compose*.yaml)
                configuration_evidence_ecosystems+=(generic)
                configuration_evidence_kinds+=(configuration-marker)
                configuration_evidence_paths+=("$relative_path")
                configuration_evidence_details+=("tracked configuration documentation or container marker; runtime consumption is not established")
                ;;
        esac
    done
}

write_configuration_evidence_records() {
    local i
    for ((i = 0; i < ${#configuration_evidence_paths[@]}; i++)); do
        write_record ecosystem "${configuration_evidence_paths[$i]}" "${configuration_evidence_ecosystems[$i]} ${configuration_evidence_kinds[$i]}: ${configuration_evidence_details[$i]}"
    done
}

check_required_paths() {
    local source_root=$1
    local target_root=${2-}
    shift 2
    local relative_path source_path target_path
    required_missing_count=0
    for relative_path in "$@"; do
        if [[ "$relative_path" == /* || "$relative_path" =~ ^[A-Za-z]:[\\/] || "$relative_path" =~ (^|/)\.\.(\/|$) ]]; then
            write_record required-rejected "$relative_path" 'required paths must be repository-relative'
            required_missing_count=$((required_missing_count + 1))
            continue
        fi
        source_path="$source_root/${relative_path//\//\/}"
        if [[ ! -f "$source_path" ]]; then
            write_record required-missing "$relative_path" 'source file is not present'
            required_missing_count=$((required_missing_count + 1))
            continue
        fi
        if [[ -n "$target_root" ]]; then
            target_path="$target_root/${relative_path//\//\/}"
            if [[ ! -f "$target_path" ]]; then
                write_record required-missing "$relative_path" 'target file is not present'
                required_missing_count=$((required_missing_count + 1))
                continue
            fi
        fi
        write_record required-present "$relative_path"
    done
}

worktree_branch() {
    local root=${1-} missing_value=${2-(not-created)} branch
    if [[ -z "$root" || ! -d "$root" ]]; then
        printf '%s' "$missing_value"
        return 0
    fi
    branch=$(git -C "$root" branch --show-current 2>/dev/null) || {
        die "Could not resolve the branch for worktree '$root'."
        return 2
    }
    if [[ -n "$branch" ]]; then
        printf '%s' "$branch"
    else
        printf '%s' '(detached)'
    fi
}

worktree_head() {
    local root=${1-} missing_value=${2-(not-created)} head
    if [[ -z "$root" || ! -d "$root" ]]; then
        printf '%s' "$missing_value"
        return 0
    fi
    head=$(git -C "$root" rev-parse HEAD 2>/dev/null) || {
        die "Could not resolve the current commit for worktree '$root'."
        return 2
    }
    head=${head//$'\r'/}
    head=${head//$'\n'/}
    [[ -n "$head" ]] && printf '%s' "$head" || printf '%s' '(no-commit)'
}

is_tracked_configuration_candidate() {
    local relative_path=$1 name lower
    name=${relative_path##*/}
    lower=$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *.config|.env|.env.*|web.config|app.config|appsettings.json|appsettings.*.json|launchsettings.json|applicationhost.config)
            return 0
            ;;
    esac
    return 1
}

load_modified_tracked_configuration() {
    local source_root=$1 output relative_path mode sorted
    tracked_configurations=()
    for mode in unstaged cached; do
        new_temp_file || return 1
        output=$new_temp_path
        if [[ "$mode" == cached ]]; then
            git -C "$source_root" diff --cached --name-only --diff-filter=ACMRTUXB -z -- >"$output" || return 1
        else
            git -C "$source_root" diff --name-only --diff-filter=ACMRTUXB -z -- >"$output" || return 1
        fi
        while IFS= read -r -d '' relative_path; do
            if is_tracked_configuration_candidate "$relative_path" &&
                ! array_contains "$relative_path" "${tracked_configurations[@]}"; then
                tracked_configurations+=("$relative_path")
            fi
        done <"$output"
    done
    if [[ ${#tracked_configurations[@]} -gt 1 ]]; then
        sorted=()
        while IFS= read -r relative_path; do
            sorted+=("$relative_path")
        done < <(printf '%s\n' "${tracked_configurations[@]}" | LC_ALL=C sort)
        tracked_configurations=("${sorted[@]}")
    fi
}

extract_configuration_references() {
    local config_path=$1
    local flattened token value tag
    flattened=$(tr '\n\r' '  ' <"$config_path") || return 1
    while [[ "$flattened" == *'<!--'* ]]; do
        local before=${flattened%%'<!--'*}
        local after=${flattened#*'<!--'}
        [[ "$after" == *'-->'* ]] || break
        after=${after#*'-->'}
        flattened=$before$after
    done

    while IFS= read -r token; do
        value=${token#*=}
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        case "$value" in
            \"*\") value=${value:1:${#value}-2} ;;
            \'*\') value=${value:1:${#value}-2} ;;
        esac
        printf 'configSource\t%s\n' "$value"
    done < <(printf '%s' "$flattened" | grep -Eio "configSource[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')" || true)

    while IFS= read -r tag; do
        while IFS= read -r token; do
            value=${token#*=}
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            case "$value" in
                \"*\") value=${value:1:${#value}-2} ;;
                \'*\') value=${value:1:${#value}-2} ;;
            esac
            printf 'appSettings file\t%s\n' "$value"
        done < <(printf '%s' "$tag" | grep -Eio "file[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')" || true)
    done < <(printf '%s' "$flattened" | grep -Eio '<appsettings([[:space:]>][^>]*)?>' || true)
}

normalize_configuration_reference() {
    local source_relative_path=$1
    local raw_path=$2
    local normalized source_directory combined segment target=""
    local segments=()
    configuration_target=""
    configuration_reason=""

    normalized=$(printf '%s' "$raw_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '\\' '/')
    if [[ -z "$normalized" ]]; then
        configuration_reason='reference path is empty'
        return 1
    fi
    if [[ "$normalized" == /* || "$normalized" =~ ^[A-Za-z]:/ || "$normalized" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; then
        configuration_target='(invalid-reference)'
        configuration_reason='reference is not a repository-relative path'
        return 1
    fi

    source_directory=${source_relative_path%/*}
    [[ "$source_directory" == "$source_relative_path" ]] && source_directory=""
    if [[ -n "$source_directory" ]]; then
        combined="$source_directory/$normalized"
    else
        combined=$normalized
    fi

    IFS='/' read -r -a segments <<<"$combined"
    for segment in "${segments[@]}"; do
        [[ -z "$segment" || "$segment" == '.' ]] && continue
        if [[ "$segment" == '..' ]]; then
            configuration_target='(invalid-reference)'
            configuration_reason='reference escapes the repository-relative configuration boundary'
            return 1
        fi
        if [[ -z "$target" ]]; then target=$segment; else target="$target/$segment"; fi
    done
    if [[ -z "${target-}" ]]; then
        configuration_target='(invalid-reference)'
        configuration_reason='reference path resolves to the repository root'
        return 1
    fi
    configuration_target=$target
    return 0
}

load_configuration_readiness() {
    local source_root=$1
    local target_root=${2-}
    local output relative_path source_path parsed kind raw key target_path target_present=false
    local mapping source_present=false
    configuration_keys=()
    configuration_sources=()
    configuration_kinds=()
    configuration_targets=()
    configuration_valid=()
    configuration_source_present=()
    configuration_target_present=()
    configuration_target_root_supplied=()
    configuration_mappings=()
    configuration_reasons=()
    configuration_reference_issue_count=0

    load_modified_tracked_configuration "$source_root" || return 1
    load_configuration_evidence "$source_root" || return 1
    new_temp_file || return 1
    output=$new_temp_path
    git -C "$source_root" ls-files -z -- >"$output" || return 1
    while IFS= read -r -d '' relative_path; do
        is_tracked_configuration_candidate "$relative_path" || continue
        source_path="$source_root/$relative_path"
        new_temp_file || return 1
        parsed=$new_temp_path
        if ! extract_configuration_references "$source_path" >"$parsed"; then
            key="$relative_path|unreadable"
            configuration_keys+=("$key")
            configuration_sources+=("$relative_path")
            configuration_kinds+=('configuration file')
            configuration_targets+=("$relative_path")
            configuration_valid+=(false)
            configuration_source_present+=(false)
            configuration_target_present+=(false)
            if [[ -n "$target_root" ]]; then configuration_target_root_supplied+=(true); else configuration_target_root_supplied+=(false); fi
            configuration_mappings+=(unmapped)
            configuration_reasons+=('could not inspect the file for explicit configuration references')
            continue
        fi
        while IFS=$'\t' read -r kind raw; do
            [[ -n "$kind" ]] || continue
            normalize_configuration_reference "$relative_path" "$raw"
            target=$configuration_target
            key="$relative_path|$kind|$target"
            array_contains "$key" "${configuration_keys[@]}" && continue
            configuration_keys+=("$key")
            configuration_sources+=("$relative_path")
            configuration_kinds+=("$kind")
            configuration_targets+=("$target")
            if [[ -z "$configuration_reason" ]]; then
                configuration_valid+=(true)
                target_path="$source_root/$target"
                [[ -f "$target_path" ]] && source_present=true || source_present=false
                if git -C "$source_root" ls-files --error-unmatch -- "$target" >/dev/null 2>&1; then
                    mapping=tracked
                elif array_contains "$target" "${standard_ignored[@]}"; then
                    mapping=ignored
                else
                    mapping=unmapped
                fi
                if [[ -n "$target_root" && -f "$target_root/$target" ]]; then
                    target_present=true
                else
                    target_present=false
                fi
                configuration_reasons+=("")
            else
                configuration_valid+=(false)
                source_present=false
                target_present=false
                mapping=unmapped
                configuration_reasons+=("$configuration_reason")
            fi
            configuration_source_present+=("$source_present")
            configuration_target_present+=("$target_present")
            if [[ -n "$target_root" ]]; then configuration_target_root_supplied+=(true); else configuration_target_root_supplied+=(false); fi
            configuration_mappings+=("$mapping")
        done <"$parsed"
    done <"$output"
}

write_configuration_reference_records() {
    local i label
    configuration_reference_issue_count=0
    for ((i = 0; i < ${#configuration_sources[@]}; i++)); do
        label="${configuration_sources[$i]} -> ${configuration_targets[$i]}"
        write_record expected "$label" "explicit ${configuration_kinds[$i]} reference"
        if [[ "${configuration_valid[$i]}" != true ]]; then
            write_record unmapped "$label" "${configuration_reasons[$i]}"
            configuration_reference_issue_count=$((configuration_reference_issue_count + 1))
            continue
        fi
        if [[ "${configuration_source_present[$i]}" != true ]]; then
            write_record missing "$label" 'referenced configuration file is missing from the source worktree'
            configuration_reference_issue_count=$((configuration_reference_issue_count + 1))
            continue
        fi
        write_record present "$label" "referenced configuration file is present in the source worktree (${configuration_mappings[$i]})"
        if [[ "${configuration_mappings[$i]}" == unmapped ]]; then
            write_record unmapped "$label" 'referenced configuration file is present but is neither tracked nor ignored'
            configuration_reference_issue_count=$((configuration_reference_issue_count + 1))
        fi
        if [[ "${configuration_target_root_supplied[$i]}" == true && "${configuration_target_present[$i]}" != true ]]; then
            write_record missing "$label" 'target worktree is missing the referenced configuration file'
            configuration_reference_issue_count=$((configuration_reference_issue_count + 1))
        fi
    done
}

write_worktree_identity() {
    local source_root=$1 target_root=${2-} target_display target_branch
    printf 'Source worktree: %s\n' "$(display_text "$source_root")"
    printf 'Source branch: %s\n' "$(display_text "$(worktree_branch "$source_root")")"
    if [[ -n "$target_root" ]]; then
        target_display=$target_root
        target_branch=$(worktree_branch "$target_root") || return 2
    else
        target_display='(not-specified)'
        target_branch='(not-specified)'
    fi
    printf 'Target worktree: %s\n' "$(display_text "$target_display")"
    printf 'Target branch: %s\n' "$(display_text "$target_branch")"
}

write_readiness_report() {
    local source_root=$1 target_root=${2-} relative_path i detail
    printf '%s\n' 'Worktree readiness: read-only'
    write_worktree_identity "$source_root" "$target_root" || return 2
    printf 'Manifest: %s\n' "$(display_text "$selection_manifest_status")"
    write_setup_contract_record
    for relative_path in "${selection_files[@]}"; do
        write_record authorized "$relative_path" 'ignored file authorized for provisioning'
    done
    for relative_path in "${selection_tracked_manifest_files[@]}"; do
        if is_tracked_configuration_candidate "$relative_path"; then
            detail='tracked application-owned configuration cannot be copied from another worktree; use project-specific manual setup or an explicit repository contract'
        else
            detail='tracked files already arrive through Git and cannot be copied from another worktree; remove this path from .worktreeinclude'
        fi
        write_record rejected "$relative_path" "$detail"
    done
    for relative_path in "${selection_tracked_instructions[@]}"; do
        write_record tracked-instructions "$relative_path" 'tracked instructions arrive through Git; not copied'
    done
    for ((i = 0; i < ${#selection_explicit_only_files[@]}; i++)); do
        if [[ "${selection_explicit_only_categories[$i]}" == agent-override ]]; then
            detail='private agent override affects agent behavior; not suggested as ordinary configuration'
        else
            detail='client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration'
        fi
        write_record "${selection_explicit_only_categories[$i]}" "${selection_explicit_only_files[$i]}" "$detail"
    done
    for relative_path in "${selection_unlisted[@]}"; do
        write_record unlisted "$relative_path" 'ignored file present but not authorized for provisioning'
    done
    for relative_path in "${tracked_configurations[@]}"; do
        write_record tracked-config "$relative_path" 'modified tracked configuration was not copied; review only if this worktree requires the local override.'
    done
    write_configuration_evidence_records
    write_configuration_reference_records
    if [[ ${#selection_files[@]} -eq 0 && ${#selection_tracked_manifest_files[@]} -eq 0 &&
        ${#selection_tracked_instructions[@]} -eq 0 && ${#selection_explicit_only_files[@]} -eq 0 &&
        ${#selection_unlisted[@]} -eq 0 && ${#tracked_configurations[@]} -eq 0 &&
        ${#configuration_evidence_paths[@]} -eq 0 &&
        $configuration_reference_issue_count -eq 0 ]]; then
        printf '%s\n' '[configuration] no local configuration differences'
    fi
    get_provision_decision
    write_readiness_states
    printf '%s\n' 'Readiness limits: fresh build, running application server, authenticated browser session, and application credentials were not checked.'
    printf '%s\n' 'Writes: none'
}

write_provision_report() {
    local source_root=$1
    local target_root=${2-}
    shift 2
    local relative_path reason source_path target_path i detail

    printf '%s\n' 'Provisioning check: read-only'
    printf 'Source worktree: %s\n' "$(display_text "$source_root")"
    printf 'Manifest: %s\n' "$(display_text "$selection_manifest_status")"
    write_setup_contract_record

    for relative_path in "${selection_files[@]}"; do
        write_record matched "$relative_path" 'Git-ignored and manifest-listed'
    done
    for relative_path in "${selection_tracked_manifest_files[@]}"; do
        if is_tracked_configuration_candidate "$relative_path"; then
            detail='tracked application-owned configuration cannot be copied from another worktree; use project-specific manual setup or an explicit repository contract'
        else
            detail='tracked files already arrive through Git and cannot be copied from another worktree; remove this path from .worktreeinclude'
        fi
        write_record rejected "$relative_path" "$detail"
    done
    for relative_path in "${selection_tracked_instructions[@]}"; do
        write_record tracked-instructions "$relative_path" 'tracked instructions arrive through Git; not copied'
    done
    for ((i = 0; i < ${#selection_explicit_only_files[@]}; i++)); do
        if [[ "${selection_explicit_only_categories[$i]}" == agent-override ]]; then
            detail='private agent override affects agent behavior; not suggested as ordinary configuration'
        else
            detail='client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration'
        fi
        write_record "${selection_explicit_only_categories[$i]}" "${selection_explicit_only_files[$i]}" "$detail"
    done
    for relative_path in "${selection_unlisted[@]}"; do
        write_record unlisted "$relative_path" 'eligible Git-ignored file is not manifest-listed'
    done
    for relative_path in "${selection_missing[@]}"; do
        write_record missing "$relative_path" 'no present Git-ignored source file matched'
    done
    for ((i = 0; i < ${#selection_rejected_patterns[@]}; i++)); do
        write_record rejected "${selection_rejected_patterns[$i]}" "${selection_rejected_reasons[$i]}"
    done

    load_configuration_readiness "$source_root" "$target_root" || return 2
    for relative_path in "${tracked_configurations[@]}"; do
        write_record tracked-config "$relative_path" 'modified tracked configuration was not copied; review only if this worktree requires the local override.'
    done
    write_configuration_evidence_records
    write_configuration_reference_records

    for relative_path in "${selection_files[@]}"; do
        if get_file_rejection_reason "$relative_path"; then
            write_record rejected "$relative_path" "$rejection_reason"
            continue
        fi
        source_path="$source_root/${relative_path//\//\/}"
        if [[ ! -f "$source_path" ]]; then
            write_record missing "$relative_path" 'source file no longer exists or is not a regular file'
            continue
        fi
        if [[ -n "$target_root" ]]; then
            target_path="$target_root/${relative_path//\//\/}"
            if [[ -e "$target_path" || -L "$target_path" ]]; then
                write_record conflict "$relative_path" 'target already exists; not overwritten'
                continue
            fi
        fi
        write_record would-copy "$relative_path"
    done

    check_required_paths "$source_root" "$target_root" "$@"
    get_provision_decision "$required_missing_count"
    if [[ $# -eq 0 ]]; then
        printf '%s\n' 'Requirement: unknown (application-specific; verify build or startup)'
    fi
    printf 'Decision: %s\n' "$(display_text "$report_decision")"
    write_readiness_states
    printf '%s\n' 'Writes: none'
}

assert_same_repository() {
    local source_common target_common
    source_common=$(common_git_directory "$1") || {
        die "Could not resolve the source repository's common Git directory."
        return 2
    }
    target_common=$(common_git_directory "$2") || {
        die "Could not resolve the target repository's common Git directory."
        return 2
    }
    if [[ "$source_common" != "$target_common" ]]; then
        die "Source and target are not worktrees of the same Git repository."
        return 2
    fi
}

provision_files() {
    local source_root=$1
    local target_root=$2
    local dry_run=${3-false}
    local pattern reason relative_path source_path target_path target_directory
    local copied=0 conflicts=0 rejected=0 i detail

    assert_same_repository "$source_root" "$target_root" || return 2
    load_selection "$source_root" || return 2
    if [[ "$selection_manifest_present" == false ]]; then
        write_record skipped .worktreeinclude "manifest not found in source worktree"
        for relative_path in "${selection_unlisted[@]}"; do
            write_record unlisted "$relative_path" 'eligible Git-ignored file is not manifest-listed'
        done
        return 0
    fi
    if [[ "$selection_manifest_status" == untracked ]]; then
        write_record rejected .worktreeinclude 'manifest exists but is not tracked'
        return 2
    fi

    for relative_path in "${selection_unlisted[@]}"; do
        write_record unlisted "$relative_path" 'eligible Git-ignored file is not manifest-listed'
    done
    for pattern in "${selection_missing[@]}"; do
        write_record missing "$pattern" "no present Git-ignored source file matched"
    done
    for ((i = 0; i < ${#selection_rejected_patterns[@]}; i++)); do
        write_record rejected "${selection_rejected_patterns[$i]}" "${selection_rejected_reasons[$i]}"
        rejected=$((rejected + 1))
    done
    for relative_path in "${selection_tracked_manifest_files[@]}"; do
        if is_tracked_configuration_candidate "$relative_path"; then
            detail='tracked application-owned configuration cannot be copied from another worktree; use project-specific manual setup or an explicit repository contract'
        else
            detail='tracked files already arrive through Git and cannot be copied from another worktree; remove this path from .worktreeinclude'
        fi
        write_record rejected "$relative_path" "$detail"
        rejected=$((rejected + 1))
    done

    for relative_path in "${selection_files[@]}"; do
        if get_file_rejection_reason "$relative_path"; then
            write_record rejected "$relative_path" "$rejection_reason"
            rejected=$((rejected + 1))
            continue
        fi

        source_path="$source_root/$relative_path"
        target_path="$target_root/$relative_path"
        if ! path_inside_root "$source_root" "$source_path" || ! path_inside_root "$target_root" "$target_path"; then
            write_record rejected "$relative_path" "resolved path escapes a worktree root"
            rejected=$((rejected + 1))
            continue
        fi
        if find_symlink "$source_root" "$source_path" true; then
            write_record rejected "$relative_path" "source path traverses a symbolic link"
            rejected=$((rejected + 1))
            continue
        fi
        if [[ ! -f "$source_path" ]]; then
            write_record missing "$relative_path" "source file no longer exists or is not a regular file"
            continue
        fi
        if find_symlink "$target_root" "$target_path" false; then
            write_record rejected "$relative_path" "target path traverses a symbolic link"
            rejected=$((rejected + 1))
            continue
        fi
        if [[ -e "$target_path" || -L "$target_path" ]]; then
            write_record conflict "$relative_path" "target already exists; not overwritten"
            conflicts=$((conflicts + 1))
            continue
        fi
        if [[ "$dry_run" == true ]]; then
            write_record would-copy "$relative_path"
            copied=$((copied + 1))
            continue
        fi

        target_directory=${target_path%/*}
        if ! mkdir -p "$target_directory"; then
            write_record rejected "$relative_path" "could not create the target directory"
            rejected=$((rejected + 1))
            continue
        fi
        if find_symlink "$target_root" "$target_path" false; then
            write_record rejected "$relative_path" "target parent became a symbolic link"
            rejected=$((rejected + 1))
            continue
        fi

        # Bash noclobber opens the destination exclusively before cat runs, so a file that
        # appears after the existence check is preserved rather than overwritten.
        if (set -o noclobber; command cat "$source_path" >"$target_path") 2>/dev/null; then
            write_record copied "$relative_path"
            copied=$((copied + 1))
        else
            if [[ -e "$target_path" || -L "$target_path" ]]; then
                write_record conflict "$relative_path" "target already exists; not overwritten"
                conflicts=$((conflicts + 1))
            else
                write_record rejected "$relative_path" "copy failed"
                rejected=$((rejected + 1))
            fi
        fi
    done

    printf 'Summary: copied=%s conflicts=%s missing=%s rejected=%s unlisted=%s\n' \
        "$copied" "$conflicts" "${#selection_missing[@]}" "$rejected" "${#selection_unlisted[@]}"
    [[ "$rejected" -eq 0 ]]
}

show_add_usage() {
    printf '%s\n' 'Usage: git wt-add [--dry-run] [--skip-copy] [--allow-unprovisioned] [--open-code] -- <git worktree add arguments>'
}

show_copy_usage() {
    printf '%s\n' 'Usage: git wt-copy [--dry-run] [--source <existing-worktree-path>]'
}

show_check_usage() {
    printf '%s\n' 'Usage: git wt-check [--source <worktree>] [--target <path>] [--required <repo-relative-path>]...'
}

show_readiness_usage() {
    printf '%s\n' 'Usage: git wt-readiness [--source <worktree>] [--target <path>]'
}

show_provision_usage() {
    printf '%s\n' 'Usage: git wt-provision --operation <copy-ignored-file|copy-external-file|merge-named-section|replace-file> --source-file <path> --target <worktree> --destination <repo-relative-path> [--approve <approval-id>] [--dry-run]'
}

get_provision_mapping() {
    local operation=$1 source_file=$2 target_root=$3 destination=$4
    local source_path source_root source_relative tracked_status ignored_status target_path target_tracked target_ignored identity
    mapping_valid=false
    mapping_reason=""
    mapping_operation=$operation
    mapping_source_path=$source_file
    mapping_source_branch='(external)'
    mapping_source_classification=""
    mapping_source_fingerprint=""
    mapping_target_root=$target_root
    mapping_target_head='(unknown)'
    mapping_target_path=""
    mapping_destination=${destination//\\//}
    mapping_approval_id=""

    case "$operation" in
        copy-ignored-file|copy-external-file) ;;
        merge-named-section|replace-file)
            mapping_reason='the generic helper does not perform section merges or whole-file replacement'
            return 0
            ;;
        *)
            mapping_reason='unsupported mapping operation'
            return 0
            ;;
    esac
    [[ -f "$source_file" ]] || { mapping_reason='source file is not present'; return 0; }
    [[ -d "$target_root" ]] || { mapping_reason='target worktree does not exist'; return 0; }
    [[ ! -L "$source_file" ]] || { mapping_reason='source file is a symbolic link'; return 0; }
    source_path=$(cd "$(dirname "$source_file")" && pwd -P)/$(basename "$source_file") || {
        mapping_reason='could not resolve the source file path'
        return 0
    }
    mapping_source_path=$source_path
    mapping_source_fingerprint=$(file_fingerprint "$source_path") || {
        mapping_reason='could not fingerprint the source file'
        return 0
    }

    source_root=$(repository_root "$(dirname "$source_path")" 2>/dev/null || true)
    if [[ -n "$source_root" ]]; then
        source_root=$(canonical_directory "$source_root") || {
            mapping_reason='could not canonicalize the source repository'
            return 0
        }
    fi
    if [[ -n "$source_root" ]]; then
        mapping_source_branch=$(worktree_branch "$source_root" 2>/dev/null || printf '(detached)')
    else
        mapping_source_branch='(external)'
    fi
    tracked_status=false
    ignored_status=false
    if [[ -n "$source_root" ]] && path_inside_root "${source_root%/}" "$source_path"; then
        source_relative=${source_path#"$source_root"/}
        if git -C "$source_root" ls-files --error-unmatch -- "$source_relative" >/dev/null 2>&1; then tracked_status=true; fi
        if git -C "$source_root" check-ignore --no-index -q -- "$source_relative" >/dev/null 2>&1; then ignored_status=true; fi
    fi
    if [[ "$tracked_status" == true ]]; then
        mapping_source_classification=tracked
        mapping_reason='tracked files, including application configuration, cannot be copied by the generic helper'
        return 0
    elif [[ "$ignored_status" == true ]]; then
        mapping_source_classification=ignored
    else
        mapping_source_classification=external
    fi
    if [[ "$operation" == copy-ignored-file && "$ignored_status" != true ]]; then
        mapping_reason='copy-ignored-file requires a Git-ignored source file'
        return 0
    fi
    if [[ "$operation" == copy-external-file && "$ignored_status" == true && -n "$source_root" ]]; then
        mapping_source_classification=ignored-external
    fi

    valid_repository_relative_contract_path "$destination" || {
        mapping_reason='destination must be a repository-relative path'
        return 0
    }
    mapping_destination=${mapping_destination//\\//}
    target_path="$target_root/$mapping_destination"
    # The destination is already validated as repository-relative. Keep the
    # lexical path so a new nested destination can be created like PowerShell.
    if ! path_inside_root "${target_root%/}" "$target_path"; then
        mapping_reason='destination escapes the target worktree'
        return 0
    fi
    find_symlink "$target_root" "$target_path" false || true
    [[ -z "$found_symlink" ]] || { mapping_reason='destination traverses a symbolic link'; return 0; }
    target_tracked=false
    if git -C "$target_root" ls-files --error-unmatch -- "$mapping_destination" >/dev/null 2>&1; then target_tracked=true; fi
    [[ "$target_tracked" != true ]] || { mapping_reason='tracked target files cannot be overwritten by a generic mapping'; return 0; }
    target_ignored=false
    if git -C "$target_root" check-ignore --no-index -q -- "$mapping_destination" >/dev/null 2>&1; then target_ignored=true; fi
    [[ "$target_ignored" == true ]] || { mapping_reason='destination must be Git-ignored in the target worktree'; return 0; }

    if [[ "$operation" == copy-ignored-file && -n "$source_root" ]]; then
        local source_common target_common
        source_common=$(common_git_directory "$source_root") || { mapping_reason='could not resolve the source repository'; return 0; }
        target_common=$(common_git_directory "$target_root") || { mapping_reason='could not resolve the target repository'; return 0; }
        [[ "$source_common" == "$target_common" ]] || {
            mapping_reason="copy-ignored-file accepts only an ignored source from the target repository's worktree set"
            return 0
        }
    fi

    mapping_target_path=$target_path
    mapping_target_head=$(worktree_head "$target_root") || {
        mapping_reason='could not resolve the target commit'
        return 0
    }
    identity="schema=2|operation=$operation|source=$mapping_source_path|fingerprint=$mapping_source_fingerprint|target=$target_root|target-head=$mapping_target_head|destination=$mapping_destination"
    mapping_approval_id=$(text_fingerprint "$identity") || {
        mapping_reason='could not compute the approval id'
        return 0
    }
    mapping_valid=true
}

write_provision_mapping_report() {
    local approval=${1-}
    printf '%s\n' 'Provisioning mapping: read-only'
    printf 'Operation: %s\n' "$(display_text "$mapping_operation")"
    printf 'Source file: %s\n' "$(display_text "$mapping_source_path")"
    printf 'Source branch: %s\n' "$(display_text "$mapping_source_branch")"
    printf 'Source classification: %s\n' "$(display_text "$mapping_source_classification")"
    [[ -n "$mapping_source_fingerprint" ]] && printf 'Source fingerprint: sha256:%s\n' "$mapping_source_fingerprint"
    printf 'Target worktree: %s\n' "$(display_text "$mapping_target_root")"
    printf 'Target branch: %s\n' "$(display_text "$(worktree_branch "$mapping_target_root")")"
    printf 'Target HEAD: %s\n' "$(display_text "$mapping_target_head")"
    printf 'Destination: %s\n' "$(display_text "$mapping_destination")"
    if [[ "$mapping_valid" != true ]]; then
        write_record mapping-rejected "$mapping_destination" "$mapping_reason"
        printf '%s\n' 'Provisioning state: provisioning-blocked'
        printf '%s\n' 'Runtime state: runtime-unverified'
        printf '%s\n' 'Writes: none'
        return 0
    fi
    printf 'Approval id: %s\n' "$(display_text "$mapping_approval_id")"
    local provisioning_state=provisioning-ready
    if [[ -e "$mapping_target_path" || -L "$mapping_target_path" ]]; then
        write_record conflict "$mapping_destination" 'target already exists; whole-file replacement is refused'
        provisioning_state=provisioning-blocked
    elif [[ -n "$approval" && "$approval" != "$mapping_approval_id" ]]; then
        write_record approval-rejected "$mapping_destination" 'approval id does not match the current source, destination, operation, target HEAD, or fingerprint'
        provisioning_state=provisioning-review-required
    elif [[ -z "$approval" ]]; then
        write_record approval-required "$mapping_destination" 'ask the user to approve this exact mapping before copying'
        provisioning_state=provisioning-review-required
    else
        write_record approved "$mapping_destination" 'exact mapping approval matches'
    fi
    printf 'Provisioning state: %s\n' "$provisioning_state"
    printf '%s\n' 'Runtime state: runtime-unverified'
    printf '%s\n' 'Writes: none'
}

provision_command() {
    local operation="" source_file="" target_argument="" destination="" approval="" dry_run=false argument target_root
    while [[ $# -gt 0 ]]; do
        argument=$1
        shift
        case "$argument" in
            --help|-h) show_provision_usage; return 0 ;;
            --operation) [[ $# -gt 0 ]] || { die '--operation requires a value.'; return 2; }; operation=$1; shift ;;
            --source-file) [[ $# -gt 0 ]] || { die '--source-file requires a path.'; return 2; }; source_file=$1; shift ;;
            --target) [[ $# -gt 0 ]] || { die '--target requires a worktree path.'; return 2; }; target_argument=$1; shift ;;
            --destination) [[ $# -gt 0 ]] || { die '--destination requires a repository-relative path.'; return 2; }; destination=$1; shift ;;
            --approve) [[ $# -gt 0 ]] || { die '--approve requires an approval id.'; return 2; }; approval=$1; shift ;;
            --dry-run) dry_run=true ;;
            *) die "Unknown wt-provision option: $(display_text "$argument")"; return 2 ;;
        esac
    done
    [[ -n "$operation" && -n "$source_file" && -n "$destination" ]] || {
        die '--operation, --source-file, and --destination are required.'
        return 2
    }
    if [[ "$source_file" != /* && ! "$source_file" =~ ^[A-Za-z]:[\\/] ]]; then source_file="$PWD/$source_file"; fi
    if [[ -n "$target_argument" ]]; then
        if [[ "$target_argument" != /* && ! "$target_argument" =~ ^[A-Za-z]:[\\/] ]]; then target_argument="$PWD/$target_argument"; fi
        target_root=$(repository_root "$target_argument") || { die 'Target is not inside a Git worktree.'; return 2; }
    else
        target_root=$(repository_root "$PWD") || { die 'Not inside a Git worktree.'; return 2; }
    fi
    target_root=$(canonical_directory "$target_root") || return 2
    get_provision_mapping "$operation" "$source_file" "$target_root" "$destination"
    write_provision_mapping_report "$approval"
    [[ "$mapping_valid" == true ]] || return 2
    [[ "$dry_run" == true ]] && return 0
    [[ -z "$approval" ]] && return 3
    [[ "$approval" == "$mapping_approval_id" ]] || return 3
    if [[ -e "$mapping_target_path" || -L "$mapping_target_path" ]]; then return 2; fi
    mkdir -p "$(dirname "$mapping_target_path")" || return 2
    find_symlink "$target_root" "$mapping_target_path" false || true
    [[ -z "$found_symlink" ]] || { write_record mapping-rejected "$mapping_destination" 'target path became a symbolic link'; return 2; }
    cp -- "$mapping_source_path" "$mapping_target_path" || {
        write_record mapping-rejected "$mapping_destination" 'copy failed'
        return 2
    }
    write_record copied "$mapping_destination" 'approved exact mapping; target was absent'
    printf '%s\n' 'Runtime state: runtime-unverified'
    return 0
}

open_worktree_in_code() {
    if ! command -v code >/dev/null 2>&1; then
        die "VS Code's 'code' command is not available on PATH."
        return 2
    fi
    code --new-window "$1" || {
        die "VS Code could not open the worktree."
        return 2
    }
}

show_handoff_reminder() {
    local worktree_path=$1

    printf '%s\n' 'Handoff reminder: continuity and uncommitted changes stay in this worktree.'
    printf '%s\n' 'Open this exact path in Claude Code, Codex, or Copilot:'
    printf '  %s\n' "$(display_text "$worktree_path")"
    printf '%s\n' 'Then say: Continue from project continuity.'
    printf '%s\n' 'Use a separate worktree for another unfinished task.'
}

find_primary_worktree() {
    local target_root=$1
    local common worktree_path git_directory
    common=$(common_git_directory "$target_root") || return 1
    load_worktree_paths "$target_root" || return 1
    primary_worktree=""
    for worktree_path in "${worktree_paths[@]}"; do
        [[ -d "$worktree_path" ]] || continue
        git_directory=$(git -C "$worktree_path" rev-parse --absolute-git-dir 2>/dev/null) || continue
        git_directory=$(canonical_directory "$git_directory") || continue
        if [[ "$git_directory" == "$common" ]]; then
            primary_worktree=$worktree_path
            return 0
        fi
    done
    return 1
}

check_command() {
    local source_argument="" target_argument="" source_root target_root="" argument
    local required_paths=()
    while [[ $# -gt 0 ]]; do
        argument=$1
        shift
        case "$argument" in
            --help|-h)
                show_check_usage
                return 0
                ;;
            --source)
                [[ $# -gt 0 ]] || { die '--source requires a path.'; return 2; }
                source_argument=$1
                shift
                ;;
            --target)
                [[ $# -gt 0 ]] || { die '--target requires a path.'; return 2; }
                target_argument=$1
                shift
                ;;
            --required)
                [[ $# -gt 0 ]] || { die '--required requires a repository-relative path.'; return 2; }
                required_paths+=("$1")
                shift
                ;;
            *)
                die "Unknown wt-check option: $(display_text "$argument")"
                return 2
                ;;
        esac
    done

    if [[ -n "$source_argument" ]]; then
        source_root=$(repository_root "$source_argument") || {
            die 'The source is not inside a Git working tree.'
            return 2
        }
    else
        source_root=$(repository_root "$PWD") || {
            die 'Not inside a Git working tree.'
            return 2
        }
    fi
    source_root=$(canonical_directory "$source_root") || return 2

    if [[ -n "$target_argument" ]]; then
        if [[ "$target_argument" == /* || "$target_argument" =~ ^[A-Za-z]:[\\/] ]]; then
            target_root=$target_argument
        else
            target_root="$PWD/$target_argument"
        fi
        if [[ -d "$target_root" ]]; then
            target_root=$(canonical_directory "$target_root") || return 2
            assert_same_repository "$source_root" "$target_root" || return 2
        fi
    fi

    load_selection "$source_root" || return 2
    write_provision_report "$source_root" "$target_root" "${required_paths[@]}"
    case "$report_decision" in
        invalid-manifest|required-local-config-missing) return 2 ;;
        eligible-ignored-files-unlisted) return 3 ;;
        *) return 0 ;;
    esac
}

readiness_command() {
    local source_argument="" target_argument="" source_root target_root="" argument
    while [[ $# -gt 0 ]]; do
        argument=$1
        shift
        case "$argument" in
            --help|-h)
                show_readiness_usage
                return 0
                ;;
            --source)
                [[ $# -gt 0 ]] || { die '--source requires a path.'; return 2; }
                source_argument=$1
                shift
                ;;
            --target)
                [[ $# -gt 0 ]] || { die '--target requires a path.'; return 2; }
                target_argument=$1
                shift
                ;;
            *)
                die "Unknown wt-readiness option: $(display_text "$argument")"
                return 2
                ;;
        esac
    done

    if [[ -n "$source_argument" ]]; then
        source_root=$(repository_root "$source_argument") || {
            die 'The source is not inside a Git working tree.'
            return 2
        }
    else
        source_root=$(repository_root "$PWD") || {
            die 'Not inside a Git working tree.'
            return 2
        }
    fi
    source_root=$(canonical_directory "$source_root") || return 2

    if [[ -n "$target_argument" ]]; then
        if [[ "$target_argument" == /* || "$target_argument" =~ ^[A-Za-z]:[\\/] ]]; then
            target_root=$target_argument
        else
            target_root="$PWD/$target_argument"
        fi
        if [[ -d "$target_root" ]]; then
            target_root=$(canonical_directory "$target_root") || return 2
            assert_same_repository "$source_root" "$target_root" || return 2
        fi
    fi

    load_selection "$source_root" || return 2
    load_configuration_readiness "$source_root" "$target_root" || {
        die 'Git could not inspect tracked configuration references.'
        return 2
    }
    write_readiness_report "$source_root" "$target_root"
}

add_command() {
    local dry_run=false skip_copy=false allow_unprovisioned=false open_code=false separator_found=false
    local argument source_root target_root result
    local before_paths=() after_paths=() wrapper_args=() git_args=() added_paths=()

    for argument in "$@"; do
        [[ "$argument" == --help || "$argument" == -h ]] && {
            show_add_usage
            return 0
        }
        if [[ "$separator_found" == false && "$argument" == -- ]]; then
            separator_found=true
        elif [[ "$separator_found" == false ]]; then
            wrapper_args+=("$argument")
        else
            git_args+=("$argument")
        fi
    done
    if [[ "$separator_found" == false ]]; then
        die "Use -- to separate wrapper options from native 'git worktree add' arguments."
        return 2
    fi
    if [[ ${#git_args[@]} -eq 0 ]]; then
        die "Native 'git worktree add' arguments are required after --."
        return 2
    fi
    for argument in "${wrapper_args[@]}"; do
        case "$argument" in
            --dry-run) dry_run=true ;;
            --skip-copy) skip_copy=true ;;
            --allow-unprovisioned) allow_unprovisioned=true ;;
            --open-code) open_code=true ;;
            *)
                die "Unknown wt-add option: $(display_text "$argument")"
                return 2
                ;;
        esac
    done

    source_root=$(repository_root "$PWD") || {
        die "Not inside a Git working tree."
        return 2
    }
    source_root=$(canonical_directory "$source_root") || return 2

    [[ "$skip_copy" == true ]] && allow_unprovisioned=true
    load_selection "$source_root" || return 2
    write_provision_report "$source_root" ""
    case "$report_decision" in
        invalid-manifest) return 2 ;;
        eligible-ignored-files-unlisted)
            if [[ "$allow_unprovisioned" == false ]]; then
                printf '%s\n' 'Creation blocked: eligible ignored files are not manifest-listed. Use --allow-unprovisioned only after reviewing the report.'
                return 3
            fi
            ;;
    esac

    if [[ "$dry_run" == true ]]; then
        printf '%s\n' "[dry-run] git worktree add arguments accepted; Git will not be executed."
        [[ "$skip_copy" == true ]] && write_record skipped .worktreeinclude "copying disabled by --skip-copy"
        [[ "$open_code" == true ]] && printf '%s\n' '[dry-run] VS Code will not be opened.'
        return 0
    fi

    load_worktree_paths "$source_root" || {
        die "Could not list Git worktrees."
        return 2
    }
    before_paths=("${worktree_paths[@]}")
    git -C "$source_root" worktree add "${git_args[@]}"
    result=$?
    [[ $result -ne 0 ]] && return "$result"

    load_worktree_paths "$source_root" || {
        die "Git created the worktree, but the updated worktree list could not be read."
        return 2
    }
    after_paths=("${worktree_paths[@]}")
    for target_root in "${after_paths[@]}"; do
        array_contains "$target_root" "${before_paths[@]}" || added_paths+=("$target_root")
    done
    if [[ ${#added_paths[@]} -ne 1 ]]; then
        die "Git created the worktree, but the new path could not be identified safely (found ${#added_paths[@]} new entries)."
        return 2
    fi
    target_root=${added_paths[0]}
    printf 'Worktree: %s\n' "$(display_text "$target_root")"

    if [[ "$skip_copy" == true ]]; then
        write_record skipped .worktreeinclude "copying disabled by --skip-copy"
    else
        provision_files "$source_root" "$target_root" || return 2
    fi
    if [[ "$open_code" == true ]]; then
        open_worktree_in_code "$target_root" || return 2
    fi
    show_handoff_reminder "$target_root"
    return 0
}

copy_command() {
    local dry_run=false source_argument="" argument target_root source_root result
    while [[ $# -gt 0 ]]; do
        argument=$1
        shift
        case "$argument" in
            --help|-h)
                show_copy_usage
                return 0
                ;;
            --dry-run) dry_run=true ;;
            --source)
                if [[ $# -eq 0 ]]; then
                    die "--source requires a path."
                    return 2
                fi
                source_argument=$1
                shift
                ;;
            *)
                die "Unknown wt-copy option: $(display_text "$argument")"
                return 2
                ;;
        esac
    done

    target_root=$(repository_root "$PWD") || {
        die "Not inside a Git working tree."
        return 2
    }
    target_root=$(canonical_directory "$target_root") || return 2
    if [[ -n "$source_argument" ]]; then
        source_root=$(repository_root "$source_argument") || {
            die "The explicit source is not inside a Git working tree."
            return 2
        }
        source_root=$(canonical_directory "$source_root") || return 2
    else
        if ! find_primary_worktree "$target_root" || [[ -z "$primary_worktree" ]]; then
            die "The source worktree is ambiguous. Supply --source <existing-worktree-path>."
            return 2
        fi
        source_root=$(canonical_directory "$primary_worktree") || return 2
    fi

    assert_same_repository "$source_root" "$target_root" || return 2
    if [[ "$source_root" == "$target_root" ]]; then
        die "Source and target must be different worktrees."
        return 2
    fi
    printf 'Source worktree: %s\n' "$(display_text "$source_root")"
    printf 'Target worktree: %s\n' "$(display_text "$target_root")"
    provision_files "$source_root" "$target_root" "$dry_run"
    result=$?
    if [[ $result -eq 0 ]]; then
        return 0
    fi
    [[ $result -eq 1 ]] && return 2
    return "$result"
}

main() {
    if [[ $# -eq 0 ]]; then
        printf '%s\n' 'Usage: git-worktree-provision.sh <add|copy|check|readiness|provision> [arguments]'
        return 2
    fi
    local command=$1
    shift
    case "$command" in
        add) add_command "$@" ;;
        copy) copy_command "$@" ;;
        check) check_command "$@" ;;
        readiness) readiness_command "$@" ;;
        provision) provision_command "$@" ;;
        *)
            die "Unknown command: $(display_text "$command")"
            return 2
            ;;
    esac
}

main "$@"
