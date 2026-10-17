# Adding a stage

The match owns scores and creates a fresh round for each attempt. A round owns
one `ArenaStage`, its chairs, introduction and elimination resolution. A stage
owns floor support, legal arena regions, navigation guidance, hazards and art.
It never chooses winners or increments scores.

The shipped stage is `game/stage/a_floor_in_the_crack.tscn`, registered through
`game/stage/a_floor_in_the_crack.tres`. Its editable centre and radius are the common
source for drawing, support tests, safe spawns and AI guidance. It deliberately
contains no collision boundary: crossing the edge causes a fall. The camera
projects the circular surface into an ellipse; geometry stays in world space.

## Create and register a map

1. Create a scene whose root extends `ArenaStage`. Keep physics coordinates in an
   unscaled `Node2D`; the camera supplies the viewing angle.
2. Create a `StageDefinition` resource with a stable `id`, readable `display_name`
   an optional `hint`, and the scene. Validate the resource using `validation_errors()`.
3. Register that resource with the match's stage selection. Each round randomly selects from the island, pit office and bull office.
   Add its definition to `MatchConfig.stages`; each round draws independently from the list.
4. Add geometry, support, spawn, navigation and lifecycle tests before shipping.
   Keep stage-specific settings exported in its script or an authored Resource.

## Required contract

All point arguments and returned poses use global world coordinates.

| Method | Responsibility |
| --- | --- |
| `has_support(point)` | Whether solid supporting surface exists beneath a chair's centre. |
| `elimination_reason(point)` | Empty `StringName` when legal; otherwise an explicit cause, e.g. `&"fall"`. The base implementation checks support. |
| `is_safe(point, margin)` | Whether a predicted position is safe, including current arena rules and danger. A positive margin requests additional clearance. |
| `safe_target(point, margin)` | Return a reachable safer steering target, accounting for holes, arena boundaries and current hazards. |
| `navigation_target(from, destination, margin)` | Route a steering waypoint around map-specific holes; the base implementation uses `safe_target`. |
| `spawn_pose(index, count)` | A safe, symmetric global `Transform2D`. Chair thrust points opposite its rotation, so point the nozzle away from the interior. |
| `start_round()` | Enable hazard state when the map title has completely faded. |
| `stop_round()` | Stop attacks and danger progression for results or teardown. Must be safe to call repeatedly. |
| `tick_hazards(delta)` | Advance active hazards on the round's physics clock. |

The circle validates computed spawns through editor configuration warnings. A map
using authored spawn markers should warn about missing markers and unsupported
or dangerous spawn poses. Test two, three and four participants. Chair centre support triggers native 3D physics after a small rim tolerance;
wheel contacts, carried momentum and gravity then determine tipping or landing.

A stage can emit `elimination_requested(seat, reason)` for an actor-specific
hazard hit. The round validates and batches those requests with support/rule
losses before deciding survivors. Do not eliminate chair nodes, resolve draws or
award points inside a hazard callback. Multiple losses in one physics tick must
remain a draw when nobody survives.

## Lifecycle, pause and reset

New stage instances start with `round_running == false`. Intro chairs are frozen
and their extinguishers are off. `start_round()` and chair activation occur on
the same physics tick. `tick_hazards()` is called only during live play, and the
stage's own logic must also honour `round_running` when it has actor callbacks.
Override lifecycle methods with `super.start_round()` / `super.stop_round()`.

Stages inherit the match's pausable process mode. Use the supplied physics delta;
avoid wall-clock deadlines, external autoload timers and `PROCESS_MODE_ALWAYS`
for hazard gameplay. Node-owned timers must stop outside live play. On results,
the round calls `stop_round()`; teardown calls it again. A fresh round replaces
the complete scene, so counters, hazards, colliders and signals reset together.
Never store mutable round progress in the shared `StageDefinition` resource.

Chair elimination immediately disables drive, spray forces and collisions. A
`&"fall"` cause plays the current falling presentation. Other causes currently
hide the eliminated chair; add a specific burn/impact presentation when that map
is actually built. A native fall confirms elimination after dropping below the floor. A chair that
physically lands upright before that point resumes planar play with its remaining momentum.
A grounded tumble receives damped righting torque after a short contact delay;
this never applies lift or prevents gravity over a void.

## Planned office maps

These are adaptation notes, not implemented maps.

- **You're Fired!**: keep office floor support separate from a slowly shrinking
  safe region. Export delay, shrink speed and minimum radius. Both elimination
  and AI guidance must use the same current fire boundary; stop shrinkage during
  intro, pause and results. Extinguishers do not implicitly suppress fire.
- **Office sumo**: floor support can continue outside the ring, while
  `elimination_reason()` reports leaving the legal arena. AI uses that legal
  boundary rather than the surrounding room's floor.
- **Pit of Death**: subtract the hole from support. Navigation must route around
  it instead of returning a nearest point across the pit. Mask falling visuals
  behind the pit rim when that presentation is added.
- **Bull** is now implemented as The Bull in the Chinese Office; see below.

For each map, test edge equality, holes, safe spawns, AI prediction, intro/pause
inactivity, fresh-round reset and simultaneous elimination. `tests/test_stage.gd`
contains small rule fixtures demonstrating independent support, arena danger and
hazard lifecycle without prematurely building these maps.

## Shared 3D presentation

Implement `create_presentation(parent: Node3D, units_per_pixel: float)` to build the
visible stage and its 3D fall-support colliders into RoundView's world. Match the
same support geometry used by `has_support`, with the walking surface at Y=0.
Map Godot 2D world `(x,y)` into 3D `(x,0,z)` using the supplied scale. Collider
surfaces support eliminated 3D falls only; they never change live 2D chair motion.
A Floor in the Crack creates a 24-metre cylinder with its top at zero.
Shared depth testing handles chairs falling behind the stage automatically.

Author `view_width` and `view_focus` on the stage scene to frame its 3D geometry.
The focus is a point in the stage's 2D coordinate system; RoundView applies the
same world transform and scale as the support geometry. These settings affect
presentation only, leaving input, spawn points and elimination queries unchanged.

## A Crack in the Floor

The second map is an office surrounding a smaller central pit. Its chipped rim
feeds both support queries and native 3D floor/shaft collision. Solid perimeter
walls bounce live chairs; falling into the opening uses the shared physical fall
and delayed elimination. Furniture uses the same reusable prefabs as the island, grouped into workstations,
printer/storage and a carpeted lounge. `OfficeWallDetails` supplies reusable
texture-free windows, closed doors and clocks mounted on solid wall geometry.
AI navigation returns intermediate waypoints around the pit instead of steering
through its center. Introductions show each definition’s name and smaller hint.


## The Bull in the Chinese Office

`OfficeStage` supplies the shared solid office shell, bouncy walls, furniture,
carpets and wall dressing. The pit map overrides floor support and floor rendering;
the bull map uses the solid floor and adds an `OfficeBull` hazard.

`bind_participants(chairs)` supplies hazards with the explicit round roster.
`tick_hazards(delta)` is the bull’s only gameplay clock. Its recovery, windup,
charge and stun phases stop during introductions, pause and results. Windup locks
a player’s predicted position or a random floor location, marks it on the floor
and gives a readable turn/paw animation. The floor guide extends all the way
to the room boundary in the locked charge direction, even when the selected
player or spot is nearer. Furniture still stops the actual charge. Charges do not home. Scenery stops native
kinematic movement; swept player hits are limited to that actual travelled segment.
Hits emit `elimination_requested(seat, &"bull")`; the round batches scoring and
starts the existing native ragdoll presentation. Any impact stuns the bull before
recovery and another windup. AI steering can seek safety away from its charge lane.

The original `BullModel` uses smooth native geometry, shared materials and a
separate presentation root. Neither the model nor the bull awards points.


Bull difficulty grows with stage-owned arrivals. The first bull waits outside the
centered saloon doorway during the intro and walks through after play begins.
Additional bulls arrive every `arrival_interval` seconds (default 14), up to
`max_bulls` (default six). An occupied entrance delays arrivals instead of stacking
bodies. Entering bulls alone bypass the closed perimeter collider and are harmless
until completely inside; player spawns and furniture leave that lane clear.
All bulls receive the same roster and contribute to AI danger queries.

`SaloonDoor` animates its two hinges with a damped spring on the same stage clock.
Batch only each leaf’s static geometry, preserving its moving pivot. Stop, pause
and results freeze door motion and arrival time; a fresh stage resets the herd.


Bull impact knockouts prepare a world-space launch velocity and tumble on the
chair before emitting elimination. The round still eliminates immediately and
batches scoring normally. `ChairView` transfers those velocities to the native
3D assembly without the live movement speed cap. The already-eliminated visual
projectile ignores scenery so it clears the room, while native gravity and angular
motion supply the flight. Ordinary edge falls retain their normal collisions and
recoverable landings. `prepare_round()` clears launch data.


## Progressive floor loss

The crack maps use `CrumblingEdge` for the current outline and pending fractured sections.
Advance it only from `tick_hazards(delta)` while `round_running`. A changed revision
updates the rendered floor, native supporting collider, carpets and support
queries together; AI must query that current outline rather than an initial
radius. Clip pit-floor geometry to the room so late fractures can reach the outer
walls without leaving invisible support. Warning and detached polygons come from
the same outline change. `FractureView` samples bounded cosmetic debris across the
whole rim; debris cannot block players. Call `OfficeProp.release_for_fracture`
with the newly removed polygons when floor changes. Partial footprint overlap
releases both fixed and sleeping loose furniture into native 3D; remaining support
then determines whether it rests, tips or falls. Stop debris with
the round, and keep mutable fracture state on the scene instance.
