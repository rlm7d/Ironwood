#!/usr/bin/env python3
"""Own two headed browsers; gameplay input is sent separately through XTEST.

This helper observes WebSocket traffic and browser errors without calling game
functions or injecting game state. Browser profiles are independent. Reconnect
tokens are removed from observations. Run with approved expanded execution so
Chromium can create its own namespaces; all browser/GPU sandboxes stay enabled.
"""
import argparse
import atexit
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import time
from playwright.sync_api import sync_playwright
from browser_runtime_guard import BrowserRuntimeLease, RuntimeGuardError, process_metadata

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "runtime/browser-clients"
RUN.mkdir(parents=True, mode=0o700, exist_ok=True)
LOGS = ROOT / "logs"
CONTROL = RUN / "control.json"
STATE = RUN / "state.json"
GPU_ARGS = ["--use-gl=angle", "--use-angle=gl", "--ignore-gpu-blocklist",
            "--gpu-sandbox-failures-fatal=yes"]
ENVIRONMENT = dict(os.environ, DISPLAY=":97", XAUTHORITY=str(ROOT / "runtime/Xauthority"),
                   GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="0", GALLIUM_THREAD="0",
                   MESA_GLTHREAD="false", MESA_SHADER_CACHE_DISABLE="true",
                   XDG_CONFIG_HOME=str(RUN / "config"), XDG_CACHE_HOME=str(RUN / "cache"))
for name in ("config", "cache"):
    (RUN / name).mkdir(mode=0o700, exist_ok=True)

def safe(value):
    if isinstance(value, dict):
        return {key: safe(item) for key, item in value.items()
                if key.lower() not in ("token", "secret", "authorization", "session_key")}
    if isinstance(value, list):
        return [safe(item) for item in value]
    return value

def now():
    return datetime.now(timezone.utc).isoformat()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build", choices=("v1", "v2"), default="v1")
parser.add_argument("--seconds", type=int, default=1200)
parser.add_argument("--inspect-only", action="store_true", help="Check startup ownership without launching or cleaning browser profiles")
args = parser.parse_args()
lease = BrowserRuntimeLease(RUN, Path(__file__))
try:
    lease.__enter__()
    startup = lease.prepare(cleanup=not args.inspect_only)
except RuntimeGuardError as error:
    lease.close()
    print(json.dumps({"status": "blocked", "reason": str(error), "profiles_preserved": True}), flush=True)
    raise SystemExit(2)
if startup["status"] == "reuse" or args.inspect_only:
    lease.close()
    print(json.dumps(dict(startup, requested_build=args.build)), flush=True)
    raise SystemExit(0)
atexit.register(lease.close)
if startup["cleaned"]:
    print(json.dumps({"status": "removed_stale_singletons", "names": startup["cleaned"]}), flush=True)
stop = False
def request_stop(*_):
    global stop
    stop = True
signal.signal(signal.SIGTERM, request_stop)
signal.signal(signal.SIGINT, request_stop)

with sync_playwright() as playwright:
    contexts = []
    pages = []
    streams = []
    state = {"pid": os.getpid(), "owner_uid": os.getuid(),
             "process_start_ticks": process_metadata(os.getpid())["start_ticks"],
             "helper_path": str(Path(__file__).resolve()),
             "build": args.build, "started_at": now(), "clients": []}
    def navigate(build):
        for number, page in enumerate(pages, 1):
            response = page.goto(f"http://127.0.0.1:9080/probe-{build}/index.html", wait_until="load", timeout=90000)
            # A metadata-only title makes OS input targeting unambiguous.
            page.evaluate("title => { document.title = title; }", f"Probe Browser {number} - {build}")
            page.bring_to_front()
            state["clients"][number - 1]["http_status"] = response.status if response else None
            state["clients"][number - 1]["url"] = page.url
        state["build"] = build
        STATE.write_text(json.dumps(state, indent=2) + "\n")

    for number in (1, 2):
        stream = (LOGS / f"browser-client-{number}.jsonl").open("a", buffering=1)
        streams.append(stream)
        def log(kind, data, stream=stream, number=number):
            stream.write(json.dumps({"at": now(), "client": number, "kind": kind, "data": safe(data)}) + "\n")
        profile = RUN / f"profile-{number}"
        context = playwright.chromium.launch_persistent_context(
            str(profile), executable_path="/usr/lib/chromium/chromium", headless=False,
            chromium_sandbox=True, ignore_default_args=["--enable-unsafe-swiftshader"],
            args=GPU_ARGS + ["--window-size=670,960", f"--window-position={(number - 1) * 680},0",
                             "--force-device-scale-factor=1"],
            viewport={"width": 640, "height": 820}, env=ENVIRONMENT,
        )
        contexts.append(context)
        # These profiles belong solely to the capability harness. Session
        # restoration may create blank or old game tabs; retain one owned page.
        page = context.new_page()
        for restored_page in context.pages:
            if restored_page is not page:
                restored_page.close()
        pages.append(page)
        page.on("console", lambda message, log=log: log("console", {"type": message.type, "text": message.text}))
        page.on("pageerror", lambda error, log=log: log("pageerror", {"message": str(error)}))
        def socket_opened(socket, log=log):
            log("websocket_open", {"url": socket.url})
            def frame(kind, payload):
                try:
                    if isinstance(payload, bytes):
                        payload = payload.decode("utf-8")
                    data = json.loads(payload)
                except (ValueError, UnicodeDecodeError):
                    data = {"unparsed_frame": True}
                log(kind, data)
            socket.on("framesent", lambda payload: frame("websocket_sent", payload))
            socket.on("framereceived", lambda payload: frame("websocket_received", payload))
            socket.on("close", lambda: log("websocket_closed", {}))
            socket.on("socketerror", lambda error: log("websocket_error", {"message": str(error)}))
        page.on("websocket", socket_opened)
        page.goto("chrome://sandbox")
        sandbox_text = page.locator("body").inner_text()
        session = context.browser.new_browser_cdp_session()
        system = session.send("SystemInfo.getInfo")
        gpu = system["gpu"]["auxAttributes"]
        version = session.send("Browser.getVersion")
        session.detach()
        command_page = context.new_page()
        command_page.goto("chrome://version")
        command = command_page.locator("#command_line").inner_text()
        command_page.close()
        if "--no-sandbox" in command or "--disable-gpu-sandbox" in command or "--enable-unsafe-swiftshader" in command:
            raise RuntimeError("Refusing browser launch with a sandbox/security-disabling switch.")
        if not gpu.get("sandboxed"):
            raise RuntimeError("Refusing an unsandboxed GPU renderer.")
        log("sandbox", {"text": sandbox_text, "gpu_sandboxed": gpu.get("sandboxed"),
                        "browser": version["product"], "args": GPU_ARGS, "headed": True})
        state["clients"].append({"number": number, "profile": str(profile),
                                  "browser": version["product"], "gpu_sandboxed": True})

    navigate(args.build)
    print(json.dumps({"status": "ready", "pid": os.getpid(), "build": args.build, "clients": 2,
                      "headed": True, "gpu_sandboxed": True}), flush=True)
    deadline = time.monotonic() + args.seconds
    while not stop and time.monotonic() < deadline:
        if CONTROL.exists():
            command = json.loads(CONTROL.read_text())
            CONTROL.unlink()
            if command.get("action") == "navigate" and command.get("build") in ("v1", "v2"):
                navigate(command["build"])
                print(json.dumps({"status": "navigated", "build": state["build"]}), flush=True)
            elif command.get("action") == "stop":
                break
        # Dispatch observation events without blocking the tool/session for a long wait.
        pages[0].wait_for_timeout(200)
    for context in contexts:
        context.close()
    for stream in streams:
        stream.close()
