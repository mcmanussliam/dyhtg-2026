# Multiplayer design

Single player is unchanged. Multiplayer is **host-authoritative LAN play** over Godot's
high-level multiplayer API with `ENetMultiplayerPeer` (desktop only; the Web build
disables Multiplayer, because ENet is unavailable there). Steam can later replace the
peer without changing the game layers.

The host's machine runs the real game: chair physics, AI seats, hazards, eliminations
and scoring, exactly as single player does. Clients send only their steering value and
render what the host streams back. There is no client prediction; on a LAN the delay is
a few milliseconds.

## Constants

| Name | Value |
| --- | --- |
| Game port (ENet, UDP) | `NetSession.DEFAULT_PORT = 7777` |
| Discovery port (UDP broadcast) | `LanDiscovery.PORT = 7778` |
| Protocol version | `NetSession.PROTOCOL_VERSION = 1` (joins must also match `config/version`) |
| Maximum players | 10 (humans plus AI fill) |

## Layers and ownership

| Layer | Folder | Owns |
| --- | --- | --- |
| Session | `game/net/` | Peers, lobby, discovery, names, colour resolution, message transport. The **only** RPC endpoint. |
| App and menus | `game/app/`, `game/ui/`, `game/home/` | Play → Single player / Multiplayer, Host, Join list, Lobby, command-line flags. |
| Match and round | `game/match/`, `game/round/`, `game/chair/`, `game/input/` | Online matches: host simulation, input relay, chair and loose-prop snapshots, events, results, disconnects. |
| Stages | `game/stage/` | Each map's hazard state and discrete events, behind the `ArenaStage` hooks. |

Layers talk only through the interfaces below. Do not edit another layer's files.

## Session (`NetSession`, `game/net/net_session.gd`)

One `NetSession` node, named `NetSession`, is a child of `GameApp`, so its node path is
identical on every peer. All RPCs live on it. Other layers never declare RPCs; they use:

```gdscript
func is_online() -> bool
func is_host() -> bool
func local_peer() -> int                       # 1 on the host
func send_to_host(kind: StringName, payload: Variant, reliable := true) -> void
func broadcast(kind: StringName, payload: Variant, reliable := true) -> void   # host → clients
signal message_received(kind: StringName, payload: Variant, from_peer: int)
signal peer_left(peer_id: int)                 # host: a client dropped (lobby or match)
signal session_closed(reason: String)          # every peer: session over (host left, kicked, failed)
```

Payloads are plain Variants (Dictionary, Array, packed arrays, numbers, strings, Color,
Vector2); never Objects. Reliable messages use channel 0; unreliable ones are
`unreliable_ordered` on channel 1. A host-side `broadcast` is not echoed to the host.

### Discovery and names

`LanDiscovery` (`game/net/lan_discovery.gd`) finds games without typing addresses:

```gdscript
signal games_changed
var games: Array[Dictionary]     # { address, port, name, players, max }, expiring when silent
func start_beacon(name: String, port: int, players: int, max_players: int) -> void   # host
func update_beacon(players: int) -> void
func stop_beacon() -> void
func start_listening() -> void   # client join list
func stop_listening() -> void
```

Guests send a discovery query once a second from their own ephemeral IPv4 UDP
socket. Hosts listen on UDP 7778 and reply directly to the guest's source address
and port. Multiple Join pages on the same machine can search concurrently. Hosts
also broadcast announcements for older passive listeners.

Targets use the actual interface broadcasts: `ifconfig` on macOS,
`ip -4 -o addr show up` on Linux, and `Get-NetIPAddress` IPv4 prefixes on Windows.
Interface discovery runs on a worker thread so PowerShell startup cannot freeze the
menu; targets refresh every ten seconds. If enumeration fails, discovery falls back
to `255.255.255.255`. Queries also reach `127.0.0.1` for same-machine play.

Godot's output includes `[LAN]` lines for local IPs, game version, broadcast targets,
the first host-side query, and every discovered game. Rejected announcements warn
once per source address; mismatched game versions are not listed. A successful send
does not prove delivery through the network.
Player name labels are omitted; discovery uses generic lobby labels. Automatic
OS user/computer names are disabled.

### Lobby

`NetSession.lobby` is a host-authoritative Dictionary, re-sent reliably to all peers on
every change (`lobby_changed` fires on every peer):

```
{
  "players": [ { "peer": int, "name": String, "hat_id": StringName, "top_id": StringName,
                 "colour_id": StringName, "colour": Color } ],   # join order; host first
  "setup":   { "player_count": int, "wins_needed": int, "stages": Array[StringName] },
  "in_match": bool
}
```

- **Names:** player and AI names are not displayed. The lobby identifies people by
  colour; results show character models and stars only. Discovery uses Lobby 1,
  Lobby 2, etc. OS user/computer names and `--name=` overrides are not used.
- **Appearance:** each peer sends its saved `CharacterAppearance` IDs on join and when it
  changes (`set_local_appearance`). The host validates them (unknown → none).
- **Colours:** the host resolves them. The earliest joiner keeps a preferred colour;
  a later clash or Random gets the next free colour in `MatchState.COLOURS` order. AI
  seats take the remaining colours. Every peer sees the resolved colours.
- **Setup:** host only (`set_setup`). `player_count` is clamped to at least the number of
  humans; extra seats are AI.
- **Joining:** refused when the lobby is full, a match is in progress, or the protocol or
  game version differs (`session_closed` gives the reason).

Starting: the host calls `start_match()`. Every peer, host included, receives
`match_started(roster: Array, setup: Dictionary)`. The roster has one entry per seat:

```
{ "id": seat, "peer": peer_id (0 = AI), "name": String, "hat_id": StringName,
  "top_id": StringName, "colour": Color, "wins": 0 }
```

Seats `0..humans-1` are humans in join order (host is seat 0); the rest are AI.
`setup` is `{ "wins_needed": int, "stages": Array[StringName] }`.

## Match and round (online)

`GameApp` reacts to `match_started` by creating a `MatchController` and calling
`start_online(net, roster, setup)`. The controller knows its role from `net.is_host()`.

- **Host:** runs the existing `MatchState` and `RoundController` simulation, with AI
  pilots on AI seats and remote seats driven by their latest `&"input"` message.
  Each round it chooses the map, then broadcasts `&"round"` (round id, stage ID,
  roster) reliably. Every physics frame it broadcasts an unreliable `&"snapshot"`:
  chairs, awake loose props, and `stage.net_state()`. It sends reliable `&"event"`
  messages for eliminations (with launch velocity and spin), round results, match results,
  and the stage's `net_event`s.
- **Client:** builds the same round scene in **mirror** mode: chairs are frozen puppets
  set from snapshots, the stage is put in `set_net_mirror(true)`, nothing decides
  eliminations or results locally, and AI pilots do not exist. Each physics frame it
  sends `&"input"` (its seat's `turn`) unreliably. Falls and knockouts replay locally
  as cosmetics from the host's event data.
- **Results:** `results_ready` fires on every peer with the host's data. In online mode
  the app forwards result-screen actions to `MatchController.handle_result_action()`.
  Only the host's Continue advances everyone; a client's Left leaves the session. After
  the final result, every peer returns to the lobby (`online_finished`).
- **Disconnects:** a client leaving mid-match turns its seat into AI on the host. The host
  leaving ends the session for everyone (`session_closed` → app returns to Multiplayer).
- Once every human is eliminated, spectators can hold Right to watch the remaining
  AI fight at 3× speed, with the same instruction and badge as single player.
  Releasing Right restores normal speed. Any connected spectator may hold it; the
  host validates the sender, round ID, and surviving humans, and combines active
  holds. The level stays visible and completes normally. Snapshots remain limited
  to about 60 per wall-clock second during acceleration.

## Stage hooks (`ArenaStage`)

Defaults are no-ops, so single player is untouched. Online:

```gdscript
var net_mirror := false
func set_net_mirror(enabled: bool) -> void      # client: never decide, only display
func net_state() -> Variant                     # host: continuous state, every frame (keep small)
func apply_net_state(state: Variant) -> void    # client
signal net_event(payload: Variant)              # host: discrete changes (crumble step, panel drop…)
func apply_net_event(payload: Variant) -> void  # client
```

In mirror mode, `tick_hazards` must not make random or player-dependent decisions or
request eliminations. It may still run purely visual time (animations, flashing). The
mirrored stage must show the same actors, warnings and holes, and report the same
`has_support`, as the host.

## Menus

```
Home ── Play ──┬─ Single player ─ Setup (unchanged) ─ match
               └─ Multiplayer ─┬─ Host game ─ Lobby (host) ── Start game
                               └─ Join game ─ Join list ─ Lobby (client)
```

The same two-key style: plain white text, no extra copy. The lobby lists players
(name and resolved colour) plus host settings. Command-line flags for demos:
`--host`, `--join=<ip>`.

## As built

Where the implementation refines the plan above:

- `NetSession` runs the host's LAN beacon itself (paused during matches); the app's
  `LanDiscovery` only listens, on the Join page.
- `leave()` is silent. `session_closed(reason)` fires only for involuntary ends:
  "Host left", "Lobby is full", "Match in progress", "Different game version",
  "Could not connect" (5 s timeout).
- `join()` returning `OK` means connecting; a client is online once its first lobby
  arrives. The host's own `send_to_host` delivers locally.
- A client dropping is removed from the lobby at once; mid-match, its seat becomes AI.
  The host calls `end_match()` when everyone returns to the lobby.
- Client chairs are collision-free dynamic puppets steered towards the latest snapshot
  (velocity plus a short correction), so lean, wheels and foam still animate.
  Eliminations replay only from the reliable event, with the host's launch.
- `MatchController.round_began(round_number)` lets clients close results when the host
  starts the next round; clients' Continue is ignored, and Home mid-match leaves.
- Messages: `&"round"`, `&"snapshot"` (keys `r p t c f o s`, about 0.6 KB for 10 seats),
  `&"event"` (`stage`, `eliminated`, `decided`, `results`, `finished`), `&"input"`.
- Stage replication sizes per frame: bulls and guards under 60 bytes, lanes under
  260 bytes, crumbling maps send events only.
- Limits: one discovery host per machine (port 7778); no late join or resync;
  debris and falling furniture are simulated locally on each machine.

## Testing

- Unit suites per layer, registered later in `tests/run_match_tests.gd`.
- In-process peer tests: give each peer its own branch with
  `tree.set_multiplayer(SceneMultiplayer.new(), branch_path)`, and put a client's round
  inside a `SubViewport` with `own_world_2d` and `own_world_3d`, so physics never mixes.
  Use a random high port.
- End-to-end: two game instances on one machine. From the project folder:

  ```sh
  godot --path . -- --host
  godot --path . -- --join=127.0.0.1
  ```

  For a two-machine check, connect both machines to the same LAN and run matching
  builds. Open a lobby on the host, then open Join game on the guest without
  `--join`. Verify that the host appears, joins work, player counts update, and
  starting the game brings both players into the match. Repeat with the other
  machine hosting. Local tests cannot establish whether Wi-Fi client isolation or
  a firewall blocks broadcasts between devices. If discovery is blocked, use
  `--join=<host's LAN IP>` (game traffic uses UDP 7777; discovery uses UDP 7778).


### Discovery troubleshooting (Windows and macOS)

Run matching project revisions on both machines. Use one Host game lobby and one
Join game page; restart running game instances after updating scripts. Watch Godot's
Output panel for `[LAN]` messages on both machines.

1. Try `godot --path . -- --join=<host LAN IPv4>` from the guest's project folder.
   Alternatively, in the guest editor choose Debug → Customize Run Instances,
   set Main Run Args to `-- --join=<host LAN IPv4>`, and press F5. Clear these
   arguments after testing so ordinary launches do not auto-join.
   If direct joining also fails, check host firewall permissions and network client
   isolation before changing discovery. Same Wi-Fi does not guarantee peer access.
2. On Windows, allow the actual Godot executable running the project through Windows
   Firewall on the current network profile. Editor and console executables can have
   different paths and rules. On macOS, check Godot's Local Network permission under
   System Settings → Privacy & Security, and its incoming-connection firewall rule.
   Game hosting needs inbound UDP 7777 and discovery hosting needs inbound UDP 7778.
3. If the host never prints `Received discovery query`, requests are not reaching its
   discovery socket. Compare the logged local IPv4 addresses and broadcast targets.
   If that line appears but the guest never prints `Found`, replies are not reaching
   the guest, or the guest logs a rejected announcement (check game versions).
4. If broadcasts are filtered by venue Wi-Fi, use direct joining or a network that
   allows devices to communicate. The game cannot override router isolation.
