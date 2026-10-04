The working headed browser uses the authenticated local Xorg display `:97` and
the installed Chromium binary `/usr/lib/chromium/chromium`. The verified versions
are Chromium `151.0.7922.173` and Python Playwright `1.62.0`.

Run the supplementary readiness probe with the approved expanded execution tool:

```sh
python3 /workspace/ironwood-cloud-harness/tools/probe_sandboxed_browser.py \
  --ignore-gpu-blocklist \
  --url http://127.0.0.1:9080/probe-v1/index.html
```

The usual restricted shell has a read-only `/proc`, `NoNewPrivs=1`, and an outer
seccomp filter. Chromium cannot create its user-namespace mappings there.
The approved expanded execution context permits mappings; Chromium then installs
its own namespace and seccomp sandboxes. No machine policy is changed by this
helper.

Use these explicit launch options for subsequent headed clients:

```python
executable_path = "/usr/lib/chromium/chromium"
headless = False
chromium_sandbox = True
ignore_default_args = ["--enable-unsafe-swiftshader"]
args = [
    "--use-gl=angle", "--use-angle=gl", "--ignore-gpu-blocklist",
    "--gpu-sandbox-failures-fatal=yes",
]
```

Set these variables only for the launched browser process:

```text
GALLIUM_DRIVER=llvmpipe
LP_NUM_THREADS=0
GALLIUM_THREAD=0
MESA_GLTHREAD=false
MESA_SHADER_CACHE_DISABLE=true
```

Mesa's raster and shader-cache worker threads otherwise start before Chromium
initializes the GPU sandbox. Without fatal sandbox enforcement, this browser can
quietly run its GPU process without that sandbox. Disabling worker creation and
the disk shader cache allows normal sandbox initialization. This trades rendering
throughput and shader-cache reuse for the small proof fixture; it establishes no
game performance target.

`--ignore-gpu-blocklist` permits the Mesa CPU renderer while the browser and GPU
sandboxes remain enabled. The verified renderer is ANGLE over Mesa llvmpipe,
LLVM 19.1.7, OpenGL 4.5. WebGL2 and WebAssembly pass. The GPU process reports
`NoNewPrivs=1`, `Seccomp=2`, and Chromium's own GPU status reports `sandboxed=true`.
The helper refuses sandbox-disabling arguments, unsafe SwiftShader opt-in, missing
GPU sandbox protection, or missing WebGL2/WebAssembly.

Do not use `--gpu-sandbox-start-early` for this verified configuration: it prevented
ANGLE from opening the authenticated X display. Softpipe could not provide GLES3.
No SwiftShader fallback or display authentication relaxation was required.

Chromium's existing administrator policy blocked `data:` navigation. The proof
uses `about:blank` solely for a supplementary capability check and the explicitly
authorized HTTP loopback server for the Godot export; that URL returned HTTP 200.
Existing administrator policy remains in force.

Evidence is saved in `runtime/sandboxed-browser/probe-result.json`,
`chrome-sandbox.txt`, `chrome-sandbox.png`, `chrome-gpu.txt`, and `chrome-gpu.png`.
These runtime diagnostics do not complete Gate 0. Real game input, observable
animation, behavior repair/rebuild/retest, two independent client synchronization,
disconnect, and reconnect must still be demonstrated separately.

The two-client helper `run_browser_clients.py` now guards its dedicated profiles
before starting. If its own live helper already exists, it reports `reuse` and
preserves both clients. New helper state records the process start time, user ID,
and helper path to detect PID reuse. A lifecycle file lock prevents simultaneous
starts. Unknown live PIDs, active profile browsers, unfamiliar Singleton files,
or unknown ownership block startup without changing them.

For stale metadata from a stopped instance, the guard unlinks only the dedicated
profiles' `SingletonLock`, `SingletonSocket`, and `SingletonCookie` symlinks after
proving no live browser uses either profile. Symlink targets and profile storage
remain intact; cookie values are never read. `--inspect-only` checks ownership
without launching browsers or cleaning profiles.

Verified against the live two-client helper and isolated stale metadata: reuse,
six stale symlinks removed while targets remain, unknown live PID preserved,
concurrent startup blocked, and unknown regular Singleton file preserved. Results
are in `logs/browser-runtime-guard.json`. This verification did not start browsers
in a newly restored cloud environment.
