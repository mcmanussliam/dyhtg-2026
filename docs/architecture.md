# Runtime ownership

`game/app/main.tscn` is the production entry point. The app owns the current
menu and one match. Home and setup use an isolated 3D office diorama; gameplay
uses native 2D rigid bodies with a shared orthographic 3D presentation.
No autoload or global event bus is required.

`MatchConfig` is a validated copy of the total player count (2–10, default 2) and win target.
`MatchState` stores stable participant IDs and round wins independently of scene
lifetimes. It accepts one result per round and ends a match at the chosen target.
A draw records the round without awarding a win.

`MatchController` owns one `RoundController` at a time. Continuing destroys the
old round and creates fresh stage, chair, input and presentation instances.
Rematching creates fresh match state. Deferred menu transitions consume their
input event before replacing UI; held arrow keys must be released before the
next screen accepts input.

`RoundController` has four phases: introduction, live, resolving and finished.
Live play begins immediately after the title. Every chair smoothly builds
extinguisher pressure over two seconds, scaling propulsion, spray pushes and
foam together while steering remains fully responsive. This curve follows the
physics clock, so pause and spectator speed stay consistent. The first bull starts
at the office center; subsequent bulls walk through the saloon doors.
The physics clock controls the introduction, which shows text on an opaque black background. All chairs unfreeze and start their
continuous jets in the same update. Stage rules and hazard requests enter one
elimination batch each physics tick, so simultaneous falls produce a draw
rather than a result that depends on iteration order. Scoring occurs only after
resolution, through MatchState. The shared round viewport stops updating behind
the results panel.

`Chair` owns steering torque, thrust, contact reactions and speed limits.
`active` means surviving, while `drive_enabled` controls propulsion and spray.
Round setup freezes rigid bodies. Elimination removes arena collisions and freezes
the 2D body. Unsupported falls transfer its planar velocity and yaw rate into a
native 3D rigid body carrying the same model. The stage and chairs share one
3D world, so real depth testing hides falls behind the floor. A base collider and
body capsule contact the platform edge, producing physical tipping before gravity
supplies the drop. No scaling, fading or extra spin is added. The legacy sandbox
retains an isolated character-render path for its independent regression fixture. The ordinary physics sandbox retains its default
always-on behaviour.

`RoundView` owns the native 3D scene, camera and lighting in the main viewport.
`RenderStyle` centralises world scale, lighting, shadows and viewport conventions.
Isolated UI previews use their own supersampled viewports.
The 2D movement simulation maps into this presentation at 43 pixels per metre;
physics heading appears exactly once. Active chairs remain 2D bodies, while
eliminated unsupported chairs transfer into native 3D fall physics. Presentation
floor colliders never affect the live 2D movement simulation.

`ArenaStage` supplies support queries, elimination rules, safe navigation targets,
spawn poses and a hazard lifecycle. `StageDefinition` supplies authored identity
and scene references. Current maps are the chipped island, the office pit and the bull office.
`SpawnLayout` retains authored poses where they fit and resolves dense rosters
against furniture, floor margins, other chairs and map-specific entrance clearance.
See [adding-stages.md](adding-stages.md) for the extension contract.

The results UI uses a plain black background and receives copied participant data. Each win is represented by a
real 3D star mesh. Confetti belongs only to the match-winning result. Menus use
Left to move through items and Right to change or activate the current item.

`game/session/gameplay.tscn` remains a development sandbox for the existing
movement and controller regression suite, rather than a second production boot
path. Its R/F2/controller-join commands do not run in a normal match.

## Validation

`tools/check.py` checks formatting and lint, imports the project, runs the legacy
physics suite and the focused match/stage/menu/round suites, then boots the main
scene. Keep `.uid` files in version control. Headless rendering does not verify
visual appearance; native graphical previews supplement these checks.

## Character appearance

CharacterAppearance is a Resource containing stable cosmetic IDs. Hat, body and
chair currently accept only `none`. Colour defaults to `random`; resolving it
chooses a palette colour once, so the preview does not change while idle. Match
configuration takes a validated independent snapshot with that resolved colour.
Scores use participant colour snapshots, and AI palette assignment avoids an
identical human colour. UI selects values; it does not own cosmetic data.

The small ConfigFile profile at `user://character_appearance.cfg` saves selection
IDs through an atomic temporary-file replacement. Runtime resolved random colours
are not saved, so Random stays random on the next launch. Missing or unsupported
values fall back to implemented defaults. App tests disable the live profile path,
and profile tests use their own temporary files.

A stage may author `content_scale` independently of its platform bounds and camera
framing. Office props scale their visual and collision transforms together. Chairs
resize unique collision shapes, render models and fall colliders without scaling
RigidBody nodes. Steering torque compensates for the resulting inertia change;
linear speed tuning stays unchanged. The office stage uses 1.18.

## Local settings

`GameSettings` owns validated anti-aliasing and shadow preferences separately
from match rules and cosmetics. `SettingsMenu` uses `TwoKeyMenu` option/value rows
and applies changes immediately. Settings and `CharacterAppearance` share
`ProfileStore` for ConfigFile loading and atomic replacement, in separate user files.
`RenderStyle` carries current anti-aliasing and shadow preferences into newly
created worlds; applying settings also updates existing viewports and key lights.

Movement tuning includes turning drag derived from actual angular speed. The
rigid body retains continuous thrust and inertia while sharp turns shed speed.

`SpectatorSpeed` belongs to the round and owns temporary 3× timing only while
the human is eliminated and multiple AI survive. It raises physics frequency
with time scale to retain the simulation step size, and restores timing on
release, pause, focus loss, resolution or removal. Its always-processing UI
keeps pause cleanup independent of the paused round.

AI attacks hold their aim long enough to turn and deliver a shove. Safety margins
and pursuit insets shrink gradually during a stalled round; total round urgency
survives eliminations so the final pair does not return to prolonged safe play.
Pilots still produce only steering commands. `PilotUnstuck` watches actual
position progress independently of the current target and reported speed. After
roughly three seconds without meaningful displacement it chooses a safe, clear
escape corridor and commits long enough to leave the obstruction. Wider retries,
asymmetric seat timing and less crowded destinations break mirrored responses;
brief pushing contests continue normally. The pit steering rollout predicts
braking toward that escape goal, avoiding false vetoes that previously pinned
chairs beside furniture. New hazards or an unsafe route cancel the escape. Long physics regressions cover six
seeded two-, three- and four-chair fights for 90 simulated seconds each, checking
completion, opening survival and bounded turning.

`RoundRoster` centers circular render-once `ScoreCharacter` close-ups along the
bottom during gameplay,
using the participant snapshot for identity. Elimination batches grey the affected
portraits with a canvas shader; no additional 3D rendering is required per frame.
Portrait lighting is neutral and the transparent premultiplied composite clips
smoothly to each circle. The spectator prompt stays at the top left.
The roster is absent from introductions and results. AI urgency now starts after
two seconds without an elimination and reaches its first peak after eighteen;
long-round urgency persists across eliminations. Seeded pacing checks require
rounds to resolve within 45 simulated seconds in the covered scenarios.

## Content definitions and timed results

`MatchConfig.stages` holds an ordered rotation of `StageDefinition` resources.
Validation rejects missing scenes and roots that do not extend `ArenaStage`.
`MatchController` selects the next definition without changing score ownership.
Default content loads at instance creation to avoid scene/class preload cycles.
`MatchState` validates only its scoring and roster inputs, not map scenes.

`CharacterSkin` resources live beside character artwork, with registration in
`SkinCatalog`. Profile body IDs resolve only against that catalog. The match
copies skin metadata; immutable meshes and shaders are shared. Every character
view consumes that same resource through `ChairModel`, keeping previews, falls
and scores consistent. See [the content guide](adding-content.md).

`ResultsScreen` owns a single-shot countdown: three seconds between rounds and
five seconds for final confetti. Manual and timed transitions use one guarded
action. `GameApp` clears obsolete pending actions whenever a screen is replaced.
The sandbox now distinguishes local stage bounds from world-space bounds and
spawns, so translated fixture geometry cannot leave bodies outside its walls.

## Movable props and edge survival

`OfficeProp` shares its authoring and presentation code across static and rigid
2D body roots. `PropMotion` owns loose furniture's stage lifecycle, native 3D
collider synchronisation and gravity handoff. Authoring scale resizes collision
resources and rendered children; simulated body nodes remain unscaled. Large
fixtures stay static, while office chairs, plants and coffee tables yield to
collisions. AI rays treat these loose props as pushable rather than fixed walls.

A round checks a chair's base for remaining floor support. Partial overhang stays
in planar gameplay. Loss of all support starts native falling but keeps the seat
alive; `ChairView` confirms the drop only when the native body descends below the
floor. The round then commits elimination, updates portraits and resolves scores.
Falling chairs cannot drive, receive planar spray forces or become AI targets.
