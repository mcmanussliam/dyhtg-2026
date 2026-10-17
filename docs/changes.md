# Match flow 0.4

- Stage radius reduces from 500 to 480 pixels, with cut furniture rebaked to the
  new boundary. Printer and adjacent cabinet share an aligned front edge on the
  upper carpet. The lounge task chair is replaced with an opposing sofa, keeping
  the coffee table between the two seats.

- The lounge expands down/right with its left carpet edge fixed. A second clean
  carpet defines the bookshelf area. The workstation bench extends to the left
  cut edge with matching baked desk ends; isolated side furniture is removed.

- A flush, muted green carpet defines the lounge, clipped to the circular floor.
  Mugs, folders and archive boxes dress existing furniture without adding driving
  obstacles. Home-menu key and fill lighting are reduced independently of gameplay.

- Office placement now balances aligned storage with a workstation island, a
  printer alcove and an open lounge. The island breaks spray contact and provides
  alternate circling routes; the printer corner trades cover for limited retreat;
  the lounge catches drifting chairs without closing off its exits. Side furniture
  interrupts the edge route while the centre/front stay open for recovery.
  Cut pieces remain at the ends of the original office runs.
- The larger office now has a four-station desk bench with acoustic dividers and
  task chairs, a copier/storage area and a separate lounge with a coffee table.
  Nine reusable furniture types share aligned 2D/3D footprints; the centre and
  front remain open for movement. A desk and bookshelf at the boundary are
  physically sliced to the circular outline, with capped baked meshes and
  clipped compound colliders. No runtime CSG is required.
- The plain grey column gains a small smooth bevel beneath the floor rim and
  refined lighting response, retaining its exact floor height, maximum radius,
  24-metre depth and long 8–24-metre fade. No surface textures are introduced.

- Office flooring is one muted navy shade with no surface textures. The plain
  grey cylinder retains lit shading, with its long fade starting 8 metres below
  the floor and ending at 24 metres. The gameplay camera is more front-facing.
- Sparse desks and a filing cabinet use reusable feature scenes with matching
  2D/3D collision footprints. Desks block spray; AI samples obstacle rays before
  steering. The home diorama reuses the same desk model.
- Gameplay renders directly through Godot's native 3D camera and main viewport.
  Shared RenderStyle conventions govern metre scale, lighting, shadow bias, MSAA
  and UI render-texture composition. The redundant gameplay compositor and 2D
  camera are removed; isolated UI previews keep their own render targets.

- The first map is **A Floor in the Crack**, a circular office-floor cutout.
  Office carpet tiles and flush floor boxes sit on exposed slab layers above a
  24-metre cylindrical foundation. Construction panels darken into the void.
  Its native mesh and collider share one radius, depth and top plane. The map
  authors its own camera framing to reveal the column while keeping rim players
  visible. Its open play area, spawn poses and 2D movement tuning are unchanged.

- Stage and live chairs now render in one shared 3D world. The platform properly
  occludes falling chairs, including at the far edge. Falls contact a real 3D
  platform collider through the chair base and body, producing physical tipping
  and an accelerating drop. The score transition allows 1.6 seconds for the fall.
  Steering, arena support rules and collisions during live play remain 2D.

- Unsupported falls now hand the existing model to a native 3D rigid body,
  preserving planar velocity and yaw rate. Gravity supplies the drop; no scripted
  slide, shrink, fade or extra tumble remains. Completed rounds freeze the fall
  bodies, and resetting the round releases them with their owning viewport.

- Score portraits are larger and visually centred against their stars. Portraits
  and stars render into independent 4x-resolution viewports, rather than containers
  silently reducing them to display resolution. Premultiplied alpha preserves clean
  transparent edges. Gameplay character renders increase from 768 to 1024 pixels;
  automatic mesh LOD is disabled for close character presentations, and the circle
  stage silhouette is antialiased.

- Office home screen and setup use only plain white option text, controlled by
  Left and Right. One human faces one to three AI chairs in first-to-N matches.
- Round introductions show only a large map name on black. Score pages show
  the actual character models beside their earned stars, without headings,
  names, counters or menu text. Right continues/rematches; Left returns home.
  The match-winning score page adds confetti.
- Round introductions and score screens use pure black backgrounds. The circle
  stage appears when the introduction ends and every extinguisher starts together.
- Unsupported chairs fall away. One survivor wins; simultaneous final falls draw.
  Scores use 3D stars and the match-winning result adds confetti.
- Body colours are stronger yellow, mint, rose and blue, retaining lighter flush
  faces and two black eyes.
- Each AI commits to opponents for several seconds, mixing direct approaches,
  flanking and short spray attacks. All seats, including other AIs, are eligible;
  ignored opponents receive more attention on later target selections.
- Predictive recovery cancels sideways as well as outward momentum. Spray attacks
  require retreat space. Angular-rate control brakes turns before alignment.
- Repeated loops and stationary pushing contests trigger safe lateral escapes and
  retargeting. Risk increases gradually during long fights without eliminations,
  then resets after an elimination. AI still uses only steering and real physics.
- Real rigid-body playtests cover solo survival, opening-fall prevention, collisions,
  spray exchanges, target coverage and extended fights, in addition to input tests.
- Stage support, legal arena rules and hazard lifecycle are separate extension
  points. The circle is the only map implemented in this milestone.

# Physics sandbox 0.3

## Current presentation and collision refinements

- Live orthographic 3D character, office chair and extinguisher artwork renders
  through transparent SubViewports over the original 2D rigid-body simulation.
- The character is one seamless mesh with a smaller head and flush painted face.
  `tools/build_character.py` rebuilds the source mesh; Python is development-only.
- The carpet floor remains; furniture, windows and all gameplay text are removed.
- Chair upholstery, gas lift, armrests and dual-wheel casters are separate from
  the original character mesh. The upright extinguisher sits between the legs,
  gripped by both hands, with its nozzle facing along the physics heading.
- Collision shape, friction and restitution now support off-centre bumps and
  rotation. Contact impulses (or normal closing speed when the backend reports
  zero impulse) drive damped seat suspension, body lean and squash. Presentation
  never adds extra collision impulses or changes the rigid-body transform.
- Stronger wall rebound and a larger, damped seat rock make impacts more visible
  while the caster base remains planted. The body uses broader joint blends,
  finer sampling and volume-preserving smoothing to soften its silhouette.
- Steering now has substantially higher torque, a higher spin limit and faster
  damping on release. Regression checks measure sharp turning in both directions.
- Curved shoulder-to-hand poses soften the elbows. The extinguisher has a rounded
  red tank, yellow band, smooth red squeeze levers, a curved hose and grey horn.
  The chair retains its curved back and lumbar pad, with one upright rear support.
- Spray now uses pooled 3D sphere meshes with depth and directional shading.
  Balls grow along the jet and fade toward its edges and end. They emit from the
  model's nozzle marker and stay inside the same obstruction distance as spray
  physics. Their clock pauses with gameplay.
- Native Mac rendering has been inspected at eight headings and in close-up.
  Physics regressions cover contact feedback, momentum transfer, glancing spin,
  wall rebound, settling and continuous thrust without false impact feedback.

The following sections describe the earlier 0.3 simplification baseline.

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
