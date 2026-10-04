# Original prototype artwork

The medieval miniature terrain, soldiers, worker, buildings, selection rings,
and animation rigs in `game/scripts/client/art.gd` were created from scratch for
the Ironwood Reach approval prototype. They use Godot primitive meshes and
original vertex geometry, with no downloaded models, images, textures, game
assets, or copied character designs. Teal and mauve identify opposing factions.

The tree icon in `game/assets/icon.svg` is also original vector artwork made
for this prototype. Exported app icons are generated from that SVG.

Procedural generation uses a fixed seed for reproducible decorative placement.
Roads, border trees, rocks, banners, and architectural details are visual only;
they do not define passability, resources, economy, ownership, or game rules.

Geometry and plain-color materials are cached across instances. Soldier parts
support idle, walking, attack, hit, and death poses. These are prototype visuals;
human approval, animation quality, and performance remain to be evaluated in
the playable build.
