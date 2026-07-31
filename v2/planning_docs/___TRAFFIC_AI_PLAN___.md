# Traffic AI — Design

> Status: v1 implemented (free roam only). Vehicle variety — mixed bikes + cars —
> implemented; per-vehicle tuning and wheel spin are not (see Deferred).
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

## Vehicle variety — implemented

Traffic is a mix of bikes and cars. Each rider rolls its own vehicle at spawn, so
free roam reads as traffic rather than a parade of one sportbike. **Traffic only** —
racing keeps its `PlayerDefinition` roster, because race bots need usernames for the
results table.

### How a vehicle is chosen

`NPCTrafficManager.start_traffic()` scans two folders — the bike skins folder and
the car skins folder — through `SkinScanner.scan_skin_dir()`, the same scan the
customize menu uses to list skins. Drop a `.tres` into either folder and it joins
the roster; there is no array to wire up and no code to touch.

Per rider, `_roll_vehicle()` rolls car-vs-bike against `car_chance`, then picks a
random skin from that folder. The roll happens **on the server only** and the
result ships in the spawn RPC — rolling per peer would give the same rider a
different car on every screen.

Deliberately **not** the `TrafficVehicleDefinition` roster resource this document
originally designed. A roster entry earns its keep when entries carry per-vehicle
tuning (spawn weight, speed scale, lateral wander); until then it is a `.tres` to
maintain per vehicle that says nothing the folder scan doesn't. See Deferred.

### `CarSkin` — its own skin, mirroring `BikeSkin`

A car gets a first-class `CarSkin` + `CarSkinDefinition` pair rather than being
smuggled through `BikeSkinDefinition`. Bike tuning (gearing, lean, trick limits,
rider pose, handlebar proxy) is meaningless on a car, and a car's own concerns
(four wheels, a box collider) have nowhere to live on a bike definition. Same
pattern, new pair — one place to look when something is car-shaped.

The pair:

| Piece | Mirrors | Notes |
| --- | --- | --- |
| `car_skin.gd` / `car_skin.tscn` | `bike_skin.{gd,tscn}` | `skin_definition` setter → `_apply_definition()` → `_spawn_mesh()` + `_apply_mods()`, `mesh_skin: SkinColor`, `rotate_wheels()` |
| `resources/cars/car_skin_definition.gd` | `bike_skin_definition.gd` | Mesh (`mesh_res`, offsets, scale), Collision (`collision_shape` + offsets), Mods |

Deliberately **not** carried over: steering handlebar proxy, rider pose block,
gearing / physics / trick groups. The NPC chassis owns motion; the skin owns looks
and collision. (Bikes live under `player/` for historical reasons — cars are
NPC-only, so `entities/` is the honest home.)

Two shared pieces were nudged:

- **`SkinColor` wheels.** It exposed `front_wheel_node` / `rear_wheel_node` under a
  "BikeSpecifics" category. A car has four+, so a "VehicleSpecifics" category adds
  `wheel_nodes: Array[Node3D]` for `CarSkin.rotate_wheels()`. Additive — bikes keep
  their two fields and leave it empty.
- **`BikeMod.apply()`** was typed to `BikeSkin`, so `ColorMod` couldn't paint a
  `CarSkin`. The parameter is now `Node3D` (documented as "any vehicle skin exposing
  `mesh_skin`") so one `ColorMod` ecosystem serves both. No behavior change for bikes.

### Rider vs car on `NPCRiderEntity`

`npc_rider_entity.tscn` carries a `CarSkin` under `VisualRoot` beside `BikeSkin` and
`CharacterSkin`. A `VehicleType { BIKE, CAR }` enum + `vehicle_type` export decides
which is worn — an explicit switch, not "whichever definition happens to be non-null".
Spawning managers set it **before `add_child`**, including `NPCRaceManager`, which
states `BIKE` rather than inheriting whatever the scene was last saved with.

A car spawns neither of the other two: no bike mesh, no character, no IK, no
`animation_controller.initialize()`, and the `NameLabel` hidden (nobody to name).

> **Ordering trap.** `bike_skin.tscn` ships a default `skin_definition` *and* a
> pre-instanced mesh, and `BikeSkin._ready()` applies it unconditionally;
> `CharacterSkin` and `CarSkin` do the same. Children run `_ready` **before** their
> parent, so by `NPCRiderEntity._ready()` all three have already built themselves.
> The unused skins are therefore dropped in the entity's **`_enter_tree`** (parent
> enter-tree precedes child ready), with `remove_child` + `free()` — `queue_free()`
> is deferred and still lets `_ready` run. `@onready` vars and `%UniqueName` haven't
> resolved that early: direct child paths only.

> **Editor trap, learned the hard way.** `NPCRiderEntity` is `@tool`, so `_enter_tree`
> runs in the editor too — and freeing a skin there deletes it out of
> `npc_rider_entity.tscn` the moment the scene is saved. It cost the scene its
> `BikeSkin` and `CharacterSkin` once. In-editor the entity now keeps every skin and
> **hides** the unused half instead. Visibility is written on every path, so a
> `visible` flag saved into the scene can't leak onto the wrong vehicle.

`_ready` follows `PlayerEntity._ready`: `_init_mesh()` then `_init_collision_shape()`
unconditionally, *then* return on `Engine.is_editor_hint()`. That's what makes the
scene preview live — set `vehicle_type` + `car_definition` in the inspector and the
car rebuilds, collider included. Two deliberate deviations from `PlayerEntity`:
`animation_controller.initialize()` stays runtime-only (this scene's `IKTargets`
lives under `VisualRoot`, so in-editor IK would re-pose markers and save them), and
`_init_collision_shape()` sources its four fields from whichever definition matches
`vehicle_type`.

### Networking

The spawn RPC ships a flat dictionary of `res://` paths — vehicle type, the skin
path, and (bikes only) the character path and username. Traffic skins live in
`res://` and ship inside the export, so **the paths are the serializer**; there is
no per-field serializer and no `to_dict()` on `CarSkinDefinition`. The constraint
that buys this: traffic skins must be `res://` and identical on every peer. No
`user://` customization for traffic — that's a player-loadout feature.

> Traffic deliberately does **not** ship `PlayerDefinition.to_dict()` any more.
> `PlayerDefinition.from_dict()` round-trips every loadout through
> `BikeSkinDefinition.from_dict()`, which ends in `save_to_disk()` — so the old path
> wrote a `.tres` into `user://skins/` for every traffic rider on every peer.

### Wheels — not wired up

`CarSkin.rotate_wheels(speed, delta)` exists and mirrors `BikeSkin`'s, but nothing
calls it yet. `NPCAnimationController` is the intended caller — it already derives
everything cosmetic from the synced transform. Note NPC **bikes** have never spun
their wheels either, for the same reason.

> When wiring it: the controller runs on **every peer**, but `current_speed` is
> server-side chassis state clients never receive. Derive speed from the position
> delta the same way `_update_yaw_rate()` derives yaw rate from the rotation delta,
> or wheels will only turn on the host.

The lean / wheelie / crash-roll block stays rider-only; a car would use the wheel
step and nothing else.

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

Vehicle variety:

| Path | What |
| --- | --- |
| `entities/vehicles/car_skin.gd` + `.tscn` | `CarSkin` — mesh spawn, colors, mods, `rotate_wheels()`. `BikeSkin` minus the bike |
| `entities/vehicles/scenes/*.tscn` | Per-car `SkinColor` mesh scenes |
| `resources/cars/car_skin_definition.gd` | `CarSkinDefinition` — mesh + collision + mods |
| `resources/cars/skins/*.tres` | Per-car definitions — **this folder is the car roster** |
| `resources/cars/hitbox/*.tres` | Car collision shapes |
| `utils/skin_scanner.gd` | `SkinScanner.scan_skin_dir()` — lifted out of `CustomizeMenuState` so the menu and traffic list skins the same way |

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

Vehicle variety:

| Path | Change |
| --- | --- |
| `entities/npc/npc_rider_entity.gd` | `@tool`; `VehicleType` enum + `vehicle_type` / `car_definition` exports; `_enter_tree` drops the unused skins at runtime and hides them in-editor; `_init_mesh` / `_init_collision_shape` mirroring `PlayerEntity`; character/IK/animation init and the name label skipped for cars |
| `entities/npc/npc_rider_entity.tscn` | Add `CarSkin` under `VisualRoot` |
| `utils/components/skin_color.gd` | Optional `wheel_nodes: Array[Node3D]` for 4+ wheeled meshes |
| `resources/bikes/mods/bike_mod.gd`, `color_mod.gd` | Widen `apply()` to `Node3D` so mods work on `CarSkin` too |
| `managers/npc_traffic_manager.gd` | `car_chance` export; scan both skin folders in `start_traffic`; `_roll_vehicle()`; spawn RPC ships `res://` paths instead of a `PlayerDefinition` dict |
| `managers/npc_race_manager.gd` | Set `vehicle_type = BIKE` explicitly at spawn |
| `menus/customize_menu/customize_menu_state.gd` | `_scan_skin_dir` moved out to `SkinScanner` |
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

8. Traffic is visibly mixed — several bike skins and several cars — and a given
   rider looks identical on host and client.
9. A car spawns a car and **nothing else** — no bike mesh, no character, no IK
   errors in the log, no name label.
10. A `CarSkinDefinition`'s `collision_shape` is what the car collides with, not
    the scene's capsule.
11. A `ColorMod` repaints a car the same way it repaints a bike.
12. Racing is untouched — `NPCRaceManager` still spawns its `PlayerDefinition`
    bots with usernames in the results table.
13. Dropping a new `.tres` into either skins folder puts it in traffic with no
    other change.
14. Opening `npc_rider_entity.tscn`, toggling `vehicle_type`, and **saving** leaves
    all three skins in the scene — the editor must never free them (see the editor
    trap above).

## Deferred

Tracked in TODO under Traffic AI / Backlog > AI/traffic:

- Traffic lane changes and overtaking (traffic follows one lane per junction leg).
- Per-vehicle traffic tuning: spawn weight, speed scale (trucks should lumber),
  lateral wander (wide vehicles shouldn't). Every vehicle currently rolls with
  equal odds, the manager's cruise speed, and the entity's default wander. This is
  what a `TrafficVehicleDefinition` roster resource would be *for* — build it when
  the tuning exists, not before.
- Per-spawn `ColorMod` roll for paint variety, off the `hash(name)`-seeded RNG
  already in `NPCRiderEntity._ready` (every peer names the rider identically, so
  every peer rolls the same paint — no extra sync). **Gotcha when doing it:** skin
  definitions are shared resources, so appending the rolled mod to a definition's
  `mods` array would repaint every rider using it, and leak into the player's bike
  if the `.tres` is shared. `duplicate()` the definition and give it a fresh `mods`
  array first.
- Wheel spin — `CarSkin.rotate_wheels()` exists but nothing calls it, and NPC bikes
  have never spun theirs either. See "Wheels — not wired up" above.
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
