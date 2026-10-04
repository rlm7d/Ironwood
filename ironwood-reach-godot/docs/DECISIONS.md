# Ironwood Reach decision record

This record distinguishes confirmed design, explicitly approved prototype experiments, implementation proposals and unresolved choices. The latest user instruction takes precedence over an older proposal. [REQUIREMENTS.md](REQUIREMENTS.md) tracks implementation and verification without assigning premature PASS results.

## Confirmed design

Follow [DESIGN.md](../DESIGN.md) in full: shared-faction Builder/General co-op; PC mouse/keyboard; fully visible genuine 3D open terrain; fixed construction sockets; automatic gathering after securing territory; angled original miniature medieval fantasy; battalions for standard troops and individual distinctive large units; two active slots per role with cooldown/positioning/tradeoffs and no initial separate energy meter.

The four-mission run, adjacent-column routes, threat disclosure, fresh mission base/army, research reset, no campaign retry, role-specific free 1-of-3 perks, separate permanent 1-of-3 boss offers entering shared future availability and no free starting unlock power remain confirmed obligations. They are deferred until the battlefield prototype is explicitly approved, not replaced by this trial.

The DOCX design record matches DESIGN.md after formatting normalization and supplies no different decisions. Old prototype code/test counts, procedural art or a deployed prototype do not approve new Godot rules or appearance.

## Explicitly approved prototype experiments

These are the user's answered trial policies, not final campaign/economy approval:

| Decision | Approved prototype behavior |
| --- | --- |
| Treasury | One shared gold balance. Holds subtract from available funds; a hold alone does not spend gold. |
| Purchase hold | At most one visible hold per player. Both roles may have their own hold when combined funds permit it. |
| Confirm | The owner manually confirms. Validate the target/current funds, then charge and start once as one authoritative transaction. |
| Cancel | The owner manually cancels an unconfirmed hold, releasing it. Cancelling a hold does not create gold or refund an already committed purchase. |
| Expiry/refunds | No automatic hold expiry. No post-confirmation refund. Do not invent cancellation/refund terms to handle a missing producer or disconnect. |
| Disconnect | Pause the entire battlefield simulation when either seat is missing. Retain both seats, world state and holds until the same player returns. |
| Reconnect | Recover the original seat through its scoped session identity, restore authoritative state and pending-command outcomes, and resume without double execution. A new transport ID is not a new player. |

The transport may exchange snapshots, acknowledgments and readiness while the world is paused. Units, workers, income, training, construction, raids and ability timers must not advance during the approved pause. No automatic seat timeout, abandonment forfeiture, release of the absent player's funds or host migration is approved.

Current scope is one in-memory authority/room. Server-restart persistence is not implemented or claimed; it differs from browser refresh/reconnection. That limitation must be visible in the handoff and failure path.

## Territory: unresolved and blocking expansion

The user redirected the proposed capture rule: **“Territory should work like Brass tactics (the vr game) this was a huge inspiration.”** The proposed outpost-based claim mechanism is **NOT APPROVED**. Brass Tactics inspiration was already recorded, but DESIGN.md does not specify the exact neutral claim, ownership transfer, contested presence, infrastructure or gathering activation rules.

Read-only HTTPS attempts to Hidden Path's Brass Tactics page, Meta/Oculus, Google search and an UploadVR review failed before content retrieval with `Tunnel connection failed: 403 Forbidden`. No primary mechanic, quotation or capture rule was verified; no network settings/credentials were changed. Lack of access is not evidence of how the game works.

The pending clarification asks how neutral territory is claimed, how ownership changes, what unit/building presence matters, and when gathering starts or stops. Do not implement an inferred tower/outpost/capture-radius rule while that is unanswered. A supplied precise mechanic description or access-approved primary tutorial can resolve it.

Current source intentionally rejects construction in unsecured territory as `territory_capture_pending`. Home territory is a predefined secured fixture with a finite deposit and automatic worker delivery. This supports independent home-economy checks; it does not prove territorial expansion or Brass Tactics conformity. Outpost content in trial tuning does not approve its capture purpose. Battlefield completion remains blocked on the required territory decision.

## Implementation proposals awaiting battlefield approval

| Proposal | Current scope and limit |
| --- | --- |
| Map/camera/controls | One bounded map, provisional socket/deposit arrangement, angled orthographic camera and RTS bindings. These support approval play and remain revisable; exact values are not final controls or map approval. |
| Trial duration/encounters | Five-minute trial limit, timed raider waves and keep-based win/loss. This is a bounded approval fixture, not the confirmed 15–20-minute campaign mission target, final difficulty or complete objective design. |
| Content/tuning | Representative footmen/archers, buildings, four visible soldiers per battalion and all costs/health/ranges/timings in `game/data/tuning.json`. No final roster, group cap, economy balance or counter design is established. |
| Ability examples | Mending, tower overcharge, forced march and shield wall are trial examples. The design's example names/mechanics are not a locked ability list. Buildings/research/perks opening and transforming options remain broader obligations. |
| Mending tradeoff | Current Mending instantly heals an allied building within a home-area radius and nearby allies, with a cooldown. Tests cover healing, cooldown, ownership and radius. Historical `005` real input heals Tower 162→262 and a nearby battalion 148→180. Whether this positioning demands meaningful retreat/cooperation remains unverified; observed healing/cooldown alone does not establish the full tradeoff requirement. Do not silently add energy, a refund or another material downside. |
| Shield wall | Current trial trades movement speed for damage reduction. The illustrative flank weakness is not currently modeled and is not a confirmed final ability rule. Historical `005` actual movement proves slowing; no active-shield incoming damage was isolated live. The separate [16-check ability supplement](evidence/ability-effects.json) verifies normal-step incoming damage 16→7 while active→16 after expiry with paired isolated fixtures. It is additional to the 136 simulation suite, and does not establish live protection or balance. |
| Visual assets | Original procedural geometry, palettes and animation rigs are representative prototype art. Gameplay-scale inspection and human visual approval remain required; final polish is not inferred from the generation method. |
| Protocol/hosting | Native Godot authority with WebSockets and a local loopback listener is the starting implementation. Packet/ledger/revision bounds are documented trial limits. Public HTTPS/WSS hosting needs a separate candidate and real deployed checks; localhost does not prove remote readiness. |

## Review and approval boundaries

Ordinary reversible implementation choices may proceed. Ask before material changes to combat, economy, progression, art direction, controls, co-op responsibilities, campaign scope, platforms or services; and before spending, new/expanded access or credentials, security/network changes, material new agreements or replacing the live prototype.

Public hosting of the intended game is authorized within available approved scope, using a separate candidate that preserves `https://ironwood-reach.rlm7d.chatgpt.site`. A successful build/publication does not establish interactive quality. Stop after the bounded battlefield with its playable build, controls, exact checks, limitations and open decisions; campaign expansion requires explicit approval.

Record automated assertions, agent-driven real input/visual inspection and human feedback separately. Gate 0 proves tools for a tiny fixture; historical Three.js tests do not certify this game's simulation, networking or controls. Human fun/balance, final art approval, cross-device compatibility, public readiness and target performance remain unproven until corresponding evidence exists.

Current `battlefield-006` has source-qualified automation (136 simulation, nine protocol families, 32 native recovery and 80 presentation assertions), distinct reachable group goals and repaired tactical feedback. Six reproduced `005` selection failures are fixed by filtering known-invalid IDs at selection/recall/outgoing boundaries, with 17 added regressions. The authority still rejects a unit dying after the last valid snapshot; no partial batch acceptance was added. Its [focused current browser retest](evidence/006-agent-interactive.json) passes known-training click/drag exclusion, eligible order/Q and saved-group recall after a normally fought casualty; the subsequent order includes only the live member. Holds190 also survive a tick-333 pause/rejoin, then confirm80/cancel110. Retained dead-visual click/drag remains automated-fixture coverage; failed preliminary group scenarios remain qualified in the record. Historical `005` real play qualifies hold/pause/reload, cancel/confirm and paid sequence-5 cached recovery before sequence 6, without duplicate charge/site. The original ACK reached the observer before closure; unseen/transport-lost ACK is not claimed. Wide controls, local healing, Shield slowing, March attack sacrifice, Overcharge/Shutdown and separate defeat 5817/victory 4762 are qualified in its own record. Isolated live damage protection/boost remains unproved. A separate 16-assertion `006` automated supplement verifies Shield reduction/expiry and Tower boost/faster fire/100-tick shutdown/normal resumption through ordinary combat steps, with explicit isolating fixtures; the 136 simulation count is unchanged.

Historical `005`, `003` victory/terminal reconnect and `002` pause/refresh keep their build identity; the `004` typed-array failure and fix are preserved. No execution result approves map, controls, roster, tuning, art or economy. Territory rules, public hosting, further input/ability boundaries and human feedback remain open in [OPEN_ISSUES.md](OPEN_ISSUES.md). Campaign work still requires explicit battlefield approval.
