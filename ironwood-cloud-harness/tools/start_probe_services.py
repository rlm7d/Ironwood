#!/usr/bin/env python3
"""Start/reuse only this fixture's loopback HTTP and Godot authority services.

Unknown live PIDs or occupied ports are preserved. Stale owned runtime metadata is
archived before refresh. HTTP content checks and a TCP probe are baseline service
readiness only; they do not prove multiplayer joins or synchronization.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime"
LOGS = ROOT / "logs"
PROJECT = Path("/tmp/ironwood-capability-probe")
BUILDS = ROOT / "builds"
AUTHORITY_COMMAND = ["godot", "--headless", "--path", str(PROJECT), "--", "--server"]
HTTP_ARGS = ["-u", "-m", "http.server", "9080", "--bind", "127.0.0.1", "--directory", str(BUILDS)]


def process_command(pid):
    try:
        data = Path(f"/proc/{pid}/cmdline").read_bytes()
    except FileNotFoundError:
        return None
    except PermissionError:
        raise RuntimeError(f"Cannot verify PID {pid}; preserving it and its metadata.")
    return [piece.decode() for piece in data.split(b"\0") if piece] or None


def command_matches(actual, expected):
    if not actual or actual[1:] != expected[1:]:
        return False
    executable = shutil.which(actual[0]) if "/" not in actual[0] else actual[0]
    expected_executable = shutil.which(expected[0]) if "/" not in expected[0] else expected[0]
    return bool(executable and expected_executable
                and Path(executable).resolve() == Path(expected_executable).resolve())


def service_pid(path, expected, authority=False):
    if not path.exists():
        return None
    if authority:
        data = json.loads(path.read_text())
        if data.get("command") != AUTHORITY_COMMAND:
            raise RuntimeError(f"Unexpected service metadata in {path}; preserving it.")
        pid = int(data["pid"])
    else:
        pid = int(path.read_text().strip())
    actual = process_command(pid)
    if actual is None:
        return None
    if not command_matches(actual, expected):
        raise RuntimeError(f"PID {pid} is not our expected service; preserving it and its metadata.")
    return pid


def port_free(port):
    with socket.socket() as connection:
        # Closed owned TCP connections may remain in TIME_WAIT. Reuse permits
        # those expired listeners without permitting a second live listener.
        connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            connection.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def preserve_stale_metadata(path):
    if path.exists():
        history = RUNTIME / "metadata-history"
        history.mkdir(exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        destination = history / (path.name + "." + stamp)
        # Preserve the original bytes, with no overwriting of existing history.
        with destination.open("xb") as saved:
            saved.write(path.read_bytes())
        path.unlink()


def start_service(path, command, log_name, port, reuse_only, authority=False):
    pid = service_pid(path, command, authority=authority)
    if pid is not None:
        return {"pid": pid, "status": "reused", "command": process_command(pid)}
    if reuse_only:
        raise RuntimeError(f"Our verified service on port {port} is absent; --reuse-only makes no changes.")
    if not port_free(port):
        raise RuntimeError(f"Port {port} is occupied by an unverified service; preserving it.")
    preserve_stale_metadata(path)
    env = dict(os.environ)
    for name, suffix in [("XDG_DATA_HOME", "godot-data"), ("XDG_CONFIG_HOME", "godot-config"),
                         ("XDG_CACHE_HOME", "godot-cache"), ("XDG_RUNTIME_DIR", "godot-runtime")]:
        directory = RUNTIME / suffix
        directory.mkdir(mode=0o700, exist_ok=True)
        env[name] = str(directory)
    # Append to the existing owned log, preserving earlier verification evidence.
    with (LOGS / log_name).open("a") as output:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(40):
        if process.poll() is not None:
            raise RuntimeError(f"Service exited; inspect {LOGS / log_name}.")
        if not port_free(port):
            break
        time.sleep(0.1)
    else:
        raise RuntimeError(f"Service did not listen; inspect {LOGS / log_name}. PID {process.pid} preserved.")
    with path.open("x") as state:
        if authority:
            state.write(json.dumps({"pid": process.pid, "command": AUTHORITY_COMMAND}) + "\n")
        else:
            state.write(str(process.pid) + "\n")
    if not command_matches(process_command(process.pid), command):
        raise RuntimeError("Service process identity check failed after startup.")
    return {"pid": process.pid, "status": "started", "command": command}


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def check_http(build_id):
    build = BUILDS / ("probe-" + build_id)
    prefix = f"http://127.0.0.1:9080/probe-{build_id}/"
    html_path = build / "index.html"
    with urllib.request.urlopen(prefix + "index.html", timeout=5) as response:
        html = response.read()
        if response.status != 200 or hashlib.sha256(html).hexdigest() != file_sha256(html_path):
            raise RuntimeError("HTTP index differs from the current fixture export.")
    wasm_digest = hashlib.sha256()
    magic = b""
    with urllib.request.urlopen(prefix + "index.wasm", timeout=5) as response:
        mime = response.headers.get_content_type()
        if response.status != 200 or mime != "application/wasm":
            raise RuntimeError("HTTP WASM response/status/MIME is incorrect.")
        while block := response.read(1024 * 1024):
            if not magic:
                magic = block[:4]
            wasm_digest.update(block)
    if magic != b"\x00asm" or wasm_digest.hexdigest() != file_sha256(build / "index.wasm"):
        raise RuntimeError("Served WASM does not match the current exported binary.")
    return {"url": prefix + "index.html", "index_matches_export": True,
            "wasm_matches_export": True, "wasm_mime": mime}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-id", default="v1", choices=["v1", "v2"])
    parser.add_argument("--reuse-only", action="store_true")
    args = parser.parse_args()
    if not (PROJECT / "project.godot").is_file():
        parser.error("Generate the disposable capability fixture first.")
    if not (BUILDS / ("probe-" + args.build_id) / "index.html").is_file():
        parser.error("Export the requested fixture build first.")
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    http_command = [sys.executable] + HTTP_ARGS
    # Verify identities first so an unknown PID prevents unrelated startup.
    service_pid(RUNTIME / "web-server.pid", http_command)
    service_pid(RUNTIME / "probe-authority.json", AUTHORITY_COMMAND, authority=True)
    http = start_service(RUNTIME / "web-server.pid", http_command, "web-server.log", 9080, args.reuse_only)
    authority = start_service(RUNTIME / "probe-authority.json", AUTHORITY_COMMAND,
                              "probe-authority.log", 8765, args.reuse_only, authority=True)
    readiness = check_http(args.build_id)
    with socket.create_connection(("127.0.0.1", 8765), timeout=3):
        pass  # No WebSocket upgrade or role/seat join; this is only a TCP readiness probe.
    authority_log = LOGS / "probe-authority.log"
    marker = "Disposable capability authority listening on loopback port 8765"
    if not authority_log.is_file() or marker not in authority_log.read_text():
        raise RuntimeError("Expected authority startup marker absent from its owned log.")
    report = {"checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
              "http": http, "authority": authority, "readiness": readiness,
              "authority_tcp_reachable": True, "authority_startup_log_marker": True,
              "scope": "service_baseline_only; multiplayer_behavior_requires_separate_browser_proof"}
    print(json.dumps(report))


if __name__ == "__main__":
    main()
