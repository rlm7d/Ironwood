# Ironwood Reach Gate 0: PASS

Recorded 4 October 2026 UTC. This definitive report supersedes the [initial BLOCKED inspection](/workspace/ironwood-reach-gate0/docs/evidence/gate_0.md). Seven mandatory checks passed for a disposable Godot fixture. The intended battlefield prototype has not been built or approved.

Testing was agent-driven visual interaction through real OS mouse/keyboard events, with independent AI review of actual recorded frames and logs. Automated self-checks and passive evidence parsing are supplementary. Human play and feedback: **NOT RUN**.

## Environment and build identity

- Debian GNU/Linux 13.6, cloud environment; authenticated local Xorg display `:97`. This does not control the user's personal desktop.
- Godot `4.6.3.stable.official.7d41c59c4`; `/usr/local/bin/godot` resolves to `/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64`. GDScript, Compatibility renderer, single-threaded Web export, WebGL 2.0.
- Matching `4.6.3.stable` web export templates were extracted from the official SHA-512-verified archive. Version, archive checksum, source URL, and retained-template hashes are in [the receipt](/workspace/ironwood-cloud-harness/runtime/web-templates-receipt.json); [cache verification](/workspace/ironwood-cloud-harness/evidence/template-cache-verification.json) confirms the retained templates after archive cleanup.
- Headed Chromium `151.0.7922.173`, executable `/usr/lib/chromium/chromium`; Python Playwright `1.62.0`. Independent main browser PIDs `8872`/`9027` used distinct `profile-1`/`profile-2` directories. Namespace/seccomp and GPU sandboxes were enabled. Rendering used ANGLE/Mesa llvmpipe, LLVM 19.1.7; no target-game performance claim follows.
- Input used `libXtst` XTEST on the authenticated display, not injected game functions/state. FFmpeg captured the actual desktop at 12 fps, 1364×1024. Playwright launched/navigated browsers and passively observed WebSockets/errors; its title change was metadata only.
- Disposable scene: `/tmp/ironwood-capability-probe`. HTTP: `http://127.0.0.1:9080/probe-v1/index.html` and `/probe-v2/index.html`. Native authoritative Godot server: loopback WebSocket port `8765`.

The fixture's rules are explicitly **toy policy**, not accepted Ironwood design: Builder moves right, General moves left, either can toggle selection, and a missing seat pauses shared animation/actions. It has no economy, campaign, final controls, art, or authority-state persistence. The existing public prototype and unrelated checkout remain intact.

SHA-256 build identities:

```text
v1 index.pck: 81cd77b46c5c1aa0f505c189266751ba704e61cfcceacb5be5df15f4b609b3cb
v2 index.pck: c20106f0c0128075ddfba3c1d2e02be3b167fe65597f7ef29f53a3f1592552d7
both index.wasm: 26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6
```

The PCK changed while the engine WASM remained the same. Both browser addresses and visible labels changed to v2; cached v1 output was not treated as a retest.

## Seven required checks

| Check and expected result | Status | Observed result and evidence |
| --- | --- | --- |
| 1. Launch Godot GUI and see the correct running scene | PASS | [Native v1 recording](/workspace/ironwood-cloud-harness/evidence/native-v1-input.mp4), 8 seconds/96 frames, shows the correct labeled running scene. Supplemental [editor inspection](/workspace/ironwood-cloud-harness/evidence/editor-v2-scene-inspected.png) shows actual Godot menus, `main.tscn`, `CapabilityProbe`, Compatibility and 4.6.3; XTEST clicks inspected the scene. The earlier project-manager-ready image was only a splash and is not used as editor-readiness proof. |
| 2. Real mouse/keyboard input; observe movement and animation over time | PASS | Native click, D, Space events occur inside the recording. Selection color changes; x moves to 0.35; actions advance 0→2→3. Recorded cube/sphere orientation and angle continue changing. |
| 3. Serve web export; repeat interactions in a real browser | PASS | [Successful v1 browser recording](/workspace/ironwood-cloud-harness/evidence/browser-v1-interactive.mp4), 14 seconds/167 frames, shows actual HTTP browsers, click/D/Space effects and animation. HTML/WASM requests succeeded. |
| 4. Deliberate behavior change, rebuild/re-export, reload and same-input retest | PASS | Spin rate changed 1→2. [V2 browser recording](/workspace/ironwood-cloud-harness/evidence/browser-v2-interactive.mp4), 20 seconds/240 frames, shows v2/rate2 in both windows; both repeat click/D/Space successfully. In the inactive right browser, recorded angle advances 195.08→196.14 over one second in v1 versus 160.23→162.29 in v2, corroborated by visibly changing cube/sphere orientation. This is an observed behavior change, not a performance benchmark. |
| 5. Two independent browser seats act on shared authoritative state | PASS | Builder/General initially receive connection IDs 1/2. Both perform actions and visibly share results. Latest snapshots match at 1,204/1,204 common ticks before 02:00 UTC; after v2 reload they match at 135/135 common ticks from 02:00:48 through 02:02:30 UTC. V2 connections 6/7 restore sequences 4/2, then shared actions advance 5→8. |
| 6. Disconnect, declared pause, same-seat recovery and no lost/double prior command | PASS | [V1 reconnect recording](/workspace/ironwood-cloud-harness/evidence/browser-v1-reconnect.mp4), 18 seconds/216 frames, covers the full sequence. General 2→4 recovers sequence1. During absence, 60 Builder snapshots preserve phase/actions3/x0; a move returns `paused`. Retrying accepted commands returns `replayed_applied` without mutation; new commands advance actions to5. V2 additionally records 81 paused snapshots at actions8, General 7→8 recovers sequence3, retry leaves8, and new actions reach10; 80 common subsequent ticks match. See [v2 checks](/workspace/ironwood-cloud-harness/evidence/browser-v2-reconnect-checks.json) and [reconnected view](/workspace/ironwood-cloud-harness/evidence/browser-v2-reconnected.png). |
| 7. Changed-build check in both clients; inspect consoles/server logs | PASS | Both v2 clients retain real input, animation, authoritative convergence and duplicate-safe commands. Redacted [browser 1](/workspace/ironwood-cloud-harness/evidence/gate-browser-client-1.jsonl), [browser 2](/workspace/ironwood-cloud-harness/evidence/gate-browser-client-2.jsonl), [authority](/workspace/ironwood-cloud-harness/evidence/gate-authority.log), and [input trace](/workspace/ironwood-cloud-harness/evidence/gate-desktop-events.jsonl) support the observations. Warnings and limitations are retained below. |

Exact input sequence: native window `0x200003`, title `Ironwood Disposable Capability Probe (DEBUG)`, click `(480,335)`, D, Space. Browser windows `0x200003`/`0xc00003`, title `Ironwood Disposable Capability Probe - Chromium`: cube click `(320,510)`, D, Space; JOIN Builder `(70,200)` / JOIN General `(190,200)`; shared cube click and D/A; REPLAY LAST `(65,235)`; DROP LINK `(175,235)`; RECONNECT `(274,235)`; replay and fresh D/A. Key holds were 0.08 seconds. Full timestamped arguments are in the input trace. For example:

```bash
python3 /workspace/ironwood-cloud-harness/tools/desktop_input.py click --window 0x200003 --title 'Ironwood Disposable Capability Probe - Chromium' 320 510
python3 /workspace/ironwood-cloud-harness/tools/desktop_input.py key --window 0x200003 --title 'Ironwood Disposable Capability Probe - Chromium' d
```

Snapshot counts compare the latest observation at each common tick: immediate command broadcasts can produce multiple states within a tick. [Independent review](/workspace/ironwood-cloud-harness/evidence/review/gate_0_review.md), [machine-readable conditions](/workspace/ironwood-cloud-harness/evidence/review/gate_0_checks.json), and extracted recording frames preserve the bounded comparisons.

## Repairs, startup and limitations

Initial graphical/browser failures were repaired with an authenticated local Xorg display, writable runtime paths and approved expanded execution allowing Chromium to create its own sandbox namespaces. Browser/GPU sandboxes stayed enabled; Mesa worker/cache settings prevented pre-sandbox worker creation. The first `browser-v1-input.mp4` attempt failed its window-title guard and is not successful-input evidence. The actual browser title was inspected, the guarded input target corrected, and the later `browser-v1-interactive.mp4` sequence succeeded.

`browser-v2-reconnect.mp4` is 12 seconds and covers disconnect/pause only. Its recording ends before the reconnect inputs; the later PNG, XTEST trace, passive snapshots and server log support that reconnect. The complete continuous reconnect recording is v1.

Owned HTTP/server processes were stopped and recreated. [Cold-start check](/workspace/ironwood-cloud-harness/evidence/services-cold-start-check.json) reports new PIDs12848/12849, served HTML/WASM matching exports, `application/wasm`, and TCP readiness. Subsequent actual XTEST joins create a **fresh** room with IDs2/3, sequences0, and D/A produces two actions visible in [startup-new-room.png](/workspace/ironwood-cloud-harness/evidence/startup-new-room.png) and the current logs. This supplements startup readiness; it does not prove server-state persistence or a fresh published-environment restore.

Warnings: native/editor VSync unsupported; ALSA audio unavailable with dummy-driver fallback; editor auxiliary Vulkan extension `VK_KHR_surface` unavailable while Compatibility UI works; v1 favicon HTTP404; FFmpeg shared-memory capture denied with successful ordinary-X11 fallback. No gameplay JavaScript or WebSocket errors were observed in the reviewed interaction windows.

The final two-browser launcher was also restarted after adding runtime ownership/profile guards. Its first restart exposed a restored blank tab hiding browser 1 despite successful HTTP navigation. The launcher now creates one owned game page per dedicated profile, closes restored tabs, and brings the intended page forward. The retest visibly showed both games, restored seats on connections 4/5 with sequence 1, and applied real D/A commands to reach four shared actions. [Startup retest](/workspace/ironwood-cloud-harness/evidence/browser-startup-retest.json) records 313 matching common ticks, enabled GPU sandboxes and no page/WebSocket errors; [recording](/workspace/ironwood-cloud-harness/evidence/browser-restart-input.mp4) covers those actual inputs. This verifies browser process restart in the current instance, not platform snapshot restoration.

The [install repeatability report](/workspace/ironwood-cloud-harness/evidence/install-repeatability.json) records two successful setup runs with browser-tested v2 artifact hashes preserved. The install script and startup instructions are saved in the environment draft and the user chose to keep them in the required [configuration review](/workspace/ironwood-cloud-harness/evidence/environment-config-review.json). Backend readback matches both saved fields. Publication remains a user action in Environment settings.

Automated disposable self-checks cover pause/resume, role permissions, accepted-command replay/conflict and sequence continuity. They do not replace the visual input proof. No intended-game implementation/approval, audible output, public endpoint/WSS, remote-device/network interoperability, target-game performance, balance, fun or human feedback is established. Runtime cookies, seat tokens, profiles and PIDs are not durable setup configuration.

Next milestone: publish the reusable environment configuration, then build only the bounded battlefield approval prototype under the confirmed design. Resolve its provisional economy and disconnect consequences before implementing material unresolved rules. Stop for user approval before campaign expansion.
