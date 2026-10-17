# Please Remain Seated

A native Godot party game about soft characters on swivel office chairs, propelled
by continuously firing extinguishers. Steer, drift and push everyone else off the
platform.

Open `project.godot` in **Godot 4.7.2 Standard** and press F5. The game starts at an
office home screen with plain white menu options. Choose Play, set 1–3 AI opponents and a first-to-1–5 win target,
then start. The default is one AI and first to five wins. Customisation and
multiplayer are deferred.

## Controls

| Context | Left arrow | Right arrow |
| --- | --- | --- |
| All menus | Select the next item, wrapping | Change a value or confirm |
| Gameplay | Steer left | Steer right |

A/D also steer during gameplay. Esc pauses or resumes without a menu. Extinguishers start automatically after each map
introduction and never run out. Introductions and score screens use plain black
backgrounds. A held menu key must be released before the next
screen accepts input or a round begins.

Each round currently uses **A Floor in the Crack**, a circular navy office floor
above a grey cylindrical foundation descending into black void. A four-station
desk island, printer alcove, aligned storage and seating nook furnish the floor. A desk and
bookshelf are sliced through by the circular edge. Crossing its edge eliminates a participant. The last survivor wins a point;
a simultaneous fall is a draw. Results show one 3D gold star per win. The first
participant to reach the selected target wins the match, with confetti on the
final results. Score pages show only characters and stars: Right continues to the
next round, or starts a fresh match after the final win; Left returns home.

## Development

The simulation uses native 2D rigid bodies with torque steering and continuous
thrust. The stage and character models share one angled 3D view, with real depth
occlusion. Live movement stays in 2D; unsupported falls transfer into 3D physics
for platform-edge contacts, tipping and gravity.
Python is development tooling only; the game itself does not require Python.

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r tools/requirements-dev.txt
python tools/check.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

Adjust the Godot path for your installation. Automated checks cover formatting,
lint, engine import, physics regressions and startup. Headless checks cannot judge
movement feel, graphics quality or physical controller behaviour; playtest those
locally.

## Code ownership

- `game/app/`: home/setup navigation and screen lifetime.
- `game/home/`: the animated office diorama.
- `game/match/`: setup configuration, participants, authoritative scores and results.
- `game/round/`: map introduction, synchronised start and elimination resolution.
- `game/stage/`: stage definitions, floor support, arena rules and hazard lifecycle.
- `game/chair/`: rigid-body movement, contact feedback, 3D models and foam.
- `game/input/`: common steering commands for human and AI controllers.
- `game/combat/`: extinguisher forces and obstruction.
- `game/ui/`: two-key menus, 3D score tokens and victory confetti.
- `tests/`: engine-driven regression suites.

The match owns its current round; the round owns its stage and chairs. Scores live
outside round scenes so replacing a round cannot reset the match. UI displays
snapshots and emits actions; it does not award points. Stage support, legal arena
boundaries and hazards remain separate so future office maps can support shrinking
fire, sumo boundaries, pits and moving hazards without rewriting scoring.

The former sandbox remains a development fixture at
`game/session/gameplay.tscn`; it is not the normal boot scene. Its reset, takeover
and controller-join shortcuts do not control normal matches.

See [the match flow plan](docs/match-flow-plan.md) for design decisions and future
map requirements. Only A Floor in the Crack is implemented; the planned office maps are
future work.

Commit Godot `.uid` files. Keep `.godot/`, virtual environments and build output out
of version control.
