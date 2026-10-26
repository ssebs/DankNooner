# NPC Racer AI — design (WIP)

> Brainstormed 2026-10-25. Replaces the lane-following race bot. Delete this file once the system
> ships and its "how it works" is folded into [Architecture](./Architecture.md#npc-race-manager).

- [Why](#why)
- [Goals / non-goals / anti-goals](#goals--non-goals--anti-goals)
- [What exists today](#what-exists-today)
- [Phases](#phases)
  - [Phase 1: racing line + driving](#phase-1-racing-line--driving)
  - [Phase 1 status (handoff)](#phase-1-status-handoff)
  - [Ramp riding (next, design in progress)](#ramp-riding-next-design-in-progress)
  - [Phase 2: contact + crashes](#phase-2-contact--crashes)
  - [Phase 3: tricks, scoring, boost](#phase-3-tricks-scoring-boost)
  - [Phase 4: items](#phase-4-items)
- [Open questions (ask before the phase that needs them)](#open-questions-ask-before-the-phase-that-needs-them)
- [Left to the builder](#left-to-the-builder)

## Why

The road generator (`RoadManager` / `RoadContainer` / `RoadLane` / `RoadLaneAgent`) is hard to
manage in the editor and is being replaced by roads modeled in Blender. Race bots are its last
real consumer in game code, so they have to move to something geometry-only: the **navmesh** plus
the **checkpoints** the race already has.

Traffic is **not** part of this — it runs on its own baked `TrafficNetwork` and must not be
touched. The racer AI must not use the traffic system either.

## Goals / non-goals / anti-goals

**Goals**
- Bots path over the navmesh toward their next checkpoint and ride a baked **racing line**.
- Realistic-ish bike handling: brake before turns, lean through them. Far simpler than the
  player's physics.
- Avoid players, other bots and traffic with raycasts / shape casts.
- Crash into each other, players and obstacles; be affected by every item.
- Do tricks and use items under the **same rules as the player**, dumbed down.
- In a stunt race, bots earn real trick score — a lone human who rides badly should lose to bots
  that tricked more.

**Non-goals**
- Netfox rollback for bots. They stay server-simulated kinematic bodies that clients watch
  (existing `NPCRiderEntity` sync + render smoothing).
- Full bike physics (gearbox, pitch, real lean dynamics).
- Changing traffic.

**Anti-goals** (failure even if it "works")
- **The train.** The last navmesh attempt had every bot follow the identical path and they rode
  nose-to-tail like a train. Bots must not trace the line perfectly or identically.
- Bots leaving the road onto grass, or into walls, while dodging / overtaking.
- A second copy of player logic (crash rules, trick scoring, item effects) living in the bot code.
  Reuse the existing rules through a shared path; don't fork them.

## What exists today

Verified 2026-10-25 — re-verify before acting.

- `entities/npc/states/npc_race_state.gd` — lane-following race behavior: lane changes to overtake,
  junction routing via `TrafficRouteGraph`, corner speed via `NPCRiderEntity.lane_speed`, and a
  `stuck` signal (no progress over a window → `NPCRaceManager.crash_npc`).
- `entities/npc/npc_rider_entity.gd` — shared chassis for race bots **and** traffic. Race-only
  pieces: `road_manager`, `lane_agent`, `lane_point_ahead`, `steer_lookahead`, `steer_toward`,
  `nearest_racer_ahead`, `wheelie()` stub. Traffic still uses `lane_speed`, `line_offset`,
  `cruise_speed`, `ride_to`, `ramp_speed`, the sync/render-smoothing code — keep those.
- `entities/npc/traffic_route_graph.gd` — despite the name, used **only** by race bots
  (`NPCRaceState`, `NPCRaceManager`). Deleted with the lane bot.
- `managers/npc_race_manager.gd` — negative-id roster, spawn/despawn RPCs, server AI tick setting
  `npc.driving` from `RaceTask.get_target_checkpoint`, crash → respawn timer at
  `RaceTask.get_npc_respawn_checkpoint` (falls back to grid slot). Builds the route graph and finds
  `RoadManager` — both go.
- `RaceTask` — `get_target_checkpoint(npc_id)` (null on grid / countdown / after finish),
  `is_point_to_point()`, checkpoint list via `runner.route.get_checkpoints()`, `lap_checkpoints`,
  `start_checkpoint`, `end_checkpoint`.
- **Navmeshes:** `racetrack_level_01`, `stunt_track_01`, `test_city_01` have an `NPCNavRegion`
  (static colliders, source = `navigation_mesh_source_group`, collision mask 1). Two also have an
  unused `NPCNavRegionBAD` (mask = layer 5). Nothing in code reads them today.
- **Collision layers** (`project.godot`): 1 = default/road surface, 2 = `crash_collision`
  (walls/obstacles; racers carry it too), 5 = `unstable_collision` (grass), 7 = `road`.
- **Blocks bots today:** every item effect checks `body is PlayerEntity` or goes through
  `SpawnManager.get_player_by_peer_id`; `ItemManager` is keyed on peer id + `PlayerEntity`;
  `TrickManager` banks score by watching each `PlayerEntity`'s synced combo state;
  `CrashController._crash_rammed_racer` only calls `report_hit` on a bot, and race bots ignore it;
  knockouts score "human victims only" (StuntRaceGamemode.md).

## Phases

Each phase is playable on its own. Order decided: 1 → 2 → 3 → 4. Added 2026-10-25: **ramp riding**
goes before Phase 3, which needs bots that get airborne. Whether it lands before or after Phase 2
is not decided.

### Phase 1: racing line + driving

> **Built 2026-10-25, playtested, still getting stuck**; see [status](#phase-1-status-handoff)
> ([plan](./PLAN-npc-racer-phase1-20261025.md)); how it works is in
> [Architecture](./Architecture.md#npc-race-manager). One rule changed with the user: grass is
> **drivable but avoided**. The racing line and wander stay on the road; overtakes, dodges and
> rejoin paths may cross grass (a costlier nav region), never walls.

Ends with the lane bot and its road-generator dependency deleted.

**Navmesh bake (decided)**
- Walkable = layer 1 only. Grass (layer 5) and anything on `crash_collision` (layer 2) must not be
  driveable. Builder's call on mechanics (my suggestion: parse layers 1 + 2 so walls cut the mesh;
  grass is never parsed, so it's a hole). Re-bake the existing `NPCNavRegion`s.

**Racing line bake (decided: once per race, before the race starts, server-side)**
1. Navmesh paths chained grid → checkpoint 1 → … → last checkpoint, closing the loop on lap races
   (`is_point_to_point()` decides). This is the corridor.
2. Smooth it into a racing line that cuts toward corner insides while every point stays on the
   navmesh with an edge margin. Fit a Bezier `Curve3D` through it.
3. Bake a target speed per point from curvature, then a backward pass so braking starts **before**
   the corner, not at the apex. Lean comes from speed × curvature.
- One bake, shared by every bot. Rebuilt per race (the level may change).

**Driving**
- Each bot steers at a point ahead on the line (lookahead scales with speed), toward the baked
  target speed, with its own lateral offset.
- A bot pushed well off the line (avoidance, respawn) navmesh-paths back onto it.
- Every steer target is clamped onto the navmesh — dodging can never put a bot on grass or in a wall.
- Lean is visual: drive the existing `NPCAnimationController` lean from speed × curvature.
- Stuck detection + respawn carries over.

**Anti-train (decided: bots must not follow the line perfectly)**
- **Wandering offset:** per-bot lateral offset from the line that drifts smoothly over the lap,
  seeded per bot. A constant offset just makes parallel trains.
- **Per-bot style:** braking point, corner-speed carry, steering reaction rolled per bot; difficulty
  scales them (keep `Difficulty` EASY / MEDIUM / HARD).
- **Overtaking shifts the line, not a lane:** closing on a rider ahead → pick the open side, commit
  to an offset for a while, go around. Not tuck-in-forever.
- **Avoidance:** forward shape casts / raycasts against players, bots and traffic. Traffic has no
  body (only a `ContactArea`), so casts must also hit areas. Feeds the offset and braking.
- **Mistakes:** rare late brakes / running wide, scaled by difficulty.

**Delete:** `NPCRaceState`'s lane logic (rewrite the state), `TrafficRouteGraph`, the race-only
lane helpers on `NPCRiderEntity`, the `RoadManager` lookups in `NPCRaceManager`.

### Phase 1 status (handoff)

> 2026-10-25. Built and playtested by the user on the `stunt_track_01` StuntRace (host/solo). The
> playtest checklists in the [plan](./PLAN-npc-racer-phase1-20261025.md)'s tasks have not been run.

**Fixed after playtesting** (lint + headless parse clean, user confirmed the first two felt better):
- **Rubber-banding.** Between refreshes the rejoin path's first point fell behind the bot, and
  `steer_toward` points velocity straight at the target, so the bot reversed every tick.
  `_rejoin_target` now consumes reached points from the front.
- **Line start.** Point-to-point lines start at the grid centre; the first checkpoint can be far up
  the road, which left every bot rejoining for most of the race.
- **Bake hitch.** The line bake runs on a `WorkerThreadPool` task (first threading in project code).
- **Corner cutting.** Chasing a point `L` ahead on curvature `k` cuts inside the line by about
  `L²·k/2`. `NPCRaceState._steer_lookahead` caps the lookahead so the cut stays under
  `max_corner_cut`. If corners still look cut, the next suspect is the line itself: Laplacian
  smoothing hugs the inside for the whole corner instead of wide-apex-wide.
- **Speed.** Bots take `move_speed` / `acceleration` / `braking` from their `bike_definition`
  (`max_speed` / `acceleration` / `brake_strength`) at spawn in `rpc_spawn_npc`, then `Difficulty`
  scales them.
- **Clearance.** Raised the road navmesh's `agent_radius` in all three levels (the bike's nose sat
  right at the old erosion edge), and `3d/default_edge_connection_margin` with it so road and grass
  regions still connect. **The user must press Bake on `NPCNavRegion` in `racetrack_level_01`,
  `test_city_01` and `stunt_track_01` and save** — until then the shipped navmesh data is stale.

**Still getting stuck** (evidence from the temp `STUCK` log on `stunt_track_01`; every hit had
`rejoin=false`, so these are on the line itself):
- **Event props aren't in the nav bake.** Event routes (`StuntRace*/Route`, `top_level`) aren't in
  `navigation_mesh_source_group`, so `StuntRace/Route/Ramp8` and the arrow walls don't exist to the
  bake. The line runs straight through `Ramp8` and bots stall partway up its lip, which is steeper
  than the NPC body can climb. Ramp riding (below) replaces "go around"; it still has to decide how
  event props reach the bake.
- **Thin obstacle tip near (-352, 509)**, between checkpoints 4 and 5. A narrow navmesh hole the line
  wraps tightly; bots offset toward it pin on its end. The object isn't in the level `.tscn`
  (probably the `StuntCity` mesh or road geometry). Re-check after the clearance rebake.
- **Lightposts 31 / 33.** Wander pushed bots to the road edge and they clipped the pole. Same
  clearance fix; re-check.
- **(-180, 180), unknown.** Three bots abreast stopped dead at full speed, raised about 1.6 m, where
  the navmesh is solid. Something raised the bake doesn't see. Look at it in the editor.
- **Finish.** A bot parked at the line's end a couple of metres short of the last checkpoint's
  trigger: the line's end (the checkpoint snapped to the navmesh) can miss the trigger.

**Temp code:** the `# DEBUG: temp` `STUCK` log in `NPCRaceState` (`_dbg_drive` is formatted every
tick) — strip it once sticking is resolved. The `PROF: temp` lines stay; it's a codebase-wide pattern.

**Parked by the user:** reusing `NPCRacingLine` for the player-visible racing line prop
(`levels/assets/props/racing_line.gd`). Open when it resumes: does the server send the baked points
(at race start + to late joiners) or does every peer bake; one colour or Forza-style brake zones.

**Small fixes made alongside:** `level_definition.gd`'s traffic comment now names `TrafficNetwork`;
`LevelManager._ready` calls `super()` (it now joins the startup validation group).

### Ramp riding (next, design in progress)

Brainstorm started 2026-10-25 and paused here; continue with `superpowers:brainstorming`, then a
written design, then `superpowers:writing-plans`.

**Decided with the user**
- Bots ride **over** stunt ramps, not around them: up at race speed like a player, launch, maybe an
  air trick, land and carry on.
- The air trick scores like the player's. That's Phase 3, done as its own design after this.

**Facts for the builder** (verified 2026-10-25)
- The player launches because its velocity follows the slope
  (`travel_dir.slide(_floor_normal) * speed` in `MovementController`). A bot's velocity is
  horizontal only plus gravity (`steer_toward` + `apply_gravity_and_move`), so it can't launch, and
  a lip steeper than its floor angle stops it like a wall.
- `ramp.gd` (a `PathTrack`): the curve ends in a steep lip. `Height.LOW` drops that last point at
  runtime only, so an editor bake always sees the high version.
- The navmesh can't cross a jump gap. Without a link from lip to landing the line can't route over a
  ramp. Nothing in the project uses `NavigationLink3D` yet.

**My guesses, not yet confirmed:** the line routes over each ramp via a link; the bot launches
along the ramp's angle and picks the line back up at the landing.

**Not yet asked:** what a bad landing does (a crash belongs to Phase 2); whether jump links are
placed by hand per ramp or computed from the ramp's curve and launch speed; whether ramps bigger
than a jump (quarter pipes, the corkscrews) are in scope.

### Phase 2: contact + crashes

- Bots crash into each other, into players, and into obstacles. Follow the player's crash rules,
  dumbed down: impact speed / angle over a threshold → crash. Reuse what `CrashController`
  already decides where possible (e.g. `_crash_rammed_racer` / wobble on low-speed taps) rather
  than restating thresholds.
- Players ramming bots take them down (today `report_hit` is ignored by race bots).
- Crash voids any open combo (relevant once phase 3 lands). Respawn flow is unchanged.

### Phase 3: tricks, scoring, boost

- Same trick set (`TrickController.Trick`), same combo / multiplier / bank rules, same boost
  economy as the player — fed into `TrickManager` so `StyleScoringComponent`, challenges and the
  leaderboard see bots like anyone else. Dumbed down: no trick physics — pick a trick, hold it for
  a rolled duration, small bail chance (difficulty-scaled). Ground tricks on straights, air tricks
  off jumps / ramps.
- Bots spend boost by the same rules.
- Visuals: the `NPCAnimationController` needs to show the trick (currently only `WHEELIE`).

### Phase 4: items

- **Pick up** by riding through pickups (`PickupSpawner` already passes `int(body.name)` — negative
  bot ids). Bots may veer slightly off-line for a nearby pickup.
- **Affected by** every item exactly as players are: Oil Slick + Shotgun knock out, Bat wobbles,
  Rally Up swaps skins, Ramp launches.
- **Use** (simple heuristics, my guesses): Shotgun / Bat when a rider is in range, Oil Slick when
  someone is close behind, Ramp / Rally Up at random.

## Open questions (ask before the phase that needs them)

- **Phase 2/4:** knockouts currently score human victims only. Do bot victims (and bot aggressors)
  count toward `KnockoutScoringComponent`?
- **Phase 3:** `FinishBonusComponent` awards placement points "among humans". Do bots take
  placement slots / points in the stunt-race standings?
- **Phase 2:** what does a bat wobble do to a bot — a scripted swerve with a crash chance, or
  something closer to the player's `WobbleController`?

## Left to the builder

- How the bot represents "a rider" to items / tricks / crashes (shared interface, duck typing, a
  component) — but it must not duplicate player rule logic.
- Line smoothing algorithm, edge margin, curve fitting, speed-profile math.
- Cast shapes, ranges, update cadence (keep the existing throttled-scan approach for perf).
- Where the bake lives (`NPCRaceManager` vs a small helper) and how bots read it.
- Tunables are exports named by behavior; docs list them by name, never by value.
