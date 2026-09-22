#!/usr/bin/env python3
"""Run one descriptor-defined development server with a worktree-specific port."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterator, Sequence
from urllib.parse import urlparse


DESCRIPTOR_NAME = ".worktree-runtime.json"
PORT_TOKEN = "{port}"
MAX_PORT_RETRIES = 10
CACHE_ENV = "WORKTREE_RUNTIME_CACHE"


class RuntimeError_(RuntimeError):
    """A safe, user-facing runtime configuration or launch error."""


def fail(message: str) -> None:
    raise RuntimeError_(message)


def git_root() -> Path:
    try:
        output = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"could not identify the current Git worktree: {exc}")
    return Path(output.strip()).resolve()


def path_inside(root: Path, candidate: Path, label: str) -> Path:
    try:
        candidate.relative_to(root)
        return candidate
    except ValueError:
        # Git and Win32 can spell the same directory with a short 8.3 component
        # or its long name. Compare existing ancestors by file identity before
        # rejecting an otherwise safe path.
        if root.exists() and candidate.exists():
            current = candidate
            while True:
                try:
                    if os.path.samefile(root, current):
                        return candidate
                except OSError:
                    pass
                if current.parent == current:
                    break
                current = current.parent
        fail(f"{label} must stay inside the worktree: {candidate}")


def descriptor_path(root: Path, value: str | None) -> Path:
    path = (root / DESCRIPTOR_NAME) if value is None else Path(value)
    if not path.is_absolute():
        path = root / path
    path = path.resolve()
    path_inside(root, path, "runtime descriptor")
    if not path.is_file():
        fail(
            f"runtime isolation is unconfigured: {path} was not found; "
            "use a manually selected port, because concurrent testing is not guaranteed"
        )
    return path


def require_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"runtime descriptor field {key!r} must be a non-empty string")
    return value


def validate_descriptor(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"could not read runtime descriptor {path}: {exc}")
    if not isinstance(data, dict):
        fail("runtime descriptor must contain a JSON object")

    allowed = {
        "schemaVersion",
        "name",
        "startCommand",
        "portRange",
        "portEnvironmentVariable",
        "healthUrl",
        "healthTimeoutSeconds",
        "workingDirectory",
        "resources",
    }
    unknown = sorted(set(data) - allowed)
    if unknown:
        fail(f"runtime descriptor has unsupported fields: {', '.join(unknown)}")
    if data.get("schemaVersion") != 1:
        fail("runtime descriptor schemaVersion must be 1")

    command = data.get("startCommand")
    if (
        not isinstance(command, list)
        or not command
        or any(not isinstance(item, str) or not item for item in command)
    ):
        fail("runtime descriptor startCommand must be a non-empty JSON string array")

    port_range = data.get("portRange")
    if (
        not isinstance(port_range, list)
        or len(port_range) != 2
        or any(isinstance(item, bool) or not isinstance(item, int) for item in port_range)
    ):
        fail("runtime descriptor portRange must contain two integer ports")
    low, high = port_range
    if not 1024 <= low <= high <= 65535:
        fail("runtime descriptor portRange must be between 1024 and 65535")

    port_env = data.get("portEnvironmentVariable")
    if port_env is not None and (
        not isinstance(port_env, str) or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", port_env) is None
    ):
        fail("runtime descriptor portEnvironmentVariable must be a valid environment name")
    if port_env is None and not any(PORT_TOKEN in item for item in command):
        fail("startCommand must contain {port} or define portEnvironmentVariable")

    health_url = require_string(data, "healthUrl")
    if PORT_TOKEN not in health_url:
        fail("runtime descriptor healthUrl must contain {port}")
    parsed = urlparse(health_url.replace(PORT_TOKEN, "40000"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        fail("runtime descriptor healthUrl must be an http(s) URL with a host")
    if parsed.username or parsed.password:
        fail("runtime descriptor healthUrl must not contain credentials")

    timeout = data.get("healthTimeoutSeconds", 30)
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 1 <= timeout <= 300:
        fail("runtime descriptor healthTimeoutSeconds must be between 1 and 300")

    working_directory = data.get("workingDirectory", ".")
    if not isinstance(working_directory, str) or not working_directory.strip():
        fail("runtime descriptor workingDirectory must be a relative path")
    workdir = (path.parent / working_directory).resolve()
    if Path(working_directory).is_absolute():
        fail("runtime descriptor workingDirectory must be relative")
    path_inside(path.parent, workdir, "runtime workingDirectory")
    if not workdir.is_dir():
        fail(f"runtime workingDirectory does not exist: {workdir}")

    resources = data.get("resources", [])
    if not isinstance(resources, list):
        fail("runtime descriptor resources must be a JSON array")
    for resource in resources:
        if not isinstance(resource, dict):
            fail("each runtime resource must be a JSON object")
        unknown_resource = sorted(set(resource) - {"name", "isolation", "note"})
        if unknown_resource:
            fail(f"runtime resource has unsupported fields: {', '.join(unknown_resource)}")
        if not isinstance(resource.get("name"), str) or not resource["name"].strip():
            fail("each runtime resource needs a non-empty name")
        if resource.get("isolation") not in {"per-worktree", "shared-safe", "unsupported"}:
            fail(
                "each runtime resource isolation must be per-worktree, shared-safe, or unsupported"
            )

    result = dict(data)
    result["workdir"] = workdir
    result["portRange"] = (low, high)
    result["healthTimeoutSeconds"] = float(timeout)
    return result


def cache_root() -> Path:
    explicit = os.environ.get(CACHE_ENV)
    if explicit:
        return Path(explicit).expanduser().resolve()
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA")
        return (Path(base) if base else Path.home() / "AppData" / "Local") / "worktree-runtime"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Caches" / "worktree-runtime"
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "worktree-runtime"


def worktree_key(root: Path) -> str:
    identity = os.path.normcase(str(root.resolve())).encode("utf-8")
    return hashlib.sha256(identity).hexdigest()[:32]


def state_path(root: Path) -> Path:
    return cache_root() / "assignments" / f"{worktree_key(root)}.json"


def lease_path(port: int) -> Path:
    return cache_root() / "leases" / f"{port}.lock"


def read_state(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return data if isinstance(data, dict) else None


def write_state(path: Path, root: Path, descriptor: Path, port: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "worktree": str(root),
        "descriptor": str(descriptor),
        "descriptorSha256": hashlib.sha256(descriptor.read_bytes()).hexdigest(),
        "port": port,
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=".runtime-", delete=False
    ) as temporary:
        json.dump(payload, temporary, indent=2)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


class PortLease:
    """Hold an inter-process lease for one port until the runtime exits."""

    def __init__(self, port: int):
        self.port = port
        self.path = lease_path(port)
        self.handle: Any = None

    def acquire(self) -> bool:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("a+b")
        if self.path.stat().st_size == 0:
            self.handle.write(b"0")
            self.handle.flush()
        self.handle.seek(0)
        try:
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, IOError):
            self.handle.close()
            self.handle = None
            return False
        return True

    def release(self) -> None:
        if self.handle is None:
            return
        try:
            if os.name == "nt":
                import msvcrt

                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
        finally:
            self.handle.close()
            self.handle = None

    def __enter__(self) -> "PortLease":
        if not self.acquire():
            fail(f"port {self.port} is already leased by another worktree runtime")
        return self

    def __exit__(self, *_: Any) -> None:
        self.release()


def can_bind(port: int, host: str) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind((host, port))
        except OSError:
            return False
    return True


def candidate_ports(root: Path, config: dict[str, Any], explicit: int | None) -> Iterator[int]:
    low, high = config["portRange"]
    if explicit is not None:
        if not low <= explicit <= high:
            fail(f"requested port {explicit} is outside the configured range {low}-{high}")
        yield explicit
        return

    saved = read_state(state_path(root))
    if (
        saved
        and isinstance(saved.get("port"), int)
        and not isinstance(saved.get("port"), bool)
        and low <= saved["port"] <= high
    ):
        yield saved["port"]

    span = high - low + 1
    start = low + (int(worktree_key(root), 16) % span)
    yielded: set[int] = set()
    if saved and isinstance(saved.get("port"), int) and not isinstance(saved.get("port"), bool):
        yielded.add(saved["port"])
    for offset in range(span):
        port = low + ((start - low + offset) % span)
        if port not in yielded:
            yielded.add(port)
            yield port


def render_command(config: dict[str, Any], port: int) -> list[str]:
    command = [item.replace(PORT_TOKEN, str(port)) for item in config["startCommand"]]
    if not config.get("portEnvironmentVariable") and not any(
        PORT_TOKEN in original for original in config["startCommand"]
    ):
        fail("startCommand must contain {port} when no portEnvironmentVariable is configured")
    return command


def listening_pids(port: int) -> set[int] | None:
    if os.name == "nt":
        command = [
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "(Get-NetTCPConnection -State Listen -LocalPort "
            f"{port} -ErrorAction SilentlyContinue).OwningProcess",
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            values = {int(item) for item in result.stdout.split() if item.isdigit()}
            if values:
                return values
        netstat = subprocess.run(["netstat", "-ano", "-p", "TCP"], capture_output=True, text=True, check=False)
        if netstat.returncode == 0:
            values = set()
            suffix = f":{port}"
            for line in netstat.stdout.splitlines():
                fields = line.split()
                if len(fields) >= 5 and fields[0].upper() == "TCP" and fields[3].upper() == "LISTENING":
                    if fields[1].endswith(suffix) or fields[1].endswith(f".{port}"):
                        if fields[4].isdigit():
                            values.add(int(fields[4]))
            return values
        return None

    if shutil.which("lsof"):
        result = subprocess.run(
            ["lsof", "-nP", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode in {0, 1}:
            return {int(item) for item in result.stdout.split() if item.isdigit()}
    if shutil.which("ss"):
        result = subprocess.run(["ss", "-ltnpH"], capture_output=True, text=True, check=False)
        values = set()
        for line in result.stdout.splitlines():
            if re.search(rf":{port}\s", line):
                values.update(int(item) for item in re.findall(r"pid=(\d+)", line))
        return values
    return None


def process_tree(root_pid: int) -> set[int] | None:
    if os.name == "nt":
        command = [
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "Get-CimInstance Win32_Process | ForEach-Object { "
            '"$($_.ProcessId):$($_.ParentProcessId)" }',
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return None
        parent: dict[int, int] = {}
        for item in result.stdout.splitlines():
            parts = item.strip().split(":", 1)
            if len(parts) == 2 and all(part.isdigit() for part in parts):
                parent[int(parts[0])] = int(parts[1])
    else:
        result = subprocess.run(["ps", "-eo", "pid=,ppid="], capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return None
        parent = {}
        for item in result.stdout.splitlines():
            parts = item.split()
            if len(parts) == 2 and all(part.isdigit() for part in parts):
                parent[int(parts[0])] = int(parts[1])

    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, parent_pid in parent.items():
            if parent_pid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def owns_port(process: subprocess.Popen[Any], port: int) -> bool:
    owners = listening_pids(port)
    if owners is None:
        fail("cannot verify which process owns the runtime port; install lsof/ss or use Windows networking tools")
    if not owners:
        return False
    tree = process_tree(process.pid)
    if tree is None:
        fail("cannot verify the runtime process tree")
    return bool(owners & tree)


def health_ok(url: str, timeout: float) -> bool:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url, timeout=timeout) as response:
            return 200 <= response.status < 400
    except (urllib.error.URLError, OSError):
        return False


def stop_process(process: subprocess.Popen[Any]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, check=False)
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except OSError:
            with contextlib.suppress(OSError):
                process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(OSError):
            process.kill()


def start_runtime(root: Path, descriptor: Path, config: dict[str, Any], explicit_port: int | None) -> int:
    host = urlparse(config["healthUrl"].replace(PORT_TOKEN, "40000")).hostname or "127.0.0.1"
    timeout = config["healthTimeoutSeconds"]
    attempts = 0
    last_collision = ""
    for port in candidate_ports(root, config, explicit_port):
        attempts += 1
        lease = PortLease(port)
        if not lease.acquire():
            last_collision = f"port {port} is leased"
            if explicit_port is not None:
                fail(last_collision)
            continue
        process: subprocess.Popen[Any] | None = None
        try:
            if not can_bind(port, host):
                last_collision = f"port {port} is already in use"
                if explicit_port is not None:
                    fail(last_collision)
                continue
            command = render_command(config, port)
            environment = os.environ.copy()
            if config.get("portEnvironmentVariable"):
                environment[config["portEnvironmentVariable"]] = str(port)
            print(f"Starting runtime on http://{host}:{port}", flush=True)
            print("Command: " + " ".join(command), flush=True)
            process = subprocess.Popen(
                command,
                cwd=config["workdir"],
                env=environment,
                start_new_session=os.name != "nt",
            )
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if health_ok(config["healthUrl"].replace(PORT_TOKEN, str(port)), 1):
                    if owns_port(process, port):
                        write_state(state_path(root), root, descriptor, port)
                        print("Runtime state: runtime-health-verified", flush=True)
                        print(
                            f"Health URL: {config['healthUrl'].replace(PORT_TOKEN, str(port))}",
                            flush=True,
                        )
                        print("Keep this process running during the manual test; press Ctrl+C to stop.", flush=True)
                        try:
                            return process.wait()
                        finally:
                            lease.release()
                    last_collision = f"port {port} answered, but another process owns it"
                    if explicit_port is not None:
                        fail(last_collision)
                    break
                if process.poll() is not None:
                    owners = listening_pids(port)
                    if owners:
                        last_collision = f"port {port} was taken by another process during startup"
                        if explicit_port is not None:
                            fail(last_collision)
                        break
                    fail(f"runtime process exited with code {process.returncode} before health check passed")
                time.sleep(0.25)
            else:
                owners = listening_pids(port)
                if owners and not owns_port(process, port):
                    last_collision = f"port {port} answered from another process"
                    if explicit_port is not None:
                        fail(last_collision)
                else:
                    fail(f"runtime health check did not pass within {timeout:g} seconds")
        finally:
            if process is not None and process.poll() is None:
                stop_process(process)
            lease.release()
        if explicit_port is not None or attempts >= MAX_PORT_RETRIES:
            break
    fail(
        f"could not allocate a verified runtime port after {attempts} attempt(s)"
        + (f": {last_collision}" if last_collision else "")
    )


def inspect_runtime(root: Path, descriptor: Path, config: dict[str, Any]) -> None:
    saved = read_state(state_path(root))
    preferred = saved.get("port") if saved else None
    candidate = next(candidate_ports(root, config, None))
    print(f"Descriptor: {descriptor}")
    print(f"Worktree: {root}")
    print(f"Port range: {config['portRange'][0]}-{config['portRange'][1]}")
    print(f"Preferred port: {preferred if preferred is not None else 'none'}")
    print(f"Next candidate: {candidate}")
    print(f"Health URL: {config['healthUrl'].replace(PORT_TOKEN, str(candidate))}")
    if config.get("resources"):
        print("Resources:")
        for resource in config["resources"]:
            note = f" — {resource['note']}" if resource.get("note") else ""
            print(f"  {resource['name']}: {resource['isolation']}{note}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for operation in ("inspect", "start"):
        subparser = subparsers.add_parser(operation)
        subparser.add_argument("--descriptor", help=f"descriptor path (default: {DESCRIPTOR_NAME})")
        subparser.add_argument("--port", type=int, help="explicit port override within the descriptor range")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = git_root()
    descriptor = descriptor_path(root, args.descriptor)
    config = validate_descriptor(descriptor)
    if args.operation == "inspect":
        inspect_runtime(root, descriptor, config)
        return 0
    start_runtime(root, descriptor, config, args.port)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError_ as exc:
        print(f"worktree-runtime: {exc}", file=sys.stderr)
        raise SystemExit(2)
