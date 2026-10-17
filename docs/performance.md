# Rendering audit

The audit began against commit `f9532ba`, before the subsequent chipped-stage
geometry changes. Native measurements use Godot 4.7.2 Compatibility on Apple M4,
1280×800, four stationary chairs with all four animated foam plumes active.

| Counter | Before | After resource sharing and batching |
| --- | ---: | ---: |
| Draw calls including shadows | 1,744 | 996 |
| MeshInstance3D nodes | 862 | 401 |
| Unique meshes on those nodes | 859 | 90 |
| Rendered primitives | 2,535,600 | 2,535,600 |

These are rendering counters, not a claim of a particular FPS gain. CPU timing
varied with editor/background activity; repeat measurements on the target Mac.
The deterministic before/after images differed by a mean of 0.009 per 8-bit
channel, with 99.97% of channels within three values. Geometry, materials, lighting,
foam population and supersampling were retained during this optimization.

## Changes

- ModelGeometry caches identical immutable mesh resources, including rounded and
  curved cushions. Materials and transforms remain independent per instance.
  A 256-entry bound prevents unbounded growth during editor experimentation.
- Repeated opaque furniture parts are instanced with MultiMesh within each prop.
  This keeps visibility bounds local rather than combining the entire map.
  Animated chair rigs and transparent objects retain independent transforms.
- Foam calculates sort depth once per sphere and uploads one packed instance
  buffer per plume. Back-to-front ordering, density, timing and fade remain intact.
- Empty score rows allocate no 3D viewport and perform no animation updates.
- After a brief first-use render warmup beneath the opaque title, the arena is
  hidden for the rest of the introduction until the synchronized round start.
- Survivor resolution runs only after queued eliminations. Presentation no longer
  requests a 2D redraw every frame for native 3D models.
- Stage safety caches its polygon and inscribed radius. Most interior safety
  queries use a circle fast path; near-edge queries use the actual chipped outline.

The audit also reviewed stage/round ownership, pause/fall cleanup, AI and spray
queries. Four-seat simulation is small; its force and controller behavior were
kept intact rather than replacing it with speculative systems. Supersampling,
mesh tessellation and foam transparency remain future GPU profiling candidates.

Godot's [3D performance guidance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html)
and [bulk MultiMesh buffer API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-multimesh-set-buffer)
provide the underlying instancing and upload conventions.

## Reproduce

```sh
godot --path . --script tools/profile_render.gd -- --capture=/tmp/office-profile.png
```

This freezes physics and manually advances four chair views for a comparable
visual workload. It reports construction time, scripted visual-update CPU time
and native rendering counters. Use a graphical run for GPU counters; headless
Godot uses a dummy renderer. The capture argument is optional. This is a
microbenchmark, not an end-to-end gameplay frame-time measurement.

Resource regression checks cover sharing without mutation, material independence,
static batching, colliders, packed foam data and empty score rows. Native runs
also validate GPU transform/color readback, which the headless renderer omits.


## Ten-player audit (October 2026)

The setup now supports 2–10 total participants. The following changes preserve
physics, foam density, geometry, materials and animated chair pivots:

- Foam sorts packed integer depth keys in native code rather than invoking a
  GDScript comparator for every comparison. Depth is quantized to 0.00001 world
  units. Fully transparent spheres no longer consume rendered instances. All
  plumes share one immutable sphere mesh and shader material.
- Extinguishers share one baked assembly with five material surfaces. Chair
  bases, individual casters and suspended seats merge their rigid parts while
  retaining separate animation pivots. Cached assemblies have a bounded cache;
  the seat colour is part of its cache key.
- Viewports use a one-pixel mesh LOD threshold instead of disabling imported
  LODs. This also applies to supersampled portraits and score characters.
- Sleeping and frozen furniture skips redundant pose and floor-support updates.
  Native impulses wake sleeping props; falling props stop processing after cleanup.

On Apple M4, a 1,200-update headless foam microbenchmark dropped from 583 to
422 microseconds per plume update (about 28%). Thirty extinguisher constructions
dropped from 187 to 11 milliseconds, including the first baked assembly.
These measure specific CPU operations, not overall gameplay FPS.

The ten-chair native island fixture reported 1,216 draw calls and 261 mesh nodes
after rigid-part batching. Enabling the one-pixel imported LOD threshold reduced
rendered primitives from 4,242,016 to 3,528,376 in that fixture (about 17%).
Counters depend on the map and foam animation frame; remeasure on target hardware.
Use `--players=10` with the profiling command above to exercise the cap. The
fixture fixes the human colour and frozen simulation for repeatable captures.


## First-use rendering stalls

The native bull-office probe reproduced an approximately 816 ms arena-reveal
frame and a 248 ms first-windup frame on Apple M4. Later turns did not have that
spike. The title previously hid the 3D world completely, so material and instanced
foam rendering paths first reached the GPU during gameplay.

Rounds now briefly render their real world beneath the opaque black title.
Presentation-only warmup also includes the bull's charge guide, stun decorations
and an in-view foam instance. It waits for normal scene-tree/render frames so
visibility and transforms reach the renderer; forcing a draw immediately after
changing them did not warm every path. Chair views keep the sample foam visible
through that warmup, then restore the normal off state. No physics, input, hazard
clock or startup pressure advances. The world stops rendering again afterward
until live play begins.

In the matching follow-up run, the first windup frame was 8 ms and no live frame
exceeded 40 ms. Compilation/upload work now occurs beneath the title. These are
local frame samples, not an FPS guarantee across hardware or background workloads.

```sh
godot --path . --script tools/profile_round_start.gd
# Optional maximum roster:
godot --path . --script tools/profile_round_start.gd -- --players=10
```

The native-only probe logs slow frames and bull phase changes, including the
previous scripted tick time, then reports live maximum and 95th-percentile frame
times. Regression checks verify warmup restores visibility and leaves player and
hazard state unchanged. Headless tests skip GPU warmup but exercise the hazard's
presentation state restoration.


## Crumbling floors

Fractures rebuild stage meshes and supporting colliders only when an outline
revision changes, rather than per physics tick. AI uses a cached 512-direction
clearance table. Warning meshes update only when their pending revision changes;
falling chips share materials and are capped at 36 non-colliding rigid bodies,
with primitive inertia proxies and finite lifetimes. Existing furniture models
are transferred at first contact with a departing chip rather than rebuilt.
