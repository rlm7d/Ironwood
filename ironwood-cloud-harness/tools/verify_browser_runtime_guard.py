#!/usr/bin/env python3
"""Exercise runtime ownership using the live clients and isolated stale metadata.

This does not launch a browser, change live profiles, read cookies, or send input.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import socket
import tempfile

from browser_runtime_guard import BrowserRuntimeLease, RuntimeGuardError, browsers_using_profiles


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "runtime/browser-clients"
HELPER = ROOT / "tools/run_browser_clients.py"
evidence = {"at": datetime.now(timezone.utc).isoformat(), "browser_launches": 0,
            "live_profiles_modified": False, "secret_values_read": False}
with BrowserRuntimeLease(RUN, HELPER) as lease:
    evidence["live_helper"] = lease.prepare(cleanup=False)
evidence["live_profile_process_count"] = len(browsers_using_profiles(
    [RUN / "profile-1", RUN / "profile-2"]))

scratch = Path(tempfile.mkdtemp(prefix="guard-proof-", dir=RUN))
try:
    profiles = [scratch / "profile-1", scratch / "profile-2"]
    for profile in profiles:
        profile.mkdir(mode=0o700)
    stale_pid = 999999999
    if Path("/proc", str(stale_pid)).exists():
        raise RuntimeError("Synthetic stale PID unexpectedly exists")
    target = scratch / "synthetic-target"
    target.write_text("Synthetic metadata fixture; no credential values.\n")

    def make_singletons():
        for profile in profiles:
            (profile / "SingletonLock").symlink_to(f"{socket.gethostname()}-{stale_pid}")
            (profile / "SingletonSocket").symlink_to(target)
            (profile / "SingletonCookie").symlink_to(target)

    def singleton_inodes():
        return {(profile.name, name): (profile / name).lstat().st_ino
                for profile in profiles for name in
                ("SingletonLock", "SingletonSocket", "SingletonCookie")}

    make_singletons()
    (scratch / "state.json").write_text(json.dumps({"pid": stale_pid, "build": "v2"}))
    with BrowserRuntimeLease(scratch, HELPER) as lease:
        result = lease.prepare()
    if result["status"] != "available" or len(result["cleaned"]) != 6 or not target.exists():
        raise RuntimeError("Stale cleanup did not preserve symlink targets")
    evidence["isolated_stale_cleanup"] = {"cleaned_count": len(result["cleaned"]),
                                          "symlink_targets_preserved": target.exists()}

    make_singletons()
    before = singleton_inodes()
    (scratch / "state.json").write_text(json.dumps({"pid": os.getpid(), "build": "v2"}))
    try:
        with BrowserRuntimeLease(scratch, HELPER) as lease:
            lease.prepare()
    except RuntimeGuardError:
        if singleton_inodes() != before:
            raise RuntimeError("Unknown live PID changed profile metadata")
    else:
        raise RuntimeError("Unknown live PID was not blocked")
    evidence["unknown_live_pid"] = {"blocked": True, "all_six_singletons_preserved": True}

    (scratch / "state.json").write_text(json.dumps({"pid": stale_pid, "build": "v2"}))
    with BrowserRuntimeLease(scratch, HELPER):
        try:
            with BrowserRuntimeLease(scratch, HELPER):
                raise RuntimeError("Concurrent startup unexpectedly acquired the same lease")
        except RuntimeGuardError:
            pass
    evidence["concurrent_startup_lease"] = {"second_startup_blocked": True}

    cookie = profiles[0] / "SingletonCookie"
    cookie.unlink()
    cookie.write_text("Synthetic non-symlink fixture; preserve unknown files.\n")
    cookie_inode = cookie.lstat().st_ino
    try:
        with BrowserRuntimeLease(scratch, HELPER) as lease:
            lease.prepare()
    except RuntimeGuardError:
        if cookie.lstat().st_ino != cookie_inode:
            raise RuntimeError("Unknown Singleton file changed")
    else:
        raise RuntimeError("Unknown Singleton file was not blocked")
    evidence["unknown_singleton_file"] = {"blocked": True, "file_preserved": True}
finally:
    shutil.rmtree(scratch)

evidence["fresh_environment_browser_start"] = "not tested by this metadata verification"
(ROOT / "logs/browser-runtime-guard.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence, indent=2))
