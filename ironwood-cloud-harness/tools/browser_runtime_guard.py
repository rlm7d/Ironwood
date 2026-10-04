"""Protect the harness's two browser profiles across cold starts.

Only metadata is inspected. Cookie values, browser storage and lock/socket targets
are never copied or printed. Cleanup unlinks the three recognized Singleton
symlinks, never their targets, after checking that no live browser owns a profile.
"""
import fcntl
import json
import os
from pathlib import Path
import socket
import stat


class RuntimeGuardError(RuntimeError):
    pass


def process_metadata(pid):
    """Return identity for a live process, or None for an absent/zombie process."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        raise RuntimeGuardError("Browser runtime state contains an invalid PID.")
    if pid <= 0:
        raise RuntimeGuardError("Browser runtime state contains an invalid PID.")
    directory = Path("/proc") / str(pid)
    try:
        status = directory.joinpath("status").read_text()
        fields = {line.split(":", 1)[0]: line.split(":", 1)[1].strip()
                  for line in status.splitlines() if ":" in line}
        if fields.get("State", "").startswith("Z"):
            return None
        stat_tail = directory.joinpath("stat").read_text().rsplit(")", 1)[1].split()
        # /proc/PID/stat field 22; stat_tail begins at field 3.
        start_ticks = int(stat_tail[19])
        argv = [part.decode(errors="replace") for part in
                directory.joinpath("cmdline").read_bytes().split(b"\0") if part]
        return {"pid": pid, "uid": int(fields["Uid"].split()[0]),
                "start_ticks": start_ticks, "argv": argv, "name": fields.get("Name", "")}
    except FileNotFoundError:
        return None
    except (PermissionError, KeyError, IndexError, ValueError) as exc:
        raise RuntimeGuardError(f"Cannot verify process identity for PID {pid}; preserving it.") from exc


def helper_identity_matches(metadata, helper_path, saved_state):
    argv = metadata["argv"]
    if metadata["uid"] != os.getuid() or len(argv) < 2:
        return False
    if "python" not in Path(argv[0]).name:
        return False
    if Path(argv[1]).resolve() != helper_path.resolve():
        return False
    saved_helper = saved_state.get("helper_path")
    if saved_helper is not None and Path(saved_helper).resolve() != helper_path.resolve():
        return False
    saved_ticks = saved_state.get("process_start_ticks")
    if saved_ticks is not None and saved_ticks != metadata["start_ticks"]:
        return False
    return saved_state.get("owner_uid", os.getuid()) == metadata["uid"]


def browsers_using_profiles(profiles):
    """Identify Chromium processes with either exact user-data-dir argument."""
    expected = {str(profile.resolve()) for profile in profiles}
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            name = entry.joinpath("comm").read_text().strip()
        except FileNotFoundError:
            continue
        except PermissionError as exc:
            raise RuntimeGuardError("Cannot verify all process names; preserving profile locks.") from exc
        if not name.lower().startswith(("chromium", "chrome")):
            continue
        metadata = process_metadata(entry.name)
        if metadata is None:
            continue
        argv = metadata["argv"]
        for index, argument in enumerate(argv):
            profile = None
            if argument.startswith("--user-data-dir="):
                profile = argument.split("=", 1)[1]
            elif argument == "--user-data-dir" and index + 1 < len(argv):
                profile = argv[index + 1]
            if profile is not None and str(Path(profile).resolve()) in expected:
                found.append({"pid": metadata["pid"], "profile": str(Path(profile).resolve())})
                break
    return found


class BrowserRuntimeLease:
    """Keep one helper active and narrowly prepare profile locks for startup."""

    def __init__(self, run_directory, helper_path):
        self.run_directory = Path(run_directory)
        self.helper_path = Path(helper_path).resolve()
        self.profiles = [self.run_directory / "profile-1", self.run_directory / "profile-2"]
        self.fd = None

    def __enter__(self):
        if self.run_directory.is_symlink() or self.run_directory.stat().st_uid != os.getuid():
            raise RuntimeGuardError("Runtime directory identity is unknown; preserving it.")
        flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW
        try:
            self.fd = os.open(self.run_directory / "startup.lock", flags, 0o600)
            if os.fstat(self.fd).st_uid != os.getuid():
                raise RuntimeGuardError("Runtime lease belongs to another user; preserving it.")
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            self.close()
            # A newer helper holds its lease throughout its lifetime.
            state = self._state()
            metadata = process_metadata(state["pid"]) if state.get("pid") else None
            if metadata and helper_identity_matches(metadata, self.helper_path, state):
                self.reuse = self._reuse_result(state)
                return self
            raise RuntimeGuardError("Another browser startup owns the runtime lease; preserving it.") from exc
        except Exception:
            self.close()
            raise
        self.reuse = None
        return self

    def _state(self):
        state_path = self.run_directory / "state.json"
        if state_path.is_symlink():
            raise RuntimeGuardError("Browser state ownership is unknown; preserving it.")
        if not state_path.exists():
            return {}
        if state_path.stat().st_uid != os.getuid():
            raise RuntimeGuardError("Browser state ownership is unknown; preserving it.")
        try:
            state = json.loads(state_path.read_text())
        except (OSError, ValueError) as exc:
            raise RuntimeGuardError("Browser runtime state cannot be verified; preserving it.") from exc
        if not isinstance(state, dict):
            raise RuntimeGuardError("Browser runtime state cannot be verified; preserving it.")
        return state

    @staticmethod
    def _reuse_result(state):
        return {"status": "reuse", "pid": state["pid"], "build": state.get("build"),
                "clients": len(state.get("clients", [])), "profiles_preserved": True}

    def prepare(self, cleanup=True):
        if self.reuse is not None:
            return self.reuse
        state = self._state()
        if state.get("pid"):
            metadata = process_metadata(state["pid"])
            if metadata:
                if helper_identity_matches(metadata, self.helper_path, state):
                    return self._reuse_result(state)
                raise RuntimeGuardError(f"State references unknown live PID {state['pid']}; preserving it and both profiles.")
        for profile in self.profiles:
            if profile.is_symlink() or (profile.exists() and profile.stat().st_uid != os.getuid()):
                raise RuntimeGuardError(f"Profile ownership is unknown for {profile.name}; preserving it.")
        live = browsers_using_profiles(self.profiles)
        if live:
            pids = sorted({item["pid"] for item in live})
            raise RuntimeGuardError(f"Live Chromium processes use the dedicated profiles: {pids}; preserving their locks.")
        candidates = []
        for profile in self.profiles:
            lock = profile / "SingletonLock"
            if lock.is_symlink():
                target = os.readlink(lock)  # Only lock identity; never Cookie or Socket targets.
                hostname, separator, pid_text = target.rpartition("-")
                if not separator or not pid_text.isdecimal():
                    raise RuntimeGuardError(f"Unrecognized SingletonLock identity in {profile.name}; preserving it.")
                if hostname == socket.gethostname() and process_metadata(pid_text) is not None:
                    raise RuntimeGuardError(f"SingletonLock references a live local PID in {profile.name}; preserving it.")
            for name in ("SingletonLock", "SingletonSocket", "SingletonCookie"):
                path = profile / name
                try:
                    metadata = path.lstat()
                except FileNotFoundError:
                    continue
                if metadata.st_uid != os.getuid() or not stat.S_ISLNK(metadata.st_mode):
                    raise RuntimeGuardError(f"Unrecognized {name} in {profile.name}; preserving it.")
                candidates.append((path, metadata.st_ino))
        cleaned = []
        if cleanup and candidates:
            if browsers_using_profiles(self.profiles):
                raise RuntimeGuardError("A browser appeared during startup inspection; preserving profile locks.")
            for path, inode in candidates:
                current = path.lstat()
                if current.st_ino != inode or current.st_uid != os.getuid() or not stat.S_ISLNK(current.st_mode):
                    raise RuntimeGuardError("Profile lock changed during inspection; preserving it.")
                path.unlink()  # Unlink the dedicated symlink, never its target.
                cleaned.append(f"{path.parent.name}/{path.name}")
        return {"status": "available", "stale_singletons": len(candidates), "cleaned": cleaned}

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def __exit__(self, *_):
        self.close()
