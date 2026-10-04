# Reusable cloud capability harness

Each cloud task is already isolated. Use the existing selected checkout and this
separate harness; do not create a Git worktree unless the user requests one.
The fixture under `/tmp/ironwood-capability-probe` is disposable and is not the
Ironwood Reach game. Preserve the existing public prototype and unrelated files.

## Installation validated in this environment

```sh
bash /workspace/ironwood-cloud-harness/tools/install.sh
```

The script checks the verified existing image prerequisites: Godot
`4.6.3.stable.official.7d41c59c4`, Chromium `151.0.7922.173`, Python Playwright
`1.62.0`, Xorg, its dummy driver, XTEST/OpenGL runtime libraries, and FFmpeg.
It verifies the eight retained web templates through their checksum receipt,
generates only the recognized disposable v2 fixture, runs supplemental headless
checks, and exports into a new `runtime/install-validation/run-*/export` folder.
It preserves the played builds, logs, running services, and browsers.

Two executions passed. Their reports are consolidated in
`evidence/install-repeatability.json`; both reused verified templates without
network access. System dependency provisioning and fresh platform snapshot
restoration were not performed by these runs. Missing or changed image tools
cause a concrete diagnostic rather than a system configuration change.

The generator refuses selected repository paths, unrecognized nonempty output
folders, symlink targets, and changed fixture sources. Its marker records file
hashes. It recognizes only the known Godot project-file formatting/default
metadata normalization.

## Start or reuse owned services

```sh
python /workspace/ironwood-cloud-harness/tools/start_display.py
python /workspace/ironwood-cloud-harness/tools/start_probe_services.py --build-id v2
```

The display helper verifies its saved PID and exact command before reuse, uses
authenticated local X11 with TCP disabled, and preserves unknown sessions.
Services bind only loopback ports 9080 and 8765. Their helper verifies process
identity, preserves unknown live PIDs or occupied ports, and archives owned stale
metadata before a new start. The browser export must already exist in
`builds/probe-v2`; install validation exports are intentionally separate.

HTTP content and WASM MIME/hash checks and authority TCP reachability establish
service readiness. They do not establish browser joins or multiplayer behavior.

## Start interactive browsers

Inspect `runtime/browser-clients/state.json` and the actual saved process command
before launching another browser harness. Reuse an existing owned, active session
when appropriate. For a fresh session:

```sh
python /workspace/ironwood-cloud-harness/tools/run_browser_clients.py --build v2
```

Chromium sandbox namespaces require the platform's approved expanded execution
path when the restricted shell blocks them. Preserve browser, renderer, and GPU
sandboxes. Do not change host policy or add security-disabling switches. The
existing session demonstrated this launch path; a future platform restoration
must be checked against actual runtime evidence.

Gameplay input uses `desktop_input.py`; real display capture uses
`capture_display.py`. See `README-desktop-input.md`. Browser observations and
supplemental automated checks are separate from actual human feedback. Re-run the
required interactive/native/browser/multiplayer evidence when the runtime changes
instead of assuming saved instructions alone prove the gate.
