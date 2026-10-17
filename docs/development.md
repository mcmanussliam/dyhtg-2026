# Development process

Use **Godot 4.7.2 Standard**, pinned in `.godot-version`. Production starts at
`game/app/main.tscn`; F5 opens the normal home screen. `game/sandbox/gameplay.tscn`
is a separate legacy movement/controller fixture with its own R/F2/join shortcuts.

## Validate a change

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r tools/requirements-dev.txt
python tools/check.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

The checker enforces engine version, formatting, lint, import, runner parsing,
physics/feature regressions and startup. Each command has a 120-second timeout.
Godot can return zero despite script errors; the checker also rejects `ERROR:`
and `SCRIPT ERROR:` output. Register new suites in the appropriate root runner.

Useful individual commands, with `godot` on PATH:

```sh
.venv/bin/gdformat game tests
.venv/bin/gdlint game tests
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script tests/run_tests.gd
godot --headless --path . --fixed-fps 60 --script tests/run_match_tests.gd
```

For physics/render changes, inspect native graphics and playtest the affected maps.
Check partial edge support, furniture impacts, falling behind the floor, cleanup,
pause/results, and a crowded round where appropriate. Do not let profile tests
write the user's real cosmetics/settings files. Engine fixtures and finite seeded
AI fights are regression coverage, not a guarantee for every possible match.

## Profile before reducing quality

```sh
godot --path . --script tools/profile_render.gd -- --players=10 --capture=/tmp/office.png
godot --path . --script tools/profile_round_start.gd -- --players=10
```

Use graphical runs for GPU counters; headless Godot uses a dummy renderer. The
render fixture freezes simulation for repeatable model/foam comparisons. The
round-start probe reports live frame samples and bull phase changes. Compare the
same map, roster, settings, hardware and background workload. Microbenchmark CPU
times and draw-call counts are not end-to-end FPS guarantees.

Preserve shared immutable meshes, static batching and animation pivots, packed
foam buffers, one-pixel imported LODs, and render-once portraits. The title hides a
brief real-world rendering warmup, including foam and bull effects: removing it
previously caused first-use stalls. It must not advance gameplay or hazards.

Do not run editor imports concurrently with native captures. When scripting a
capture, allow scene/render state to update before forcing a draw. Repair stale
ignored editor tabs after resource moves instead of adding compatibility assets.

## Before committing

Review resource paths, `.uid` sidecars and import descriptors after moves. Keep
source assets and attribution with their owning feature. Never hand-edit Godot
binary resources; use ResourceLoader/ResourceSaver or the relevant bake tool.
Exclude `.godot/`, virtual environments, temporary captures and build output.
