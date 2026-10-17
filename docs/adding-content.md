# Adding content

Keep feature-owned scripts, scenes, resources and artwork together. Runtime state
belongs to scene instances; shared definitions contain authored data only.

## A map

1. Create `game/stage/<map>/<map>.gd`, `.tscn` and `.tres`. Keep private actors and
   assets there too. The scene root extends `ArenaStage`; shared office features
   can extend `OfficeStage` from `game/stage/shared/`.
2. Implement the support, spawn and navigation contracts documented on `ArenaStage`.
   Inputs and returned poses use world coordinates. Keep the rendered floor,
   physical support, native fall colliders and AI boundaries consistent.
3. Put a stable ID, name, hint and scene in a `StageDefinition`. Register it in
   `MatchConfig.STAGE_PATHS`; the testing selector includes it automatically.
   `MatchConfig.stages` holds the chosen pool, from which rounds draw independently.
4. Advance hazards only through the live round's supplied physics delta. Respect
   `round_running`, stop on results and keep mutable state out of shared resources.
   Request eliminations with `elimination_requested`; maps never award scores.
5. Test spawn clearance for 2–10 seats, transformed support, navigation, collisions,
   lifecycle/reset and real chair physics. Check native rendering as well.

Use `RenderStyle.PIXELS_PER_UNIT` (43). Stage `content_scale` resizes shapes/models;
never scale simulated rigid-body nodes. Reuse furniture from `game/props/<type>/`.
Keep fixed pieces flush in rows or provide genuinely traversable aisles; avoid
staggered pockets between shelves, printers and cabinets. Loose clutter should yield.

Both crack maps reuse `game/stage/shared/crumbling/`. One evolving outline supplies
support, rendering and collision. Pending sections warn before disappearing, and
full-depth falling sections use the map's world-height fade on top and sides.
Call `OfficeProp.release_for_fracture()` with departing polygons so partially
supported furniture transfers into native physics while retaining player collision.

### Furniture cut at an edge

The island owns its baked meshes in `game/stage/a_floor_in_the_crack/art/`.
Update the source poses/outline in `tools/bake_office_cut.gd`, then run:

```sh
godot --headless --path . --script tools/bake_office_cut.gd
```

Assign the result through `baked_visual_mesh` and tag `cut_at_edge`. `OfficeProp`
clips compound colliders at their own heights; capped visual CSG runs only during
this offline bake. Rebuild when the baked prop pose, content scale or outline changes.

## A skin or hat

Create `game/character/skins/<skin>/` with its `CharacterSkin` resource and private
shader/logo assets. Register its resource path in `SkinCatalog.PATHS`. Profiles
save stable IDs, never arbitrary paths; unknown values fall back safely.

Preserve the seated model's origin, scale, +Z forward direction and hand positions.
The unchanged body uses `game/character/art/character_surface.gdshaderinc`
for its flush face panel and exactly two eyes. Clothing uses separate closed
meshes and the shared fabric shader; collars, cuffs and hems have real thickness.
`CharacterGarments` adds shared hood, pocket and cord geometry. Rebuild clothing
with `python3 tools/build_clothing.py`, then import in Godot. The offline tool
validates closed surfaces; no mesh baking runs during play.

Colour uniforms use `source_color`;
`CosmeticColours` supplies saturated garment colours and contrasting logo ink.
Keep attribution beside third-party artwork. New hats register in `CharacterHats`.

Home, gameplay, falls, roster and scores all consume appearance snapshots through
`ChairModel`. Meshes/shaders are shared immutable data; materials are instance-owned.
Cosmetics must not change movement, mass or collision. The exposed slots are Hat,
Top and Colour; there is no Chair option. Validate profile persistence,
fallbacks and all character views before exposing new choices.
