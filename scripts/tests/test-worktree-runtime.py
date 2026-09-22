#!/usr/bin/env python3
"""Focused tests for the descriptor-driven worktree runtime helper."""

from __future__ import annotations

import json
import importlib.util
import os
import signal
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


# Loading the source helper by path would otherwise create ignored bytecode in the chezmoi
# source tree, which makes `chezmoi diff` report a false target addition after this test.
sys.dont_write_bytecode = True

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
HELPER = REPOSITORY_ROOT / "home" / "dot_local" / "share" / "worktree-runtime.py"
_spec = importlib.util.spec_from_file_location("worktree_runtime", HELPER)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"could not load runtime helper: {HELPER}")
runtime = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(runtime)


class WorktreeRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="worktree-runtime-tests-")
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.cache = Path(self.temp.name) / "cache"
        self.previous_cache = os.environ.get(runtime.CACHE_ENV)
        os.environ[runtime.CACHE_ENV] = str(self.cache)

    def tearDown(self) -> None:
        if self.previous_cache is None:
            os.environ.pop(runtime.CACHE_ENV, None)
        else:
            os.environ[runtime.CACHE_ENV] = self.previous_cache
        self.temp.cleanup()

    def descriptor(self, port_low: int, port_high: int | None = None) -> Path:
        descriptor = self.root / runtime.DESCRIPTOR_NAME
        descriptor.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "name": "test server",
                    "startCommand": [
                        sys.executable,
                        "-m",
                        "http.server",
                        "{port}",
                        "--bind",
                        "127.0.0.1",
                    ],
                    "portRange": [port_low, port_high or port_low],
                    "healthUrl": "http://127.0.0.1:{port}/",
                    "healthTimeoutSeconds": 5,
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return descriptor

    def test_validation_requires_port_injection(self) -> None:
        descriptor = self.root / runtime.DESCRIPTOR_NAME
        descriptor.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "startCommand": ["server"],
                    "portRange": [43000, 43010],
                    "healthUrl": "http://127.0.0.1:{port}/",
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaises(runtime.RuntimeError_):
            runtime.validate_descriptor(descriptor)

    def test_lease_is_exclusive(self) -> None:
        first = runtime.PortLease(43001)
        second = runtime.PortLease(43001)
        self.assertTrue(first.acquire())
        try:
            self.assertFalse(second.acquire())
        finally:
            first.release()
        self.assertTrue(second.acquire())
        second.release()

    def test_inspect_reports_stable_candidate(self) -> None:
        descriptor = self.descriptor(45100, 45110)
        config = runtime.validate_descriptor(descriptor)
        first = next(runtime.candidate_ports(self.root, config, None))
        runtime.write_state(runtime.state_path(self.root), self.root, descriptor, first)
        second = next(runtime.candidate_ports(self.root, config, None))
        self.assertEqual(first, second)

    def test_start_uses_health_and_persists_port(self) -> None:
        descriptor = self.descriptor(45200, 45202)
        environment = os.environ.copy()
        process = subprocess.Popen(
            [sys.executable, str(HELPER), "start"],
            cwd=self.root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            output = []
            for _ in range(3):
                line = process.stdout.readline() if process.stdout else ""
                output.append(line)
            self.assertTrue(any("Runtime state: runtime-health-verified" in line for line in output))
            state = runtime.read_state(runtime.state_path(self.root))
            self.assertIsNotNone(state)
            port = state["port"]
            with socket.create_connection(("127.0.0.1", port), timeout=2):
                pass
        finally:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                        capture_output=True,
                        check=False,
                    )
                else:
                    process.send_signal(signal.SIGINT)
                process.wait(timeout=10)
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()

    def test_explicit_occupied_port_fails(self) -> None:
        descriptor = self.descriptor(45300)
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(("127.0.0.1", 45300))
        listener.listen(1)
        try:
            result = subprocess.run(
                [sys.executable, str(HELPER), "start", "--port", "45300"],
                cwd=self.root,
                env=os.environ.copy(),
                capture_output=True,
                text=True,
                timeout=10,
            )
        finally:
            listener.close()
        self.assertEqual(result.returncode, 2)
        self.assertIn("already in use", result.stderr)

    def test_automatic_port_fallback_skips_occupied_preferred_port(self) -> None:
        descriptor = self.descriptor(45400, 45401)
        runtime.write_state(runtime.state_path(self.root), self.root, descriptor, 45400)
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(("127.0.0.1", 45400))
        listener.listen(1)
        process = subprocess.Popen(
            [sys.executable, str(HELPER), "start"],
            cwd=self.root,
            env=os.environ.copy(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            output = []
            for _ in range(3):
                line = process.stdout.readline() if process.stdout else ""
                output.append(line)
            self.assertTrue(any("Runtime state: runtime-health-verified" in line for line in output))
            state = runtime.read_state(runtime.state_path(self.root))
            self.assertIsNotNone(state)
            self.assertEqual(state["port"], 45401)
        finally:
            listener.close()
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                        capture_output=True,
                        check=False,
                    )
                else:
                    process.send_signal(signal.SIGINT)
                process.wait(timeout=10)
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()


if __name__ == "__main__":
    unittest.main()
