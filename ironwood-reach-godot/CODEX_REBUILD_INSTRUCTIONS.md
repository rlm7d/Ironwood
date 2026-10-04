# Ironwood Reach Godot rebuild instructions

Prepared 4 October 2026. This is a portable implementation brief for a future Codex task. It does not report a completed Godot rebuild or grant permission to begin work merely because the file is present. The user starts the task by sending the kickoff in `START_HERE.txt` or equivalent instructions.

## The assignment

Rebuild Ironwood Reach from scratch in Godot, following the accompanying `DESIGN.md`. Deliver a real, interactive, browser-playable cooperative game through small, verified increments. Keep the current public prototype intact. Start with proof that the actual development environment can launch, interact with, observe, change, and retest Godot gameplay. Then make the bounded map, camera, controls, visual direction, and co-op approval prototype. Stop for user approval before expanding into the campaign.

The design describes the intended game. These instructions describe the execution and verification contract. Read both in full before scaffolding the game. Do not collapse the intended game into whatever is easiest to implement, and do not present an attractive render or a passing simulation as proof that the actual game plays well.

### Source of truth and decisions

1. Follow the user's latest explicit instructions and the receiving environment's applicable safety and repository instructions.
2. Preserve every explicit game decision in `DESIGN.md`. Record a conflict or missing material decision and ask the user before implementing the disputed part.
3. Keep source facts, accepted decisions, proposed defaults, and unresolved choices separate. A proposal in the design is not an approved fact.
4. Use old prototype code and tests, if provided, as reference material and regression examples. They are not authority to reintroduce rejected design, and their previous results do not certify the new implementation.
5. You may make ordinary, reversible implementation choices that do not change the game. Ask before material changes to combat, economy, progression, art direction, controls, co-op responsibilities, campaign scope, target platforms, or services.
6. Keep a requirement matrix linking each design requirement to implementation files, checks, and current status. Never silently drop a requirement because it is inconvenient.

Protect these confirmed decisions in the requirement matrix:

- Shared-faction Builder/General co-op; free movement on a fully visible genuine 3D map; fixed construction sockets; automatic gathering after territory is secured.
- Four missions per run: three standard missions, then the same exceptionally difficult boss for every route. Fresh base/army each mission; purchased research resets each mission. Mission duration target: 15–20 minutes.
- Three route columns; start in any column and thereafter remain or move one adjacent column. Disclose major threats before entry.
- Base destruction or required-objective failure ends the run, with no mission retry and no retained run perks.
- After each standard mission, each role independently chooses one of three distinct free major perks. After boss victory, each player independently chooses one of three permanent unlocks; both enter the shared future availability pool. Unlocks add options rather than free starting power.
- Two active ability slots per role, cooldowns/positioning/tradeoffs, and no initial separate energy meter. Standard troops use battalions; distinctive large units are individual entities.
- Original expressive miniature medieval-fantasy art. Prototype visuals, exact controls, roster statistics, group counts, and the shared treasury/per-player reservation proposal remain subject to approval.

Do not promote the suggested 4–6 soldiers or 8–12 groups into locked limits, or turn illustrative abilities into a final list. A practice reset does not change campaign failure rules.

## First response and inspection

Before editing, give a short response stating the first deliverable and any real blocker. Inspect the selected project folder, `AGENTS.md` files, existing files, dependencies, and dirty worktree. Do not overwrite unrelated work or initialize a new project inside the live prototype by accident.

Keep a short `PLAN.md` with the goal, constraints, next milestone, observable acceptance checks, stopping condition, and material open questions. Ask only questions needed for that milestone. Record the isolated working location and preserve the [current public prototype](https://ironwood-reach.rlm7d.chatgpt.site).

If original project files or art are not included, say so and continue only where the design is sufficient. Do not assume that private paths or cloud workspaces from an earlier session exist on the user's computer. This package must work as a standalone handoff.

## Gate 0 Prove the interactive workflow before the rebuild

This gate is mandatory. Do not start the full game project, campaign, asset production pipeline, or extensive systems work until it passes. A minimal disposable Godot project is allowed and required to establish the gate.

### Confirm actual tools and versions

Prefer a supported Codex desktop workflow on the user's selected computer when it has working Godot, GUI access, and browser interaction. Inspect the actual available capabilities; a product feature description is not evidence that this particular session has them. Do not assume that CLI access, a running display server, an installed Godot binary, or a screenshot tool supplies interactive control.

Verify and record:

- Operating system, environment, selected project path, and actual Godot executable.
- Exact stable Godot version, matching export-template version, renderer, and export preset. Godot 4.6.3 was available in the environment where this brief was prepared; the receiver must verify its own installation and current official support before pinning a version. Do not assume that 4.6.3 is installed, the newest stable version, or required forever.
- A working method to see the running game and send genuine mouse and keyboard input.
- A working live-browser method, with the browser name/version and whether it is local or remote.
- How two independent browser sessions will connect to the test server. Each must have its own connection and seat; two views of one client do not count.
- Required permissions, unavailable tools, firewall/hosting constraints, and any setup step needing the user's approval. Do not bypass an access denial.

Official setup references describe native GUI testing and live browser playtesting, but do not guarantee the Godot-specific workflow. On Windows, supported Computer Use operates in the foreground with the target visible in the active, unlocked desktop session. Verify the current guidance and avoid competing mouse/keyboard use during the test. Use the receiving Codex session's supported setup; connecting the user's computer to a separate assistant is not a prerequisite for this handoff. Sources: [Computer Use](https://learn.chatgpt.com/docs/computer-use) and [Browser game development](https://learn.chatgpt.com/use-cases/browser-games).

### Build a tiny isolated proof

Put this in a separate throwaway directory such as `capability_probe/`, outside the public prototype and outside the eventual game project. Use a tiny scene with a selectable/movable object, a visibly animated action, and a small server-owned shared state. Original geometric placeholders are enough. It must be small enough to debug quickly.

Perform every step below through the actual supported tools:

1. Launch Godot's GUI and the running scene. Confirm the correct scene/build is visible.
2. Use mouse input to select or command the object and keyboard input to perform a distinct action. Observe the resulting movement and animation over time. A before/after still without observation of the transition is insufficient.
3. Export the probe for the web and serve it through a web server. Open the export in a real browser and repeat the interactions. Do not use `file://` as the deployed test.
4. Make one deliberate, observable behavior change, such as correcting an intentionally wrong response or changing a movement/animation property. Rebuild/re-export, reload the actual browser artifact, and repeat the same input sequence. Verify the changed behavior and that the original interaction still works. Record the old and new revision/build identifiers so cached output cannot masquerade as a retest.
5. Start an authoritative server for the probe. Open two independent live browser clients, join one room with complementary test seats, and perform an action from each. Observe the same server-owned result on both clients. Inspect independent connection identities and state revision/tick evidence as well as the visible effects.
6. Disconnect one client while the other remains connected. Verify the declared disconnect/pause behavior. Reconnect the original session and verify state convergence, seat recovery, and that its previous command is neither lost nor executed twice.
7. Repeat the changed-build check across both browser clients. Check browser consoles and server logs for failures; record any outstanding warnings rather than hiding them.

Use real input to prove the visible interaction path. Direct function calls, injected game state, test hooks, native clients, HTTP requests, or synthetic simulation clients are valuable supplementary checks, but do not replace steps 1–7. The server itself may run headlessly. Headless game runs, compilation, screenshots alone, offline renders, and source inspection do not satisfy this interactive gate.

### Gate 0 acceptance and failure handling

Pass only when the complete launch → input → animated observation → code change → rebuild → interactive retest loop worked, and two independent browser clients joined, synchronized, disconnected, and reconnected successfully.

Record the real commands/actions, versions, project/build identifiers, expected and observed outcomes, supporting logs, and captured visual evidence in `docs/evidence/gate_0.md`. A recording or several timestamped frames can support the observation, but must be linked to actual input and an observed running sequence. Clearly distinguish automated interaction from human play.

If anything fails, try safe, authorized repairs within the probe. If GUI access, browser access, networking, or permissions remain blocked, pause the dependent rebuild and report:

- The exact operation that failed and the observed error.
- What worked and what remains unproven.
- The smallest setup change, permission, or user action needed.

Do not proceed with a headless-only substitute and promise to test later. Native success alone never establishes browser readiness. Passing this gate establishes tool capability for a tiny probe, not the quality or performance of the real game.

## Technical baseline

Use a verified stable Godot 4 release, pinned exactly with matching export templates. Use GDScript and the Compatibility renderer for the browser target. Keep the first web export single-threaded; evaluate other options only after measuring a need and validating host support. Recheck official documentation for the pinned version before implementation.

Godot 4 web exports require WebAssembly and WebGL 2.0/Compatibility; C# web export is unsupported in the referenced 4.6 guidance. Browser networking supports WebSocket clients and WebRTC rather than raw UDP/ENet. Threaded exports need a secure context and cross-origin isolation configuration. Serve `.wasm` with the proper MIME type and verify export files, compression, host limits, and startup in the actual browser. Browser storage and background-tab behavior need explicit tests. [Godot web export guidance](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)

For the initial browser co-op implementation, propose a native authoritative Godot server with a browser-compatible WebSocket transport and secure WSS for public HTTPS deployment. Confirm its adequacy with measured command latency and two-client tests. Godot supports WebSockets in native and web exports, including its high-level multiplayer interface. [Godot WebSockets](https://docs.godotengine.org/en/4.6/tutorials/networking/websocket.html)

This is a recommended starting architecture, not permission to substitute a different game or deploy infrastructure. Document a justified alternative before adopting it if it materially changes operations, hosting, cost, persistence, or player experience. A WebRTC design needs its own demonstrated signaling and connectivity plan. Do not select native ENet for the browser clients or presume a static website host can run the authoritative server. [Godot multiplayer overview](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html)

## Repository and project structure

Create a new repository or clearly isolated project after inspecting existing work. Keep it independently runnable, exportable, and testable. Suggested layout:

```text
ironwood-reach-godot/
  DESIGN.md, CODEX_REBUILD_INSTRUCTIONS.md, PLAN.md, README.md
  game/
    project.godot, export_presets.cfg
    scenes/                  # map, units, buildings, UI
    scripts/
      simulation/            # authoritative rules and deterministic state
      client/                # input, camera, presentation
      server/                # rooms, permissions, persistence
      shared/                # protocol, schemas, IDs, validation
    data/                    # versioned content and tuning
    assets/source/, assets/runtime/
  tests/                     # unit, simulation, network, saves, browser
  tests/fixtures/, tests/replays/
  tools/                     # reproducible run, test, build, export
  deploy/                    # templates/runbook, no secrets
  docs/                      # requirements, decisions, protocol/save format
  docs/evidence/             # actual results and playtest records
```

Use a few concise documents rather than a large empty documentation scaffold. Preserve editable asset sources, import configuration, pinned dependencies, and export presets. Exclude caches, temporary builds, credentials, secrets, and incidental recordings from source control. Document asset provenance and licenses.

The README must include commands verified in the receiving environment for opening Godot, running the game/server, testing, exporting, and locally serving the web build. State prerequisites and provide OS-appropriate commands.

## Simulation and presentation

Keep authoritative simulation separate from visual scenes, camera, UI, and input. The same rules must run in solo/practice, networked co-op, and automated simulation tests; do not maintain a separate simplified test implementation.

- Use a fixed simulation step and explicitly ordered commands/events. Rendering may interpolate between states without deciding outcomes.
- Use explicit seeded random streams, stable entity identifiers, deterministic collection order, and reproducible fixtures. Record seeds and content/protocol versions in replays.
- Keep currency, counts, cooldown ticks, and other exact resources in suitable exact representations. Define rounding and overflow behavior.
- Use a pathfinding/collision representation whose order and results are testable. Do not depend on visually convenient engine physics behavior for deterministic economic or combat rules.
- Claim determinism only for the scope actually tested. If Godot physics or platform-specific floats prevent cross-platform bitwise replay, document the limitation and retain authoritative state synchronization. Do not claim lockstep safety from one machine's run.
- Commands express intent; validation decides whether they are legal; accepted commands change state; presentation shows those changes. Avoid clients creating authoritative units, costs, damage, unlocks, or victories.
- Keep rules and content data configurable with schema validation. Do not scatter unexplained balancing constants across scripts.

Rebuild the game cleanly rather than wrapping the old browser simulation in a Godot window. Preserve game intent and regression cases; do not blindly preserve accidental prototype behavior.

## Authoritative two-player co-op

The server owns room state, the simulation clock, roles, economy, entities, orders, results, and committed progression. Browsers are untrusted command clients. Validate permissions server-side even when the UI hides an action; connection IDs are not durable player identities.

Write a versioned protocol before expanding networking. Define joins, seat claims, readiness, commands, acknowledgments/rejections, snapshots/deltas, disconnects, reconnects, and end-of-battle results. Use bounded payloads and safe schemas. Reject malformed, oversized, out-of-range, non-finite, unknown, stale, or unauthorized input without corrupting the room. Do not accept executable data or arbitrary object deserialization from clients.

### Roles and lifecycle

- Encode the exact Builder/General permissions and shared actions from the design. Test each allowed action and its forbidden counterpart.
- Enforce the complementary two-seat limit, readiness requirements, and valid lifecycle transitions on the server. Define how practice controls both roles without weakening co-op validation.
- A refreshed or reconnected player must regain the correct seat through an appropriate scoped session mechanism. Never trust a client-supplied role label or allow a third client to take an occupied seat.
- Define timeout, temporary absence, pause/resume, explicit leaving, and abandoned-room behavior according to the design. If a rule is unresolved, ask rather than silently choosing what the remaining player loses.
- Do not add host migration or substitute peer-to-peer authority without a reviewed need. Document server failure behavior instead of pretending browser refresh and server recovery are the same problem.

### Command ordering and idempotency

Give every command a room/session-scoped identity and sequence/revision expectations. The server must distinguish a retry from a new action. A retried accepted command returns its prior result without charging, spawning, damaging, upgrading, or rewarding again. Reusing a command ID with a different payload must be rejected.

Define stale-state responses, reordered commands, duplicate delivery, gaps, lost acknowledgments, and expiry of deduplication records. Keep sufficient committed command identity/state through reconnect and any supported server restart. Do not rely solely on disabled UI buttons or client timers.

### Shared treasury and reservations

The design's shared treasury with one player-visible purchase reservation per player is provisional. Confirm it for the approval prototype, or label an explicitly approved prototype experiment; do not silently finalize reservation amounts, duration, cancellation, or conflict-resolution rules. Internal transaction safeguards are implementation details and do not by themselves approve a visible reservation mechanic.

For any approved shared-economy implementation, updates must be atomic with the accepted action. Serialize or transactionally arbitrate concurrent spending. Available gold must account for committed reservations; two clients cannot spend the same funds.

Model the lifetime of a reservation explicitly: request, validated reservation/commit, fulfillment, cancellation, and any authorized refund. Charge once, fulfill once, and release/refund at most once. Apply the design's cancellation/refund rules; do not invent a generous refund mechanic as a technical shortcut.

Test simultaneous purchases that are individually affordable but jointly exceed the treasury: accept only a valid serial outcome, never negative funds, and converge both clients. Repeat with retries, cancellation, lost acknowledgments, disconnects, and recovery. Check income/cost/refund conservation.

### Synchronization and reconnection

Use server ticks/state revisions and versioned snapshots. Specify when clients can predict presentation and how they reconcile; never let a visual prediction spend authoritative money. A reconnect requests an authoritative snapshot and resolves pending command status without blindly replaying paid commands.

Test refresh, brief and prolonged disconnects, an inactive/background tab, reconnect at wave/battle boundaries, a lost result response, version mismatch, and a server restart if recovery is claimed. Resume with the correct entities, resources, timers, role, orders, and progression. Record state hashes/revisions alongside visible client observations.

Protect room/session credentials, avoid logging secrets, use secure transport for public deployment, and scope credentials to the required room/seat. New credentials, persistent grants, or account/security configuration require the user's applicable approval. Do not add account signup or external analytics merely to make the architecture feel complete.

## Save data and progression

Implement only the persistence needed by the current approved milestone. Establish a versioned save boundary early, then add campaign and unlock persistence after approval.

- Distinguish room recovery, a run save, and permanent unlock/profile state. Follow the design's ownership and co-op reward rules; ask if those are unresolved.
- Persist data schemas, content versions, stable IDs, seed/random state, relevant simulation tick, and required committed command identity. Do not serialize scene references as durable game truth.
- Write saves atomically or transactionally, validate on load, maintain recovery/backups where appropriate, and test interrupted writes and corrupted data.
- Make mission completion, run rewards, and unlock grants idempotent. Reconnect, refresh, reloading a result screen, or replaying a result request must not multiply rewards.
- Test migrations with fixtures. Never silently reset a player's progress or convert an incompatible save without an approved policy.
- Test the actual browser persistence path, disabled/unavailable storage, refresh, and a new browser session. State plainly whether progress is local, server-backed, or unavailable; do not promise persistence from an untested browser API.
- Keep testing/debug reset controls out of the normal campaign flow. Provide clearly scoped development fixtures rather than weakening the no-retry or unlock rules.

## Art and interaction quality

Follow the complete visual specification in `DESIGN.md`. Assets must be original to the project or explicitly authorized for use, with provenance and any license recorded. Do not copy identifiable characters, branded game UI, meshes, textures, music, or sound effects from another game. If supplied original assets are reusable, preserve their editable sources and adapt them deliberately rather than losing them in a conversion.

Build a small representative asset set first. Verify it at actual gameplay zoom before producing a whole roster. Confirm distinct silhouettes, scale, team/role/readiness states, selection, targeting, construction, movement, attack timing, hit reaction, damage, and death/destruction where applicable. Animation must communicate state and intent; a static showcase is insufficient.

Use actual Godot/browser captures for claims about in-game appearance. Label concept images and offline renders as such. Check camera clipping, occlusion, terrain intersections, shadows/materials in Compatibility rendering, readability, selection feedback, and whether effects obscure commands. Keep UI legible across tested window sizes and ensure hover text, modals, and focus do not steal game input accidentally.

Test the design's mouse/keyboard controls in the real game, including click, drag, modifiers, selection groups, contextual commands, attack-move, camera motion/zoom, role abilities, UI interaction, lost focus, and key release. Verify browser context menus and scrolling do not conflict. Do not silently redesign controls after finding an input bug.

## Milestones and approval gates

At every milestone, implement a small coherent slice, run focused automated checks, play it through real GUI/browser input, inspect it, fix what failed, and repeat. A checklist written in advance is a plan, not a result.

### Milestone 1 Battlefield approval prototype

Create only the bounded battlefield prototype specified by the design: representative map/terrain, camera, readable original visuals and animations, basic units/buildings/economy/orders, both co-op roles, and the minimum battle loop necessary for meaningful approval. Keep scope bounded to what lets the user judge the map, feel, control scheme, visual direction, and cooperation.

Acceptance:

- The actual browser build loads, supports real input, and has no known blocker to the approval loop.
- Both roles can join, ready, act, observe each other's results, disconnect, and reconnect in independent browser clients.
- The implemented slice matches its requirement matrix and has focused simulation/network/input regression coverage.
- The map/camera/readability and representative animation have been inspected while playing, not just rendered offline.
- Known incomplete or untested systems are plainly listed. Campaign progression, content breadth, balance, and fun are not claimed complete.

Deliver the playable prototype, controls, exact testing performed, and material open questions. Stop for explicit user approval of this prototype before starting the full campaign. Technical success is not aesthetic or game-design approval. If the user requests revisions, iterate on this slice and retest before asking again.

### Milestone 2 Complete one approved mission slice

After prototype approval, complete one representative mission end-to-end using the approved rules: setup, meaningful economic/tactical decisions, role interaction, escalation, win/loss, and the approved transition/reward/save boundary. Do not build many missions first and discover the core loop is weak afterward.

Acceptance includes successful automated regression runs, real two-browser completion and failure paths, clean reward idempotency/save recovery, measured performance, and an actionable playtest report. Ask for any still-open material decisions before they become architecture. Seek human feedback on readability, workload, pacing, and cooperation; automated play does not prove enjoyment.

### Milestone 3 Campaign and progression

Only after the earlier approval gate and a working mission loop, expand the exact campaign, routes, roster, perks, threats, unlocks, and permanent progression described in the design. Add one feature/content family at a time with compatibility and regression tests. Maintain traceability to the design; keep unresolved proposals out of the accepted requirement column.

Acceptance includes representative early/mid/late run coverage, legal choices and transitions, defeat and completion behavior, persistence, repeated-session unlock behavior, co-op parity, and strategic exploit checks. Use test fixtures to reach late content without fabricating human completion claims.

### Milestone 4 Public browser candidate

Public hosting for the intended browser game is authorized. Publish a separate browser candidate and authoritative backend within the available approved hosting scope; preserve the current public prototype and its URL. Replacing or retiring that prototype is a separate decision. New spending, credentials, access, or security configuration still requires the applicable approval.

Acceptance requires the deployment checks below, repeatable startup and rollback instructions, actual two-browser testing against the deployed endpoint, and a clear report of unsupported browsers/devices or known limitations. A localhost-only success is not public multiplayer evidence.

For final handoff, provide the requirement matrix, runnable source, build/export/run instructions, test and playtest evidence, measured limits, and known issues. State exactly which scope is complete.

## Automated verification and strategic testing

Use deterministic tests against production simulation rules, plus integration and actual browser tests. All automated tests must assert outcomes and fail meaningfully; a script that logs activity without checking it is not a regression test. Capture failing seeds/replays before fixing a bug, then add the smallest useful regression.

Minimum test families, as they become applicable:

1. **Input and authority:** each role's allowed/forbidden actions; malformed and adversarial packets; invalid coordinates/IDs; target ownership; complementary roles; third-seat rejection; authentication; ready/pause state rules; stale/duplicate commands.
2. **Movement and collision:** reachable/unreachable orders; navigation around terrain and physical building footprints; construction on routes; group formation; obstruction and rerouting; worker arrival; units near map edges; attack-move continuation; repeated and rapidly changed orders; no illegal teleports or terrain penetration.
3. **Economy and production:** finite deposits; actual worker mining/carry/delivery; no income without delivery where the design requires physical transport; conservation; simultaneous spending; reservations/cancellation/refunds; blocked recruitment/worker spawns; capacity and build-slot limits; invalid placements; pause/time invariants.
4. **Combat and abilities:** target validity, ranges, line/obstruction rules if designed, attack timing, damage and death once, cooldowns, area effects, focus/stop/retreat, building destruction, victory/defeat boundaries, and ability role restrictions.
5. **Networking:** independent joins, retries/reordering/lost acknowledgments, concurrent orders, state convergence, refresh, disconnect/reconnect, stale builds, throttled background tabs, latency/jitter, bounded load, and recovery behavior actually supported.
6. **Saves and progression:** round-trip state, interrupted/corrupt writes, schema migration, unlock persistence, duplicate-safe grants, loss/end-run rules, incompatible content, and browser storage failures.
7. **Presentation and controls:** actual click/drag/keyboard sequences, selection feedback, UI focus/modal guards, camera/selection separation, cancel/context actions, blur/keyup cleanup, animation-state continuity, and browser reload showing the intended build.
8. **Strategic exploits:** passive turtling or idle income abuse; infinite/duplicate resource loops; spawn/placement blocking; unreachable enemy traps; pathfinding choke exploits; attack-cancel/retarget abuse; invulnerable kiting; role/ability spam; wave/ready/pause manipulation; disconnect as an advantage; early/late progression skips; and dominant strategies that erase the intended tradeoffs. Judge cases against the accepted design so a valid strategy is not mislabeled a bug.

Test multiple relevant seeds, maps, role orderings, and progression states. Include positive and negative cases. Give raw counts, conditions, and failure cases rather than invented confidence percentages. Compare meaningful alternatives under controlled conditions when tuning; do not nerf the entire game to make a bot complete one script.

Keep a concise input/event trace, seed, build ID, state hash, and outcome for reproducible failures. Separate mechanical reachability tests, automated strategy probes, agent-driven interactive tests, and real human playtests in reports. A human-fun verdict remains unproven until humans actually play and give feedback.

## Browser deployment and measured performance

Before choosing a host, verify current support for the actual export and server: complete asset set, maximum artifact/file sizes, MIME types, compression, headers, HTTPS/WSS, persistent WebSocket connections, process/runtime limits, room persistence, and any storage constraints. Inspect actual response headers and downloads, not just a marketing feature list. Do not assume the current prototype's web stack can host a native Godot server.

Local and public hosting are separate gates. A browser in the development environment reaching localhost does not prove that a friend elsewhere can join. Two same-machine sessions prove some protocol behavior but do not establish cross-device/network compatibility; label that limitation and test representative remote clients before claiming it.

Measure on identified target hardware/browser and relevant gameplay loads: first uncached load, cached reload, download/asset size, frame time/FPS, memory where available, command-to-visible-response latency, server tick duration, and room resource usage. Report measurement conditions and sample duration. Establish performance budgets as explicit targets, then test them; do not invent achieved numbers or silently trade away the design to meet a target.

Check resize/fullscreen, focus changes, audio start after user input, browser refresh, unavailable persistent storage, stale cached exports, slow assets, network interruptions, and failure messages. Use consistent build IDs for browser artifacts and server protocol/content versions. Provide a compatibility error instead of corrupting a room when versions differ.

Keep public deployment within approved scope. Ask before spending/subscriptions, new or expanded credentials/access, security/network changes, material new agreements, or replacing a live service. Keep secrets out of files, logs, screenshots, and chat. If deployment is blocked, deliver the tested local build with the pending decision; do not claim a public URL is ready.

## Evidence and reporting discipline

For each significant test or playtest, record:

```text
Check ID and requirement:
Build/revision and content/protocol versions:
Date and tester type (automated, agent interactive, or human):
Environment, OS, Godot, renderer, browser, server target:
Setup, seed, fixture, and prerequisites:
Exact commands or input sequence:
Expected result:
Observed result:
Status: PASS / FAIL / BLOCKED / NOT RUN
Logs, replay, screenshots, or recording:
Scope and limitations:
Fix and retest reference, if applicable:
```

Do not prefill `PASS` in a template. Do not reuse a prior build's test result after relevant changes without retesting. A screenshot can support a visual assertion but cannot by itself prove animation, input handling, multiplayer, persistence, performance, or fun. A passing compile shows that compilation passed, no more.

At a milestone, lead the update with the usable result or blocker. State what changed, what was actually tested, what failed/remains untested, and the next gate or decision. Use links/paths to the full evidence without burying the caveat. Keep routine updates short; deliver complete source and documentation at handoff.

## First-session stopping condition

Under the kickoff, prove Gate 0, then build and verify only the battlefield approval prototype if no material question blocks it. Stop for the user's review or a genuine setup/permission/design blocker. Silence does not approve campaign expansion.

This package records future obligations. It does not assert that the Godot rebuild, interactive gate, networking, deployment, performance, balance, or human enjoyment has already been verified.
