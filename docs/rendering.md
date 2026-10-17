# Native 3D presentation

Gameplay renders stage meshes, chairs, foam and falling bodies together in the
main viewport through one orthographic Camera3D. A shared depth buffer handles
occlusion. The existing 2D rigid bodies remain authoritative for flat movement;
fallen visual rigs use native 3D rigid bodies and stage support colliders.

One model unit represents one metre. `RenderStyle.PIXELS_PER_UNIT` defines the
43-pixel bridge to the established 2D simulation. The gameplay camera has a shared 0.60 vertical direction component for a more
front-facing view. Framing remains authored
by each stage; UI portraits retain their own framing.

## Shared style

`game/render/render_style.gd` configures the native viewport quality, lighting,
orthographic cameras and texture composition. All views use neutral white ambient
light (0.35), the same white key light (0.9, rotation −45°/−35°) and a soft white
fill (0.18). Material colours supply hue; full-screen colour overlays do not tint
the home character differently from its gameplay and score versions.

World scenes enable directional shadows, using an orthogonal shadow map, 70-metre
range and bias values tuned for metre-scale meshes. The project uses a 4096-pixel
directional shadow map. Score portraits and stars share the same illumination
but omit shadows because they have no supporting environment. Gold tokens retain
their metallic, roughness-controlled material. The stage floor uses one flat navy StandardMaterial3D. The cylinder has a plain
grey lit shader with only a long height fade from 8 to 24 metres below the floor.
There are no grain, checker, tile or panel textures. Viewport
textures are render targets for UI previews, rather than painted surface assets.

Main rendering and UI viewports use 4× MSAA. Automatic mesh LOD is disabled for
these small smooth models. Camera far distance is 100 metres. Compatibility remains
the desktop renderer; this change does not require Forward+ or a new graphics API.

## Isolated UI views

Home renders its office diorama in a 2560×1600 SubViewport. Score portraits render
at 560×528 for a 140×132 display; stars use one 1400×256 viewport per row for a
350×64 display, regardless of how many tokens that row contains.

These viewports own separate World3D instances so preview objects cannot collide
with the arena. TextureRect displays preserve the independent render resolution:
a stretching SubViewportContainer would resize its child and defeat supersampling.
Transparent previews use premultiplied-alpha composition and linear texture
filtering to avoid dark outline halos. UI text and controls remain native Controls.

## Validation

Headless tests verify actual portrait/token render dimensions after layout,
vertical alignment, stage support dimensions and match cleanup. Native Mac captures
check shadow acne, material colour, silhouettes, occlusion and alpha edges.
Performance and graphical quality still need playtesting on target hardware;
these conventions are project decisions, not a universal industry specification.

Relevant Godot documentation:

- [Viewports, isolated worlds and render targets](https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html)
- [3D lighting and shadow bias](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html)
- [StandardMaterial3D surface properties](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
