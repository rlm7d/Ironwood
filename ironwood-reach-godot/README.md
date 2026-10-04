# Ironwood Reach — Godot battlefield trial

This is a **partial battlefield development candidate**, rebuilt as an isolated Godot project. Current `006` fixes dead/training selection and stale control groups, with a qualified real-browser retest of training click/drag and group recall after an actual casualty. Historical `005` real input verified economy/recovery, wide controls, ability tradeoffs and separate loss/victory trials. Territory rules, public hosting and battlefield approval remain pending; the campaign is deferred.

The existing [public Three.js prototype](https://ironwood-reach.rlm7d.chatgpt.site) is preserved. **This Godot candidate has no public URL.** Its loopback address works only in browsers running on the same machine as its services.

## Prerequisites and local startup

Use official **Godot 4.6.3**, exact version `4.6.3.stable.official.7d41c59c4`, with matching 4.6.3 web export templates; Python 3; and a browser supporting WebAssembly/WebGL 2.0. The game uses GDScript, Compatibility rendering and a single-threaded Web export. The cloud tools reuse the verified template receipt; elsewhere install matching official templates. Set `GODOT_BIN` if the executable is not on PATH.

Official Godot 4.6.3 notices for the included Web engine are bundled as [license](docs/third-party/Godot-LICENSE.txt), [copyright](docs/third-party/Godot-COPYRIGHT.txt) and [authors](docs/third-party/Godot-AUTHORS.md), with [source provenance](docs/third-party/provenance.json).

Run from this project folder:

```sh
python3 tools/build.py
python3 tools/run_server.py
python3 tools/serve.py --build battlefield-006
```

These owned service launchers are verified on Linux. The current generated Web
export is `builds/battlefield-006`; a handoff must include it with matching source. On another desktop,
import its source with the pinned engine, then run the authority and HTTP server
in separate foreground terminals:

```sh
godot --headless --path game --import
godot --headless --path game -- --server
python3 tools/serve.py --foreground
```

The import command finishes first; leave the last two commands running. Matching
export templates are needed to rebuild, rather than to run the included export.
These desktop foreground instructions have not been executed on Windows/macOS.

Open `http://127.0.0.1:9088/battlefield-006/index.html` in **two independent browser profiles** on that machine. One joins **Builder**, the other **General**; both press **Ready**. Two views/tabs of one client are insufficient verification. The authority uses `ws://127.0.0.1:8775`, with one in-memory room, `REACH-01`.

`build.py` reads the build ID from shared rules and records source/artifact hashes in `builds/<build-id>/build-manifest.json`. Unchanged candidates are reused; changed source triggers a guarded rebuild with prior owned artifacts retained. Unknown files/processes/occupied ports are preserved. See [tooling instructions](tools/README.md) for lifecycle checks and rebuild options.

For the configured cloud display and two dedicated headed clients:

```sh
python3 /workspace/ironwood-cloud-harness/tools/start_display.py
python3 tools/browser_clients.py --build battlefield-006 --seconds 1800
```

The second command may need the platform's approved expanded execution path to permit Chromium's own sandbox namespaces. It keeps browser/GPU sandboxes enabled. Its dedicated profiles are separate from the Gate 0 probe. Gameplay input uses the authenticated XTEST desktop helper; browser automation observes navigation/network/error events. This cloud helper requires the existing harness; ordinary desktop browsers do not.

To open Godot or run a native client on a local desktop:

```sh
godot --editor --path game
godot --path game
```

The cloud launch tools configure project-local writable XDG paths automatically. Direct Godot commands in the restricted cloud also need those bindings and authenticated display `:97`; use the launch tooling for the verified cloud workflow. Native success does not replace browser verification.

## Controls and trial rules

| Action | Control |
| --- | --- |
| Join/start | Join Builder / Join General; both press Ready |
| Select | Left-click; General can drag-select battalions; Shift adds selection |
| Move / attack-move / stop | General: right-click / A then left-click / S |
| Selection groups | Ctrl+1–9 assigns; 1–9 recalls |
| Camera | Arrow keys or middle-drag pan; wheel zooms; minimap click pans |
| Recenter | F centers selection; H returns to overview |
| Abilities | Q / E; select the applicable building or battalions |
| Cancel / help | Esc cancels selection/order mode; Controls opens help |
| Purchase | Builder selects a home-area fixed socket; General selects the barracks. Hold a purchase, then Confirm purchase or Cancel hold |
| Connection / retry | Disconnect pauses; Reconnect recovers the original seat; Retry last repeats the same command identity |

Historical `005` real input covers joining/readiness, both holds, cancel/confirm, disconnect, actual browser reload/rejoin, paid-command status/retry recovery, Shift selection, right-click movement/S stop, a settled 1280×820 browser viewport, minimap/middle-drag/arrows/wheel and Controls/Esc. Its separate ability cycle and win/loss evidence retain their build identity. Earlier `003` covered drag selection, Ctrl+1/1, A attack-move, F/H and terminal reconnect. Current `006` [focused real-input evidence](docs/evidence/006-agent-interactive.json) covers training click/drag exclusion, accepted eligible orders/Q, saved-group recall after a real casualty, and hold/pause/rejoin. Dead-visual click/drag remains automated-fixture coverage; its browser viewports were 640×820. The 640→1280→640 layout regression remains headless. See [verification](docs/VERIFICATION.md) and [open issues](docs/OPEN_ISSUES.md) for exact scopes.

Builder handles buildings/defenses; General recruits and commands battalions. Workers automatically collect and physically deliver from the secured home deposit. The trial has keep-based victory/defeat, representative raids and a proposed five-minute limit. The map, bindings, roster subset, costs, timings and original procedural assets remain approval proposals, not final tuning/art.

The owner approved **trial** shared gold and one visible purchase hold per player. Holds have no automatic expiry; manual confirmation charges/starts once; cancellation releases an unconfirmed hold; there is no post-confirmation refund. Missing either player pauses the whole simulation, retaining both seats and holds until that same player returns. These experiments do not finalize the campaign economy.

Unsecured expansion sockets remain unavailable. The owner requested territory like Brass Tactics; outpost-based capture was not approved. Home-only worker delivery does not establish that territory requirement.

## Tests, evidence and recovery limits

For simulation assertions:

```sh
python3 tools/check.py
```

`check.py` configures writable project-local Godot paths, checks the pinned engine, runs without starting services, and saves source-qualified [simulation evidence](docs/evidence/simulation.json). For each integration test, start a **fresh dedicated authority** in a separate terminal with `godot --headless --path game -- --server`, using writable project-local XDG bindings in the cloud, then run one of:

```sh
python3 tests/protocol_smoke.py --build battlefield-006 --output .runtime/protocol-smoke.json
godot --headless --path game --script "$PWD/tests/client_recovery.gd"
```

Protocol testing needs Python `websockets` (the recorded environment uses 16.0). These tests claim both seats; stop that dedicated foreground server with Ctrl+C and start a fresh one between tests and before browser play. Do not run them against a room being played, or stop an unknown process. The production-client recovery test uses narrowly scoped pending-state fixtures and is automated native integration, not browser input/localStorage proof.

Current `006` records identify tested source hashes: **136 simulation assertions**, [nine protocol families](docs/evidence/protocol-smoke.json), [32 native recovery assertions](docs/evidence/client-recovery.json), and [80 headless presentation assertions](docs/evidence/client-snapshot.json), with zero Godot errors and unchanged sources. Presentation includes actual 640→1280→640 headless resizing, synthetic tactical label fixtures, and 17 new selection checks. The [six pre-fix selection failures](docs/evidence/archive/battlefield-005/client-selection-prefix-failure.json) and original [63-check `005` report](docs/evidence/archive/battlefield-005/client-snapshot.json) remain archived. [Requirements](docs/REQUIREMENTS.md#automated-evidence-scope) describe fixture limits. Distinct group goals and the earlier [`004` typed-array failure](docs/evidence/archive/battlefield-004/client-snapshot-tooltip-type-failure.json) also retain their fix/retest history.

A separate [16-assertion `006` ability-effect supplement](docs/evidence/ability-effects.json) passes with zero failures/errors; it is additional to the 136 simulation assertions. Paired battles use normal purchases, ability commands, timed raids and combat steps, with explicit positions/stopped orders/high health to isolate hits. Shield incoming damage is 16 normally, 7 active, then 16 after expiry. Tower damage is 26 normally versus 44 overcharged, with 22 versus 12 ticks between shots; Shutdown has no hits for 100 ticks, then normal 26-damage fire resumes. This is automated combat evidence, not live protection/boost, multiplayer, balance or performance proof.

Historical `005` [browser-network evidence](docs/evidence/005-root-browser-network.json) qualifies real XTEST play with passive observation. Both holds totaled 190; a settled approximately 59-second comparison stayed frozen at tick 769. General's actual reload restored its seat/holds at sequence 2 on connection 4. Builder cancelled the 110 hold; General confirmed 80; a subsequent tower confirmation produced cumulative spent 190. Builder resumed on connection 5, looked up and replayed sequence 5's cached outcome, then continued with sequence 6 without another charge/site. **The original acknowledgment frame reached the browser observer before closure; this is not proof of an unseen or transport-lost acknowledgment.**

The [historical `005` ability/outcome record](docs/evidence/005-agent-interactive.json) qualifies main-keep defeat at tick 5817, before the 6000-tick limit, and separate victory at tick 4762. Actual Mending healed a tower and nearby battalion; Shield slowed movement; Overcharge was followed by Shutdown; March stopped keep damage until expiry. These samples do not isolate Shield damage protection or Overcharge damage/rate boosts. That play exposed training/dead selection; `006` filters click/drag/recall and outgoing commands, retaining server rejection for later death races. Its [focused browser retest](docs/evidence/006-agent-interactive.json) passes the changed training/group boundaries: click/drag excluded still-training unit 004; order/Q used ready units 001/002. After unit 001 died in ordinary combat at tick 1817, real group recall selected live unit 002; its subsequent right-click order contained only 002 and was accepted. Two holds totaling 190 also survived a tick-333 pause of at least 5.2 seconds and same-seat rejoin; General confirmed 80 once and Builder cancelled 110. Direct dead-visual click/drag remains automated only. Read [VERIFICATION.md](docs/VERIFICATION.md) for qualified results; this is agent-operated play with no human feedback or target-performance verdict.

Earlier `003` [victory evidence](docs/evidence/archive/battlefield-003/browser-play.json) remains historical: keep HP 1100→0, tick 1806, gold 370/spent 190/gathered 220, and 882 matching shared snapshots. Its [terminal reconnect](docs/evidence/terminal-browser-reconnect.json) retained the completed world. It does not certify a later changed build.

Actual `002` evidence separately records [pause with both holds retained](docs/evidence/interactive-pause.json), [refresh and same-seat recovery](docs/evidence/browser-refresh-recovery.json), and [committed purchases](docs/evidence/purchase-commits-baseline.json). Its [failed combat approach](docs/evidence/combat-approach-failure.json) led to the played `003` fix. Additional input/ability boundaries, human feedback, fun, balance, final visual approval, remote compatibility and target performance remain unverified.

The authority has no restart persistence, host migration or campaign saves. Disconnect/reconnect works within the same running room; restarting the authority loses it. Old seat tokens cannot recover a restarted room; use new dedicated profiles after an explicit trial-room reset. Storage failure/lost-token handling and other limits are listed in [OPEN_ISSUES.md](docs/OPEN_ISSUES.md).

## Design and next gate

Read [DESIGN.md](DESIGN.md), [rebuild instructions](CODEX_REBUILD_INSTRUCTIONS.md), [requirements](docs/REQUIREMENTS.md), [decisions](docs/DECISIONS.md), and [protocol](docs/PROTOCOL.md). Original artwork provenance is [recorded here](assets/source/PROVENANCE.md).

The earlier disposable [Gate 0 proof archive](docs/GATE_0.md) is separate from
this game's verification.

Milestone 1 remains partial: capture is unresolved, public hosting is unavailable and human battlefield approval has not occurred. Deliver the bounded playable battlefield and open issues, then obtain explicit approval before campaign work. Four missions, routes, research progression, perk drafts and permanent unlocks remain deferred confirmed obligations.

Public hosting requires a separate HTTPS asset candidate plus a persistent native authoritative service with secure WSS and actual deployed two-client checks. No public-deployment tool is available in the current session. Do not imply that the existing static/prototype host can run that backend. New spending, credentials/access, security/network changes and replacing the public prototype require approval.
