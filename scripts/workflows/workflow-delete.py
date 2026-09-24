#!/usr/bin/env python3
"""Delete an explicit reusable workflow source bundle and queue chezmoi cleanup."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import subprocess
import sys
import tempfile


SCHEMA_VERSION = 1
NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
ROOT_FILES = {
    ".gitattributes",
    ".chezmoiroot",
    ".worktreeinclude",
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "README.zh-TW.md",
}
GENERATED_ROOTS = {".agents", ".claude", ".codex", ".copilot", "AppData", "Library"}
PRIVATE_NAMES = {"AGENTS.override.md", "CLAUDE.local.md", "settings.local.json"}
REMOVE_FILE = Path("home") / ".chezmoiremove"


class DeleteError(Exception):
    """A reviewed deletion request that cannot safely be completed."""


def git(repo: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise DeleteError(f"git {' '.join(arguments)} failed: {detail}")
    return result.stdout.strip()


def repository_root(raw_repo: str) -> Path:
    candidate = Path(raw_repo).expanduser().resolve()
    try:
        return Path(git(candidate, "rev-parse", "--show-toplevel")).resolve()
    except (DeleteError, OSError) as error:
        raise DeleteError(f"not a Git repository: {candidate}") from error


def relative_path(raw_path: str, repo: Path) -> str:
    if not raw_path or "\\" in raw_path:
        raise DeleteError(f"repository paths must use forward slashes: {raw_path!r}")
    posix = PurePosixPath(raw_path)
    windows = PureWindowsPath(raw_path)
    if posix.is_absolute() or windows.is_absolute() or any(part in {"", ".", ".."} for part in posix.parts):
        raise DeleteError(f"path must be a normalized repository-relative path: {raw_path!r}")
    normalized = posix.as_posix()
    if normalized != raw_path:
        raise DeleteError(f"path must be normalized with forward slashes: {raw_path!r}")
    candidate = repo.joinpath(*posix.parts)
    try:
        candidate.resolve().relative_to(repo.resolve())
    except ValueError as error:
        raise DeleteError(f"path escapes the repository: {raw_path!r}") from error
    return normalized


def validate_canonical_path(path: str) -> None:
    parts = PurePosixPath(path).parts
    if not parts:
        raise DeleteError("definition contains an empty file path")
    if parts[0] in {".git", "archives", ".task-continuity", ".project-continuity"}:
        raise DeleteError(f"deletion path is not canonical source: {path}")
    if parts[0] in GENERATED_ROOTS:
        raise DeleteError(f"generated target is not canonical source: {path}")
    if any(part in {".task-continuity", ".project-continuity"} for part in parts):
        raise DeleteError(f"continuity state is excluded from deletion: {path}")
    if any(part in PRIVATE_NAMES for part in parts):
        raise DeleteError(f"private local configuration is excluded from deletion: {path}")
    if parts[0] not in {"home", "scripts", "docs"} and path not in ROOT_FILES:
        raise DeleteError(f"path is outside the repository's canonical source roots: {path}")


def require_tracked_file(repo: Path, path: str) -> Path:
    validate_canonical_path(path)
    try:
        git(repo, "ls-files", "--error-unmatch", "--", path)
    except DeleteError as error:
        raise DeleteError(f"definition file is not tracked: {path}") from error
    candidate = repo.joinpath(*PurePosixPath(path).parts)
    if candidate.is_symlink() or not candidate.is_file():
        raise DeleteError(f"definition file is not a regular file: {path}")
    return candidate


def require_definition_file(repo: Path, path: str) -> Path:
    validate_canonical_path(path)
    candidate = repo.joinpath(*PurePosixPath(path).parts)
    if candidate.is_symlink() or not candidate.is_file():
        raise DeleteError(f"workflow definition is not a regular file: {path}")
    return candidate


def relative_target_path(raw_path: str) -> str:
    if not raw_path or "\\" in raw_path:
        raise DeleteError(f"target paths must use forward slashes: {raw_path!r}")
    posix = PurePosixPath(raw_path)
    windows = PureWindowsPath(raw_path)
    if posix.is_absolute() or windows.is_absolute() or any(part in {"", ".", ".."} for part in posix.parts):
        raise DeleteError(f"target path must be normalized and home-relative: {raw_path!r}")
    if posix.parts[0] == "~":
        raise DeleteError(f"target path must be relative to the home directory: {raw_path!r}")
    normalized = posix.as_posix()
    if normalized != raw_path:
        raise DeleteError(f"target path must be normalized with forward slashes: {raw_path!r}")
    if posix.parts[0] in {".git", "archives", ".task-continuity", ".project-continuity"}:
        raise DeleteError(f"target path is not removable workflow output: {raw_path}")
    return normalized


def require_string_list(value: object, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise DeleteError(f"{field} must be a list of non-empty strings")
    return value


def load_definition(repo: Path, raw_definition: str) -> tuple[dict[str, object], str, list[str], list[Path]]:
    definition_path = Path(raw_definition)
    if definition_path.is_absolute():
        try:
            definition_path = definition_path.resolve().relative_to(repo.resolve())
        except ValueError as error:
            raise DeleteError("workflow definition must be inside the repository") from error
    definition_rel = relative_path(definition_path.as_posix(), repo)
    definition_file = require_definition_file(repo, definition_rel)
    try:
        data = json.loads(definition_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DeleteError(f"could not read JSON workflow definition: {definition_rel}") from error
    if not isinstance(data, dict) or data.get("schemaVersion") != SCHEMA_VERSION:
        raise DeleteError(f"workflow definition must use schemaVersion {SCHEMA_VERSION}")
    name = data.get("name")
    if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
        raise DeleteError("workflow definition name must be lowercase kebab-case")
    files = data.get("files")
    if not isinstance(files, list) or not files or any(not isinstance(item, str) for item in files):
        raise DeleteError("workflow definition files must be a non-empty list of paths")
    if len(set(files)) != len(files):
        raise DeleteError("workflow definition contains duplicate file paths")
    normalized_files = []
    file_paths = []
    for path in files:
        normalized = relative_path(path, repo)
        normalized_files.append(normalized)
        file_paths.append(require_tracked_file(repo, normalized))
    description = data.get("description", "")
    if not isinstance(description, str):
        raise DeleteError("workflow definition description must be a string")
    dependencies = require_string_list(data.get("dependencies"), "dependencies")
    assumptions = require_string_list(data.get("profileAssumptions"), "profileAssumptions")
    shared_files = []
    for path in require_string_list(data.get("sharedFiles"), "sharedFiles"):
        normalized = relative_path(path, repo)
        shared_files.append(normalized)
        require_tracked_file(repo, normalized)
    if set(shared_files).intersection(normalized_files):
        raise DeleteError("workflow definition cannot classify a file as both owned and shared")
    targets = [relative_target_path(path) for path in require_string_list(data.get("targets"), "targets")]
    if len(set(shared_files)) != len(shared_files):
        raise DeleteError("workflow definition contains duplicate shared file paths")
    if len(set(targets)) != len(targets):
        raise DeleteError("workflow definition contains duplicate target paths")
    metadata = {
        "schemaVersion": SCHEMA_VERSION,
        "name": name,
        "description": description,
        "definition": definition_rel,
        "dependencies": dependencies,
        "profileAssumptions": assumptions,
        "files": normalized_files,
        "sharedFiles": shared_files,
        "targets": targets,
    }
    return metadata, definition_rel, normalized_files, file_paths


def require_clean_tracked_tree(repo: Path) -> None:
    if git(repo, "diff", "--name-only") or git(repo, "diff", "--cached", "--name-only"):
        raise DeleteError("workflow deletion requires a clean tracked working tree")


def existing_remove_entries(repo: Path) -> tuple[Path, list[str], str]:
    remove_file = repo / REMOVE_FILE
    if not remove_file.exists():
        return remove_file, [], ""
    if remove_file.is_symlink() or not remove_file.is_file():
        raise DeleteError(f"{REMOVE_FILE.as_posix()} must be a regular file")
    content = remove_file.read_text(encoding="utf-8")
    entries = [line.strip() for line in content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    return remove_file, entries, content


def append_remove_entries(repo: Path, targets: list[str]) -> list[str]:
    remove_file, existing, content = existing_remove_entries(repo)
    additions = [target for target in targets if target not in existing]
    if not additions:
        return []
    updated = content
    if updated and not updated.endswith("\n"):
        updated += "\n"
    updated += "\n".join(additions) + "\n"
    remove_file.parent.mkdir(parents=True, exist_ok=True)
    temporary_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", prefix=".chezmoiremove-", dir=remove_file.parent, delete=False
        ) as temporary:
            temporary_name = temporary.name
            temporary.write(updated)
        os.replace(temporary_name, remove_file)
    except Exception:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)
        raise
    return additions


def delete_workflow(repo: Path, definition: str, apply: bool, delete_definition: bool) -> int:
    require_clean_tracked_tree(repo)
    metadata, definition_rel, files, source_files = load_definition(repo, definition)
    shared_files = metadata["sharedFiles"]
    targets = metadata["targets"]
    assert isinstance(shared_files, list)
    assert isinstance(targets, list)

    delete_files = list(files)
    catalog_is_tracked = False
    try:
        git(repo, "ls-files", "--error-unmatch", "--", definition_rel)
        catalog_is_tracked = True
    except DeleteError:
        pass
    if delete_definition and definition_rel not in delete_files:
        if not catalog_is_tracked:
            raise DeleteError(f"cannot delete untracked catalog definition without reviewing it: {definition_rel}")
        delete_files.append(definition_rel)

    print(f"workflow: {metadata['name']}")
    print("owned canonical sources:")
    for path in delete_files:
        print(f"  {'delete' if apply else 'would delete'}: {path}")
    if shared_files:
        print("shared canonical dependencies (kept):")
        for path in shared_files:
            print(f"  keep: {path}")
    else:
        print("shared canonical dependencies: none declared")
    if catalog_is_tracked and definition_rel not in delete_files:
        print(f"catalog definition (kept): {definition_rel}")
    elif not catalog_is_tracked:
        print(f"catalog definition (untracked; kept): {definition_rel}")
    if targets:
        print("generated targets:")
        for target in targets:
            print(f"  {'queued for removal' if apply else 'would queue for removal'}: {target}")
        print(f"  via: {REMOVE_FILE.as_posix()}")
    else:
        print("generated targets: none declared; no live target cleanup will be scheduled")
    print("no archive or restore copy is created by this operation")
    print("continuity state (kept): .task-continuity/ (unmigrated .project-continuity/ also excluded)")
    if not apply:
        print(f"dry-run: {len(delete_files)} source file(s) would be deleted")
        return 0

    additions = append_remove_entries(repo, targets)
    for source_file in source_files:
        source_file.unlink()
    if delete_definition and definition_rel not in files:
        (repo / Path(*PurePosixPath(definition_rel).parts)).unlink()
    print(f"delete complete: {len(delete_files)} source file(s) deleted")
    if additions:
        print(f"queued {len(additions)} target path(s) in {REMOVE_FILE.as_posix()}")
    print("next: review git diff; run chezmoi diff, then apply separately when approved")
    return 0


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description="Delete explicit workflow source bundles and queue chezmoi cleanup.")
    command.add_argument("--repo", default=".")
    command.add_argument("--definition", required=True)
    command.add_argument("--apply", action="store_true", help="delete confirmed source files and queue target cleanup")
    command.add_argument("--delete-definition", action="store_true", help="also delete the reviewed catalog definition")
    return command


def main() -> int:
    arguments = parser().parse_args()
    try:
        repo = repository_root(arguments.repo)
        return delete_workflow(repo, arguments.definition, arguments.apply, arguments.delete_definition)
    except (DeleteError, OSError) as error:
        print(f"workflow delete: ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
