"""Shared local tool paths, pinned Godot setup, and owned service lifecycle."""
from datetime import datetime, timezone
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
RUNTIME = ROOT / ".runtime"
BUILDS = ROOT / "builds"
HARNESS = Path("/workspace/ironwood-cloud-harness")
OWNER = "ironwood-reach-godot-tools"
GODOT_VERSION = "4.6.3.stable.official.7d41c59c4"


def now():
    return datetime.now(timezone.utc).isoformat()


def owned_directory(path):
    path = Path(path)
    for component in [path, *path.parents]:
        if component.is_symlink():
            raise RuntimeError(f"Preserving unexpected directory symlink: {component}")
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    if hasattr(os, "getuid") and path.stat().st_uid != os.getuid():
        raise RuntimeError(f"Directory belongs to another user: {path}")
    return path


@contextmanager
def candidate_lease(identifier):
    directory = owned_directory(RUNTIME / "build-locks")
    path = directory / (identifier + ".lock")
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    if path.is_symlink():
        raise RuntimeError("Preserving unexpected candidate-lock symlink.")
    descriptor = os.open(path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RuntimeError("Preserving unexpected candidate-lock file type.")
        if hasattr(os, "getuid") and os.fstat(descriptor).st_uid != os.getuid():
            raise RuntimeError("Candidate lock belongs to another user.")
        if os.name == "nt":
            import msvcrt
            if os.fstat(descriptor).st_size == 0:
                os.write(descriptor, b" ")
            os.lseek(descriptor, 0, os.SEEK_SET)
            msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def verify_web_template(environment):
    import sys
    import zipfile
    if environment.get("XDG_DATA_HOME"):
        directory = Path(environment["XDG_DATA_HOME"]) / "godot/export_templates/4.6.3.stable"
    elif os.name == "nt":
        directory = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Godot/export_templates/4.6.3.stable"
    elif sys.platform == "darwin":
        directory = Path.home() / "Library/Application Support/Godot/export_templates/4.6.3.stable"
    else:
        directory = Path.home() / ".local/share/godot/export_templates/4.6.3.stable"
    template = directory / "web_nothreads_release.zip"
    if not template.is_file():
        raise RuntimeError(f"Install matching Godot 4.6.3 non-threaded web templates at {directory}.")
    version_file = directory / "version.txt"
    if version_file.is_file() and version_file.read_text().strip() not in ("4.6.3.stable", "4.6.3"):
        raise RuntimeError("Template version metadata does not match pinned Godot 4.6.3.")
    retained = HARNESS / "runtime/godot-data/godot/export_templates/4.6.3.stable"
    if directory.resolve() == retained.resolve():
        receipt_file = HARNESS / "runtime/web-templates-receipt.json"
        receipt = json.loads(receipt_file.read_text())
        expected_archive = "da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"
        detail = receipt.get("templates", {}).get(template.name, {})
        if (receipt.get("version") != "4.6.3" or receipt.get("official_archive_sha512") != expected_archive
                or detail.get("sha256") != sha256(template) or detail.get("bytes") != template.stat().st_size):
            raise RuntimeError("Retained web template does not match the pinned official verification receipt.")
        return {"template": str(template), "verification": "pinned official archive receipt + template SHA256"}
    with zipfile.ZipFile(template) as archive:
        names = set(archive.namelist())
        if not any(name.endswith(".wasm") for name in names) or not any(name.endswith(".js") for name in names):
            raise RuntimeError("Installed desktop web template is missing required WASM/JavaScript files.")
        if archive.testzip() is not None:
            raise RuntimeError("Installed desktop template ZIP integrity check failed.")
    return {"template": str(template), "verification": "matching version directory + ZIP CRC; desktop installation supplied by user"}


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def godot_environment(use_templates=False):
    owned_directory(RUNTIME)
    environment = dict(os.environ)
    for variable, folder in [("XDG_CONFIG_HOME", "godot-config"),
                             ("XDG_CACHE_HOME", "godot-cache"),
                             ("XDG_RUNTIME_DIR", "godot-runtime")]:
        if variable not in environment:
            environment[variable] = str(owned_directory(RUNTIME / folder))
    if "XDG_DATA_HOME" not in environment:
        source = HARNESS / "runtime/godot-data/godot/export_templates/4.6.3.stable"
        if use_templates and source.is_dir():
            data = owned_directory(RUNTIME / "godot-data")
            parent = owned_directory(data / "godot/export_templates")
            link = parent / "4.6.3.stable"
            if link.is_symlink():
                if link.resolve() != source.resolve():
                    raise RuntimeError("Preserving unexpected export-template symlink.")
            elif link.exists():
                if not link.is_dir():
                    raise RuntimeError("Preserving unexpected export-template path.")
            else:
                link.symlink_to(source, target_is_directory=True)
            environment["XDG_DATA_HOME"] = str(data)
        elif not use_templates:
            environment["XDG_DATA_HOME"] = str(owned_directory(RUNTIME / "godot-data"))
        # A desktop without the cloud harness keeps Godot's default template
        # location, or its explicitly supplied XDG_DATA_HOME binding.
    return environment


def godot_binary(environment=None):
    candidate = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not candidate:
        raise RuntimeError("Install official Godot 4.6.3 and matching web templates, or set GODOT_BIN.")
    candidate = str(Path(candidate).resolve())
    version = subprocess.run([candidate, "--version"], env=environment,
                             capture_output=True, text=True, check=True).stdout.strip()
    if version != GODOT_VERSION:
        raise RuntimeError(f"Expected {GODOT_VERSION}; installed Godot reports {version!r}.")
    return candidate


def port_free(port):
    with socket.socket() as connection:
        connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            connection.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def wait_for_port_release(port, timeout=5.0):
    """Wait briefly after an identified owned exit; never signal a listener."""
    if not 0 <= timeout <= 5.0:
        raise ValueError("Port-release timeout must be between zero and five seconds.")
    started = time.monotonic()
    deadline = started + timeout
    while True:
        if port_free(port):
            return {"port": port, "released": True,
                    "waited_seconds": round(time.monotonic() - started, 3)}
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError(
                f"Loopback port {port} remained occupied after the owned process exited; "
                "preserving its current listener. Retry once that service has released the port.")
        time.sleep(min(0.05, remaining))


def process_matches(metadata, command):
    if metadata is None or metadata["uid"] != os.getuid():
        return False
    actual = metadata["argv"]
    if not actual or actual[1:] != command[1:]:
        return False
    executable = shutil.which(actual[0]) if "/" not in actual[0] else actual[0]
    return bool(executable and Path(executable).resolve() == Path(command[0]).resolve())


def append_owned_log(path):
    descriptor = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_APPEND | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    metadata = os.fstat(descriptor)
    if metadata.st_uid != os.getuid() or not stat.S_ISREG(metadata.st_mode):
        os.close(descriptor)
        raise RuntimeError("Preserving unexpected log ownership/type.")
    return os.fdopen(descriptor, "a", buffering=1)


def stop_owned_service(name, command, port):
    """Stop only an identified saved process; never infer ownership from a port."""
    import fcntl
    from browser_runtime_guard import process_metadata
    owned_directory(RUNTIME)
    directory = owned_directory(RUNTIME / "services")
    state_path = directory / (name + ".json")
    lease_path = directory / (name + ".startup.lock")
    if state_path.is_symlink() or lease_path.is_symlink():
        raise RuntimeError("Preserving unexpected service state/lease symlink.")
    descriptor = os.open(lease_path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        if os.fstat(descriptor).st_uid != os.getuid():
            raise RuntimeError("Service lease belongs to another user; preserving it.")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if not state_path.exists():
            return {"status": "not_running", "name": name, "unknown_processes_preserved": True}
        metadata = state_path.stat()
        if metadata.st_uid != os.getuid() or not stat.S_ISREG(metadata.st_mode):
            raise RuntimeError("Preserving unknown service metadata.")
        state = json.loads(state_path.read_text())
        if (state.get("owner") != OWNER or state.get("name") != name
                or state.get("command") != command or state.get("port") != port
                or state.get("host") != "127.0.0.1"):
            raise RuntimeError("Service metadata does not identify the requested owned service.")
        pid = int(state["pid"])
        actual = process_metadata(pid)
        if actual is None:
            return {"status": "already_stopped", "name": name, "pid": pid}
        if not process_matches(actual, command) or actual["start_ticks"] != state.get("process_start_ticks"):
            raise RuntimeError(f"Preserving unknown live process PID {pid}.")
        pidfd = None
        try:
            if hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal"):
                pidfd = os.pidfd_open(pid)
                again = process_metadata(pid)
                if again is None:
                    return {"status": "already_stopped", "name": name, "pid": pid}
                if not process_matches(again, command) or again["start_ticks"] != actual["start_ticks"]:
                    raise RuntimeError("Process identity changed before stop; preserving it.")
                signal.pidfd_send_signal(pidfd, signal.SIGTERM)
            else:
                again = process_metadata(pid)
                if again is None:
                    return {"status": "already_stopped", "name": name, "pid": pid}
                if not process_matches(again, command) or again["start_ticks"] != actual["start_ticks"]:
                    raise RuntimeError("Process identity changed before stop; preserving it.")
                os.kill(pid, signal.SIGTERM)
        finally:
            if pidfd is not None:
                os.close(pidfd)
        for _ in range(50):
            remaining = process_metadata(pid)
            if remaining is None:
                return {"status": "stopped", "name": name, "pid": pid, "state_discarded": name == "authority"}
            if remaining["start_ticks"] != actual["start_ticks"]:
                return {"status": "owned_process_exited", "name": name, "pid_reused_preserved": True}
            time.sleep(0.1)
        raise RuntimeError(f"Owned PID {pid} has not exited after SIGTERM; preserved for diagnosis.")
    finally:
        os.close(descriptor)


def ensure_service(name, command, port, ready, environment=None, reuse_only=False):
    # Lifecycle guards are Linux-specific; build/export remain usable without them.
    import fcntl
    from browser_runtime_guard import process_metadata
    owned_directory(RUNTIME)
    directory = owned_directory(RUNTIME / "services")
    logs = owned_directory(RUNTIME / "logs")
    state_path = directory / (name + ".json")
    lease_path = directory / (name + ".startup.lock")
    if state_path.is_symlink() or lease_path.is_symlink():
        raise RuntimeError("Preserving unexpected service state/lease symlink.")
    descriptor = os.open(lease_path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        if os.fstat(descriptor).st_uid != os.getuid():
            raise RuntimeError("Service lease belongs to another user; preserving it.")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = None
        if state_path.exists():
            if state_path.stat().st_uid != os.getuid() or not stat.S_ISREG(state_path.stat().st_mode):
                raise RuntimeError("Service metadata belongs to another user; preserving it.")
            state = json.loads(state_path.read_text())
            if (state.get("owner") != OWNER or state.get("name") != name
                    or state.get("port") != port or state.get("host") != "127.0.0.1"
                    or state.get("command") != command):
                raise RuntimeError("Service metadata does not identify our expected command; preserving it.")
            actual = process_metadata(state["pid"])
            if actual is not None:
                if not process_matches(actual, command) or actual["start_ticks"] != state.get("process_start_ticks"):
                    raise RuntimeError(f"Service metadata references unknown live PID {state['pid']}; preserving it.")
                readiness = ready()
                return {"status": "reused", "pid": state["pid"], "name": name,
                        "port": port, "readiness": readiness, "log": state["log"]}
        if reuse_only:
            raise RuntimeError("No verified live owned service; --reuse-only preserves current state.")
        if not port_free(port):
            raise RuntimeError(f"Loopback port {port} is occupied by an unverified service; preserving it.")
        if state_path.exists():
            history = owned_directory(directory / "history")
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
            with (history / (state_path.name + "." + timestamp)).open("xb") as output:
                output.write(state_path.read_bytes())
            state_path.unlink()
        logfile = logs / (name + ".log")
        with append_owned_log(logfile) as output:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        actual = process_metadata(process.pid)
        if actual is None or not process_matches(actual, command):
            raise RuntimeError("Could not verify the newly started service process.")
        state = {"owner": OWNER, "name": name, "pid": process.pid,
                 "owner_uid": os.getuid(), "process_start_ticks": actual["start_ticks"],
                 "command": command, "host": "127.0.0.1", "port": port,
                 "started_at": now(), "log": str(logfile)}
        with state_path.open("x") as output:
            output.write(json.dumps(state, indent=2) + "\n")
        last_error = None
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError(f"Owned service exited; inspect {logfile}.")
            try:
                readiness = ready()
                return {"status": "started", "pid": process.pid, "name": name,
                        "port": port, "readiness": readiness, "log": str(logfile)}
            except (OSError, RuntimeError) as error:
                last_error = error
                time.sleep(0.1)
        raise RuntimeError(f"Owned service is not ready: {last_error}. PID {process.pid} preserved; inspect {logfile}.")
    finally:
        os.close(descriptor)
