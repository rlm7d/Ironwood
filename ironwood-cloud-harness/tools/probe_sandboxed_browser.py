#!/usr/bin/env python3
"""Probe an actual headed Chromium while retaining Chromium's sandbox.

Run through the approved expanded execution tool when the restricted shell's
read-only /proc mapping prevents Chromium's user-namespace sandbox. This helper
does not modify operating-system policy, publish a listener, or disable browser
sandboxing. Its results supplement, and do not replace, the interactive Gate 0.
"""

import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import shlex
import signal
import time

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--display", default=":97")
    parser.add_argument("--hold-seconds", type=float, default=0)
    parser.add_argument("--ignore-gpu-blocklist", action="store_true",
                        help="Permit Mesa CPU rendering; the GPU sandbox remains required")
    parser.add_argument("--angle", choices=("gl", "gles", "vulkan"), default="gl")
    parser.add_argument("--url", help="Optional explicitly authorized local test URL")
    parser.add_argument("--sandbox-start-early", action="store_true")
    parser.add_argument("--mesa-driver", choices=("llvmpipe", "softpipe"), default="llvmpipe")
    parser.add_argument("--egl-platform", choices=("surfaceless",))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    runtime = root / "runtime" / "sandboxed-browser"
    runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in ("xdg-cache", "xdg-config", "xdg-runtime", "profile"):
        (runtime / name).mkdir(exist_ok=True, mode=0o700)
    browser_env = os.environ.copy()
    browser_env.update({
        "DISPLAY": args.display,
        "XAUTHORITY": str(root / "runtime" / "Xauthority"),
        "XDG_CACHE_HOME": str(runtime / "xdg-cache"),
        "XDG_CONFIG_HOME": str(runtime / "xdg-config"),
        "XDG_RUNTIME_DIR": str(runtime / "xdg-runtime"),
        "GALLIUM_DRIVER": args.mesa_driver,
        "LP_NUM_THREADS": "0",
        "GALLIUM_THREAD": "0",
        "MESA_GLTHREAD": "false",
        "MESA_SHADER_CACHE_DISABLE": "true",
    })
    if args.egl_platform:
        browser_env["EGL_PLATFORM"] = args.egl_platform
    evidence = {
        "playwright_version": importlib.metadata.version("playwright"),
        "display": args.display,
        "headed": True,
        "requested_chromium_sandbox": True,
        "renderer_environment": {
            name: browser_env[name] for name in (
                "GALLIUM_DRIVER", "LP_NUM_THREADS", "GALLIUM_THREAD",
                "MESA_GLTHREAD", "MESA_SHADER_CACHE_DISABLE",
            )
        },
        "gate_0_passed": False,
    }

    def stop_browser(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop_browser)
    try:
        with sync_playwright() as p:
            context = p.chromium.launch_persistent_context(
                str(runtime / "profile"),
                executable_path="/usr/lib/chromium/chromium",
                headless=False,
                chromium_sandbox=True,
                ignore_default_args=["--enable-unsafe-swiftshader"],
                args=[
                    "--use-gl=angle", f"--use-angle={args.angle}",
                    "--gpu-sandbox-failures-fatal=yes",
                ] + (["--gpu-sandbox-start-early"] if args.sandbox_start_early else [])
                  + (["--ignore-gpu-blocklist"] if args.ignore_gpu_blocklist else []),
                env=browser_env,
                viewport={"width": 1100, "height": 720},
            )
            try:
                evidence["chromium_version"] = context.browser.version
                page = context.pages[0] if context.pages else context.new_page()
                page.goto("chrome://version/", wait_until="domcontentloaded")
                command_line = page.locator("#command_line").inner_text()
                evidence["browser_command_line"] = command_line
                flags = shlex.split(command_line)
                forbidden = {
                    "--no-sandbox", "--disable-gpu-sandbox",
                    "--disable-seccomp-filter-sandbox", "--enable-unsafe-swiftshader",
                }
                present = sorted({f.split("=", 1)[0] for f in flags} & forbidden)
                if present:
                    raise RuntimeError(f"Unexpected unsafe browser arguments: {present}")
                evidence["no_sandbox_argument_absent"] = True
                evidence["unsafe_swiftshader_argument_absent"] = True
                page.goto("chrome://sandbox/", wait_until="domcontentloaded")
                sandbox_text = page.locator("body").inner_text()
                (runtime / "chrome-sandbox.txt").write_text(sandbox_text + "\n")
                evidence["chrome_sandbox_text"] = sandbox_text
                try:
                    page.screenshot(path=str(runtime / "chrome-sandbox.png"))
                except Exception as exc:
                    evidence.setdefault("screenshot_errors", []).append(str(exc))
                page.goto("chrome://gpu/", wait_until="domcontentloaded")
                page.wait_for_timeout(1500)
                gpu_text = page.evaluate(r"""() => {
                    function collect(node) {
                        if (node.nodeType === Node.TEXT_NODE) return node.textContent;
                        if (node.nodeType === Node.ELEMENT_NODE && ['STYLE', 'SCRIPT'].includes(node.tagName)) return '';
                        const children = node.shadowRoot ? node.shadowRoot.childNodes : node.childNodes;
                        return Array.from(children || [], collect).join('\n');
                    }
                    return collect(document.body);
                }""")
                (runtime / "chrome-gpu.txt").write_text(gpu_text + "\n")
                try:
                    page.screenshot(path=str(runtime / "chrome-gpu.png"))
                except Exception as exc:
                    evidence.setdefault("screenshot_errors", []).append(str(exc))
                evidence["gpu_diagnostics_file"] = str(runtime / "chrome-gpu.txt")
                cdp = context.browser.new_browser_cdp_session()
                gpu_info = cdp.send("SystemInfo.getInfo")["gpu"]
                gpu_attributes = gpu_info.get("auxAttributes", {})
                evidence["gpu_aux_attributes"] = {
                    name: gpu_attributes.get(name) for name in (
                        "sandboxed", "processCrashCount", "glImplementationParts",
                        "glVendor", "glRenderer", "glVersion", "inProcessGpu",
                    )
                }
                evidence["gpu_process_status"] = []
                for proc in cdp.send("SystemInfo.getProcessInfo")["processInfo"]:
                    if proc["type"] == "GPU":
                        status_path = Path("/proc") / str(proc["id"]) / "status"
                        evidence["gpu_process_status"].append({
                            "pid": proc["id"],
                            "status": [line for line in status_path.read_text().splitlines()
                                       if line.startswith(("NoNewPrivs:", "Seccomp:", "Seccomp_filters:"))],
                        })
                cdp.detach()
                if evidence["gpu_aux_attributes"].get("sandboxed") is not True:
                    raise RuntimeError("GPU process has not reported an enabled sandbox")
                if not evidence["gpu_process_status"] or not all(
                    "NoNewPrivs:\t1" in proc["status"] and "Seccomp:\t2" in proc["status"]
                    for proc in evidence["gpu_process_status"]
                ):
                    raise RuntimeError("GPU process is missing expected NoNewPrivs/seccomp protection")
                page.goto("about:blank", wait_until="domcontentloaded")
                page.set_content("<title>Cloud browser capability probe</title><body>Cloud browser capability probe: supplemental evidence only.</body>")
                evidence["capabilities"] = page.evaluate("""() => {
                    const canvas = document.createElement('canvas');
                    document.body.appendChild(canvas);
                    const gl = canvas.getContext('webgl2');
                    const debug = gl && gl.getExtension('WEBGL_debug_renderer_info');
                    const basicWasm = new Uint8Array([0,97,115,109,1,0,0,0]);
                    return {
                        webgl2: !!gl,
                        webglVersion: gl ? gl.getParameter(gl.VERSION) : null,
                        renderer: gl ? gl.getParameter(gl.RENDERER) : null,
                        unmaskedRenderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : null,
                        wasm: typeof WebAssembly === 'object' && WebAssembly.validate(basicWasm),
                        crossOriginIsolated: self.crossOriginIsolated,
                        viewport: {width: innerWidth, height: innerHeight},
                        userAgent: navigator.userAgent
                    };
                }""")
                if args.url:
                    response = page.goto(args.url, wait_until="domcontentloaded", timeout=20000)
                    evidence["local_http_navigation"] = {
                        "url": page.url,
                        "status": response.status if response else None,
                        "title": page.title(),
                    }
                if not evidence["capabilities"]["webgl2"] or not evidence["capabilities"]["wasm"]:
                    raise RuntimeError("WebGL2 and WebAssembly are required for the Godot browser probe")
                (runtime / "probe-result.json").write_text(json.dumps(evidence, indent=2) + "\n")
                print(json.dumps(evidence, indent=2), flush=True)
                if args.hold_seconds:
                    print(f"Browser remains open for {args.hold_seconds:g} seconds; evidence: {runtime}", flush=True)
                    deadline = time.monotonic() + args.hold_seconds
                    while time.monotonic() < deadline:
                        page.wait_for_timeout(250)
            finally:
                context.close()
    except Exception as exc:
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        (runtime / "probe-result.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence, indent=2), flush=True)
        raise


if __name__ == "__main__":
    main()
