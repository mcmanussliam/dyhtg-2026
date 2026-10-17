# Home screen, first-to-N matches and reusable stages

Status: implemented for the circular-stage milestone. Future office hazards and multiplayer remain deferred.

## Confirmed scope

- Boot into a home screen showing the existing character sitting on its chair in
  an office. No character customisation or placeholder customisation button.
- Play opens setup for AI count and **wins needed**. The match ends when someone
  reaches that many round wins; this is not a fixed number of rounds.
- Initially one human and one to three AIs, using the current four-chair capacity.
  Multiplayer implementation is deferred. Proposed defaults: one AI, first to five.
- Every round uses the same circular platform surrounded by black void.
- Last surviving participant wins the round. Falling off eliminates a participant.
- Every round begins with its map name on plain black, hiding stationary chairs with
  extinguishers off. The text fades away before all extinguishers activate together.
- After every round, display all participants and their accumulated round wins.
  Each won round gets a 3D token next to the participant's name.
- The match-winning results screen adds confetti. Ordinary round wins do not.
- All menu actions work with Left and Right only.

## Player flow and two-key navigation

Home -> Match setup -> Round introduction -> Live round -> Round results.
Results -> Next introduction while nobody has reached the target.
Results -> Match victory and confetti when someone reaches the target.
Match victory -> Rematch or Home.

Use an animated office diorama behind readable Godot Control-based menus. Reuse
ChairModel directly with no gameplay physics or foam emitter on the home screen.

| Screen | Focusable elements | Left | Right |
| --- | --- | --- | --- |
| Home | Play, Quit | Next item, wrapping | Activate item |
| Setup | AI count, Wins needed, Start match, Back | Next item, wrapping | Cycle value or activate button |
| Round results | Continue, End match | Next item, wrapping | Activate item |
| Match victory | Rematch, Home | Next item, wrapping | Activate item |

Proposed setup ranges are 1-3 AIs and 1-5 wins. Values wrap from maximum to minimum,
so neither a third key nor a separate decrement interaction is required. The
range can be expanded without changing navigation.

Use explicit focus order, a clear selection highlight and a compact instruction
such as "Left: select / Right: change or confirm". Process activation on key press,
ignore key-repeat activation, and consume handled events. Transfer focus explicitly
when screens change. Prevent a held confirmation key from activating the next
screen or accidentally steering on entry to gameplay. Do not require Enter,
Escape, Up/Down or the mouse for any menu path.

Menu actions and steering actions remain separate Input Map actions even though
the physical arrow keys are shared. Normal matches must not react to sandbox
reset, F2 takeover, secondary-keyboard takeover or controller hot-join shortcuts.
No new pause gesture or extra control scheme is needed for this milestone.

## Design principles

Apply Godot's documented practices: independently usable scenes, explicit ownership,
Resources for authored data, and parent coordinators connecting child signals.
There is no single mandatory "industry standard" architecture; these conventions
fit this project's size without adding a framework or a global event bus.

Keep the native 2D rigid-body simulation and the current orthographic 3D artwork.
A full 3D physics conversion is unnecessary for a flat platform with ring-outs and
would invalidate movement already tuned through playtesting. Falls will have a
separate gravity-driven visual animation; gameplay elimination is authoritative
and happens in the physics update. Revisit 3D physics if later stages require
stacking, ramps or true vertical rigid-body interactions.

## Ownership and proposed feature layout

| Owner | Responsibility |
| --- | --- |
| App root | Home/setup/match screen transitions and ownership of the current match |
| Match controller | Participants, target wins, scores, round creation and match victory |
| Round controller | Intro/live/resolving phases, spawning, simulation and elimination |
| Stage scene | Surface, spawns, arena rules, hazards, visual environment and obstacles |
| Chair | Steering, propulsion, contacts and explicit drive/elimination state |
| Chair view | Models, foam, chair rocking and falling presentation |
| Menu/result screens | Display supplied state, manage focus, emit user intentions |

Proposed layout (new files are created only when their implementation phase needs them):

    game/app/          entry scene and screen flow
    game/home/         home menu and office diorama
    game/match/        setup data, runtime scores, match controller, result screens
    game/round/        round scene, round controller, map-title overlay
    game/stage/        stage contract, stage definitions, circle stage scene
    game/chair/        existing chair physics, models and foam
    game/input/        steering commands, local input and AI
    game/combat/       existing spray force/obstruction
    game/ui/           shared two-key navigation, theme and 3D win-token scene
    tests/            runner and focused feature suites
    tools/            existing development checks and asset generation

Keep scripts beside their scenes and resources. The app root owns one match;
the match owns one round; the round owns its stage and chairs. A fresh round scene
replaces the previous one, ensuring physics bodies, particles and signals are
cleaned up together. Score data lives in match state, not chair nodes or UI rows.

Use a small explicit enum for round phases, not a class-per-state framework.
Authored MatchConfig and StageDefinition Resources describe settings and maps;
mutable match results are separate per-match state so shared Resources are never
accidentally used as save data. Participant IDs remain stable across respawns.
Controllers consume ChairCommand for every human and AI. Do not add networking,
lobbies, Steam services or persistence as part of this refactor.

## Round lifecycle

1. Instantiate the chosen stage, validate its definition and create all chairs at
   safe spawn poses. Keep velocities zero, bodies frozen and spray/steering disabled.
2. Show the map name, for example "A Floor in the Crack", with a proposed 2-second hold and
   0.5-second fade. These durations are editable presentation settings.
3. At the intro deadline, after the title is transparent, enable all surviving
   chairs together on the same physics tick. The UI follows the round's clock;
   round logic must work in headless tests without waiting on a UI animation.
4. Run steering, thrust, spray and contact physics. Tick active stage hazards,
   evaluate support and arena rules for every participant, collect elimination
   requests, then resolve the survivor count once. Hazards never award wins.
5. On falling, immediately disable that chair's steering, thrust, spray force and
   collisions with living chairs. Animate its retained outward motion, downward
   acceleration and fade into the void, removing its ground shadow. It cannot
   re-enter the round. Remaining participants continue playing.
6. Once at most one survivor remains, stop gameplay and let the brief fall/end
   presentation finish. Freeze remaining chairs and show results.
7. Award one win if there is one survivor. If everyone falls on the same physics
   tick, record a draw with no award. Show results and play another round; the
   first-to-N target never changes. Never choose a winner by player iteration order.
8. Record the result exactly once. Once a participant reaches N wins, show final
   results with confetti. Otherwise Continue creates a new round on the same map.

Keep "alive" separate from "drive enabled": intro chairs are alive with their
extinguishers off. The present Chair.active/spraying coupling must be refactored
rather than used as a substitute for round state. Fallen chairs cannot apply spray
forces while their last foam particles/fall animation are being presented.

The match controller owns scoring and emits result snapshots. UI animations,
repeated button presses, delayed callbacks and scene teardown must not be able to
award an additional win or start two rounds.

## First stage and future map contract

The first map is a circular carpeted platform, viewed through the current angled
camera, surrounded by a genuinely black void. The projected circle will appear
elliptical on screen. Give the edge enough visual definition to read the drop,
but add no collision wall, invisible guardrail or floor beneath the void.

StageDefinition contains an ID, display name and PackedScene. The stage scene owns
spawn markers, surface geometry, optional obstacle collisions and its visuals.
The round controller asks the stage for spawn poses, support and elimination
conditions. It does not know a map's radius, mesh names or room-specific child paths.

For the circle, use one editable centre/radius as the source for rendering, spawn
validation, AI navigation and support checks. A chair loses support when its centre
crosses the edge, permitting a readable partial overhang before it falls. Check
boundary cases explicitly. Use symmetric, safely inset spawns with initial thrust
toward the platform interior, so players do not lose immediately after the intro.

Replace the AI's rectangular refuge check with stage-aware support prediction.
It should anticipate the edge using position, velocity and turning ability, while
still steering through the exact same torque and inertia as the human.

Future maps implement the same support/spawn/navigation contract with their own
polygons, holes and physical obstacles. Provide editor configuration warnings for
missing spawns, invalid stage data and unsupported spawn positions. Adding a map
should mean adding its scene and definition and registering it in the stage list,
without editing scoring, menu or chair code. Initially the list contains only the
circle, repeated for every round; no map picker or rotation feature is needed yet.

## Planned office maps and the extension points they need

These maps inform the architecture now. Their assets and full gameplay are later
milestones; the first implementation still repeats the simple circle stage.

| Working title | Intended behaviour | Required stage capability |
| --- | --- | --- |
| You're Fired! | Fire slowly encroaches around an office arena, reducing safe space | A time-varying danger region, its own shrink controller and readable warning/edge visuals |
| Sumo-ring in the office | A sumo platform inside an office; leaving the ring eliminates a player | An allowed arena boundary independent of the surrounding office floor |
| Pit of death in the office | A pit within an otherwise solid office floor | Walkable surface with an interior hole and a pit-specific falling presentation |
| Bull in the Chinese office? | A bull moves around the office and attacks chairs | A moving physical hazard with targeting, charge behaviour and contact feedback |

**Separate support from safety.** A chair can have solid office floor beneath it
but already be outside the sumo boundary or inside the fire. Conversely, a chair
can be inside the office boundary but over a pit. Do not implement every loss as
"outside one rectangle/circle", and do not make a rendered floor imply safety.
Each stage provides surface support, legal arena regions and active danger
queries separately. The circle initially uses the same edge for support and loss.

**Give hazards a round lifecycle.** Stage-owned hazards have initialise/start/stop
behaviour. Their movement, attacks and danger timers start with the live-round
transition, never during the map-name introduction. They stop for pause and
results and reset with a fresh stage instance. The match controller remains
unaware of fire radii, pits or bull behaviour.

**Collect eliminations centrally.** Stages report participant IDs and causes such
as ring-out, pit fall, fire contact or a configured hazard hit. The round controller
validates and batches these requests with support losses before checking survivors.
An already eliminated participant cannot be eliminated or scored again. Stage
presentation chooses the appropriate fall/burn/impact animation; scoring stays
identical across maps. Pit presentation can mask a falling chair behind its rim
instead of showing the chair through the surrounding solid office floor.

**Fire settings belong to its map.** Author the initial safe radius, delay before
encroachment, shrink speed and minimum radius in editable stage data. Start with
slow, clearly visible encroachment and tune through playtesting. Direct contact
elimination is the proposed first rule; any warning/grace interval is explicit
stage data. The new fire mechanic does not require a shared heat, health or fuel
system. Extinguisher/fire interaction is a separate future design decision.

**The bull is a physical actor.** Keep its reusable visual scene separate from a
stage-owned physics/behaviour controller. Give charges a visible wind-up, collision
response and recovery so players can read and evade attacks. Its impacts use
native rigid-body/contact physics. The bull is not a scoring participant and does
not teleport or arbitrarily change chair transforms. Whether a charge directly
eliminates a player or knocks them into another danger remains a map-rule decision;
the stage supports either without changing match scoring. Implement the actual
bull behaviour when that map is built, not as an empty framework now.

**AI sees the same danger rules.** Stage navigation exposes safe movement guidance
for the current live state: the shrinking fire radius, sumo edge, pit openings and
moving hazard threats. Reuse the chair AI's velocity prediction and torque steering;
do not hard-code all avoidance around the first circle's radius. This supplies
the necessary inputs without introducing a general-purpose navigation framework.

**Validation before each map ships:**

- Fire does not shrink during intro/pause, shrinks at the authored slow rate, and
  resets between rounds. Its visible edge matches its elimination region.
- Sumo elimination works outside the ring even while over a visible office floor.
- Pit elimination works inside the arena boundary; valid floor around the hole
  remains safe, and spawn markers cannot be placed over it.
- Bull attacks are disabled before round start, physical impacts are bounded,
  eliminated chairs are ignored, and the bull never enters the score table.
- Simultaneous hazard and ring-out events produce one consistent round result,
  with no duplicate eliminations, awards or callbacks after stage teardown.

## Results and presentation

Use an original small gold 3D star as the initial win token. It is readable at UI
size and can later be replaced with another object through the same token scene.
Each participant has a stable row: name, readable win count and one token per win.
Animate the newly earned token into place while retaining prior tokens. Show zero
wins clearly. A draw adds no token. Do not let row reordering make names jump after
wins; highlight the round winner within their stable row.

Render tokens in small transparent SubViewports using shared meshes/materials.
Avoid a separate viewport for every individual star. Final victory uses the same
score view with a winner heading and a one-shot confetti layer. Confetti appears
only after the winning result is committed and must not obscure menu focus.

## Build order and acceptance gates

1. **Separate match logic and input ownership.** Introduce match configuration,
   participant/result state and explicit round phases. Extract the current session's
   mixed responsibilities. Move useful old sandbox behaviour to a development-only
   scene or test fixture; remove it from normal boot. Preserve current movement,
   contact feedback, models and foam tuning.
2. **Build a complete playable round.** Add the circle, surface/arena-rule contract
   and stage lifecycle,
   spawning, map-name intro, synchronised activation, falls, elimination and result
   resolution. Teach AI the circle's edge. Verify the entire first-to-N loop with
   simple results before polishing the menus.
3. **Add the two-key front end.** Home office diorama, Play, setup values, Start,
   Back, results Continue/End match, final Rematch/Home. Switch project boot to the
   home scene. Verify every path using only Left and Right.
4. **Polish scoring and victory.** Add 3D tokens, award transitions, final confetti,
   clean fall presentation and camera/edge readability. Respect gameplay pause in
   every transition and avoid expensive background rendering behind menus.
5. **Finish repository cleanup and verification.** Split the existing regression
   script into focused suites without adding an unnecessary test framework. Update
   the project README, architecture notes and a short adding-a-stage guide. Remove
   obsolete sandbox UI/code after replacements are covered. Keep .uid files and
   authored/import metadata; exclude .godot, virtual environments and build output.

Tests accompany each phase; the last phase is cleanup, not the first time the
feature is tested. Make each phase a reviewable change. Do not introduce unrelated
movement retuning, customisation or multiplayer while implementing this flow.

## Verification

- Preserve existing input isolation, physics limits, rebound, rocking, spray
  obstruction and reset cleanup checks using an appropriate physics fixture.
- Check intro chairs cannot move, steer or spray; all begin on the same tick only
  after the title has faded.
- Test support at the circle edge, safe spawns, fallen-chair collision/spray
  removal, and stage-aware AI over extended simulated play.
- Exercise the stage contract with small test fixtures for a changing danger
  region, a ring boundary over solid floor, an interior hole and a moving collider.
  These verify extension points without prematurely implementing the four maps.
- Test normal wins, simultaneous falls, no duplicate awards, score preservation
  across respawns, first-to-N victory, rematch reset and repeated Continue presses.
- Test focus wrapping, value wrapping, Back/Home, no key-repeat activation, held-key
  transitions and no menu/gameplay input leakage using only Left and Right.
- Check trophy counts against authoritative scores, final-only confetti, pause
  behaviour and cleanup of viewports/particles after many rounds.
- Run tools/check.py for formatting, linting, engine import, regression and startup.
  Visually inspect home/setup, intro, falls, results and confetti in native Mac
  rendering. Measure four-chair rendering again after integrating the new flow.

## References

These are the Godot conventions behind the proposed structure, not a claim that
one architecture is mandatory for every shipped game:

- [Scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
- [Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Keyboard/controller navigation and focus](https://docs.godotengine.org/en/stable/tutorials/ui/gui_navigation.html)
