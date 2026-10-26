# NPC Racer AI — Phase 1 (racing line + driving) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the lane-following race bot with bots that ride a navmesh-baked racing line, and delete the race bot's road-generator dependency.

**Architecture:** Each race level gets two nav regions on the default map: a road region and a grass region with a higher travel cost. A small `@tool` bake script keeps grass out of the road region. At `race_start`, `NPCRaceManager` builds one `NPCRacingLine` (a `RefCounted`) on the server. It chains road-only navmesh paths through the checkpoints, smooths them into a `Curve3D`, and samples curvature speed and road half-width along it. Each bot's rewritten `NPCRaceState` runs its own braking pass over that line and steers at a lookahead point. The steer point carries a per-bot lateral offset: a wandering offset normally, a committed one while overtaking. Every steer point is clamped onto the nav map.

**Tech Stack:** Godot 4.7 GDScript, `NavigationServer3D`, `Curve3D`, `PhysicsDirectSpaceState3D.intersect_shape`, DebugDraw3D (debug only).

**Spec:** [`planning_docs/____NPC_RACER_AI_WIP.md`](./____NPC_RACER_AI_WIP.md) (Phase 1 only), plus [Architecture — NPC Race Manager](./Architecture.md#npc-race-manager) and [NPC transform sync + render smoothing](./Architecture.md#npc-transform-sync--render-smoothing).

## Decisions made with the user (2026-10-25), overriding the spec

- **Grass is drivable but avoided.** The spec says grass must not be drivable. Instead, the racing line and the wandering offset stay on the road. Overtakes, dodges and the rejoin path may use grass, and grass costs more for pathing.
- `NPCNavRegionBAD` gets rebaked as the grass region (renamed `NPCNavGrassRegion`), not deleted. stunt_track_01 gets one too.
- Why the spec's "parse layer 1, grass is a hole" can't work as written: grass carries layer 1 in two of the three levels (test_city_01 `GBGrass*`/`SAND` = 19, stunt_track_01 grass/ground = 17). The road bake has to exclude layer-5 colliders explicitly.

## Re-verified "What exists today" (2026-10-25)

Accurate, except for these differences:

- `wheelie()` / `stop_wheelie()` have no callers. They stay, because they are the hook for Phase 3.
- `steer_lookahead()` / `steer_toward()` aren't lane-specific. They are **reused** by the new state, not deleted.
- `nearest_racer_ahead()` and its `_blocker*` cache are race-only and get deleted. `_next_scan_delay_ms()` is shared with traffic's `lane_speed()` and is kept, made public.
- stunt_track_01's navmesh parses **mesh instances** (`geometry_parsed_geometry_type` default), not static colliders. All three navmeshes use `cell_size` 0.5, but the project has no `[navigation]` section, so the map default is 0.25 (a mismatch).
- `RaceTask.is_point_to_point()` is wrong at `race_start`. `_collect_checkpoints()` only runs on the first human `on_enter`, so before that it reads two nulls and reports "loop".
- Race events with `enable_npcs`: racetrack_level_01 and test_city_01 only.
- `NPCAnimationController` leans from yaw rate. Yaw rate *is* speed × path curvature (ω = v·κ) and works on clients with no extra sync, so **lean needs no change**. Task 3 only verifies it.
- A traffic rider far from every player has its `ContactArea` turned off (traffic LOD), so a cast can't see it. Accepted: nobody can see that encounter either, and traffic is out of scope.
- The `race_gamemode.gd` comment at line 56 and `GamemodeSystem.md:174` give "the route graph must exist" as the reason for hook order. That reason dies with the route graph.

## Global Constraints

- Do not touch `NPCTrafficManager`, `NPCTrafficState`, `TrafficNetwork`, `TrafficLaneFollower`, `JunctionState`, or any traffic-only member of `NPCRiderEntity` (`lane_speed`, `line_offset`, `max_line_offset`, `cruise_speed`, `ride_to`, `ramp_speed`, `stop_line_speed`, the sync/render-smoothing code).
- The racer AI must not use the traffic system.
- No netfox rollback for bots. They stay server-simulated `CharacterBody3D`s, with the existing sync and smoothing.
- **Anti-train is a hard requirement:** bots must not trace the line perfectly or identically. A constant offset only makes parallel trains.
- Every steer target is clamped onto the nav map. Dodging can never put a bot inside a wall.
- Keep `Difficulty` EASY / MEDIUM / HARD.
- Tunables are exports named by behavior. Docs list them by name, never by value.
- Keep the throttled-scan approach for anything that sweeps other racers (`scan_interval_min/max`).
- Fail loudly (no silent null guards), and use `DebugUtils.DebugMsg()` for prints.
- No unit tests (Testing.md: out of scope). Every task is verified by lint, then the headless parse, then a **human playtest** (only the user runs the game).
  - Lint: `python -m gdtoolkit.linter <files>`. Expected: `Success: no problems found`.
  - Parse: `timeout 280 "c:/Users/ssebs/Desktop/DankNoonerDev/win64-g472-s165-gs423-editor/godotsteam.472.editor.win64.exe" --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" -A1`. Expected: no output.
- No `git` commands. Each task ends at a **checkpoint**, where the user reviews and commits.
- Out of scope: Phases 2–4 (contact/crashes, tricks, items).

## Review Focus

1. **The line passes near itself** (bridge over road, figure-8, stunt track corkscrew). A bot's progress `s` must not jump to the other pass. Pinned by Task 3's local-window `track_offset` and its playtest step.
2. **The nav map isn't synced yet at `race_start`** (same frame as level load). The bake must wait for the map, never build from empty paths, and bots must hold on the grid until it's ready. Pinned in Task 2.
3. **A checkpoint the road navmesh can't reach** (gate over a ramp gap, a navmesh hole). This gets a loud `push_error` naming the checkpoint, plus a straight bridge, so it's never a silent dead line. Pinned in Task 2.
4. **Race restart / retry / `race_end` while the bake is waiting.** A stale bake must not land on the next race's bots. Pinned by the bake generation guard in Task 2.
5. **A full grid closing on the same blocker at the start.** Bots must fan out to different sides, not form a nose-to-tail line. Pinned by Task 4's side choice (which considers the other riders) and its max-bots playtest step.

---

### Task 1: Nav bake that keeps grass out of the road region

**Files:**
- Create: `levels/components/npc_nav_region.gd`
- Modify: `utils/constants.gd` (nav layer consts)
- Modify: `levels/level_definition.gd` (export)
- Modify: `project.godot` (`[navigation]` section)
- Modify (in editor): `levels/racetracks/racetrack_level_01/racetrack_level_01.tscn`, `levels/test_levels/test_city_01/test_city_01.tscn`, `levels/racetracks/stunt_track_01/stunt_track_01.tscn`

**Interfaces:**
- Produces: `class_name NPCNavRegion extends NavigationRegion3D` (`@tool`)
  - `@export_flags_3d_physics var exclude_layers: int`: a collider carrying any of these bits is left out of the bake, even when it also matches `navigation_mesh.geometry_collision_mask`.
  - `@export_tool_button("Bake") var bake_btn = bake`, and `func bake() -> void`.
- Produces: `UtilsConstants.NAV_LAYER_ROAD: int = 1` and `UtilsConstants.NAV_LAYER_GRASS: int = 2` (navigation-layer bitmasks, not physics).
- Produces: `LevelDefinition.npc_nav_region: NPCNavRegion` (the road region; null on levels without NPC races).

- [ ] **Step 1: Add the consts and the `LevelDefinition` export.** No configuration warning, because most levels legitimately have no region. `NPCRaceManager` fails loudly when a race needs it (Task 2).
- [ ] **Step 2: Write `NPCNavRegion.bake()`.** Approach: collect every `CollisionObject3D` and `CSGShape3D` under the nodes in `navigation_mesh.geometry_source_group_name` whose `collision_layer & exclude_layers` is non-zero. Zero their `collision_layer`, run `NavigationServer3D.parse_source_geometry_data(navigation_mesh, src, self)`, restore every layer, then run `bake_from_source_geometry_data(navigation_mesh, src)`. Restore before baking, and regardless of what parse did. The engine's parser then handles every shape type (trimesh, box, CSG), so no shape code gets written. One-line comment on why the layer is zeroed: the parser has an include mask, not an exclude one.
- [ ] **Step 3: Project settings.** Add a `[navigation]` section with `3d/default_cell_size` and `3d/default_cell_height` matching the navmeshes' 0.5. Also add `3d/default_edge_connection_margin`, wide enough to bridge the road↔grass gap. Each region erodes by `agent_radius`, so the gap is about 2 × agent_radius.
- [ ] **Step 4: Lint + parse** (commands in Global Constraints).
- [ ] **Step 5: Re-author each level in the editor:**
  - `NPCNavRegion`: attach the script. Source = static colliders, `geometry_collision_mask` = layers 1+2, `exclude_layers` = layer 5, `navigation_layers` = `NAV_LAYER_ROAD`. On stunt_track_01, switch `geometry_parsed_geometry_type` to static colliders.
  - `NPCNavRegionBAD` → rename to `NPCNavGrassRegion`, attach the script. `geometry_collision_mask` = layers 5+2 (so walls standing on grass still cut it), `exclude_layers` = none, `navigation_layers` = `NAV_LAYER_GRASS`. Lower `enter_cost`/`travel_cost` from 999 to a moderate value, so grass is a real but discouraged shortcut. stunt_track_01: create one.
  - Wire `LevelDefinition.npc_nav_region` to the road region on all three levels, then press Bake on both regions.
- [ ] **Step 6: Human check, in editor and in-game with Debug > Visible Navigation:**
  - The road region has holes wherever grass/sand is, on all three levels.
  - The grass region covers exactly those holes.
  - Walls and obstacles cut both regions.
  - Edge connections are drawn across the road↔grass seam.
  - No cell-size mismatch warning in the Output.
- [ ] **Checkpoint:** user reviews + commits.

---

### Task 2: `NPCRacingLine` bake + manager orchestration

**Files:**
- Create: `entities/npc/npc_racing_line.gd`
- Modify: `managers/gamemodes/tasks/race_task.gd:225-233` (`_collect_checkpoints`)
- Modify: `managers/npc_race_manager.gd`
- Modify: `managers/gamemodes/types/race/components/npc_racers_component.gd:9-20`

**Interfaces:**
- Consumes: `LevelDefinition.npc_nav_region`, `UtilsConstants.NAV_LAYER_ROAD` (Task 1).
- Produces: `static func RaceTask.is_lap_route(checkpoints: Array[CheckPointMarker]) -> bool`, which holds the existing `"StartStop" in checkpoints[0].name` rule. `_collect_checkpoints()` calls it, so the rule lives in one place.
- Produces: `class_name NPCRacingLine extends RefCounted`
  - `func _init(road_region: RID, checkpoints: PackedVector3Array, closed: bool, sample_spacing: float, smoothing_passes: int, corner_grip: float, max_half_width: float)`
  - `var closed: bool`
  - `func get_length() -> float`
  - `func wrap_offset(s: float) -> float`: `fposmod` on a closed line, clamp on an open one
  - `func point_at(s: float) -> Vector3`
  - `func right_at(s: float) -> Vector3`: horizontal unit vector, right of travel
  - `func curvature_at(s: float) -> float`: signed, positive = turning left
  - `func half_width_at(s: float, side: float) -> float`: road room from the line to the eroded road edge, on the `sign(side)` side (+ = right)
  - `func braking_profile(decel: float, corner_scale: float) -> PackedFloat32Array`: per-sample target speeds
  - `func profile_speed(profile: PackedFloat32Array, s: float) -> float`
  - `func closest_offset(pos: Vector3) -> float`: global search
  - `func track_offset(pos: Vector3, s_hint: float, window: float) -> float`: local search
- Produces on `NPCRaceManager`:
  - `var racing_line: NPCRacingLine` (null until baked and after despawn)
  - `func bake_racing_line(route: EventRoute) -> void` (coroutine)
  - Exports: `line_sample_spacing`, `line_smoothing_passes`, `corner_grip`, `line_max_half_width`
- The old lane bot still drives during this task. Its `road_manager` wiring stays until Task 3, and nothing hands the line to bots yet.

- [ ] **Step 1: `RaceTask.is_lap_route`** and route `_collect_checkpoints` through it. `is_point_to_point()` stays as is.
- [ ] **Step 2: Bake corridor in `NPCRacingLine._init`.**
  - Snap each checkpoint with `NavigationServer3D.region_get_closest_point(road_region, p)`.
  - Chain `map_get_path(region_get_map(road_region), a, b, true, UtilsConstants.NAV_LAYER_ROAD)` between consecutive checkpoints, plus last→first when `closed`. Road layer only: the line never routes over grass.
  - If a path's last point lands more than `sample_spacing` short of its target, `push_error` naming both checkpoint indices, then bridge straight to it.
  - Checkpoints only: the grid is not part of the line. Bots on the grid steer or rejoin onto it like any off-line bot (Task 3).
- [ ] **Step 3: Smooth into the line.**
  - Resample the corridor at `sample_spacing`.
  - Run `smoothing_passes` Laplacian passes (`p[i] = lerp(p[i], (p[i-1] + p[i+1]) / 2, 0.5)`, with wrapped neighbours when `closed` and pinned endpoints when open). After each pass, re-clamp every point with `region_get_closest_point(road_region, …)`.
  - Why this yields a racing line: the funnel path already touches corner insides at the eroded edge. Smoothing rounds entry and exit, and the clamp holds the apex on the road. The navmesh's own erosion is the edge margin, so there is no separate margin knob.
  - Fit a `Curve3D` through the points, with Catmull-Rom tangents (`(p[i+1] - p[i-1]) / 6` as out, negated as in) and `closed` set.
- [ ] **Step 4: Per-sample data.** Store per sample index:
  - Signed curvature: horizontal heading change between neighbouring segments ÷ spacing.
  - `corner_speed = sqrt(corner_grip / max(|κ|, ε))`.
  - Left/right half-width: march outward along `∓right_at` in `sample_spacing` steps until the step's horizontal distance to `region_get_closest_point` exceeds half a step, capped at `max_half_width`. Marching rather than one long probe means a parallel road beyond a median can't count as room.
- [ ] **Step 5: `braking_profile(decel, corner_scale)`.** Copy `corner_speed * corner_scale`, then sweep backward with `p[i] = min(p[i], sqrt(p[i+1]² + 2·decel·spacing))`. A closed line sweeps twice around the seam, so a corner just past the start/finish still brakes before it. This is the spec's backward pass. It runs per bot (Task 3), so each bot brakes from its own `npc.braking` and no shared braking knob duplicates it.
- [ ] **Step 6: `track_offset`.** Return the sample nearest `pos` within `[s_hint - window/4, s_hint + window]`, wrapped. Forward-biased and local, so the other pass of a crossing is never considered (Review Focus 1). `closest_offset` is the global `Curve3D.get_closest_offset` and is used only after a teleport.
- [ ] **Step 7: Manager orchestration.**
  - Delete `_route_graph`, its build in `spawn_npc`, its clear in `despawn_all_npcs`, and the `race_state.route_graph` / `race_state.race_task` assignments. The old state treats a null `route_graph` as "no junction".
  - `bake_racing_line(route)`:
    - Take `region := level_manager.current_level.npc_nav_region` (no null guard; a NPC race on a level without one should crash).
    - Capture `_bake_generation`. While `map_get_iteration_id(region.get_navigation_map()) == 0`, `await NavigationServer3D.map_changed` (Review Focus 2).
    - Drop the result if the generation changed. `despawn_all_npcs` bumps it and nulls `racing_line` (Review Focus 4).
    - Build `racing_line = NPCRacingLine.new(region.get_rid(), <route checkpoint positions>, RaceTask.is_lap_route(route.get_checkpoints()), …exports)`.
- [ ] **Step 8: Call `npc_race_manager.bake_racing_line(race_mode.get_route())`** from `NPCRacersComponent.race_start` after the spawn loop, without `await` (bots hold until it lands).
- [ ] **Step 9: Debug draw.** `Console.add_command("dbg_racing_line", …)` in `NPCRaceManager._ready`, following `LevelManager`'s `dbg_traffic` pattern. On toggle, DebugDraw3D draws the line once, coloured slow→fast by `braking_profile(<any bot>.braking, 1.0)`, with both half-width edges. It's server/host only, and it's here only to verify the bake. Delete it with the WIP doc if unwanted.
- [ ] **Step 10: Lint + parse.**
- [ ] **Step 11: Human playtest** (racetrack_level_01 lap race, both test_city_01 NPC events), then `dbg_racing_line` during the countdown:
  - The line is on asphalt everywhere and visibly cuts corner insides.
  - Slow colour starts *before* each corner, not at the apex.
  - The loop closes cleanly at the start/finish on the lap race, and the point-to-point line is open.
  - Edges sit at the road edge.
  - No `push_error` in the Output.
  - Restart the race from results: no errors, and the line redraws.
- [ ] **Checkpoint:** user reviews + commits.

---

### Task 3: Rewrite `NPCRaceState` driving; delete the lane bot

**Files:**
- Rewrite: `entities/npc/states/npc_race_state.gd`
- Modify: `entities/npc/npc_rider_entity.gd`
- Modify: `managers/npc_race_manager.gd` (line hand-off, `_respawn_npc`, road-manager removal)
- Delete: `entities/npc/traffic_route_graph.gd`, `entities/npc/traffic_route_graph.gd.uid`

**Interfaces:**
- Consumes: `NPCRacingLine` API, `NPCRaceManager.racing_line` / `bake_racing_line` (Task 2).
- Produces on `NPCRaceManager`: `func _race_state(npc_id: int) -> NPCRaceState`, mirroring `NPCTrafficManager._traffic_state`.
- Produces on `NPCRaceState`:
  - `var racing_line: NPCRacingLine`, whose setter builds this bot's `_profile` via `racing_line.braking_profile(npc.braking * _brake_scale, _corner_carry)` and calls `reset_line_progress()`
  - `func reset_line_progress() -> void`, which sets `_s = racing_line.closest_offset(npc.global_position)`
  - Keeps `signal stuck`, `enum Difficulty`, `difficulty`, `stuck_window`, `stuck_min_progress`, `enable_overtaking` (now: off = ride the line with wander only)
  - New exports: `wander_fraction`, `wander_wavelength`, `style_spread`, `offset_response`, `rejoin_distance`, `rejoin_lookahead`
- Produces on `NPCRiderEntity`: `func next_scan_delay_ms() -> int` (renamed from `_next_scan_delay_ms`; `lane_speed` is updated to the new name).

- [ ] **Step 1: Entity cleanup.**
  - Delete `road_manager`, `lane_agent`, the `_ready` lane-agent block, `lane_point_ahead`, `nearest_racer_ahead`, `_blocker`, `_blocker_next_scan_ms`, and the `teleport_to` lane re-latch.
  - Rename `_next_scan_delay_ms` → `next_scan_delay_ms`.
  - Rewrite the class docstring's race paragraph (lines 10-13) to one line: race steering rides the shared `NPCRacingLine` (see `NPCRaceState`).
  - Drop the `RoadLaneAgent` mentions in `lane_speed`'s docstring (traffic is now its only caller).
  - Everything traffic uses stays byte-identical.
- [ ] **Step 2: Delete `traffic_route_graph.gd` + `.uid`.**
- [ ] **Step 3: Per-bot style in `Enter`.**
  - Seed an RNG from `hash(npc.name)` combined with a fixed salt, so it doesn't repeat the entity's own roll.
  - Roll `_corner_carry`, `_brake_scale` and `_reaction` each in `1 ± style_spread`, plus two wander phases and two wavelengths around `wander_wavelength`.
  - Difficulty: keep the existing `move_speed` / `min_turn_speed` scaling. Also shift the means of corner carry and brake scale (EASY lower, HARD higher), and scale `wander_fraction` (HARD narrower, as it used to halve `max_line_offset`). Values are the builder's call. Stop mutating `npc.max_line_offset`, which is a traffic knob.
- [ ] **Step 4: Wandering offset.**
  - `_wander_target(s) = wander_fraction × (0.6·sin(2πs/λ1 + φ1) + 0.4·sin(2πs/λ2 + φ2))`, a fraction of road half-width, converted to metres with `half_width_at(s, sign)`.
  - On a closed line, round each λ so a whole number of cycles fits the lap (`λ = L / round(L/λ)`), so the offset doesn't jump at the seam.
  - The live `_lateral` (metres) eases toward its target at `offset_response × _reaction` m/s. That ease is the bot's steering reaction.
- [ ] **Step 5: `_drive(delta)`.**
  - `_s = racing_line.track_offset(pos, _s, <window ≥ 2 × max_steer_lookahead>)`.
  - Steer point: `racing_line.point_at(s_t) + right_at(s_t) × _lateral` with `s_t = wrap_offset(_s + npc.steer_lookahead())`, clamped with `map_get_closest_point` (whole map; dodges may use grass).
  - Target speed: `min(npc.cruise_speed(), max(npc.min_turn_speed, profile_speed(_profile, _s)))`.
  - Then `npc.steer_toward(target, speed, delta)`.
  - On an open line past its end, hold the end point (the `RaceTask` finish stops the bot).
- [ ] **Step 6: Rejoin.**
  - Trigger: the bot's horizontal distance from `point_at(_s)` exceeds `|_lateral| + rejoin_distance` (pushed off, respawned, grid).
  - Repath on the `npc.next_scan_delay_ms()` cadence with `map_get_path(map, pos, point_at(_s + rejoin_lookahead), true, NAV_LAYER_ROAD | NAV_LAYER_GRASS)`, then steer at the first path point beyond `npc.min_steer_lookahead`. Region costs make it prefer road.
  - Leave rejoin once back within `rejoin_distance`.
- [ ] **Step 7: Physics_Update.** Same shape as today: drive while `npc.driving and racing_line != null` and not CRASHED/FINISHED, else `coast_to_stop`. Then `apply_gravity_and_move`, then `_check_stuck` (carried over unchanged) while driving.
- [ ] **Step 8: Manager wiring.**
  - Delete `_find_road_manager()` and `npc.road_manager = …`.
  - Add `_race_state(npc_id)`.
  - `bake_racing_line` assigns the finished line to every live bot's `_race_state(id).racing_line`, and `rpc_spawn_npc` (server branch) assigns the current `racing_line`, which may still be null.
  - `_respawn_npc` calls `_race_state(npc_id).reset_line_progress()` right after `teleport_to`.
- [ ] **Step 9: Lint + parse.** Also grep for any leftover `RoadLaneAgent|RoadManager|TrafficRouteGraph|lane_agent|road_manager` outside `addons/` and `road_demos/`. Expected: only doc/comment hits that Task 5 fixes.
- [ ] **Step 10: Human playtest:**
  - Bots leave the grid at the green and merge onto the line.
  - They brake before corners and lean through them (existing yaw-rate lean, nothing changed).
  - No two bots ride the same line for long, and spacing drifts over a lap.
  - Ram a bot onto grass: it cuts back and prefers road.
  - Wedge one: the stuck respawn fires and it continues from the checkpoint.
  - Where a track crosses itself, bots don't snap to the other pass.
  - Traffic in a test_city_01 event still drives normally.
- [ ] **Checkpoint:** user reviews + commits.

---

### Task 4: Avoidance, overtaking and mistakes

**Files:**
- Modify: `entities/npc/states/npc_race_state.gd`

**Interfaces:**
- Consumes: Task 3's `_s`, `_lateral`, `_profile`, `npc.next_scan_delay_ms()`.
- New exports: `avoid_lookahead_time`, `avoid_min_range`, `avoid_scan_half_width`, `avoid_lane_half_width`, `overtake_clearance`, `overtake_commit_time`, `mistake_interval`, `mistake_duration`, `late_brake_distance`, `run_wide_fraction`.

- [ ] **Step 1: Throttled forward scan** (`npc.next_scan_delay_ms()` cadence; cache the result between scans, like the deleted `nearest_racer_ahead` did).
  - One `intersect_shape`: a box `2·avoid_scan_half_width` wide, reaching `max(avoid_min_range, speed × avoid_lookahead_time)` ahead along the bot's heading.
  - `collide_with_areas = true`, mask = layer 2 (`crash_collision`: racer bodies are layer 3, and traffic `ContactArea`s are layer 2), excluding the bot's own body and `ContactArea` RIDs.
  - Map each hit to a rider: the collider if it's in the `Racers` group, else its parent if that is. Drop non-riders (walls are the navmesh's job) and dedupe.
  - For each rider, keep its forward distance `d` and its line-relative lateral `(rider.pos - point_at(_s + d)) · right_at(_s + d)`.
- [ ] **Step 2: Blocker + speed.** The blocker is the nearest rider whose lateral is within `avoid_lane_half_width` of our `_lateral` and who is slower than us. While a blocker exists and there's no open side, cap the target speed at `npc.horizontal_speed(blocker)`.
- [ ] **Step 3: Overtake, when `enable_overtaking` is on.**
  - On a blocker with no commit active, pick the side whose target `blocker_lateral ± overtake_clearance` has no other scanned rider within `avoid_lane_half_width`. Prefer the side with more `half_width_at` room (ties: the side the wander already leans).
  - Set `_lateral` target to that value for `overtake_commit_time`, then hand back to the wander.
  - The target may exceed road width (grass is allowed for dodges). The steer-point clamp keeps it out of walls.
  - Because the side choice counts the other scanned riders, bots stacked behind one blocker take different sides (Review Focus 5).
- [ ] **Step 4: Mistakes.**
  - A per-bot timer rolled around `mistake_interval` (EASY more often, HARD rarer) fires one of two mistakes for `mistake_duration`:
    - **Late brake:** read `profile_speed` at `_s - late_brake_distance`.
    - **Run wide:** push the `_lateral` target toward the outside of the corner (`-sign(curvature_at(_s))`) by `run_wide_fraction` of that side's half-width.
  - The clamp still applies to both.
- [ ] **Step 5: Lint + parse.**
- [ ] **Step 6: Human playtest, at max bots on the racetrack and with traffic in a test_city_01 event:**
  - At the start the pack fans out, not single-file.
  - Bots pass each other and the player on both sides, then return to wandering.
  - Bots slow behind, or go around, traffic and a stopped player.
  - Nobody pins on a wall while dodging.
  - Over a few laps there's the occasional visible lock-up or wide line, and more of them on EASY.
  - Flip `enable_overtaking` off on the scene's NPCRaceState: bots still wander and don't train.
- [ ] **Checkpoint:** user reviews + commits.

---

### Task 5: Docs

**Files:**
- Modify: `planning_docs/Architecture.md`: the "Terrain & Roads" junction-routing bullet (drop `TrafficRouteGraph`, since race bots no longer read the addon), plus "NPC Race Manager"
- Modify: `planning_docs/GamemodeSystem.md:174` and `managers/gamemodes/types/race/race_gamemode.gd:56` (drop the dead "route graph must exist" reason; the order stays)
- Modify: `CLAUDE.md:129` (`TrafficRouteGraph` → `NPCRacingLine`)
- Modify: `planning_docs/____NPC_RACER_AI_WIP.md`: mark Phase 1 done, and record the grass decision against the original rule. Don't delete it; Phases 2–4 remain.

- [ ] **Step 1: Architecture "NPC Race Manager".** Cover:
  - The two nav regions and why the road bake excludes layer 5.
  - Bake once per race on the server, wait for the map, and the generation guard.
  - The shared line plus the per-bot braking pass (and why it's per bot).
  - Local progress tracking.
  - The anti-train set (wander, style, overtake commit, mistakes).
  - The accepted gap: far traffic is invisible to casts.

  Tunables by name only.
- [ ] **Step 2: The remaining doc and comment edits above.** Re-lint `race_gamemode.gd`.
- [ ] **Checkpoint:** user reviews + commits.
