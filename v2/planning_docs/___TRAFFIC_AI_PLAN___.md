# Traffic AI — Design

> Status: implemented (free roam only), untested in-game.
> Related: [StreetRaceMode](./StreetRaceMode.md), [GamemodeSystem](./GamemodeSystem.md), [Architecture](./Architecture.md)

## Goal

Basic traffic riders that circulate the road network in free roam: follow lanes,
pick a random exit at junctions, don't ram each other, recover from crashes and
from getting stuck. Racing AI keeps working exactly as it does today.

Secondary goal, and the reason for the refactor: `npc_rider_entity.gd` currently
mixes chassis (physics, lane following, speed) with race-specific decisions
(overtaking, lane changes, difficulty). Traffic needs the chassis and none of the
race decisions, so the two are separated via a state machine rather than
duplicated.

## Constraint: the road generator can't route through intersections

`RoadLaneAgent.move_along_lane` follows a single `lane_next` NodePath.
`intersection_ngon.gd` generates *multiple* lanes per entering lane (one through
lane plus one turn lane per other branch), and `RoadContainer.update_lane_seg_connections()`
only links segment-to-segment — intersection lanes receive `lane_next_tag` /
`lane_prior_tag` but never get their `lane_next` NodePath assigned. The addon's
own demo readme acknowledges pathing is unfinished (upstream issue #171).

The agent's only recovery is a short-radius `find_nearest_lane` fallback inside
`_move_along_lane`, which is not a deliberate choice and cannot be steered.

**Therefore junction routing is ours to build.** See `TrafficRouteGraph` below.

## Architecture

### `NPCRiderEntity` — chassis only

Keeps: skin + animation init, `Racers` group registration, multiplayer authority,
`road_manager`, the synced `npc_state`, `username`, `driving`, `crash()`,
`finish()`, `teleport_to()`, and velocity-facing. `_lane_agent` becomes public
`lane_agent`; `_speed` becomes public `current_speed`.

Drops `_physics_process` entirely — **the states own the tick**. A child
`StateMachine`'s `_physics_process` runs *after* its parent's, so splitting the
tick across both would apply gravity and `move_and_slide` before the state had
chosen a steering target.

Clients never simulate: `_ready()` disables physics processing on the state
machine when not the server. Transform and `npc_state` continue to arrive through
the existing child `MultiplayerSynchronizer`.

Shared helpers the states call:

| Helper                               | Purpose                                                           |
| ------------------------------------ | ----------------------------------------------------------------- |
| `lane_point_ahead(dist)`             | Point ahead on the lane curve, already nudged by `line_offset`    |
| `cruise_speed()`                     | `move_speed` scaled by this rider's stable speed variance         |
| `lane_speed()`                       | Corner-aware target speed from the lane's bend lookahead          |
| `steer_toward(target, speed, delta)` | Ramps `current_speed` via accel/braking, sets horizontal velocity |
| `coast_to_stop(delta)`               | Decays horizontal velocity                                        |
| `apply_gravity_and_move(delta)`      | Gravity, `move_and_slide`, face velocity                          |
| `nearest_racer_ahead(range, cone)`   | Nearest slower racer in the forward cone (humans included)        |
| `horizontal_speed(racer)`            | Horizontal speed of any racer                                     |

Tunables that stay on the entity because both states use them: base move speed,
speed variance, acceleration, braking, minimum turn speed, turn sharpness, turn
lookahead, steering lookahead time and its clamps, max line offset.

Per-rider variety comes from the existing `hash(name)`-seeded RNG in `_ready`,
which already produces the lateral line offset and now also produces the speed
scale. Stable per rider, different between riders, no manager plumbing.

### State machine

`npc_rider_entity.tscn` gains a `StateMachine` node whose initial state is the
idle state. Each state is a `State` child with an exported reference back to the
entity, wired in the scene — the same pattern `NPCAnimationController` uses.

New scripts under `entities/npc/states/`:

- **`npc_idle_state.gd`** — coast and fall. Where clients sit, and where a bot
  sits before its manager starts it.
- **`npc_race_state.gd`** — today's race behavior, relocated unchanged:
  difficulty scaling, overtake blocker detection and side choice, lane changes,
  and the merge-when-the-lane-dead-ends recovery. Zeroes `line_offset` on enter
  when overtaking is disabled, preserving the current master-switch behavior.
- **`npc_traffic_state.gd`** — new, described below.

Managers move a bot into its behavior after spawn with
`npc.state_machine.get_state_by_name(...)` + `request_state_change`. The call is
deferred: `StateMachine._ready` defers its own transition into the idle state, so
an immediate request would be overwritten by it.

Race-only tunables (difficulty, overtake range/cone, lane-change cooldown, the
overtaking master switch) live on `NPCRaceState`; traffic-only ones (follow
range/cone, junction proximity, stuck window/threshold) on `NPCTrafficState`.

Both states' tick reduces to the same four steps — `lane_speed()`, cap to the
blocker from `nearest_racer_ahead`, `steer_toward`, `apply_gravity_and_move` —
and differ only in the routing/decision step before it:

|         | Race state                                        | Traffic state                         |
| ------- | ------------------------------------------------- | ------------------------------------- |
| Routing | Lane changes, overtake side, merge when lane ends | Random next lane from the route graph |
| Extra   | Difficulty scaling                                | Crash on contact, stuck detection     |

### `TrafficRouteGraph`

A `RefCounted` in `entities/npc/`, built once per level by the traffic manager.

Walks every lane in the RoadManager's AI lane group and maps each lane to its
candidate successors: the linked `lane_next` where one exists, otherwise any lane
whose **start** falls within a snap distance of this lane's **end** with a
forward-facing heading. That geometric fallback is what carries riders onto
intersection turn lanes, which the addon never links.

**Lanes don't survive the level load.** `RoadContainer._ready` defers
`rebuild_segments(true)`, which frees and regenerates every RoadLane — so a graph
built when the gamemode enters holds dead instances seconds later. The manager
connects each container's `on_road_updated` and rebuilds the graph in place
(coalesced to once per frame) so riders' references stay valid.

API: `next_lanes(lane)`, `random_lane()`, `lane_start_transform(lane)` (where a
rider dropped onto a lane starts, facing along the curve), and the public `lanes`
list the manager shuffles for spawn spread. Snap distance and heading tolerance
are constructor tunables.

### `NPCTrafficState`

Per server tick:

1. Coast and return if not driving, or crashed.
2. Re-latch to a lane if the current one went invalid (spawn, teleport, rebuild).
3. If close to the lane end, pick a random successor from the route graph and
   assign it. Falls back to nearest-lane recovery when the graph has no successor.
4. Target = `lane_point_ahead(steer lookahead)`.
5. Speed = `lane_speed()`, capped to a blocker's speed via `nearest_racer_ahead`
   so riders tuck in behind rather than ram.
6. `steer_toward`, then `apply_gravity_and_move`.
7. Post-move, scan slide collisions for a collider in the `Racers` group and
   `crash()` on contact.
8. Track progress per second; below a threshold for a sustained window, report
   stuck to the manager.

### `NPCTrafficManager`

A `BaseManager` alongside `NPCRaceManager`. Exports: level manager, NPC
definitions roster, traffic count, cruise speed, respawn delay.

Public `start_traffic()` / `stop_traffic()`. `start_traffic` builds the route
graph from the level's RoadManager, picks spread-out spawn lanes, and spawns via
a broadcast RPC mirroring `NPCRaceManager.rpc_spawn_npc` (same
instantiate-name-definition-road_manager sequence), additionally assigning the
rider's base move speed from `cruise_speed` before `add_child` and moving it into
the traffic state.

Owns the crash-to-respawn timer and the stuck-to-relocate handler (fed by
`NPCTrafficState`'s `crashed` / `stuck` signals). Both drop the rider back on the
road a few metres ahead along its current lane, falling back to the start of a
random lane from the graph when it no longer has a lane under it.

**ID space:** race NPCs count down from −1. Traffic NPCs count down from a
distinct lower offset so the two can never collide on node names, since both
parent their riders under the level's spawn node.

### Wiring

`FreeRoamGameMode` gains an exported traffic manager reference, calls
`start_traffic()` in `Enter` and `stop_traffic()` in `Exit` (server only), and
validates the export in `_get_configuration_warnings`. `main_game.tscn` gains the
manager node with its exports wired.

Traffic is free-roam only in v1. Races stay clean.

## Files

### New

| Path | What |
| --- | --- |
| `entities/npc/states/npc_idle_state.gd` | Coast + fall. Initial state; where clients and un-started bots sit |
| `entities/npc/states/npc_race_state.gd` | Race behavior lifted out of the entity (difficulty, overtaking, lane changes, merge-on-dead-end) |
| `entities/npc/states/npc_traffic_state.gd` | Traffic behavior (route-graph junctions, car-following, crash-on-contact, stuck detection) |
| `entities/npc/traffic_route_graph.gd` | `RefCounted` lane-successor table built from the RoadManager's AI lane group |
| `managers/npc_traffic_manager.gd` | Spawns/despawns traffic riders, owns crash-respawn + stuck-relocate |

### Modified

| Path | Change |
| --- | --- |
| `entities/npc/npc_rider_entity.gd` | Strip to chassis + shared helpers; drop `_physics_process`; disable state-machine physics on clients |
| `entities/npc/npc_rider_entity.tscn` | Add `StateMachine` + three `State` children, wire `npc` exports and `initial_state` |
| `managers/npc_race_manager.gd` | Move spawned NPCs into the race state |
| `managers/gamemodes/types/free_roam/free_roam_gamemode.gd` | New traffic manager export; `start_traffic()` / `stop_traffic()`; config warning |
| `main_game.tscn` | Add `NPCTrafficManager` node, wire its exports |
| `planning_docs/TODO.md` | Mark Traffic AI progress, move deferred items to backlog |
| `planning_docs/___TRAFFIC_AI_PLAN___.md` | This doc |

### Read-only reference

Needed to follow existing patterns, not edited.

| Path | Why |
| --- | --- |
| `CLAUDE.md`, `.gdlintrc` | Conventions + lint rules |
| `utils/state_machine/state.gd` | `State` lifecycle (`Enter` / `Physics_Update` / `Exit`) |
| `utils/state_machine/state_machine.gd` | Registration, `request_state_change`, tick order |
| `utils/constants.gd` | `GROUPS["Racers"]` |
| `managers/base_manager.gd` | Manager base class |
| `managers/level_manager.gd`, `levels/level_definition.gd` | `current_level`, `player_spawn_pos`, grid markers |
| `entities/npc/npc_animation_controller.gd` | Exported back-reference pattern; consumes `npc_state` and `visual_root` |
| `managers/gamemodes/types/street_race/street_race_gamemode.gd` | Race lifecycle that must keep working unchanged |
| `addons/road-generator/nodes/road_lane_agent.gd` | `move_along_lane`, `close_to_lane_end`, `change_lane`, `assign_nearest_lane` |
| `addons/road-generator/nodes/road_lane.gd` | `lane_next`/`lane_prior`/`lane_left`/`lane_right`, `get_lane_start`/`get_lane_end` |
| `addons/road-generator/nodes/road_manager.gd` | `ai_lane_group`, `get_containers()` |
| `addons/road-generator/nodes/road_container.gd` | `update_lane_seg_connections()`, `force_assign_lanes()` — why intersection lanes are unlinked |
| `addons/road-generator/procgen/intersection_ngon.gd` | How through/turn lanes are generated and tagged |
| `player/controllers/crash_controller.gd` | Layer-2 head-on crash path (deferred item) |
| `levels/racetracks/racetrack_level_01/` | Test level with the road loop |

## Testing

Runs on `racetrack_level_01` immediately — its road loop gives riders somewhere
to circulate before the city map exists. Success criteria:

1. Existing street race behaves identically to before the refactor (bots complete
   a race, overtake, crash-respawn, produce results rows).
2. Traffic riders spawn in free roam, follow lanes, and keep circulating
   indefinitely without leaving the road.
3. Riders queue behind a slower rider rather than driving through it.
4. A rider knocked over recovers on a lane after the respawn delay.
5. A rider wedged against geometry relocates rather than staying stuck.
6. Clients see traffic move smoothly and run no simulation locally.
7. `.gd` files lint clean against `.gdlintrc`.

## Deferred

Tracked in TODO under Traffic AI / Backlog > AI/traffic:

- Traffic lane changes and overtaking (traffic follows one lane per junction leg).
- Near-miss detection feeding a trick/score bonus.
- Traffic during races (the "race thru traffic" mode).
- Level-driven traffic spawner node for per-map density on the city map.
- Consolidating `NPCRaceManager` and `NPCTrafficManager` onto a shared base —
  they were kept standalone to avoid destabilizing the working racing AI, at the
  cost of a duplicated spawn/despawn RPC pattern.
- A* pathfinding and the fuller sequence system from the original backlog entry.
