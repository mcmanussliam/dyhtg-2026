# Physics sandbox 0.3

## Requested simplification

- Removed the visible room wall border, surround and frame; floor fills the view.
- Removed the fire obstacle, suppression, heat, elimination and auto-rematch logic.
- Removed fuel, refill, brake, aiming vector, firing-button and obsolete HUD state.
- Extinguishers now spray and propel continuously, without a finite tank.
- Left/right steering is the only gameplay action. Keyboard, controller and AI
  produce the same scalar command.
- Characters use pale bodies, lighter inset face panels and two black eyes.

## Physics

Chairs are actual rotating rigid bodies rather than rotation-locked circles with
an independently animated nozzle. Steering applies angular impulse; angular drag
lets the spin settle when input is released. Linear thrust remains opposite the
nozzle. Both linear and angular speed are bounded. Collisions retain a small bounce.

Body artwork rotates with the rigid body once; world-facing shadows and player
numbers counter-rotate. Spray direction and obstacle raycasts read that same body
heading. This avoids double-rotated artwork and mismatched jet force.

## Sandbox boundaries

Invisible edge collisions keep the continuously moving test on screen. These
are deliberate testing bounds, not a visible room wall or a stage obstacle set.
The stage scene and spawn markers are separate from simulation, ready for future
maps. There are currently no scores, winners, timed rounds or eliminations.

## Validation

The engine runner checks the new steering and continuous-spray contract, actual
linear/angular physics, input isolation, no obsolete resource state, light face
colour, obstacle obstruction, pause, resets, hot joining and a long AI simulation.
Headless checks also catch draw-call errors. Mac graphics and real-controller
playtesting remain necessary; this environment has no usable graphics display.
