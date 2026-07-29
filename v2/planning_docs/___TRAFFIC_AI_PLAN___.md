# Traffic AI — Design

> Status: v1 implemented (free roam only), untested in-game.
> Vehicle variety (skins + cars) is designed below, not yet implemented.
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

## Vehicle variety — skins now, cars later

> Not implemented. Everything above this line is.

Goal: traffic isn't a parade of the same sportbike. Swap in other bike skins now,
and cars once they're modelled — **traffic only**, racing keeps its roster.

### What already works, and what actually blocks it

`NPCTrafficManager.npc_definitions` is an `Array[PlayerDefinition]` picked
round-robin, and `rpc_spawn_npc` already assigns `def.bike_skin` /
`def.character_skin` per rider. Dropping more `.tres` files into that array
already yields mixed skins. Three things are wrong with stopping there:

- `PlayerDefinition` is the wrong shape — loadouts, money, `ui_icon`, a username.
  Traffic wants a vehicle, not a player.
- Round-robin is deterministic and cyclical; density-per-map wants weights.
- It can only ever describe a rider on a bike.

### `CarSkin` — its own skin, mirroring `BikeSkin`

A car gets a first-class `CarSkin` + `CarSkinDefinition` pair rather than being
smuggled through `BikeSkinDefinition`. Bike tuning (gearing, lean, trick limits,
rider pose, handlebar proxy) is meaningless on a car, and a car's own concerns
(four wheels, a box collider) have nowhere to live on a bike definition. Same
pattern, new pair — one place to look when something is car-shaped.

New under `entities/vehicles/`:

| Piece | Mirrors | Notes |
| --- | --- | --- |
| `car_skin.gd` / `car_skin.tscn` | `bike_skin.{gd,tscn}` | `skin_definition` setter → `_apply_definition()` → `_spawn_mesh()` + `_apply_mods()`, `mesh_skin: SkinColor`, `rotate_wheels()` |
| `resources/vehicles/car_skin_definition.gd` | `bike_skin_definition.gd` | Mesh (`mesh_res`, offsets, scale, `colors`), Mods, Collision (`collision_shape` + offsets) |

Deliberately **not** carried over: steering handlebar proxy, rider pose block,
gearing / physics / trick groups. The NPC chassis owns motion; the skin owns looks
and collision. (Bikes live under `player/` for historical reasons — cars are
NPC-only, so `entities/` is the honest home.)

Two shared pieces need a nudge:

- **`SkinColor` wheels.** It exposes `front_wheel_node` / `rear_wheel_node` under a
  "BikeSpecifics" category. A car has four+, so add an optional
  `wheel_nodes: Array[Node3D]` that `CarSkin.rotate_wheels()` spins. Additive —
  bikes keep their two fields and ignore it.
- **`BikeMod.apply(_bike_skin: BikeSkin)`** is typed to `BikeSkin`, so `ColorMod`
  can't paint a `CarSkin` as-is. Widen the parameter to `Node3D` (documented as
  "any vehicle skin exposing `mesh_skin`") so one `ColorMod` ecosystem serves both.
  Two one-line changes; no behavior change for bikes.

### Rider vs car on `NPCRiderEntity`

`npc_rider_entity.tscn` gains a `CarSkin` under `VisualRoot` beside `BikeSkin` and
`CharacterSkin`. **A car spawns neither of the other two** — no bike mesh, no
character, no IK, no `animation_controller.initialize()`. The definition decides:
`car_definition != null` ⇒ car.

> **Ordering trap — this is the one that will bite.** `bike_skin.tscn` ships a
> default `skin_definition` *and* a pre-instanced mesh, and `BikeSkin._ready()`
> applies it unconditionally; `CharacterSkin` does the same. Children run `_ready`
> **before** their parent, so by the time `NPCRiderEntity._ready()` gets a say,
> both have already built themselves. The unused branch must be removed in the
> entity's **`_enter_tree`** (parent enter-tree precedes child ready), which works
> because the spawning manager already assigns the definitions before `add_child`.
> `@onready` vars and `%UniqueName` haven't resolved that early — use direct child
> paths, or exported node references, in that pass.

Also per-vehicle at spawn: collision shape + offsets from the chosen definition
(a car in the scene's capsule is wrong — copy `PlayerEntity._init_collision_shape()`),
and the `NameLabel` hidden for cars, which have no rider to name.

### Wheels via `NPCAnimationController`

`CarSkin.rotate_wheels(speed, delta)` mirrors `BikeSkin`'s, and the animation
controller is the right caller — it already derives everything cosmetic from the
synced transform. Note it fixes a current gap either way: **NPC bikes don't spin
their wheels today** because nothing calls `rotate_wheels()` on them.

> The controller runs on **every peer**, but `current_speed` is server-side chassis
> state that clients never receive. Derive speed from the position delta the same
> way `_update_yaw_rate()` derives yaw rate from the rotation delta — otherwise
> wheels only turn on the host.

The lean / wheelie / crash-roll block stays rider-only; a car uses the wheel step
and nothing else.

### `TrafficVehicleDefinition`

New `Resource` at `resources/traffic/traffic_vehicle_definition.gd`, one `.tres`
per traffic vehicle under `resources/traffic/vehicles/`.

| Field | Purpose |
| --- | --- |
| `display_name` | Name label text; blank hides the label |
| `car_definition: CarSkinDefinition` | **Set ⇒ this entry is a car**, and neither bike nor character spawns |
| `bike_definition: BikeSkinDefinition` | The bike, when `car_definition` is null |
| `character_definition: CharacterSkinDefinition` | Who rides that bike |
| `color_mods: Array[BikeMod]` | Per-instance paint variety; one is picked per spawn (below) |
| `speed_scale: float` | Multiplies the manager's `cruise_speed` — trucks lumber, sportbikes don't |
| `max_line_offset: float` | Lateral wander; 0 for anything wide |
| `spawn_weight: float` | Relative odds in the roster |

The roster entry stays about *spawning* (which vehicle, how often, how fast);
the skin definitions stay about *looks and collision*. `_get_configuration_warnings`
should reject an entry with neither a car nor a bike, and one with a car **and** a
character — that combination has no meaning and would otherwise fail silently.

### Roster and selection

`NPCTrafficManager.npc_definitions: Array[PlayerDefinition]` becomes
`vehicle_roster: Array[TrafficVehicleDefinition]`, picked by `spawn_weight`
instead of round-robin. `NPCRaceManager` keeps `PlayerDefinition` — race bots need
usernames for the results table.

Per-instance variety reuses the existing `hash(name)`-seeded RNG in
`NPCRiderEntity._ready`, which already produces the line offset and speed scale:
it also picks one entry from `color_mods`. Every peer instantiates the rider under
the same node name, so every peer rolls the same paint — **no extra sync**.

> **Gotcha:** `BikeSkinDefinition` is a shared resource. Appending a picked mod to
> its `mods` array would repaint every rider using that definition (and leak into
> the player's bike if it's a shared `.tres`). The spawn path must `duplicate()`
> the definition and assign a fresh `mods` array before adding the roll.

### Networking

The spawn RPC currently ships `PlayerDefinition.to_dict()`. Traffic definitions
live in `res://` and ship inside the export, so the RPC only needs the
definition's `resource_path` plus the id — cheaper, and it covers any vehicle
without a serializer per field. The constraint that buys this: **traffic
definitions must be `res://` and identical on every peer.** No `user://`
customization for traffic (that's a player-loadout feature, and traffic doesn't
want it).

### Ordering

1. `TrafficVehicleDefinition` + one bike entry reproducing today's rider →
   verify: traffic looks identical to now.
2. Weighted roster + per-spawn `color_mods` roll (on a `duplicate()`d definition) →
   verify: mixed skins and paints, and every peer sees the same rider the same way.
3. Branch the entity's `_enter_tree` on `car_definition`, dropping the unused
   skins → verify with a **bike** entry that nothing regressed, then with a car
   entry pointed at a placeholder box mesh: no bike, no rider, no IK errors.
4. `CarSkin` + `CarSkinDefinition` + `SkinColor.wheel_nodes` + the `BikeMod`
   widening → verify a `ColorMod` repaints both a bike and the car.
5. Definition-driven collision shape + `speed_scale` + `max_line_offset`.
6. Wheel spin in `NPCAnimationController`, speed derived from position delta →
   verify wheels turn on a **client**, not just the host.
7. First real car `.tres` once a car `SkinColor` scene exists.

Only step 7 waits on a car model — a placeholder box mesh with four wheel nodes
unblocks everything above it.

### Known rough edges

- A crashed car just stops. The wipeout roll is the rider's lean/roll block, which
  a car skips. Fine for v1; a car deserves its own hit reaction eventually.
- The chassis still steers like a bike — it yaws toward its velocity with no
  turning circle, so a car pivots tighter than it should at low speed.
- Cars join the `Racers` group like everything else, so the player's contact
  crash and `nearest_racer_ahead` queueing work on them unchanged — but a car and
  a bike get the same `contact_min_speed_delta`, which is probably too forgiving
  for a head-on with a truck.
- Traffic riders still follow one lane per junction leg, so a wide vehicle can
  clip a tight turn lane. Traffic lane-changing is already deferred; wide-vehicle
  turn radius rides along with it.

## Files

### New

| Path | What |
| --- | --- |
| `entities/npc/states/npc_idle_state.gd` | Coast + fall. Initial state; where clients and un-started bots sit |
| `entities/npc/states/npc_race_state.gd` | Race behavior lifted out of the entity (difficulty, overtaking, lane changes, merge-on-dead-end) |
| `entities/npc/states/npc_traffic_state.gd` | Traffic behavior (route-graph junctions, car-following, crash-on-contact, stuck detection) |
| `entities/npc/traffic_route_graph.gd` | `RefCounted` lane-successor table built from the RoadManager's AI lane group |
| `managers/npc_traffic_manager.gd` | Spawns/despawns traffic riders, owns crash-respawn + stuck-relocate |

Vehicle variety (planned):

| Path | What |
| --- | --- |
| `entities/vehicles/car_skin.gd` + `.tscn` | `CarSkin` — mesh spawn, colors, mods, `rotate_wheels()`. `BikeSkin` minus the bike |
| `resources/vehicles/car_skin_definition.gd` | `CarSkinDefinition` — mesh + colors + mods + collision |
| `resources/vehicles/skins/*.tres` | Per-car definitions |
| `resources/traffic/traffic_vehicle_definition.gd` | One roster entry: car **or** bike+rider, spawn weight, traffic tuning |
| `resources/traffic/vehicles/*.tres` | The roster itself — one per bike skin, later one per car |

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

Vehicle variety (planned):

| Path | Change |
| --- | --- |
| `entities/npc/npc_rider_entity.gd` | `car_definition` export; drop the unused skin branch in `_enter_tree`; skip character/IK/animation init for cars; collision shape from the chosen definition; roll a `color_mod` off the seeded RNG onto a duplicated definition |
| `entities/npc/npc_rider_entity.tscn` | Add `CarSkin` under `VisualRoot` |
| `entities/npc/npc_animation_controller.gd` | Wheel-spin step for both skins, speed derived from position delta (runs on clients too); rider-only lean block guarded |
| `utils/components/skin_color.gd` | Optional `wheel_nodes: Array[Node3D]` for 4+ wheeled meshes |
| `resources/bikes/mods/bike_mod.gd`, `color_mod.gd` | Widen `apply()` to `Node3D` so mods work on `CarSkin` too |
| `managers/npc_traffic_manager.gd` | `npc_definitions` → weighted `vehicle_roster`; spawn RPC ships a definition `resource_path` instead of a `PlayerDefinition` dict; apply `speed_scale` / `max_line_offset` |
| `planning_docs/Skins.md` | Document `CarSkin` / `CarSkinDefinition` alongside the bike pair |

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
| `player/controllers/crash_controller.gd` | Layer-2 head-on crash path |
| `levels/racetracks/racetrack_level_01/` | Test level with the road loop |
| `planning_docs/Skins.md` | Skin/mod system the vehicle roster builds on |
| `player/bikes/scripts/bike_skin.gd` | `has_steering()` / `rotate_wheels()` — why a car needs no new visual pipeline |
| `utils/components/skin_color.gd` | `steering_rotation_node` / wheel nodes a vehicle mesh scene may expose |
| `resources/bikes/bike_skin_definition.gd` | `collision_shape` + offsets + `mods` the vehicle definition reuses |
| `player/player_entity.gd` | `_init_collision_shape()` — the three lines the NPC entity should copy |

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

Vehicle variety adds:

8. A roster of several bike definitions produces visibly mixed traffic, and the
   same rider looks identical on host and client (same skin, same paint roll).
9. A car roster entry spawns a car and **nothing else** — no bike mesh, no
   character, no IK errors in the log, no name label.
10. A `CarSkinDefinition`'s `collision_shape` is what the car collides with, not
    the scene's capsule.
11. Wheels spin on a client, not just the host — on both cars and bikes.
12. A `ColorMod` repaints a car the same way it repaints a bike.
13. Racing is untouched — `NPCRaceManager` still spawns its `PlayerDefinition`
    bots with usernames in the results table.

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
- Splitting `NPCRiderEntity` into an `NPCVehicleEntity` base with rider/car
  subclasses (and the matching rename) — the skins are separate, but one chassis
  drives both until cars need different *behavior* (turning circle, reverse,
  trailers), not just a different look.
- Player-drivable cars. `CarSkin` is deliberately NPC-only for now: `PlayerEntity`
  reads gearing / physics / trick tuning off `BikeSkinDefinition`, none of which
  `CarSkinDefinition` carries.
- Per-level traffic rosters: the city map spawns cars, the racetrack spawns bikes.
  Folds into the deferred level-driven traffic spawner node.
- A car-specific hit reaction (crashed cars currently just stop, since the wipeout
  roll lives in the rider's animation controller).
