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
- The arena is hidden during its opaque black introduction, eliminating covered
  geometry and shadow draws until the synchronized round start.
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
