# Runtime ownership

`game/app/main.tscn` is the production entry point. The app owns the current
menu and one match. Home and setup use an isolated 3D office diorama; gameplay
uses native 2D rigid bodies with a shared orthographic 3D presentation.
No autoload or global event bus is required.

`MatchConfig` is a validated copy of the chosen AI count and win target.
`MatchState` stores stable participant IDs and round wins independently of scene
lifetimes. It accepts one result per round and ends a match at the chosen target.
A draw records the round without awarding a win.

`MatchController` owns one `RoundController` at a time. Continuing destroys the
old round and creates fresh stage, chair, input and presentation instances.
Rematching creates fresh match state. Deferred menu transitions consume their
input event before replacing UI; held arrow keys must be released before the
next screen accepts input.

`RoundController` has four phases: introduction, live, resolving and finished.
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
and scene references. The circle is the only production map in this milestone.
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
