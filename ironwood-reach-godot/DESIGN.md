# Ironwood Reach Design Decisions

Design record as of 3 October 2026

Ironwood Reach is a two-player cooperative real-time strategy game in which both players operate one shared faction. One player builds and expands; the other trains and commands the army. The intended experience combines a readable miniature fantasy battlefield with a four-mission run, transformative role-specific perks, and permanent options unlocked by defeating an exceptionally difficult final boss.

This record separates agreed design decisions from provisional systems, illustrative content, and work that remains unimplemented or unverified. The game owner retains control of the design; open details are not permission to silently replace an agreed direction.

## Game identity

- Two-player co-op with Archon-style shared-faction control, inspired by the shared-control concept in StarCraft.
- PC play with mouse and keyboard. The browser version is intended to support two cooperating clients.
- Brass Tactics is a gameplay and battlefield inspiration, adapted to non-VR play.
- Open movement across a genuine 3D battlefield, with buildings placed at fixed sockets.
- A fully visible map with no fog of war.

## Player responsibilities

### Builder

The Builder handles structures, defenses, and expansion. Securing territory enables the economy and creates the infrastructure from which the General can recruit.

### General

The General trains units from structures and commands the army. The role focuses on army positioning, combat, and tactical use of the units and abilities available during the mission.

Both roles must have meaningful decisions and opportunities for cooperation. Their abilities and perk choices should create cross-role synergies.

## How to read decision status

Confirmed means an agreed direction or rule. Provisional means a current proposal that may change. Example means an illustration of the desired design space, not a locked content specification. Pending means a choice, implementation, or verification step has not yet been completed.


## Battlefield and presentation

### Movement and construction

Units move freely through open terrain rather than following fixed lanes. Construction uses fixed building sockets. The map remains visible throughout play, so readable terrain, threats, positioning, and defenses are central to tactical decisions.

The exact map layout, camera feel, and controls remain subject to player approval. A particular prototype layout or binding does not become a final design decision merely because it exists in the current build.

### Territory and gathering

Workers automatically gather resources from deposits after territory has been secured. The economy supports structures, defenses, expansion, unit recruitment, and mission research. Resource gathering should not require manual worker micromanagement as the basic play loop.

Resource research is purchased during a mission and resets for the next mission. The shared treasury and purchase-reservation proposal is described separately under provisional systems.

### Visual direction

The battlefield is an angled, genuine 3D miniature world with a medieval fantasy setting. The intended art is original, stylized, and inspired by the readability and expressive fantasy character of World of Warcraft. Bold silhouettes and expressive animation should make units and actions easy to understand.

High visual quality, polish, and testing are required. The prototype is a battlefield approval trial; its current procedural assets are not approval of the final art quality.

## Army scale and roster

The broad roster direction includes footmen, knights, archers, siege units, mages, golems, and dragons. It should also make room for imaginative fantasy concepts, such as a shielding bell tower and a thorn giant that roots enemies.

Standard troops are controlled as battalions. Large or distinctive pieces, including giants, dragons, and the bell tower, operate as individual entities rather than small-soldier battalions.

Suggested tuning only: approximately 4 to 6 visible soldiers per battalion and 8 to 12 controllable groups. These are starting points for testing, not locked counts or limits.

The named roster categories and fantasy concepts establish breadth and feel. Final unit lists, costs, statistics, counters, animations, and content quantities remain unspecified.


## Mission run and failure rules

A run contains four missions: three standard missions followed by one extremely difficult final boss mission. The duration target is 15 to 20 minutes per mission.

- Standard missions mix offensive, defensive, and objective-driven play.
- Each mission starts with a fresh base and army.
- Destruction of the main base or failure of a required objective immediately ends the entire run.
- A failed run has no mission retry. Run-specific perks reset on defeat.

Difficulty escalates from mission 1 to mission 2 to mission 3, followed by a much larger jump for the boss. Initial failures are expected. Difficulty must still be fair, readable, and learnable, so defeat provides information players can use in later attempts.

## Route choices

Each standard mission stage has three columns of possible missions. Players can start in column 1, 2, or 3. Between standard stages, they can remain in their column or move to an adjacent column; they cannot jump directly from column 1 to column 3 or the reverse.

| Current position | Available next positions |
| --- | --- |
| Run start | Column 1, 2, or 3 |
| Column 1 | Column 1 or 2 |
| Column 2 | Column 1, 2, or 3 |
| Column 3 | Column 2 or 3 |
| After standard mission 3 | The same final boss for every route |

All routes converge on the same final boss. Route choice changes the sequence of standard missions and the opportunities encountered on the way.

### Information shown before choosing

The full route reveals mission types and broad danger and reward categories. Exact enemy compositions, optional objectives, and perk offers can be revealed later. Major threats must be disclosed before entering a mission.

The route should support informed choices without requiring every detail to be exposed at the start of the run. Exact mission definitions, reward category contents, and optional objectives remain to be designed.


## Progression and rewards

### Mission research

Players spend gathered resources on research during a mission. These purchases reset at the next mission. Research is distinct from the free perk choices earned by completing standard missions and from permanent options earned through boss victory.

### Perks within a run

After each standard mission, each player independently chooses one of three distinct major perks tailored to that player's role. These are free rewards, not purchases from the mission treasury.

The perk pool should be large, and the choices should be meaningfully transformative. Builder and General perks should interact through cross-role synergies. Each selected perk persists within the current run and resets when the run is lost.

The three choices offered to one role must be distinct. Exact perk text, pool size, rarity, offer-generation rules, and balancing numbers are not yet locked.

### Permanent unlocks from the boss

After defeating the final boss, each player independently receives a separate three-choice offer of permanent unlocks and selects one. Both selected unlocks are added to the shared availability pool for future runs.

An unlock could make a new unit, building, or upgrade available. It adds a future option; it does not automatically spawn that option for free or grant free starting power. Exact acquisition costs and availability rules for each unlocked option remain content-design decisions.

| Progression layer | How it is gained | Persistence |
| --- | --- | --- |
| Base and army | Established during a mission | Fresh each mission |
| Mission research | Bought with gathered resources | Resets each mission |
| Role perk | Each player chooses 1 of 3 after each standard mission | Within the current run; resets on defeat |
| Permanent option | Each player chooses 1 of 3 after boss victory | Shared availability in future runs |

The important distinction is between resources spent now, run-specific transformations, and lasting additions to future choice. These layers should remain separate in the rules and interface.


## Role abilities and cooperation

Each role has two active ability slots. Abilities use cooldowns, positional limits, and meaningful tradeoffs. The initial design does not add a separate energy meter.

Buildings and research open new ability options. Perks can transform those abilities. The system should support coordinated Builder and General decisions rather than isolated, costless button presses.

### Illustrative ability tradeoffs

The following are examples of the intended approach. Their names, mechanics, and numbers are not a final ability list.

- Forced march: gain mobility while giving up the ability to attack.
- Shield wall: gain protection while moving slowly and exposing a flank weakness.
- Overcharge: gain a temporary advantage followed by a shutdown period.
- Local healing: require positioning or a retreat to obtain healing.

## Provisional cooperative economy

The current proposal is a shared treasury with one purchase reservation per player. This is expressly provisional and may change. Reservation amounts, duration, cancellation, interface behavior, and conflict resolution have not been locked.

This proposal must be tested for whether both roles can make meaningful choices without frustrating one another. It must not be treated as a confirmed final spending system simply because shared resources already exist in the prototype.

## Decisions that remain open

- Final map layout, camera behavior, control feel, and approval of the battlefield presentation.
- Final army size, visible soldiers per battalion, and the limit on controllable groups.
- Exact unit and building content, resource values, costs, production times, research trees, cooldowns, and balance.
- Exact mission objectives, optional objectives, enemy compositions, boss mechanics, perk pool, and permanent unlock pool.
- Whether the shared treasury and per-player reservation proposal survives cooperative playtesting.

Unspecified values remain open for explicit design and playtesting decisions.


## Current prototype and verification

The current public Ironwood Reach build is a battlefield approval prototype built with Three.js and custom JavaScript and TypeScript. It is not the complete campaign described in this document.

[Current public prototype](https://ironwood-reach.rlm7d.chatgpt.site)

### Documented prototype scope

The prototype documents open terrain, fixed construction sockets, physical building footprints, economic territories, finite deposits, automatic worker loops, a shared resource balance, building recruitment, battalion movement and combat, role abilities, timed enemy raids, co-op rooms, and one battlefield win or loss state.

Its current practice reset is a testing feature. It does not change the confirmed no-retry rule for a failed campaign run. Campaign routes, perk drafting, permanent rewards, the full roster, final art quality, and final difficulty are not implemented or approved as complete.

### Recorded technical evidence

- 47 of 47 regression cases passed.
- 5,000 of 5,000 building-aware movement orders passed.
- A local production HTTP smoke test covered 51 requests, including room lifecycle, authorization, concurrency, readiness, simulation, and pause consistency.

These results support mechanical and integration coverage. They do not establish that the game is fun, balanced, visually approved, or proven with two people in live browser play.

### Required verification gates

Interactive playtesting must be followed by fixing observed issues and retesting. For the browser goal, a real two-client test is required. The map, camera, controls, actual browser rendering, and cooperative play still need direct validation and approval.

The recorded browser preview attempt was blocked with ERR_BLOCKED_BY_CLIENT. Actual interactive browser validation and human fun or balance validation have not been completed. Offline renders and automated tests cannot substitute for those checks.

### Godot and implementation direction

A separate Codex handoff for a from-scratch Godot rebuild has been requested. Godot 4.6.3 was installed in the preparation environment; availability in a different environment must be checked. The current prototype remains a Three.js implementation. A Godot rebuild has not yet been carried out or proven.

Before beginning the full rebuild, prove that the target workflow supports interactive playtesting, fixing observed issues, and retesting. Do not defer that proof until replacement of the current prototype. Public hosting is authorized. Engine changes, a successful build, or publication alone do not satisfy the playability and quality gates.
