#!/usr/bin/env python3
"""Start an authenticated, local-only disposable Xorg display for cloud checks."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime"
RUNTIME.mkdir(mode=0o700, exist_ok=True)
RUNTIME.chmod(0o700)
LOGS = ROOT / "logs"
LOGS.mkdir(exist_ok=True)
DISPLAY = ":97"
AUTH = RUNTIME / "Xauthority"
STATE = RUNTIME / "display.json"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reuse-only", action="store_true")
args = parser.parse_args()

def command_for(logfile):
    return ["Xorg", DISPLAY, "-noreset", "-nolisten", "tcp", "-auth", str(AUTH),
            "-logfile", str(logfile)]

def actual_command(pid):
    try:
        data = Path(f"/proc/{pid}/cmdline").read_bytes()
    except FileNotFoundError:
        return None
    except PermissionError:
        raise SystemExit("Cannot verify the saved display PID; preserving it.")
    return [part.decode() for part in data.split(b"\0") if part] or None

if STATE.exists():
    state = json.loads(STATE.read_text())
    saved = state.get("command", [])
    if (state.get("display") != DISPLAY or state.get("xauthority") != str(AUTH)
            or len(saved) != 9 or Path(saved[-1]).parent != LOGS
            or not Path(saved[-1]).name.startswith("xorg")
            or saved != command_for(Path(saved[-1]))):
        raise SystemExit("Preserving unexpected display metadata.")
    actual = actual_command(int(state["pid"]))
    if actual and (actual[0] not in ("Xorg", "/usr/lib/xorg/Xorg") or actual[1:] != saved[1:]):
        raise SystemExit("Saved display PID identifies an unexpected process; preserving it.")
    env = dict(os.environ, DISPLAY=DISPLAY, XAUTHORITY=str(AUTH))
    check = subprocess.run(["xdpyinfo", "-display", DISPLAY], env=env, capture_output=True, text=True)
    if actual and check.returncode == 0:
        print(json.dumps({"status": "already_running", "display": DISPLAY, "pid": state["pid"]}))
        raise SystemExit(0)
    if actual:
        raise SystemExit("Our existing display process is not ready; preserving it for diagnosis.")

if args.reuse_only:
    raise SystemExit("No verified ready display; --reuse-only leaves processes and authentication unchanged.")

if Path("/tmp/.X97-lock").exists() or Path("/tmp/.X11-unix/X97").exists():
    raise SystemExit("Display :97 is occupied; preserving the existing server.")

if AUTH.exists() and AUTH.stat().st_size and not STATE.exists():
    raise SystemExit("Preserving unrecognized existing display authentication; no owned metadata found.")
if STATE.exists():
    history = RUNTIME / "metadata-history"
    history.mkdir(exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    with (history / (STATE.name + "." + stamp)).open("xb") as backup:
        backup.write(STATE.read_bytes())
    STATE.unlink()

AUTH.touch(mode=0o600, exist_ok=True)
AUTH.chmod(0o600)
subprocess.run(
    ["xauth", "-f", str(AUTH)],
    input=f"add {DISPLAY} MIT-MAGIC-COOKIE-1 {secrets.token_hex(16)}\n",
    text=True, check=True, capture_output=True,
)
logfile = LOGS / "xorg.log"
if logfile.exists():
    logfile = LOGS / ("xorg-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".log")
cmd = command_for(logfile)
with (LOGS / "xorg-launch.log").open("a") as output:
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                            start_new_session=True)
env = dict(os.environ, DISPLAY=DISPLAY, XAUTHORITY=str(AUTH))
for _ in range(30):
    if proc.poll() is not None:
        print((LOGS / "xorg-launch.log").read_text())
        raise SystemExit(proc.returncode or 1)
    check = subprocess.run(["xdpyinfo", "-display", DISPLAY], env=env, capture_output=True, text=True)
    if check.returncode == 0:
        state = {"pid": proc.pid, "display": DISPLAY, "xauthority": str(AUTH), "command": cmd}
        with STATE.open("x") as saved:
            saved.write(json.dumps(state, indent=2) + "\n")
        dimensions = re.search(r"dimensions:\s+([^\n]+)", check.stdout)
        print(json.dumps({"status": "ready", "display": DISPLAY, "pid": proc.pid,
                          "dimensions": dimensions.group(1).strip() if dimensions else None,
                          "tcp": "disabled", "authentication": "MIT-MAGIC-COOKIE-1"}))
        break
    time.sleep(0.1)
else:
    proc.terminate()
    raise SystemExit("Xorg did not become ready; inspect logs/xorg.log.")
