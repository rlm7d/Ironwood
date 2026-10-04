# Ironwood Reach battlefield approval prototype

Goal: build an original Godot 4.6.3 browser-compatible, authoritative two-player battlefield that lets the owner judge terrain, camera, controls, presentation and cooperation.

Working location: `/workspace/Ironwood/ironwood-reach-godot`, a new isolated project in the previously empty repository. The public Three.js prototype is preserved.

Gate 0 passed in the prior task. The published environment restored and further real two-browser input was exercised on 4 October 2026 UTC. The [portable archive](docs/GATE_0.md) distinguishes the complete original proof, the restoration baseline/short recording, and this battlefield's later full browser trial. Full evidence remains in `/workspace/ironwood-cloud-harness/evidence`.

User-approved trial rules: shared gold; one visible reservation per player; funds held until Confirm/Cancel; Confirm charges and starts once; no automatic expiry or post-confirmation refund. On disconnection the whole battle pauses, seats and reservations remain, and the original player reconnects. These are prototype experiments, not final design approval. Server-restart persistence is outside this milestone.

Milestones: (1) map/camera/original representative visuals; (2) shared fixed-step battlefield, physical building navigation, automatic worker delivery, orders and combat; (3) two-role networking and ready/reconnect/idempotency; (4) focused regression checks and actual two-browser play, fix and retest; (5) runnable build, controls, evidence and known limits.

Current candidate: `battlefield-006`. Source-qualified checks pass 136 simulation assertions, nine protocol families, 32 native recovery assertions and 80 headless presentation assertions. A separate 16-assertion paired-combat ability supplement also passes; it isolates damage effects through ordinary steps and remains automated evidence. Selection filtering fixes six reproduced `005` failures with 17 added regressions; its focused `006` training/casualty-group browser retest now passes within the recorded scope, with direct dead-visual click/drag still covered by automated fixtures. Historical `005` economy/recovery, wide controls, abilities, defeat tick 5817 and victory tick 4762 remain separately archived. Territory, public deployment and human approval keep the milestone partial; full campaign work remains gated.

All costs, roster subset, timings, map layout, control bindings and encounter tuning are trial values pending battlefield approval. The user wants territory to match Brass Tactics; the proposed outpost-based claim rule was not approved. Exact capture and ownership rules are awaiting clarification because developer/Meta research requests were blocked with HTTP 403. No affected territory mechanic will be finalized before that answer.

Stop after the bounded battlefield for explicit approval. Campaign routes, four missions, perks, permanent unlocks and content breadth remain deferred requirements. No existing prototype replacement, spending, new credentials/access, or external security/network changes are authorized by this implementation plan.
