# Ironwood cloud development harness

This cloud session can run the Godot editor, a visible native game, and two independent headed browser clients with real mouse and keyboard input. The disposable fixture passed Gate 0. The selected Ironwood repository and existing public prototype were preserved.

Read [the evidence report](../ironwood-reach-godot/docs/GATE_0.md) and [independent review](../ironwood-reach-godot/docs/evidence/gate0/review/gate_0_review.md). These results concern the tiny capability fixture, not the intended battlefield or campaign.

## Environment settings

| Setting | Configuration and purpose |
| --- | --- |
| Install script | `bash /workspace/ironwood-cloud-harness/tools/install.sh` checks the pinned dependencies, verifies retained export templates, regenerates only the owned disposable fixture, and validates a separate web export. |
| Start skill | Start the authenticated virtual display and loopback services, then launch the two headed browsers through approved expanded execution. Inspect actual game frames and send XTEST input. |
| Internet access | Existing package-manager preset covers the GitHub release and package sources used. No custom domain expansion was needed. |
| Network secrets / environment variables | No new secrets or global environment variables are needed for this fixture. Graphics variables are scoped to the browser process. |

The configuration draft is separate from the installed filesystem and running processes. Review and save the draft in Environment settings, then **Publish** to capture the installed environment. A fresh published task has not been tested; it must recheck readiness and permissions. The helpers intentionally preserve unknown live processes and occupied ports.

## Verified startup

Run from an ordinary supported shell:

```sh
bash /workspace/ironwood-cloud-harness/tools/install.sh
python3 /workspace/ironwood-cloud-harness/tools/start_display.py
python3 /workspace/ironwood-cloud-harness/tools/start_probe_services.py --build-id v2
```

Launch this command through the supported execution tool with approved expanded execution:

```sh
python3 /workspace/ironwood-cloud-harness/tools/run_browser_clients.py --build v2 --seconds 1200
```

The standard restricted executor prevents Chromium from writing its own namespace mappings. The approved executor context permits them; Chromium still applies its namespace, seccomp, and GPU sandboxes. [Browser runtime details](tools/BROWSER_RUNTIME.md) document the tested flags and diagnostics. No machine security policy was changed.

Browsers are owned local cloud processes, each with an independent profile. They run on the authenticated Xorg dummy display `:97`, with display TCP disabled. Rendering uses Mesa llvmpipe. Browser navigation and passive WebSocket observation use Playwright; gameplay input uses OS XTEST events, and visuals come from the actual X11 display through FFmpeg capture. No native Codex computer-use tool is assumed or installed.

Discover current window IDs rather than reusing IDs from old evidence:

```sh
DISPLAY=:97 XAUTHORITY=/workspace/ironwood-cloud-harness/runtime/Xauthority xwininfo -root -tree
python3 /workspace/ironwood-cloud-harness/tools/desktop_input.py --help
python3 /workspace/ironwood-cloud-harness/tools/capture_display.py --help
```

Input requires an exact title match. Chromium titles use `_NET_WM_NAME`. For the recorded layout, the first browser's cube is around `(320,510)`; JOIN BUILDER is `(70,200)`, JOIN GENERAL `(190,200)`, REPLAY LAST `(65,235)`, DROP LINK `(175,235)`, and RECONNECT `(274,235)`, relative to the selected window. Reinspect layout before using these coordinates.

## Disposable fixture

The fixture is generated at `/tmp/ironwood-capability-probe`, outside the checkout. It uses Godot `4.6.3.stable.official.7d41c59c4`, matching `4.6.3.stable` export templates, GDScript, Compatibility, and a single-threaded web export. Native and browser controls: click the cube, D moves, Space toggles selection. Before joining, these are local actions. After joining, toy Builder moves right with D and toy General moves left with A; both may select. A missing seat pauses toy phase and rejects new actions. Replay retries the last command without duplicating an accepted mutation.

HTTP listens on loopback 9080; the separate Godot authority listens on loopback 8765. v1 rotates at one radian per second; v2 rotates at two. They have separate export paths and PCK hashes. These test-seat permissions, disconnect rules, and in-memory session state are deliberately disposable. They do not settle unresolved game design or prove authority state persistence across a server restart.

The source geometry is original. The Godot engine/export templates are upstream software, verified against the official release checksums. Generated game files, browser profiles, Xauthority, and runtime tokens should not be committed to GitHub. A portable source-only harness archive can be created from `tools/`, this README, and the license; actual installed dependencies remain part of the cloud environment snapshot.

## Why these harnesses

The useful parts of GitHub-hosted GUI harnesses are a virtual display, real input, capture, and browser orchestration. This environment already had Xorg and its dummy driver, so a small local harness was sufficient. [Xpra's Xdummy documentation](https://github.com/Xpra-org/xpra/blob/v6.3.3/docs/Usage/Xdummy.md) describes the same virtual display approach; [xdotool](https://github.com/jordansissel/xdotool/tree/v3.20211022.1) documents the XTEST input mechanism. The local helper uses the existing X11 libraries directly.

[Playwright](https://github.com/microsoft/playwright) manages the real headed browsers. [noVNC](https://github.com/novnc/noVNC) could add a human remote viewer, but it would also require an approved access/hosting arrangement; it was unnecessary for this agent's successful interaction proof. GitHub Actions could run a later regression workflow, but a CI pass alone would not establish the required interactive gate.

## Evidence limits

AI-driven live interaction and supplementary automated checks are recorded separately. No human feedback, intended-game performance, audio output, public WSS deployment, remote-device compatibility, balance, or fun is established. The full battlefield prototype remains to be built under the original design constraints after the environment setup. Its treasury/reservation and disconnect decisions must remain provisional until confirmed.
