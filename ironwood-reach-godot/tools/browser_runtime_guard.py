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
import tempfile
from datetime import datetime, timezone


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
    saved_helper = saved_state.get("helper_path")
    if saved_helper is not None and Path(saved_helper).resolve() != helper_path.resolve():
        return False
    saved_ticks = saved_state.get("process_start_ticks")
    if saved_ticks is not None and saved_ticks != metadata["start_ticks"]:
        return False
    invoked = Path(argv[1])
    if invoked.is_absolute():
        if invoked.resolve() != helper_path.resolve():
            return False
    elif saved_state.get("launch_cwd"):
        if (Path(saved_state["launch_cwd"]) / invoked).resolve() != helper_path.resolve():
            return False
    elif (saved_helper is None or saved_ticks is None
          or invoked.parts != ("tools", helper_path.name)
          or helper_path.parent.name != "tools"):
        # Earlier project helpers recorded exact UID/start ticks/absolute helper
        # path, but not their cwd. Recognize only their documented tools/<name>
        # launch form; unfamiliar relative forms remain blocked.
        return False
    return saved_state.get("owner_uid", os.getuid()) == metadata["uid"]


def browsers_using_profiles(profiles):
    """Identify live processes with either exact user-data-dir argument.

    Process names can change; a relative profile is resolved against that
    process's cwd, rather than the cwd of this inspection command.
    """
    expected = {str(profile.resolve()) for profile in profiles}
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
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
            if profile is not None:
                candidate = Path(profile)
                if not candidate.is_absolute():
                    try:
                        candidate = entry.joinpath("cwd").resolve(strict=True) / candidate
                    except FileNotFoundError:
                        if process_metadata(entry.name) is None:
                            break
                        raise RuntimeGuardError("Cannot verify a live process's profile cwd; preserving profiles.")
                    except PermissionError as exc:
                        raise RuntimeGuardError("Cannot verify a live process's profile cwd; preserving profiles.") from exc
                resolved = str(candidate.resolve())
                if resolved in expected:
                    found.append({"pid": metadata["pid"], "profile": resolved})
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
            lease_stat = os.fstat(self.fd)
            if lease_stat.st_uid != os.getuid() or not stat.S_ISREG(lease_stat.st_mode):
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
        state_stat = state_path.stat()
        if state_stat.st_uid != os.getuid() or not stat.S_ISREG(state_stat.st_mode) or state_stat.st_size > 262144:
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
                "clients": len(state.get("clients", [])), "profiles_preserved": True,
                "capabilities": state.get("capabilities", {}),
                "viewports": [{"number": item.get("number"), "viewport": item.get("viewport")}
                              for item in state.get("clients", [])]}

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
            if profile.is_symlink() or (profile.exists() and (profile.stat().st_uid != os.getuid()
                                                             or not profile.is_dir())):
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

    def archive_profiles(self):
        """Archive identified, closed helper profiles without reading their data."""
        if self.fd is None or self.reuse is not None:
            raise RuntimeGuardError("Stop the owned helper before requesting fresh profiles.")
        if self.prepare(cleanup=False)["status"] != "available":
            raise RuntimeGuardError("Stop the owned helper before requesting fresh profiles.")
        existing = [profile for profile in self.profiles if profile.exists()]
        if not existing:
            return {"archived": [], "profiles_fresh": True}
        state = self._state()
        if (state.get("owner_uid") != os.getuid()
                or state.get("helper_path") != str(self.helper_path)):
            raise RuntimeGuardError("Previous helper ownership is unproven; preserving profiles.")
        clients = state.get("clients", [])
        expected = {number: str(profile) for number, profile in enumerate(self.profiles, 1)}
        recorded = {}
        for client in clients:
            if (not isinstance(client, dict) or type(client.get("number")) is not int
                    or client["number"] not in expected or client["number"] in recorded
                    or client.get("profile") != expected[client["number"]]):
                raise RuntimeGuardError("Recorded profile ownership is unproven; preserving profiles.")
            recorded[client["number"]] = client
        if set(recorded) != {1, 2}:
            raise RuntimeGuardError("Both prior profile records are required; preserving profiles.")
        identities = {}
        for number, profile in enumerate(self.profiles, 1):
            if not profile.exists():
                continue
            info = profile.lstat()
            if info.st_uid != os.getuid() or not stat.S_ISDIR(info.st_mode):
                raise RuntimeGuardError("A profile identity is unknown; preserving profiles.")
            if (recorded[number].get("profile_inode", info.st_ino) != info.st_ino
                    or recorded[number].get("profile_device", info.st_dev) != info.st_dev):
                raise RuntimeGuardError("A recorded profile was replaced; preserving it.")
            identities[profile] = (info.st_dev, info.st_ino)
        state_path = self.run_directory / "state.json"
        state_info = state_path.lstat()
        history = self.run_directory / "profile-history"
        for path in [history, *history.parents]:
            if path.is_symlink():
                raise RuntimeGuardError("Unexpected archive ancestor symlink; preserving profiles.")
        history.mkdir(mode=0o700, exist_ok=True)
        history_info = history.lstat()
        if history_info.st_uid != os.getuid() or not stat.S_ISDIR(history_info.st_mode):
            raise RuntimeGuardError("Archive directory ownership is unknown; preserving profiles.")
        destination = Path(tempfile.mkdtemp(prefix="profiles-", dir=history))
        moved = []
        try:
            # Preflight every directory before the first rename; recheck at each
            # rename too, because the lease excludes only cooperating helpers.
            if self._state() != state or state_path.lstat().st_ino != state_info.st_ino:
                raise RuntimeGuardError("Browser state changed before archive; preserving profiles.")
            for profile, identity in identities.items():
                if browsers_using_profiles(self.profiles):
                    raise RuntimeGuardError("A live profile user appeared; preserving its profile.")
                info = profile.lstat()
                if ((info.st_dev, info.st_ino) != identity or info.st_uid != os.getuid()
                        or not stat.S_ISDIR(info.st_mode)):
                    raise RuntimeGuardError("Profile changed before archive; preserving it.")
                profile.rename(destination / profile.name)
                moved.append(profile.name)
            if self._state() != state or state_path.lstat().st_ino != state_info.st_ino:
                raise RuntimeGuardError("Browser state changed during archive; preserving it.")
            state_path.rename(destination / "previous-state.json")
        except Exception as error:
            raise RuntimeGuardError(f"Profile archive preserved at {destination}; moved={moved}. {error}") from error
        marker = {"owner_uid": os.getuid(), "helper_path": str(self.helper_path),
                  "archived_at": datetime.now(timezone.utc).isoformat(), "profiles": moved,
                  "browser_data_read": False, "profiles_deleted": False}
        with (destination / "archive.json").open("x") as output:
            output.write(json.dumps(marker, indent=2) + "\n")
        return {"archived": moved, "archive_directory": str(destination), "profiles_fresh": True}

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def __exit__(self, *_):
        self.close()
