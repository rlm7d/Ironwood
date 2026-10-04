# Battlefield verification — partial candidate 006

The current Godot battlefield runs in the published cloud environment. It uses
two independent headed browser clients and real mouse/keyboard input. Expanded
005 play is archived, and the focused 006 selection/recovery retest passed.
Milestone 1 remains **partial**: Brass Tactics territory rules need the
owner’s answer, a separate public Godot candidate is not deployed, and no human
has played or approved this battlefield. The existing public prototype remains
preserved.

## Automated evidence

| Check | Result | Evidence and scope |
| --- | --- | --- |
| Deterministic simulation | 136 assertions passed | [Report](evidence/simulation.json): role permissions, transactional holds, physical gathering, footprints/navigation, distinct group destinations, combat, abilities, terminal state and sampled replay. |
| WebSocket authority integration | 9 scenario families passed | [Report](evidence/protocol-smoke.json): separate seats, permissions, holds, exact-once confirmation, deliberate dropped acknowledgment/reconnect, invalid traffic and limits. The optional 4096-outcome capacity run was not performed. |
| Production native client recovery | 32 assertions passed | [Report](evidence/client-recovery.json): real sockets with explicit pending-state fixtures; separate from browser storage and real input. |
| Production presentation boundary | 80 assertions passed | [Report](evidence/client-snapshot.json): JSON IDs, stable visuals, actual headless 640→1280→640 layout, health/construction/effect feedback, tooltips and selection boundaries. New selection tests use ordinary training commands, explicit death/removal fixtures and captured local payloads; ability labels use synthetic snapshots. |
| Isolated ability combat effects | 16 assertions passed | [Report](evidence/ability-effects.json): ordinary role/purchase/ability commands and fixed-step combat, paired explicit position/stop/high-health fixtures, Shield damage/expiry and Tower damage/rate/shutdown/recovery. Automated only. |

These current reports identify **battlefield-006**, pinned official Godot
**4.6.3.stable.official.7d41c59c4**, and tested source hashes. Automated success
does not establish fun, balance, final art or performance.

## Agent-driven real browser play and build scope

Gameplay input uses guarded XTEST events on the authenticated X11 desktop.
Chromium 151 runs headed with browser and GPU sandboxes retained. Separate owned
profiles join Builder and General. Browser automation performs navigation,
viewport changes and passive observation, without sending game commands or
injecting game state. Actual X11 frames and recordings are inspected. Cloud
rendering uses CPU llvmpipe; target-hardware performance is unproved.

The [current 006 focused browser record](evidence/006-agent-interactive.json)
separates three disposable owned trial rooms and preserves unsuccessful setup
attempts. The [current synchronization supplement](evidence/006-synchronization.json)
compares full states within each separate authority lifetime: **1649, 1567 and
1491 common revision pairs**, respectively. All **4707 pairs matched**, with no
cross-room revision pairing or performance/RTT inference. Two independent clients joined/readied, held 190 gold, paused on
General disconnect at tick 333, reconnected with both holds, confirmed 80 once
and canceled the 110 hold. A real click/drag selection while a new battalion was
still training excluded it: the outgoing group order and March command contained
only the two ready members, and the authority accepted them.

The final trial assigned two ready members to group 1, isolated the spare, and
observed the other member die through real raid combat at tick 1817. A passive
conditional watcher then used an **actual OS click on Builder Disconnect** to
freeze the world at tick 1819. This pause step is automated OS interaction,
separate from the agent’s subsequent real-key group recall and mouse order.
The inspected General view recalled **one survivor, 180/180 HP**. Builder
reconnected; a real right-click sent sequence 8 with only `unit_002`, and the
authority accepted it. The final inspected frame showed both players online,
one selected survivor and Order Accepted. No game state or protocol commands
were injected by the browser/desktop harness.

Retained-death-animation click/drag is covered by the explicitly native
presentation fixture; it was not reproduced through browser input. Previous
attempts where both members died are recorded as unsuccessful test setups and
do not count as a surviving-member recall pass. Current 006 victory/defeat was
not repeated as an acceptance claim; the complete 005 outcome and ability
cycles below retain their original build scope.

- [Current saved-group recall frame](evidence/battlefield-006-final-group-recall-one-live.png)
- [Current accepted survivor order](evidence/battlefield-006-final-survivor-order-accepted.png)

The [historical 005 network analysis](evidence/005-root-browser-network.json) covers a
single original 005 room, excluding earlier failed 004 records. It verifies
**2,819 common snapshot revisions with no full-state mismatch**, and no observed
browser console/page error indicators in that interval.

Actual input exercised joining/readiness, two visible purchase holds, Confirm
and Cancel, worker delivery, Shift selection, group right-click movement and S
stop. Wide General layout settled at **1280×820** before inspection; minimap
clicks, middle-button drag, held arrow keys and wheel zoom were exercised. The
readable narrow Controls dialog was inspected and dismissed through Esc.

- [Both holds](evidence/battlefield-005-holds.png)
- [Settled wide layout](evidence/battlefield-005-wide-settled.png)
- [Wide camera inputs](evidence/battlefield-005-wide-controls.mp4)
- [Controls dialog](evidence/battlefield-005-help-visible.png)
- [Refresh recovery and purchase confirmation](evidence/battlefield-005-refresh-confirm.mp4)
- [Shift selection, move and stop](evidence/battlefield-005-shift-move-stop.png)

Disconnecting General froze all serialized battlefield fields at **tick 769**,
revision **776**, including both holds totaling **190 gold**. The passive record
contains **908 identical paused snapshots** spanning **93.56 seconds**. An actual
browser-toolbar refresh, followed by Join General, recovered the same seat from
production browser storage on a new transport with sequence 2. All simulation
fields matched on recovery; only connection/lifecycle metadata changed.

Builder canceled its 110-gold hold, General confirmed an 80-gold battalion, and
Builder then held/confirmed one 110-gold tower. Cumulative spending progressed
**0→80→190**, with no extra confirmed purchase or duplicate tower. A subsequent
Builder disconnect/reconnect recovered pending sequence 5 through
`command_status`, replayed the original result/revision, and continued with
sequence 6. The original acknowledgment frame had reached the passive browser
observer before disconnect: this proves pending recovery and no extra charge,
without claiming transport loss. Deliberate lost-ack scenarios are automated
protocol/native tests, separately labeled above.

Both 005 browser clients later showed **Defeat** when the allied keep reached
zero health at **tick 5817**, before the 6000-tick practice limit. This is an
actual main-base destruction playthrough, not a timer-only loss.

- [Defeat recording](evidence/battlefield-005-live-keep-destruction.mp4)
- [Both clients after keep destruction](evidence/battlefield-005-keep-destroyed.png)

The [focused 005 play record](evidence/005-agent-interactive.json) additionally
verifies a distinct three-battalion arrival, local healing (Tower 162→262 HP and
nearby battalion 148→180), active Shield movement slowing (median 1.2 versus 3.0
world units per simulation second across qualified intervals), and Tower’s six
seconds of Overcharge followed by five seconds of Shutdown. Real March
activation held enemy-keep HP at 484 for its full active interval, then attacks
resumed and both clients reached **Victory at tick 4762**. Isolated Shield damage
protection and Overcharge damage/rate boosts were not demonstrated in those live
samples. The 136-check suite covers activation/slowing/shutdown. The separate
[16-check combat supplement](evidence/ability-effects.json) measures Shield
incoming damage 16→7→16 after expiry; Tower shot damage 26→44, interval 22→12
ticks, zero damage during all 100 shutdown ticks, and normal 26-damage recovery.
Those deliberately isolated fixtures establish automated mechanics, without
claiming live protection/boost comparisons, fun or balance.

- [Ability-cycle recording](evidence/battlefield-005-actual-ability-cycle.mp4)
- [March ending and victory](evidence/battlefield-005-march-ended-attacks-resumed.png)
- [Portable 005 proof index](evidence/archive/battlefield-005/browser-play.json)

That play also exposed the dead/training/stale-control-group selection defect.
Those unsuccessful commands are retained and explicitly qualified. Source and
manifest snapshots preserve exactly the 005 build that was played. The final 006
changes client selection and its build ID; authority, network and ability rules
remain identical. The focused current 006 real-input selection/recovery retest is recorded
separately above and passed. It does not broaden the 005 ability/outcome scope.

## Selection fix, regression cycles and earlier evidence

Known dead or still-training battalions can no longer enter click/drag selection.
Current selections, saved-group recall and outgoing orders/General abilities
filter IDs against the received alive/ready allied state. The authority still
rejects a unit that dies after the client’s last valid snapshot; no partial server
command acceptance was introduced. Six deterministic pre-fix failures are
[preserved](evidence/archive/battlefield-005/client-selection-prefix-failure.json).
The 006 presentation run adds 17 selection checks to the prior 63, for **80
passing assertions with zero errors**.

The new deterministic group planner selects distinct reachable destinations
before mutating any unit order. Regression cases cover occupied keep goals,
stacked arrivals and map edges. Friendly-unit collision/avoidance remains a
separate unresolved policy; distinct commanded endpoints do not establish it.

Selected battalions now show health and active March/Shield tradeoffs. Buildings
show construction progress and Overcharge/Shutdown durations. A typed-array
ternary introduced a runtime presentation failure in 004; its
[22-failure/18-error report](evidence/archive/battlefield-004/client-snapshot-tooltip-type-failure.json)
is retained. The corrected 005 presentation run passed all 63 original assertions without
Godot errors, followed by real browser retesting. The later selection regression
was added after those checks; it is not concealed by the earlier pass.

Earlier 003 real play separately reached `enemy_keep_destroyed` at tick **1806**,
spent **190**, gathered **220**, and compared **882 matching shared revisions**.
Its terminal reconnect restored the original seat while preserving the completed
world. Drag selection, control-group assignment/clear/recall, attack-move, F/H,
and basic March/Overcharge activation were exercised there. This is historical
003 evidence, not a second current 005 victory claim:
[qualified archive](evidence/archive/battlefield-003/browser-play.json),
[victory frame](evidence/battlefield-003-victory.png),
[terminal recovery](evidence/terminal-browser-reconnect.json).

Gate 0’s disposable launch/input/change/export/browser/reconnect proof is
archived separately in [GATE_0.md](GATE_0.md). Compilation, native tests and
presentation fixtures do not replace that interactive proof.

## Limits and required decisions

No human playtest or battlefield approval has occurred. Costs, bindings, example
abilities, visuals, map, raid timing and five-minute trial limit remain proposals.
The owner approved trial treasury/hold and disconnect-pause behavior; those
answers do not finalize campaign economy, tuning, art, fun or balance. Other
browsers, touch, target hardware performance, public HTTPS/WSS play, authority
restart persistence and lost-identity recovery remain unverified.

Territory claim/loss/contest and gathering transitions must follow the owner’s
Brass Tactics intent. Research pages currently fail with HTTP 403; the precise
rules were requested. Unsecured expansion sockets stay unavailable and only home
resource delivery is implemented. No General-clear/Builder-outpost capture rule
was approved.

The [deployment draft](DEPLOYMENT.md) is concrete but unexecuted. A shareable
candidate needs an approved HTTPS host and persistent native authority behind WSS.
No usable deployment integration or approved host is available in this session.
Localhost is not a public playable address. The prior public prototype has not
been replaced or modified.

Four campaign missions, research, route choices, perk drafts and permanent
unlocks remain deferred until explicit battlefield approval. See
[OPEN_ISSUES.md](OPEN_ISSUES.md) for the remaining scope.

A [fresh cloud handoff](evidence/006-handoff.json) leaves a new unclaimed authority
and two clean headed browser profiles ready to join. This startup baseline is
separate from the archived gameplay proof; its localhost URL is not public.
