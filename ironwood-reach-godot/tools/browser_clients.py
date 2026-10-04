#!/usr/bin/env python3
"""Own two sandboxed headed candidate browsers; gameplay input stays OS-level.

Playwright observes networking/errors and controls browser navigation/viewport only. It
does not issue game commands, change game state, or read browser storage.
"""
import argparse
import atexit
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shlex
import signal
import stat
import tempfile
import time
from urllib.parse import parse_qs, urlparse
from build import build_id
from browser_runtime_guard import BrowserRuntimeLease, RuntimeGuardError, process_metadata
from tool_runtime import BUILDS, HARNESS, OWNER, RUNTIME, append_owned_log, now, owned_directory

RUN = RUNTIME / "browser-clients"
GPU_ARGS = ["--use-gl=angle", "--use-angle=gl", "--ignore-gpu-blocklist",
            "--gpu-sandbox-failures-fatal=yes"]
FORBIDDEN_FLAGS = {"--no-sandbox", "--disable-gpu-sandbox", "--disable-seccomp-filter-sandbox",
                   "--disable-setuid-sandbox", "--enable-unsafe-swiftshader", "--in-process-gpu"}
VIEWPORT_LIMITS = {"width": [640, 1920], "height": [480, 1080]}


def viewport_size(width, height):
    values = {"width": width, "height": height}
    for name, value in values.items():
        low, high = VIEWPORT_LIMITS[name]
        if type(value) is not int or not low <= value <= high:
            raise RuntimeError(f"Viewport {name} must be an integer from {low} to {high}.")
    return values


def safe(value):
    if isinstance(value, dict):
        return {key: safe(item) for key, item in value.items()
                if key.lower() not in {"token", "secret", "authorization", "session_key", "cookie", "cookies"}
                and not key.lower().endswith(("_token", "_secret"))}
    if isinstance(value, list):
        return [safe(item) for item in value]
    return value


def target(build=None, url=None):
    if url is None:
        if not build or not re.fullmatch(r"[A-Za-z0-9_-]+", build):
            raise RuntimeError("Candidate build identifier is invalid.")
        url = f"http://127.0.0.1:9088/{build}/index.html"
    parsed = urlparse(url)
    if (parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost")
            or parsed.port != 9088 or parsed.username or parsed.password or parsed.fragment):
        raise RuntimeError("Browser URLs must target our loopback HTTP9088 candidate service.")
    match = re.fullmatch(r"/([A-Za-z0-9_-]+)/index\.html", parsed.path)
    if not match:
        raise RuntimeError("URL must reference a candidate's index.html.")
    identifier = match.group(1)
    if build and build != identifier:
        raise RuntimeError("Requested build identifier does not match the URL.")
    for endpoint in parse_qs(parsed.query).get("server", []):
        server = urlparse(endpoint)
        if (server.scheme != "ws" or server.hostname not in ("127.0.0.1", "localhost")
                or server.port != 8775 or server.username or server.password
                or server.path not in ("", "/") or server.query or server.fragment):
            raise RuntimeError("A server query override must remain our loopback authority8775.")
    candidate = BUILDS / identifier
    marker = candidate / ".ironwood-build.json"
    if candidate.is_symlink() or not (candidate / "index.html").is_file() or not marker.is_file() or marker.is_symlink():
        raise RuntimeError("Candidate has not been exported through the owned build helper.")
    metadata = json.loads(marker.read_text())
    if metadata.get("owner") != OWNER or metadata.get("build_id") != identifier:
        raise RuntimeError("Candidate ownership cannot be verified.")
    from build import existing_candidate
    existing_candidate(candidate, identifier)
    return identifier, url


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=None)
    parser.add_argument("--url")
    parser.add_argument("--seconds", type=int, default=1800)
    parser.add_argument("--viewport-width", type=int, default=640)
    parser.add_argument("--viewport-height", type=int, default=820)
    parser.add_argument("--resize-owned", action="store_true", help="Request a viewport resize from this project's verified live helper")
    parser.add_argument("--client", type=int, choices=(1, 2), help="Resize only client 1 or 2; omitted means both")
    parser.add_argument("--fresh-profiles", action="store_true", help="Archive verified closed profiles before starting a clean trial")
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--stop-owned", action="store_true", help="Request only this project's verified browser helper to close its contexts")
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("--seconds must be positive.")
    try:
        viewport = viewport_size(args.viewport_width, args.viewport_height)
    except RuntimeError as error:
        parser.error(str(error))
    if sum((args.inspect_only, args.stop_owned, args.resize_owned, args.fresh_profiles)) > 1:
        parser.error("Choose one inspection, stop, resize, or fresh-profile mode.")
    if args.client is not None and not args.resize_owned:
        parser.error("--client applies only to --resize-owned.")
    build = args.build or (None if args.url else build_id())
    owned_directory(RUNTIME)
    owned_directory(RUN)
    logs = owned_directory(RUNTIME / "logs")
    control = RUN / "control.json"
    state_path = RUN / "state.json"
    lease = BrowserRuntimeLease(RUN, Path(__file__))
    try:
        lease.__enter__()
        startup = lease.prepare(cleanup=not (args.inspect_only or args.stop_owned or args.resize_owned or args.fresh_profiles))
        if args.fresh_profiles:
            target(build, args.url)  # Validate the candidate before archiving anything.
            archive = lease.archive_profiles()
            print(json.dumps(dict(archive, status="fresh_profiles", browser_data_read=False)), flush=True)
    except RuntimeGuardError as error:
        lease.close()
        print(json.dumps({"status": "blocked", "reason": str(error), "profiles_preserved": True}), flush=True)
        raise SystemExit(2)
    if args.resize_owned:
        lease.close()
        if startup["status"] != "reuse":
            print(json.dumps({"status": "not_running", "profiles_preserved": True}))
            return
        if not startup.get("capabilities", {}).get("viewport_control"):
            raise RuntimeError("The live helper predates viewport control; stop-owned and restart it first.")
        instruction = {"action": "viewport", **viewport}
        if args.client is not None:
            instruction["client"] = args.client
        with control.open("x") as request:
            request.write(json.dumps(instruction) + "\n")
        print(json.dumps(dict(instruction, status="resize_requested", pid=startup["pid"])), flush=True)
        return
    if args.stop_owned:
        lease.close()
        if startup["status"] != "reuse":
            print(json.dumps({"status": "not_running", "unknown_processes_preserved": True}))
            return
        pid = startup["pid"]
        original = process_metadata(pid)
        with control.open("x") as request:
            request.write(json.dumps({"action": "stop"}) + "\n")
        for _ in range(50):
            remaining = process_metadata(pid)
            if remaining is None:
                print(json.dumps({"status": "stopped", "pid": pid, "profiles_preserved": True}))
                return
            if original is None or remaining["start_ticks"] != original["start_ticks"]:
                print(json.dumps({"status": "owned_helper_exited", "pid_reused_preserved": True}))
                return
            time.sleep(0.1)
        print(json.dumps({"status": "stop_requested", "pid": pid, "contexts_closing": True}))
        return
    if startup["status"] == "reuse" or args.inspect_only:
        lease.close()
        print(json.dumps(dict(startup, requested_build=build, requested_url=args.url)), flush=True)
        return
    atexit.register(lease.close)
    build, url = target(build, args.url)
    if startup["cleaned"]:
        print(json.dumps({"status": "removed_stale_singletons", "names": startup["cleaned"]}), flush=True)
    from playwright.sync_api import sync_playwright
    environment = dict(os.environ, DISPLAY=":97", XAUTHORITY=str(HARNESS / "runtime/Xauthority"),
                       GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="0", GALLIUM_THREAD="0",
                       MESA_GLTHREAD="false", MESA_SHADER_CACHE_DISABLE="true")
    if not Path(environment["XAUTHORITY"]).is_file():
        raise RuntimeError("Start the authenticated cloud harness display :97 first.")
    for variable, folder in [("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
                             ("XDG_RUNTIME_DIR", "xdg-runtime")]:
        environment[variable] = str(owned_directory(RUN / folder))
    stop = False

    def request_stop(*_):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    streams = []
    contexts = []
    pages = []
    metadata = process_metadata(os.getpid())
    state = {"pid": os.getpid(), "owner_uid": os.getuid(), "process_start_ticks": metadata["start_ticks"],
             "owner": OWNER, "default_viewport": viewport, "viewport_limits": VIEWPORT_LIMITS,
             "capabilities": {"viewport_control": True, "fresh_profiles": True},
             "helper_path": str(Path(__file__).resolve()), "build": build, "url": url,
             "launch_cwd": str(Path.cwd()), "started_at": now(),
             "playwright": importlib.metadata.version("playwright"), "clients": []}

    def save_state():
        if state_path.is_symlink():
            raise RuntimeError("Preserving unexpected browser-state symlink.")
        if state_path.exists():
            current = state_path.stat()
            if current.st_uid != os.getuid() or not stat.S_ISREG(current.st_mode):
                raise RuntimeError("Preserving unknown browser-state ownership/type.")
        descriptor, name = tempfile.mkstemp(prefix="state-", suffix=".pending", dir=RUN)
        temporary = Path(name)
        try:
            with os.fdopen(descriptor, "w") as output:
                output.write(json.dumps(state, indent=2) + "\n")
            temporary.replace(state_path)
        finally:
            if temporary.exists():
                temporary.unlink()

    def navigate(identifier, address):
        from serve import ready
        ready(identifier)  # Verify served HTML/WASM and headers before loading.
        for number, page in enumerate(pages, 1):
            response = page.goto(address, wait_until="load", timeout=90000)
            page.bring_to_front()
            if response is None or response.status != 200:
                raise RuntimeError("Candidate HTTP navigation did not return200.")
            state["clients"][number - 1].update({"http_status": response.status,
                                                "url": page.url, "title": page.title()})
        state.update({"build": identifier, "url": address})
        save_state()

    try:
        with sync_playwright() as playwright:
            for number in (1, 2):
                logfile = logs / f"browser-client-{number}.jsonl"
                if logfile.is_symlink():
                    raise RuntimeError("Preserving unexpected browser log symlink.")
                stream = append_owned_log(logfile)
                streams.append(stream)

                def log(kind, data, stream=stream, number=number):
                    stream.write(json.dumps({"at": now(), "client": number, "kind": kind, "data": safe(data)}) + "\n")

                profile = RUN / f"profile-{number}"
                context = playwright.chromium.launch_persistent_context(
                    str(profile), executable_path="/usr/lib/chromium/chromium", headless=False,
                    chromium_sandbox=True, ignore_default_args=["--enable-unsafe-swiftshader"],
                    args=GPU_ARGS + [f"--window-size={viewport['width'] + 8},{viewport['height'] + 131}", f"--window-position={(number - 1) * 680},0",
                                     "--force-device-scale-factor=1"],
                    viewport=dict(viewport), env=environment,
                )
                contexts.append(context)
                page = context.new_page()
                for restored_page in context.pages:
                    if restored_page is not page:
                        restored_page.close()
                pages.append(page)
                page.on("console", lambda message, log=log: log("console", {"type": message.type, "text": message.text}))
                page.on("pageerror", lambda error, log=log: log("pageerror", {"message": str(error)}))

                def socket_opened(websocket, log=log):
                    log("websocket_open", {"url": websocket.url})

                    def frame(kind, payload):
                        try:
                            if isinstance(payload, bytes):
                                payload = payload.decode("utf-8")
                            data = json.loads(payload)
                        except (ValueError, UnicodeDecodeError):
                            data = {"unparsed_frame": True}
                        log(kind, data)

                    websocket.on("framesent", lambda payload: frame("websocket_sent", payload))
                    websocket.on("framereceived", lambda payload: frame("websocket_received", payload))
                    websocket.on("close", lambda: log("websocket_closed", {}))
                    websocket.on("socketerror", lambda error: log("websocket_error", {"message": str(error)}))

                page.on("websocket", socket_opened)
                page.goto("chrome://sandbox")
                sandbox_text = page.locator("body").inner_text()
                session = context.browser.new_browser_cdp_session()
                gpu = session.send("SystemInfo.getInfo")["gpu"]["auxAttributes"]
                browser = session.send("Browser.getVersion")["product"]
                processes = session.send("SystemInfo.getProcessInfo")["processInfo"]
                session.detach()
                command_page = context.new_page()
                command_page.goto("chrome://version")
                command = command_page.locator("#command_line").inner_text()
                command_page.close()
                actual_flags = {flag.split("=", 1)[0] for flag in shlex.split(command)}
                if actual_flags & FORBIDDEN_FLAGS:
                    raise RuntimeError("Refusing a browser with sandbox/security-disabling arguments.")
                if gpu.get("sandboxed") is not True:
                    raise RuntimeError("Refusing an unsandboxed GPU process.")
                gpu_security = []
                for process in processes:
                    if process["type"] == "GPU":
                        status = Path(f"/proc/{process['id']}/status").read_text()
                        fields = {line.split(":", 1)[0]: line.split(":", 1)[1].strip()
                                  for line in status.splitlines() if ":" in line}
                        if fields.get("NoNewPrivs") != "1" or fields.get("Seccomp") != "2":
                            raise RuntimeError("GPU namespace/seccomp protection is not demonstrated.")
                        gpu_security.append({"pid": process["id"], "NoNewPrivs": 1, "Seccomp": 2})
                if not gpu_security:
                    raise RuntimeError("No protected GPU process could be verified.")
                log("sandbox", {"text": sandbox_text, "gpu_sandboxed": True, "gpu_processes": gpu_security,
                                "browser": browser, "args": GPU_ARGS, "headed": True})
                state["clients"].append({"number": number, "profile": str(profile), "browser": browser,
                                         "gpu_sandboxed": True, "position": [(number - 1) * 680, 0],
                                         "viewport": dict(viewport), "profile_inode": profile.stat().st_ino,
                                         "profile_device": profile.stat().st_dev})
                save_state()
            navigate(build, url)
            print(json.dumps({"status": "ready", "pid": os.getpid(), "build": build,
                              "clients": 2, "headed": True, "gpu_sandboxed": True}), flush=True)
            deadline = time.monotonic() + args.seconds
            last_metadata = 0.0
            while not stop and time.monotonic() < deadline:
                if control.exists() or control.is_symlink():
                    if (control.is_symlink() or control.stat().st_uid != os.getuid()
                            or not stat.S_ISREG(control.stat().st_mode) or control.stat().st_size > 8192):
                        raise RuntimeError("Preserving unrecognized browser control file.")
                    instruction = json.loads(control.read_text())
                    if instruction.get("action") == "stop":
                        control.unlink()
                        break
                    if instruction.get("action") == "viewport":
                        if set(instruction) - {"action", "width", "height", "client"}:
                            raise RuntimeError("Unknown viewport control fields; file preserved.")
                        requested_size = viewport_size(instruction.get("width"), instruction.get("height"))
                        selected = instruction.get("client")
                        if selected is not None and (type(selected) is not int or selected not in (1, 2)):
                            raise RuntimeError("Viewport client must be 1 or 2; file preserved.")
                        control.unlink()
                        for number, page in enumerate(pages, 1):
                            if selected is None or selected == number:
                                page.set_viewport_size(requested_size)
                                state["clients"][number - 1]["viewport"] = dict(page.viewport_size)
                        save_state()
                        print(json.dumps({"status": "viewport_changed", "client": selected or "both", "viewport": requested_size}), flush=True)
                        continue
                    if instruction.get("action") != "navigate":
                        raise RuntimeError("Unknown browser control action; file preserved.")
                    requested = instruction.get("build", instruction.get("build_id"))
                    identifier, address = target(requested, instruction.get("url"))
                    control.unlink()
                    navigate(identifier, address)
                    print(json.dumps({"status": "navigated", "build": identifier}), flush=True)
                if time.monotonic() - last_metadata > 1:
                    for number, page in enumerate(pages):
                        state["clients"][number]["title"] = page.title()
                    save_state()
                    last_metadata = time.monotonic()
                pages[0].wait_for_timeout(200)
    finally:
        for context in reversed(contexts):
            try:
                context.close()
            except Exception:
                pass
        for stream in streams:
            stream.close()
        state["stopped_at"] = now()
        if state["clients"]:
            save_state()
        lease.close()


if __name__ == "__main__":
    main()
