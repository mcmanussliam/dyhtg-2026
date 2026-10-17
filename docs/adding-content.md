# Adding maps and character skins

Keep gameplay code, scenes and resources together by feature. Authored definitions
are reusable resources; round state, scores and elimination flags belong to the
running match. Do not put runtime state into shared resources.

## Maps

1. Create an `ArenaStage` scene and script under `game/stage/<map_name>/`.
2. Implement `spawn_pose`, `has_support`, `is_safe`, `safe_target` and
   `create_presentation`. Support and navigation consume world coordinates;
   spawn poses also return world transforms. Account for the stage's transform.
3. Build the floor, static furniture and falling-body collision in one 3D world.
   Use `RenderStyle.PIXELS_PER_UNIT` (43 authoring pixels per metre). Visual
   geometry and physical support must share the same boundary. Keep live chair
   bodies unscaled; `content_scale` resizes their collision shapes and artwork.
4. Put hazards behind `start_round`, `tick_hazards` and `stop_round`. Request an
   elimination through `elimination_requested`; never award scores in the map.
5. Create a `StageDefinition` resource with a stable ID, display name and scene.
   Add it to `GameApp.config.stages` in the Inspector, or to an authored
   `MatchConfig` resource. The match cycles through the array in order, wrapping.
   Empty or invalid rotations fall back to A Floor in the Crack. Definitions are
   validated at match start and metadata is copied into the match snapshot.
6. Cover spawn clearance, translated support, navigation, hazards, obstruction
   and falling-body collision with tests. Run actual chair physics on the map.

Only A Floor in the Crack ships today. Do not add a planned map just to fill the
rotation. Reuse furniture scenes from `game/props/`; see its README for clipping
and offline baking. New maps do not require changes to scoring or chair controls.

## Body skins

- `game/character/art/` owns character mesh and skin shader sources.
- `game/character/skins/` owns `CharacterSkin` resources. Each defines a stable ID,
  display name, mesh, body shader and face lightening. Keep IDs stable in saves.
- `SkinCatalog.PATHS` explicitly registers supported resources. Profiles save IDs,
  never arbitrary paths. Unknown IDs fall back to the default body.

Duplicate `skins/default.tres`, supply original artwork and register its path.
Keep the seated mesh's origin, scale, forward direction (+Z) and hand positions
compatible with the chair and held extinguisher. The default face shader uses
body-local coordinates for its flush panel and two eyes; a differently shaped
mesh can supply its own shader with the same `skin_colour` and `face_colour`
uniforms. Colour uniforms must use `source_color`.

`CharacterAppearance.body_id` resolves the registered resource. The match copies
its metadata into the participant roster. Home previews, live chairs, falling
models, HUD portraits and scores all use `ChairModel.build(colour, skin)`.
Shared meshes and shaders are immutable; each model owns its material instance.
Skins must not change mass, collision, thrust or steering.

The Body menu cycles None and registered non-default skin IDs. It currently
includes JPMorgan, a black T-shirt using the original mesh and a clothing shader.
Its optional `chest_logo` texture is supplied by the skin resource. The shared
`character_surface.gdshaderinc` keeps the default face and two eyes identical
between skins. Registering another valid resource exposes it in Body automatically.
Hat and chair slots remain None and need their own authored attachment contract
before options are introduced.

## UI and lifecycle

Introductions and scores remain plain black. Scores advance after three seconds;
the final celebration returns home after five. Arrow keys can advance early.
Each score screen emits one action and stops its countdown. Removed screens own
no surviving timers. Held spectator input cannot block automatic progression.

HUD portraits render once, retain transparent circular crops and grey out after
the round commits eliminations. Do not add continuously rendered preview worlds
for static icons. Dynamic stage and character presentation stays in the shared
main 3D viewport. Fast-forward increases physics frequency with time scale, and
restores both when spectating ends.

## Checks

Run `python tools/check.py --godot /path/to/Godot` in the development environment.
This checks formatting, lint, import, the sandbox and match suites, and startup.
The regression suite covers resource validation, map rotation, skin persistence,
single-shot timed results and long seeded AI matches. Also inspect native
rendering and playtest: headless checks cannot establish appearance or game feel.
