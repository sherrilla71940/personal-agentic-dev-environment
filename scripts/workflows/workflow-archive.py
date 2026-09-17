#!/usr/bin/env python3
"""Archive, restore, and delete explicit reusable workflow source bundles."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import subprocess
import sys
import tempfile


SCHEMA_VERSION = 1
ARCHIVE_ROOT = Path("archives") / "workflows"
NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
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


class ArchiveError(Exception):
    pass


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
        raise ArchiveError(f"git {' '.join(arguments)} failed: {detail}")
    return result.stdout.strip()


def repository_root(raw_repo: str) -> Path:
    candidate = Path(raw_repo).expanduser().resolve()
    try:
        return Path(git(candidate, "rev-parse", "--show-toplevel")).resolve()
    except (ArchiveError, OSError) as error:
        raise ArchiveError(f"not a Git repository: {candidate}") from error


def relative_path(raw_path: str, repo: Path) -> str:
    if not raw_path or "\\" in raw_path:
        raise ArchiveError(f"repository paths must use forward slashes: {raw_path!r}")
    posix = PurePosixPath(raw_path)
    windows = PureWindowsPath(raw_path)
    if posix.is_absolute() or windows.is_absolute() or any(part in {"", ".", ".."} for part in posix.parts):
        raise ArchiveError(f"path must be a normalized repository-relative path: {raw_path!r}")
    normalized = posix.as_posix()
    if normalized != raw_path:
        raise ArchiveError(f"path must be normalized with forward slashes: {raw_path!r}")
    candidate = repo.joinpath(*posix.parts)
    resolved_repo = repo.resolve()
    try:
        candidate.resolve().relative_to(resolved_repo)
    except ValueError as error:
        raise ArchiveError(f"path escapes the repository: {raw_path!r}") from error
    return normalized


def validate_canonical_path(path: str) -> None:
    parts = PurePosixPath(path).parts
    if not parts:
        raise ArchiveError("manifest contains an empty file path")
    if parts[0] in {".git", "archives", ".project-continuity"}:
        raise ArchiveError(f"archive path is not canonical source: {path}")
    if parts[0] in GENERATED_ROOTS:
        raise ArchiveError(f"generated target is not canonical source: {path}")
    if any(part == ".project-continuity" for part in parts):
        raise ArchiveError(f"continuity state is excluded from archives: {path}")
    if any(part in PRIVATE_NAMES for part in parts):
        raise ArchiveError(f"private local configuration is excluded from archives: {path}")
    if parts[0] not in {"home", "scripts", "docs"} and path not in ROOT_FILES:
        raise ArchiveError(f"path is outside the repository's canonical source roots: {path}")


def require_tracked_file(repo: Path, path: str) -> Path:
    validate_canonical_path(path)
    try:
        git(repo, "ls-files", "--error-unmatch", "--", path)
    except ArchiveError as error:
        raise ArchiveError(f"manifest file is not tracked: {path}") from error
    candidate = repo.joinpath(*PurePosixPath(path).parts)
    if candidate.is_symlink() or not candidate.is_file():
        raise ArchiveError(f"manifest file is not a regular file: {path}")
    return candidate


def require_definition_file(repo: Path, path: str) -> Path:
    """Read a catalog definition without requiring the catalog entry to be committed."""
    validate_canonical_path(path)
    candidate = repo.joinpath(*PurePosixPath(path).parts)
    if candidate.is_symlink() or not candidate.is_file():
        raise ArchiveError(f"workflow definition is not a regular file: {path}")
    return candidate


def relative_target_path(raw_path: str) -> str:
    if not raw_path or "\\" in raw_path:
        raise ArchiveError(f"target paths must use forward slashes: {raw_path!r}")
    posix = PurePosixPath(raw_path)
    windows = PureWindowsPath(raw_path)
    if posix.is_absolute() or windows.is_absolute() or any(part in {"", ".", ".."} for part in posix.parts):
        raise ArchiveError(f"target path must be normalized and home-relative: {raw_path!r}")
    if posix.parts[0] == "~":
        raise ArchiveError(f"target path must be relative to the home directory: {raw_path!r}")
    normalized = posix.as_posix()
    if normalized != raw_path:
        raise ArchiveError(f"target path must be normalized with forward slashes: {raw_path!r}")
    if posix.parts[0] in {".git", "archives", ".project-continuity"}:
        raise ArchiveError(f"target path is not removable workflow output: {raw_path}")
    return normalized


def require_string_list(value: object, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise ArchiveError(f"{field} must be a list of non-empty strings")
    return value


def load_definition(repo: Path, raw_definition: str) -> tuple[dict[str, object], str, list[str], list[Path]]:
    definition_path = Path(raw_definition)
    if definition_path.is_absolute():
        try:
            definition_path = definition_path.resolve().relative_to(repo.resolve())
        except ValueError as error:
            raise ArchiveError("workflow definition must be inside the repository") from error
    definition_rel = relative_path(definition_path.as_posix(), repo)
    definition_file = require_definition_file(repo, definition_rel)
    try:
        data = json.loads(definition_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ArchiveError(f"could not read JSON workflow definition: {definition_rel}") from error
    if not isinstance(data, dict) or data.get("schemaVersion") != SCHEMA_VERSION:
        raise ArchiveError(f"workflow definition must use schemaVersion {SCHEMA_VERSION}")
    name = data.get("name")
    if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
        raise ArchiveError("workflow definition name must be lowercase kebab-case")
    files = data.get("files")
    if not isinstance(files, list) or not files or any(not isinstance(item, str) for item in files):
        raise ArchiveError("workflow definition files must be a non-empty list of paths")
    if len(set(files)) != len(files):
        raise ArchiveError("workflow definition contains duplicate file paths")
    normalized_files = []
    file_paths = []
    for path in files:
        normalized = relative_path(path, repo)
        normalized_files.append(normalized)
        file_paths.append(require_tracked_file(repo, normalized))
    description = data.get("description", "")
    if not isinstance(description, str):
        raise ArchiveError("workflow definition description must be a string")
    dependencies = require_string_list(data.get("dependencies"), "dependencies")
    assumptions = require_string_list(data.get("profileAssumptions"), "profileAssumptions")
    shared_files = []
    for path in require_string_list(data.get("sharedFiles"), "sharedFiles"):
        normalized = relative_path(path, repo)
        shared_files.append(normalized)
        require_tracked_file(repo, normalized)
    if set(shared_files).intersection(normalized_files):
        raise ArchiveError("workflow definition cannot classify a file as both owned and shared")
    targets = [relative_target_path(path) for path in require_string_list(data.get("targets"), "targets")]
    if len(set(shared_files)) != len(shared_files):
        raise ArchiveError("workflow definition contains duplicate shared file paths")
    if len(set(targets)) != len(targets):
        raise ArchiveError("workflow definition contains duplicate target paths")
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
    return metadata, definition_rel, metadata["files"], file_paths


def require_clean_tracked_tree(repo: Path, operation: str = "workflow archive") -> None:
    if git(repo, "diff", "--name-only") or git(repo, "diff", "--cached", "--name-only"):
        raise ArchiveError(f"{operation} requires a clean tracked working tree")


def write_json(path: Path, data: dict[str, object]) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def archive_workflow(
    repo: Path,
    definition: str,
    archive_id: str,
    reason: str,
    apply: bool,
    delete_definition: bool,
) -> int:
    if not NAME_PATTERN.fullmatch(archive_id):
        raise ArchiveError("archive id must be lowercase kebab-case")
    require_clean_tracked_tree(repo, "workflow archive")
    metadata, definition_rel, files, source_files = load_definition(repo, definition)
    name = metadata["name"]
    assert isinstance(name, str)
    archive_root = repo / ARCHIVE_ROOT
    current = archive_root
    while current != repo and current != current.parent:
        if current.is_symlink():
            raise ArchiveError("archive path must not contain symlinks")
        current = current.parent
    archive_root = archive_root.resolve()
    destination = archive_root / name / archive_id
    if destination.exists() or destination.is_symlink():
        raise ArchiveError(f"archive already exists: {destination.relative_to(repo).as_posix()}")
    source_commit = git(repo, "rev-parse", "HEAD")
    if not COMMIT_PATTERN.fullmatch(source_commit):
        raise ArchiveError(f"unexpected source commit: {source_commit}")
    shared_files = metadata["sharedFiles"]
    targets = metadata["targets"]
    assert isinstance(shared_files, list)
    assert isinstance(targets, list)
    catalog_is_tracked = False
    try:
        git(repo, "ls-files", "--error-unmatch", "--", definition_rel)
        catalog_is_tracked = True
    except ArchiveError:
        pass

    delete_files = list(files)
    delete_source_files = list(source_files)
    if delete_definition and definition_rel not in delete_files:
        if not catalog_is_tracked:
            raise ArchiveError(
                f"cannot delete untracked catalog definition without first reviewing it: {definition_rel}"
            )
        files.append(definition_rel)
        delete_files.append(definition_rel)
        delete_source_files.append(repo / Path(*PurePosixPath(definition_rel).parts))

    archive_manifest = dict(metadata)
    archive_manifest["files"] = list(files)
    archive_manifest["id"] = archive_id
    archive_manifest["sourceCommit"] = source_commit
    if reason:
        archive_manifest["reason"] = reason

    print(f"workflow: {name}")
    print(f"archive: {destination.relative_to(repo).as_posix()}")
    print(f"source commit: {source_commit}")
    print("archive and active-source operation:")
    for path in files:
        print(f"  {('archive and delete' if apply else 'would archive and delete')}: {path}")
    if delete_definition:
        print(f"  {('delete' if apply else 'would delete')} catalog definition: {definition_rel}")
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
            print(f"  {('queued for removal' if apply else 'would queue for removal')}: {target}")
        print(f"  via: {REMOVE_FILE.as_posix()}")
    else:
        print("generated targets: none declared; no live target cleanup will be scheduled")
    print("archives: created by this operation" if apply else "archives: would be created by this operation")
    print("continuity state (kept): .project-continuity/")
    if not apply:
        print(f"dry-run: archive would contain {len(files)} file(s); {len(delete_files)} source file(s) would be deleted")
        return 0

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{archive_id}-", dir=destination.parent))
    try:
        for source_file, relative in zip(delete_source_files, files):
            target = temporary / "source" / Path(*PurePosixPath(relative).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_file, target)
        write_json(temporary / "manifest.json", archive_manifest)
        os.replace(temporary, destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    try:
        additions = append_remove_entries(repo, targets)
        for source_file in delete_source_files:
            source_file.unlink()
    except Exception:
        raise ArchiveError(
            f"archive created at {destination.relative_to(repo).as_posix()}, but active-source deletion failed; "
            "review the archive and working tree before retrying"
        )

    print(f"archive created: {destination.relative_to(repo).as_posix()}")
    print(f"source files deleted: {len(delete_files)}")
    if additions:
        print(f"queued {len(additions)} target path(s) in {REMOVE_FILE.as_posix()}")
    print("next: review git diff; run chezmoi diff, then apply separately when approved")
    return 0


def archive_directory(repo: Path, raw_archive: str) -> Path:
    archive_root_unresolved = repo / ARCHIVE_ROOT
    if archive_root_unresolved.is_symlink():
        raise ArchiveError(f"archive root must not be a symlink: {ARCHIVE_ROOT.as_posix()}")
    archive_root = archive_root_unresolved.resolve()
    supplied = Path(raw_archive)
    if not supplied.is_absolute():
        supplied = repo / supplied
    current = supplied
    while current != repo and current != current.parent:
        if current.is_symlink():
            raise ArchiveError("archive path must not contain symlinks")
        current = current.parent
    archive = supplied.resolve()
    try:
        archive.relative_to(archive_root)
    except ValueError as error:
        raise ArchiveError(f"archive must be under {ARCHIVE_ROOT.as_posix()}/") from error
    if not archive.is_dir() or archive.is_symlink():
        raise ArchiveError(f"archive directory not found: {raw_archive}")
    return archive


def load_archive(repo: Path, raw_archive: str) -> tuple[Path, dict[str, object], list[str]]:
    archive = archive_directory(repo, raw_archive)
    manifest_file = archive / "manifest.json"
    if manifest_file.is_symlink() or not manifest_file.is_file():
        raise ArchiveError("archive is missing a regular manifest.json")
    try:
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ArchiveError("archive manifest is not valid JSON") from error
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise ArchiveError(f"archive manifest must use schemaVersion {SCHEMA_VERSION}")
    name = manifest.get("name")
    archive_id = manifest.get("id")
    if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
        raise ArchiveError("archive manifest name must be lowercase kebab-case")
    if not isinstance(archive_id, str) or not NAME_PATTERN.fullmatch(archive_id):
        raise ArchiveError("archive manifest id must be lowercase kebab-case")
    if archive.parent.name != name or archive.name != archive_id:
        raise ArchiveError("archive path does not match manifest name and id")
    description = manifest.get("description", "")
    if not isinstance(description, str):
        raise ArchiveError("archive manifest description must be a string")
    definition = manifest.get("definition", "")
    if not isinstance(definition, str):
        raise ArchiveError("archive manifest definition must be a string")
    if definition:
        definition = relative_path(definition, repo)
        validate_canonical_path(definition)
    reason = manifest.get("reason", "")
    if not isinstance(reason, str):
        raise ArchiveError("archive manifest reason must be a string")
    source_commit = manifest.get("sourceCommit")
    if not isinstance(source_commit, str) or not COMMIT_PATTERN.fullmatch(source_commit):
        raise ArchiveError("archive manifest sourceCommit must be a full Git commit id")
    files = manifest.get("files")
    if not isinstance(files, list) or not files or any(not isinstance(item, str) for item in files):
        raise ArchiveError("archive manifest files must be a non-empty list of paths")
    normalized_files = [relative_path(item, repo) for item in files]
    if len(set(normalized_files)) != len(normalized_files):
        raise ArchiveError("archive manifest contains duplicate file paths")
    for path in normalized_files:
        validate_canonical_path(path)
        source_file = archive / "source" / Path(*PurePosixPath(path).parts)
        if source_file.is_symlink() or not source_file.is_file():
            raise ArchiveError(f"archive source file is missing or not regular: {path}")
        try:
            source_file.resolve().relative_to(archive.resolve())
        except ValueError as error:
            raise ArchiveError(f"archive source escapes the archive: {path}") from error
    allowed_entries = {"manifest.json", "source"}
    for entry in archive.iterdir():
        if entry.is_symlink() or entry.name not in allowed_entries:
            raise ArchiveError("archive contains an unexpected or symlinked top-level entry")
    source_root = archive / "source"
    if source_root.is_symlink():
        raise ArchiveError("archive source directory must not be a symlink")
    actual_files = set()
    if source_root.exists():
        for root, directories, filenames in os.walk(source_root, followlinks=False):
            for directory in directories:
                if (Path(root) / directory).is_symlink():
                    raise ArchiveError("archive source contains a symlinked directory")
            for filename in filenames:
                file_path = Path(root) / filename
                if file_path.is_symlink():
                    raise ArchiveError("archive source contains a symlink")
                actual_files.add(file_path.relative_to(source_root).as_posix())
    if actual_files != set(normalized_files):
        missing = sorted(set(normalized_files) - actual_files)
        extra = sorted(actual_files - set(normalized_files))
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if extra:
            details.append(f"extra: {', '.join(extra)}")
        raise ArchiveError("archive source does not match manifest (" + "; ".join(details) + ")")
    require_string_list(manifest.get("dependencies"), "dependencies")
    require_string_list(manifest.get("profileAssumptions"), "profileAssumptions")
    shared_files = [relative_path(path, repo) for path in require_string_list(manifest.get("sharedFiles"), "sharedFiles")]
    for path in shared_files:
        validate_canonical_path(path)
    if len(set(shared_files)) != len(shared_files) or set(shared_files).intersection(normalized_files):
        raise ArchiveError("archive manifest has invalid shared file inventory")
    targets = [relative_target_path(path) for path in require_string_list(manifest.get("targets"), "targets")]
    if len(set(targets)) != len(targets):
        raise ArchiveError("archive manifest contains duplicate target paths")
    return archive, manifest, normalized_files


def restore_workflow(repo: Path, raw_archive: str, apply: bool) -> int:
    archive, manifest, files = load_archive(repo, raw_archive)
    print(f"workflow: {manifest['name']}")
    print(f"archive: {archive.relative_to(repo).as_posix()}")
    print(f"source commit: {manifest['sourceCommit']}")
    dependencies = manifest.get("dependencies", [])
    if dependencies:
        print("dependencies: " + ", ".join(dependencies))
    profile_assumptions = manifest.get("profileAssumptions", [])
    if profile_assumptions:
        print("profile assumptions: " + "; ".join(profile_assumptions))
    missing_targets = []
    already_present = []
    collisions = []
    for path in files:
        target = repo / Path(*PurePosixPath(path).parts)
        if os.path.lexists(target):
            if target.is_symlink() or not target.is_file():
                collisions.append(path)
                continue
            archived = archive / "source" / Path(*PurePosixPath(path).parts)
            if target.read_bytes() == archived.read_bytes():
                already_present.append(path)
            else:
                collisions.append(path)
        else:
            try:
                target.parent.resolve().relative_to(repo.resolve())
            except ValueError as error:
                raise ArchiveError(f"restore target escapes repository: {path}") from error
            missing_targets.append(path)
    if collisions:
        raise ArchiveError("restore refused because existing files differ or are not regular: " + ", ".join(collisions))
    for path in already_present:
        print(f"already present: {path}")
    for path in missing_targets:
        print(("restore: " if apply else "would restore: ") + path)
    if not apply:
        print(f"dry-run: {len(missing_targets)} file(s) would be restored")
        return 0
    if not missing_targets:
        print("restore complete: no files changed")
        return 0
    with tempfile.TemporaryDirectory(prefix=".workflow-restore-", dir=repo) as temporary_name:
        temporary = Path(temporary_name)
        for path in missing_targets:
            source = archive / "source" / Path(*PurePosixPath(path).parts)
            staged = temporary / Path(*PurePosixPath(path).parts)
            staged.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, staged)
        for path in missing_targets:
            target = repo / Path(*PurePosixPath(path).parts)
            if os.path.lexists(target):
                raise ArchiveError(f"restore target appeared during validation: {path}")
            target.parent.mkdir(parents=True, exist_ok=True)
            staged = temporary / Path(*PurePosixPath(path).parts)
            with staged.open("rb") as source, target.open("xb") as destination:
                shutil.copyfileobj(source, destination)
    print(f"restore complete: {len(missing_targets)} file(s) written")
    print("next: review git diff and run the repository validation before chezmoi apply")
    return 0


def existing_remove_entries(repo: Path) -> tuple[Path, list[str], str]:
    remove_file = repo / REMOVE_FILE
    if not remove_file.exists():
        return remove_file, [], ""
    if remove_file.is_symlink() or not remove_file.is_file():
        raise ArchiveError(f"{REMOVE_FILE.as_posix()} must be a regular file")
    content = remove_file.read_text(encoding="utf-8")
    entries = [
        line.strip()
        for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
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
            mode="w",
            encoding="utf-8",
            newline="\n",
            prefix=".chezmoiremove-",
            dir=remove_file.parent,
            delete=False,
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
    require_clean_tracked_tree(repo, "workflow deletion")
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
    except ArchiveError:
        pass
    if delete_definition and definition_rel not in delete_files:
        if not catalog_is_tracked:
            raise ArchiveError(
                f"cannot delete untracked catalog definition without first reviewing it: {definition_rel}"
            )
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
    archive_path = (ARCHIVE_ROOT / str(metadata["name"])).as_posix()
    print("no archive created by this operation")
    print(f"existing archives (unchanged): {archive_path}/")
    print("continuity state (kept): .project-continuity/")
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


def delete_archive(repo: Path, raw_archive: str, apply: bool) -> int:
    archive, manifest, files = load_archive(repo, raw_archive)
    relative = archive.relative_to(repo).as_posix()
    print(f"archive: {relative}")
    print(f"workflow: {manifest['name']}")
    print(f"source files preserved elsewhere: {len(files)}")
    print("canonical source files: unchanged")
    if not apply:
        print("dry-run: archive directory would be deleted")
        return 0
    if not archive.exists() or archive.is_symlink() or not archive.is_dir():
        raise ArchiveError("archive changed or disappeared before deletion")
    shutil.rmtree(archive)
    print(f"archive deleted: {relative}")
    return 0


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description="Archive, restore, and delete explicit workflow source bundles.")
    subcommands = command.add_subparsers(dest="command", required=True)

    archive = subcommands.add_parser("archive", help="archive a workflow and delete its active sources")
    archive.add_argument("--repo", default=".")
    archive.add_argument("--definition", required=True)
    archive.add_argument("--id", required=True)
    archive.add_argument("--reason", default="")
    archive.add_argument("--apply", action="store_true", help="create the archive, delete confirmed sources, and queue target cleanup")
    archive.add_argument(
        "--delete-definition",
        action="store_true",
        help="also delete the tracked catalog definition after review",
    )

    delete = subcommands.add_parser("delete", help="dry-run or delete workflow source files without archiving")
    delete.add_argument("--repo", default=".")
    delete.add_argument("--definition", required=True)
    delete.add_argument("--apply", action="store_true", help="delete confirmed source files and queue target cleanup")
    delete.add_argument(
        "--delete-definition",
        action="store_true",
        help="also delete the tracked catalog definition after review",
    )

    restore = subcommands.add_parser("restore", help="validate and restore an archive")
    restore.add_argument("archive")
    restore.add_argument("--repo", default=".")
    restore.add_argument("--apply", action="store_true", help="write missing canonical source files")

    delete = subcommands.add_parser("delete-archive", help="dry-run or delete one workflow archive")
    delete.add_argument("archive")
    delete.add_argument("--repo", default=".")
    delete.add_argument("--apply", action="store_true", help="delete the validated archive directory")
    return command


def main() -> int:
    arguments = parser().parse_args()
    try:
        repo = repository_root(arguments.repo)
        if arguments.command == "archive":
            return archive_workflow(
                repo,
                arguments.definition,
                arguments.id,
                arguments.reason,
                arguments.apply,
                arguments.delete_definition,
            )
        if arguments.command == "restore":
            return restore_workflow(repo, arguments.archive, arguments.apply)
        if arguments.command == "delete":
            return delete_workflow(repo, arguments.definition, arguments.apply, arguments.delete_definition)
        return delete_archive(repo, arguments.archive, arguments.apply)
    except (ArchiveError, OSError) as error:
        print(f"workflow archive: ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
