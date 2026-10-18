# Please Remain Seated

A native Godot party game about soft characters on swivel office chairs, propelled
by continuously firing extinguishers. Steer, drift and push everyone else off the
floor. Open `project.godot` in **Godot 4.7.2 Standard** and press F5.

## Play

Home offers Play, Customise, Settings and Quit. Matches have **2–10 total players**
(default 2): one human and the remaining seats controlled by AI. Multiplayer is
not implemented. Choose a **first-to-1–5 wins** target; the default is first to five.
Setup’s Select maps page scrolls with Left and toggles maps with Right; all maps
start selected. Start match is unavailable while the pool is empty. Each round
independently picks a selected map, so repeats are possible:

- **A Floor in the Crack:** a chipped navy office island above black void.
- **A Crack in the Floor:** an office around a central pit, with bouncy outer walls.
- **The Bull in the Chinese Office:** bulls telegraph and charge; impacts launch
  players out. The first bull starts centrally; more enter through the saloon doors.
- **HR Training:** three horizontal office rail crossings with flashing red warnings. Trains
  sweep the top, middle and bottom. Independent arrivals accelerate and overlap;
  each train warns before entering, with opposing traffic held until its track clears.
- **Faulty Floors:** occupied office panels highlight before dropping into the void.
  Keep moving; holes remain for the rest of the round.

- **Under Construction:** an office with desks, site fences and a movable tool trolley.
  Two horizontal and two vertical lanes run through smashed openings in all four walls.
  A flat orange path highlights each digger's lane before it drives through, flattening
  furniture and launching any player in its way.

- **Computer Bugs** (*THE BUGS NEVER SLEEP*): sixteen workstations on four open-plan benches fill
  the floor, with a print area in one corner. Computers break one after another, starting
  with a random one. A broken computer is announced with an amber zone, then turns red and
  eliminates anyone standing in it; its zone keeps widening until it is repaired, and zones
  that overlap fuse into one flowing shape that is lethal throughout. Infection leaps from
  random broken computers to random clean ones along straight, harmless columns of bugs, in
  bigger and faster waves. Bugs never roam. One technician walks the aisles and repairs a
  single computer at a time, speeding up over the round but always slower than the infection.

Both crack maps begin crumbling after roughly 15 seconds: the island shrinks and
the hole widens. Full-depth sections fall away. Furniture tips under native 3D
physics and remains solid to players until it drops below chair height.

| Context | Left arrow | Right arrow |
| --- | --- | --- |
| Menus | Select next item | Change value or confirm |
| Gameplay | Turn left | Turn right |
| Spectating after elimination | — | Hold for 3× fast-forward |

A/D also steer. Esc pauses/resumes. Extinguishers are continuous and unlimited;
steering is the only gameplay action. After the black map title, controls start
immediately while propulsion, spray force and foam build over two seconds.
Wheel overhang alone does not eliminate a player: they must actually fall.
Last survivor wins a point; simultaneous elimination is a draw. Black score
screens show characters and 3D win stars, advancing after three seconds between
rounds. Final confetti returns to home after five seconds. Right advances early;
Left returns home. Held keys must be released between screens.

Customisation offers Hat, Top and Colour. Hats include Traffic Cone, Top Hat, Cap,
Mohawk, Glasses, Bald Side Hair, Hot Dog Hat and
Construction Helmet. Tops include JPMorgan, Hoodie, JPMorgan Hoodie,
T-shirt, Tank Top and High Vis Vest. Hats and tops default to None, colour to
Random; choices persist locally. Settings contains only anti-aliasing and shadows.

## Repository layout

Keep scenes, scripts and owned assets together by feature. Shared code belongs at
its narrowest common owner, rather than in another map's folder.

| Directory | Responsibility |
| --- | --- |
| `game/app/`, `game/home/` | Screen navigation and the home office diorama. |
| `game/match/`, `game/round/` | Persistent scores, round lifetime, spawning, results and spectator timing. |
| `game/stage/<map>/` | Each map's scene, definition, script and private actors/assets. |
| `game/stage/shared/` | Reusable office shell, rim geometry, shaders and crumbling. |
| `game/props/<type>/` | Reusable furniture scene, visual scene and model. |
| `game/props/physics/`, `shared/` | Furniture movement/collision handoff and common model helpers. |
| `game/chair/` | Chair physics and tuning; `presentation/` owns models, views and foam. |
| `game/character/` | Cosmetic IDs and profiles; `skins/<skin>/` keeps each definition with its assets. |
| `game/input/`, `game/input/ai/` | The shared steering command, local input and AI. |
| `game/combat/`, `game/render/` | Spray forces and shared rendering/mesh utilities. |
| `game/ui/`, `game/settings/` | Reusable UI, graphics preferences and atomic profile storage. |
| `game/sandbox/` | Legacy movement/controller fixture, not production boot. |
| `tests/<feature>/` | Feature regression suites; root runners preserve execution order. |
| `tools/`, `docs/` | Development utilities and short process guides. |

The app owns a match; the match owns one round; the round owns its stage and chairs.
`MatchState` owns scores outside replaceable round scenes. Maps request eliminations
but never award points. `ArenaStage` documents world-coordinate navigation and
physics-clock hazard hooks. AI supplies the same scalar steering command as humans.

Live movement uses 2D rigid bodies, with real torque and inertia. Stage, furniture,
characters and foam share one angled 3D world/depth buffer. Unsupported chairs and
furniture transfer to native 3D physics. `PropCollisionBridge` keeps falling props
solid to live 2D chairs. `RenderStyle` defines **43 pixels per metre**; keep simulated
rigid-body nodes unscaled. Python is tooling only, never a game dependency.

## Development

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r tools/requirements-dev.txt
python tools/check.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

Adjust the Godot path for your installation. Checks cover formatting, lint,
import/parse, engine regressions and startup. Also playtest natively: headless checks
cannot judge appearance, controller hardware or subjective movement feel.

See [development and profiling](docs/development.md) and
[adding content](docs/adding-content.md). Implementation contracts live in script
doc comments. Keep `.uid` files; exclude `.godot/`, virtual environments and builds.
