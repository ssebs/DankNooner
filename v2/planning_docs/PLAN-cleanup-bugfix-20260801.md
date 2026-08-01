# Bugfix + Pattern-Cleanup Implementation Plan (2026-08-01)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the multiplayer regressions on TODO.md's Active list (traffic host-only, join speed-cap, bot DNF, Terrain3D fall-through, ramp crash loop) and refactor the AI-written systems back onto the project's original patterns (controllers own synced state, request-based late-join, guarded RPC surface), then bring the docs back in line with the code.

**Architecture:** Three phases. Phase 1 fixes bugs with minimal diffs. Phase 2 refactors (RPC authority, late-join contract, BoostController, NPC smoothing). Phase 3 updates docs. Human-test gates between phases — this project has no automated tests and only the human runs the game.

**Tech Stack:** Godot 4.7 / GDScript, netfox (RollbackSynchronizer/TickInterpolator), Terrain3D GDExtension, godot-road-generator.

## Global Constraints

- **NEVER run `git` or `gh` commands** (CLAUDE.md). At each "Commit point" step, STOP and ask the user to review + commit.
- **NEVER edit `planning_docs/TODO.md`** — the user owns it. Report status in chat.
- **Only the human runs the game.** Verification per task = LSP diagnostics clean (`mcp__ide__getDiagnostics`) against `.gdlintrc` (watch `class-definitions-order`). Gameplay verification happens at the phase gates via the human checklists.
- Use `DebugUtils.DebugMsg()` for all debug output. Tabs for indentation. Match each file's local style.
- Fail loudly: no `if x == null: return` without a comment explaining why null is expected.
- Doc updates list tunables by **name + behavior only, never current values**.
- When editing `.tscn` files: text edits only, minimal diffs. Omit `unique_id=` on new nodes (the editor assigns one on next save). New script `ext_resource` entries may omit `uid=` — Godot re-adds it.
- Reuse existing signals/patterns before adding new ones. Every new method in this plan exists because no current API covers it — do not add more beyond what's specced.

## Verified facts this plan relies on (do not re-derive)

- `GamemodeManager.start_game` suspends on `await RenderingServer.frame_post_draw` (gamemode_manager.gd:74); RPCs arriving during the await are processed **before** `spawn_level` runs on that peer.
- `_sync_game_to_late_joiner` ships only `level_name` + `gamemode`; `latespawn_player` re-sends players only — nothing re-sends NPCs.
- `StateMachine.clear_current_state()` **does** run `Exit()` (state_machine.gd:63); `_transition_to` early-returns on same-state.
- `SequentialTaskRunner.stop()` **clears `_player_states` and nulls `task._runner`** — results code must not read runner state after `stop()`. RaceTask's checkpoint signals stay connected after stop, and NPC `_advance` never touches `_runner`, so NPC scoring continues during the results countdown.
- `RollbackSynchronizer` lists in player_entity.tscn:1159-1160 are correct/complete today. `%MovementController` / `%GearingController` / `%TrickController` / `%HUDController` / `%InputController` all have `unique_name_in_owner = true`.
- NPCs sync via plain `MultiplayerSynchronizer` (server authority), **no** TickInterpolator. `NPCRiderEntity` id names: traffic ids start at -1000, race ids at -1.
- Terrain3D collision defaults to camera-tracked dynamic mode; `camera_controller.gd:277` hands it the local player camera via the `Terrain3D` group. API (GDExtension): `terrain.collision.mode`, enum constants on `Terrain3DCollision` (seen in terrain3d_demo/src/CodeGenerated.gd:75).
- netfox perf monitors exist (addons/netfox/network-performance.gd:4-14), e.g. `&"netfox/Rollback ticks simulated"`.
- localization.csv header: `keys,en,es`.
- Boost/combo var readers (grep-verified): movement_controller, player_entity, trick_controller, hud_controller, trick_manager, camera_controller, input_controller, hud_elements/combo_counter, hud_elements/boost_gauge.

---

# PHASE 1 — BUG FIXES

### Task 1: NPCTrafficManager — gated, idempotent, resync-able spawns

Fixes "traffic ai only loads for host" (both mechanisms: fresh-start RPC-vs-level-load race, and late-join never receiving spawns).

**Files:**
- Modify: `managers/npc_traffic_manager.gd`

**Interfaces:**
- Produces: `request_traffic_sync()` (client, call from gamemode Enter), `reset_local_traffic()` (client, call from gamemode Exit). Task 2 calls both.
- `rpc_spawn_npc` / `rpc_despawn_npc` become safe under duplicate delivery and missing-node delivery.

- [ ] **Step 1: Add state vars** (below the existing `var _npcs` declaration):

```gdscript
var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Server-side copy of each rider's rolled vehicle dict, kept so a peer whose level
## loaded after the spawn broadcast can be resynced (see request_traffic_sync).
var _vehicles: Dictionary[int, Dictionary] = {}
## Client-side gate: false until this peer's gamemode Enter confirms the level is
## loaded. Spawn broadcasts arriving earlier would parent riders under the outgoing
## level and be freed with it — they're dropped here and recovered by the sync request.
var _accept_spawns: bool = false
```

- [ ] **Step 2: Record payloads in `start_traffic`** — in the spawn loop, before the rpc call:

```gdscript
		var vehicle := _roll_vehicle(def, npc_id)
		_vehicles[npc_id] = vehicle
		rpc_spawn_npc.rpc(npc_id, vehicle, lane_transform.origin, lane_transform.basis)
```

- [ ] **Step 3: Clear payloads in `stop_traffic`** — add `_vehicles.clear()` after the despawn loop.

- [ ] **Step 4: Add the client sync API** (new region after `stop_traffic`, before `_on_road_updated`):

```gdscript
#region Client spawn sync


## Client-side, from gamemode Enter once THIS peer's level is loaded: accept spawn
## broadcasts from here on and pull whatever the server spawned before that. Covers
## the fresh-start race (the server's broadcast beats our spawn_level while start_game
## is suspended on frame_post_draw) and late join (broadcasts predate our connection).
func request_traffic_sync() -> void:
	# A previous session's Exit can be skipped (start_game clears gamemode state while
	# this peer is mid-load) — purge entries freed with their old level so the has()
	# dedupe in rpc_spawn_npc doesn't block their resync.
	for npc_id in _npcs.keys():
		if !is_instance_valid(_npcs[npc_id]):
			_npcs.erase(npc_id)
	_accept_spawns = true
	_rpc_request_traffic_sync.rpc_id(1)


## Client-side, from gamemode Exit: stop accepting spawns and drop local riders.
## The server's stop_traffic despawns normally do the freeing — this covers orderings
## where our Exit runs before those despawn RPCs arrive.
func reset_local_traffic() -> void:
	_accept_spawns = false
	for npc_id in _npcs.keys():
		if is_instance_valid(_npcs[npc_id]):
			_npcs[npc_id].queue_free()
	_npcs.clear()


## A peer's level just finished loading — resend every rider currently on the road,
## at its CURRENT spot (riders have moved since their original spawn broadcast).
@rpc("any_peer", "reliable")
func _rpc_request_traffic_sync() -> void:
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		rpc_spawn_npc.rpc_id(
			peer_id, npc_id, _vehicles[npc_id], npc.global_position, npc.global_basis
		)


#endregion
```

- [ ] **Step 5: Guard `rpc_spawn_npc`** — add at the top of the function, before the DebugMsg:

```gdscript
	# Our level isn't loaded yet (spawn broadcast raced our spawn_level) — dropped
	# here, recovered by request_traffic_sync once the gamemode enters.
	if !multiplayer.is_server() and !_accept_spawns:
		return
	# Broadcast and resync can both deliver the same rider — first one wins.
	if _npcs.has(npc_id):
		return
```

- [ ] **Step 6: Guard `rpc_despawn_npc`**:

```gdscript
@rpc("call_local", "reliable")
func rpc_despawn_npc(npc_id: int):
	# This peer may never have accepted the spawn (late join / level still loading) —
	# skip is intentional.
	if !_npcs.has(npc_id):
		return
	_npcs[npc_id].queue_free()
	_npcs.erase(npc_id)
```

- [ ] **Step 7: Verify** — LSP diagnostics clean on the file. Confirm `_vehicles` is written in exactly one place (start_traffic) and cleared in stop_traffic.

### Task 2: Gamemode hooks — clients pull traffic on Enter, reset on Exit

**Files:**
- Modify: `managers/gamemodes/types/free_roam/free_roam_gamemode.gd:39-59` (Enter), `:122-123` (Exit)
- Modify: `managers/gamemodes/types/street_race/street_race_gamemode.gd:47-54` (Enter), `:81-85` (Exit)

**Interfaces:**
- Consumes: `NPCTrafficManager.request_traffic_sync()` / `reset_local_traffic()` from Task 1.

- [ ] **Step 1: FreeRoamGameMode.Enter** — the `if multiplayer.is_server():` block that ends with `npc_traffic_manager.start_traffic()` gets an else branch:

```gdscript
	if multiplayer.is_server():
		# ... existing grid/respawn distribution ...
		npc_traffic_manager.start_traffic()
	else:
		# Our level just finished loading — pull any traffic spawned before we could
		# accept it (fresh-start broadcasts race our spawn_level; late join misses
		# them entirely).
		npc_traffic_manager.request_traffic_sync()
```

- [ ] **Step 2: FreeRoamGameMode.Exit**:

```gdscript
	if multiplayer.is_server():
		npc_traffic_manager.stop_traffic()
	else:
		npc_traffic_manager.reset_local_traffic()
```

- [ ] **Step 3: StreetRaceGameMode.Enter** — same else branch after the server block (which ends with `_start_next_runner()`):

```gdscript
	else:
		# Same pull as FreeRoamGameMode — see that Enter for why.
		npc_traffic_manager.request_traffic_sync()
```

- [ ] **Step 4: StreetRaceGameMode.Exit** — the server block (`_reset_all_player_input()` … `_race_task = null`) gets:

```gdscript
	else:
		npc_traffic_manager.reset_local_traffic()
```

- [ ] **Step 5: Verify** — diagnostics clean on both files. Trace the transition ordering once by reading: server `change_gamemode` → `_rpc_transition_gamemode.rpc()` sends transition FIRST, then runs locally (Exit→stop_traffic despawns, Enter→start_traffic spawns). Client therefore processes: transition (its Exit+Enter, flag on, request sent) → old despawns (skipped by has-guard) → new spawns (accepted) → resync reply (deduped). No step may reorder this.

- [ ] **Step 6: Commit point** — ask the user to review + commit Tasks 1-2 together ("traffic sync: gate client spawns + pull resync").

### Task 3: NPCRaceManager — late-join resync for race bots

Late joiners during a race currently get zero bot nodes + per-packet MultiplayerSynchronizer errors (prime suspect for the join speed-cap).

**Files:**
- Modify: `managers/npc_race_manager.gd`
- Modify: `managers/gamemodes/types/road_race/road_race_gamemode.gd:322` (`_on_player_latejoined`)
- Modify: `managers/gamemodes/types/street_race/street_race_gamemode.gd:331` (`_on_player_latejoined`)

**Interfaces:**
- Produces: `NPCRaceManager.sync_npcs_to_peer(peer_id: int) -> void` (server only).

- [ ] **Step 1: Store definition dicts.** Add var next to `_npcs`:

```gdscript
## Server-side copy of each bot's PlayerDefinition dict for late-joiner resync.
var _defs: Dictionary[int, Dictionary] = {}
```

In `spawn_npc`, replace the rpc line:

```gdscript
	var def := npc_definitions[(-npc_id - 1) % npc_definitions.size()]
	var def_dict := def.to_dict()
	_defs[npc_id] = def_dict
	rpc_spawn_npc.rpc(npc_id, def_dict, pos, basis)
```

In `despawn_all_npcs`, add `_defs.clear()` after the loop.

- [ ] **Step 2: Add resync + guards** (mirror Task 1's comments):

```gdscript
## Server only. A late joiner's level just loaded — resend every live bot at its
## current spot so their MultiplayerSynchronizers have a node to land on. Without
## this the newcomer takes a per-packet sync error for every bot, every tick.
func sync_npcs_to_peer(peer_id: int) -> void:
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		rpc_spawn_npc.rpc_id(peer_id, npc_id, _defs[npc_id], npc.global_position, npc.global_basis)
```

Top of `rpc_spawn_npc`:

```gdscript
	# Broadcast and late-join resync can both deliver the same bot — first one wins.
	if _npcs.has(npc_id):
		return
```

`rpc_despawn_npc`:

```gdscript
	# This peer may have joined after the race ended mid-teardown — skip is intentional.
	if !_npcs.has(npc_id):
		return
```

- [ ] **Step 3: Call it from both race gamemodes** (identical edit in both files — they are deliberately duplicated):

```gdscript
func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)
	npc_race_manager.sync_npcs_to_peer(peer_id)
```

- [ ] **Step 4: Verify** — diagnostics clean on all three files.

### Task 4: Terrain3D — full collision on the server

The host simulates every player's physics, but Terrain3D's camera-tracked dynamic collision only exists near the host's own bike → remote players fall through authoritatively.

**Files:**
- Modify: `levels/level_definition.gd:25-30` (`_ready`)

- [ ] **Step 1: Add to `LevelDefinition._ready()`** after the existing debug-spawn swap:

```gdscript
	# The server simulates EVERY player's physics, but Terrain3D's default dynamic
	# collision only builds around one tracked camera (the local player's — see
	# CameraController.switch_to_cam). Remote players ride over collision-less
	# terrain on the host and fall through the map. Full collision on the server
	# trades memory for correctness; clients keep the cheap camera-tracked mode.
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		for terrain in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Terrain3D"]):
			terrain.collision.mode = Terrain3DCollision.FULL_GAME
```

- [ ] **Step 2: Verify enum name.** Terrain3D is a GDExtension; confirm `Terrain3DCollision.FULL_GAME` resolves via LSP diagnostics on the file (the demo uses `Terrain3DCollision.DYNAMIC_EDITOR`, so the class + naming scheme is confirmed; if `FULL_GAME` is not a member, check editor autocomplete for the `CollisionMode` constant spelled `FULL_GAME`/`FULL_EDITOR` and use the game variant). If it truly doesn't exist, STOP and report — do not guess an alternative.

- [ ] **Step 3: Commit point** — ask the user to review + commit Tasks 3-4.

### Task 5: Race results — bots race the countdown, rows update live

**Files:**
- Modify: `managers/gamemodes/tasks/race_task.gd` (public accessors)
- Modify: `managers/gamemodes/hud/results_hud.gd` (row-refresh RPC)
- Modify: `managers/gamemodes/types/road_race/road_race_gamemode.gd` (results region)
- Modify: `managers/gamemodes/types/street_race/street_race_gamemode.gd` (results region — same edits, duplicated on purpose)
- Modify: `localization/localization.csv` (one new key)

**Interfaces:**
- Produces: `RaceTask.get_completion_time_ms(racer_id) -> float` (−1.0 when unfinished), `RaceTask.has_racer(racer_id) -> bool`; `ResultsHUD.rpc_update_rows(results_dict)`.
- Constraint honored: `TaskRunner.stop()` clears `_player_states`, so human rows are cached once at snapshot time; only NPC rows re-derive.

- [ ] **Step 1: RaceTask accessors** — add to the public region (near `get_target_checkpoint`):

```gdscript
## Recorded finish time for any racer (humans and NPCs), -1.0 while unfinished.
## Public so the race gamemodes stop reaching into _peer_progress.
func get_completion_time_ms(racer_id: int) -> float:
	return _peer_progress[racer_id].get("completion_time_ms", -1.0)


func has_racer(racer_id: int) -> bool:
	return _peer_progress.has(racer_id)
```

- [ ] **Step 2: ResultsHUD refresh RPC.** Extract the row-building loop of `rpc_show_results` (results_hud.gd:38-48) into `_rebuild_rows(data: ResultsData)`, call it from `rpc_show_results`, and add:

```gdscript
## Refresh title + rows only — countdown, focus and input state are untouched, so
## this is safe to call repeatedly while the results screen is up.
@rpc("call_local", "reliable")
func rpc_update_rows(results_dict: Dictionary):
	var data := ResultsData.from_dict(results_dict)
	title_label.text = data.title
	_rebuild_rows(data)
```

- [ ] **Step 3: Localization key.** Append to `localization/localization.csv` (columns `keys,en,es`):

```csv
RACE_RACING,"Racing...","Corriendo..."
```

- [ ] **Step 4: Rework the results region — in BOTH race gamemode files identically.** Add fields near `_results_countdown`:

```gdscript
## Human rows cached at the all-finished snapshot — the runner clears its state on
## stop(), so they can't be re-derived. NPC rows re-derive live from RaceTask.
var _human_rows: Array[Dictionary] = []
var _results_refresh_accum: float = 0.0

const RESULTS_REFRESH_SECS: float = 1.0
```

Replace `_show_results` with:

```gdscript
func _show_results(runner: TaskRunner):
	_human_rows = []
	for peer_id in runner._player_states:
		var state = runner._player_states[peer_id] as PlayerTaskState
		var username: String = lobby_manager.lobby_players[peer_id].username
		# Prefer the RaceTask clock (starts at the race body, like the lap HUD and
		# NPC rows) over the runner clock (starts at grid/countdown).
		var time_ms: float = state.completion_time_ms
		if _race_task != null and _race_task.has_racer(peer_id):
			var task_ms := _race_task.get_completion_time_ms(peer_id)
			if task_ms >= 0.0:
				time_ms = task_ms
		_human_rows.append(_result_row(username, time_ms))
	_results_countdown = _results_countdown_total
	_results_refresh_accum = 0.0
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(_build_results_data().to_dict(), _results_countdown_total)


## Cached human rows + live NPC rows. Bots keep racing through the results
## countdown — a bot that finishes mid-countdown gets its real time on the next
## refresh instead of a DNF.
func _build_results_data() -> ResultsData:
	var rows: Array[Dictionary] = _human_rows.duplicate()
	if _race_task != null:
		for npc_id in npc_race_manager.get_npc_ids():
			var npc_name: String = npc_race_manager.get_npc(npc_id).username
			var time_ms := _race_task.get_completion_time_ms(npc_id)
			if time_ms >= 0.0:
				rows.append(_result_row(npc_name, time_ms))
			else:
				rows.append({"Username": npc_name, "Time": tr("RACE_RACING"), "_sort_key": INF})
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])
	return ResultsData.create(tr("RACE_COMPLETE"), ["Username", "Time"], rows)
```

Replace `_update_results_countdown` with:

```gdscript
func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	_results_refresh_accum -= delta
	if _results_refresh_accum <= 0.0:
		_results_refresh_accum = RESULTS_REFRESH_SECS
		results_hud.rpc_update_rows.rpc(_build_results_data().to_dict())
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true
```

Note: `_show_results(...)` call sites pass the runner already; `race_task := npc_race_manager.race_task` locals in the old code are gone — `_race_task` (the gamemode's own field, still set until Exit) replaces them. Clear `_human_rows = []` in `Exit()` and in `_on_results_restart_pressed` (next to `_active_runner_index = -1`).

- [ ] **Step 5: Delete the old direct `_peer_progress` reads** in both gamemodes (`_push_checkpoint_markers` keeps its `_race_task._peer_progress.has(peer_id)` → change to `_race_task.has_racer(peer_id)`).

- [ ] **Step 6: Verify** — diagnostics clean on all five files; grep both gamemodes for `_peer_progress` — zero matches must remain outside race_task.gd.

- [ ] **Step 7: Commit point** — ask the user to review + commit ("race results: bots race the countdown, live rows").

### Task 6: Free roam — crash on a ramp respawns you off the ramp

Crash-site respawn + the steep-slope stall-crash rule interact into an infinite loop on grades > `MAX_CLIMB_ANGLE_DEG`.

**Files:**
- Modify: `managers/gamemodes/types/free_roam/free_roam_gamemode.gd`

- [ ] **Step 1: Add breadcrumb state + tunables** (consts near `_respawn_delay`):

```gdscript
## Crash-site respawn is only safe on ground the bike can actually stand on.
## Steeper than this at the crash site → fall back to the last flat breadcrumb.
const RESPAWN_STEEP_SLOPE_DEG: float = 35.0
## A breadcrumb is only recorded on ground at least this gentle.
const RESPAWN_FLAT_MAX_SLOPE_DEG: float = 25.0
const BREADCRUMB_INTERVAL_SECS: float = 1.0

## Server-only: last known flat-ground transform per peer. Crash respawns fall back
## here when the crash site is a ramp/loop/steep grade (or has no ground at all —
## e.g. fell out of the map), which otherwise loops the steep-slope stall crash.
var _flat_breadcrumbs: Dictionary[int, Transform3D] = {}
var _breadcrumb_accum: float = 0.0
```

- [ ] **Step 2: Sample breadcrumbs** — add `Physics_Update` (base `State` declares it; StateMachine calls it every physics frame):

```gdscript
func Physics_Update(delta: float):
	if Engine.is_editor_hint() or !multiplayer.is_server():
		return
	_breadcrumb_accum -= delta
	if _breadcrumb_accum > 0.0:
		return
	_breadcrumb_accum = BREADCRUMB_INTERVAL_SECS
	for peer_id in gamemode_manager.lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null or player.is_crashed:
			continue
		var normal := _ground_normal_at(player.global_position)
		if normal != Vector3.ZERO and normal.angle_to(Vector3.UP) <= deg_to_rad(RESPAWN_FLAT_MAX_SLOPE_DEG):
			_flat_breadcrumbs[peer_id] = Transform3D(
				Basis(Vector3.UP, player.global_rotation.y), player.global_position
			)


## Ground normal just under pos, Vector3.ZERO when there is no ground within 3m.
func _ground_normal_at(pos: Vector3) -> Vector3:
	var space_state := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 3.0)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]
```

- [ ] **Step 3: Use it in `_respawn_at_crash_site`** — replace the body after the existing `is_crashed` early-return:

```gdscript
	var normal := _ground_normal_at(player.global_position)
	var too_steep := (
		normal == Vector3.ZERO
		or normal.angle_to(Vector3.UP) > deg_to_rad(RESPAWN_STEEP_SLOPE_DEG)
	)
	if too_steep and _flat_breadcrumbs.has(peer_id):
		var crumb := _flat_breadcrumbs[peer_id]
		spawn_manager.respawn_player_in_place.rpc(peer_id, crumb.origin, crumb.basis)
		return
	var upright := Basis(Vector3.UP, player.global_rotation.y)
	spawn_manager.respawn_player_in_place.rpc(peer_id, player.global_position, upright)
```

- [ ] **Step 4: Cleanup** — in `Exit()`: `_flat_breadcrumbs.clear()`. In `_on_player_disconnected`: `_flat_breadcrumbs.erase(peer_id)`.

- [ ] **Step 5: Verify** — diagnostics clean. Note the freebie: falling out of the map (ray misses) now also recovers to the breadcrumb.

### Task 7: Netfox debug overlay (instrument for the join speed-cap)

The April review called for a corrections/perf readout; it's the tool that verifies the speed-cap hypothesis at Gate A.

**Files:**
- Modify: `player/controllers/hud_controller.gd`

- [ ] **Step 1: Create the label in code** (no `.tscn` surgery — HUDController is itself a Control). In `_ready` (or `show_hud` if `_ready` doesn't exist — follow the file), local-client + debug builds only:

```gdscript
	if OS.has_feature("debug"):
		_netfox_debug_label = Label.new()
		_netfox_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_netfox_debug_label.add_theme_font_size_override("font_size", 12)
		_netfox_debug_label.position = Vector2(8, 8)
		add_child(_netfox_debug_label)
```

with `var _netfox_debug_label: Label` and a 1 Hz refresh in `_process` (accumulate with delta, reuse the file's existing `_process` if present):

```gdscript
	_netfox_dbg_accum -= delta
	if _netfox_debug_label != null and _netfox_dbg_accum <= 0.0:
		_netfox_dbg_accum = 1.0
		_netfox_debug_label.text = (
			"rb ticks/s: %d | rb ms: %.1f | state props full/sent: %d/%d"
			% [
				Performance.get_custom_monitor(&"netfox/Rollback ticks simulated"),
				Performance.get_custom_monitor(&"netfox/Rollback loop duration (ms)"),
				Performance.get_custom_monitor(&"netfox/Full state properties count"),
				Performance.get_custom_monitor(&"netfox/Sent state properties count"),
			]
		)
```

(`var _netfox_dbg_accum: float = 0.0`.) Guard: `Performance.get_custom_monitor` errors if a monitor is absent — monitors register when netfox's `NetworkPerformance.ENABLED` is on; wrap with `Performance.has_custom_monitor(&"netfox/Rollback ticks simulated")` check once at label creation and skip creating the label if absent (comment why).

- [ ] **Step 2: Verify** — diagnostics clean.

- [ ] **Step 3: Commit point** — ask the user to review + commit Tasks 6-7.

## GATE A — human test checklist (STOP; ask the user to run)

All MP tests: one host + one client (second machine or `--headless`-less second instance).

1. **Traffic, fresh start:** host + client in lobby → start racetrack_level_01 free roam. Client must see the same ~18 traffic riders as host. Client console: zero "node not found"/sync errors.
2. **Traffic, late join:** host alone in free roam with traffic → client joins. Client sees all riders (at current positions, not spawn points).
3. **Join speed-cap:** in test 2, client rides full throttle with auto-trans. Expect: normal top speed. Watch the new debug overlay — if speed still caps, report overlay numbers + console output (that's the next diagnostic, not a failure of this plan's tasks).
4. **Terrain3D:** on a t3d map, client rides far away from host. No fall-through.
5. **Bot DNF:** run a street race, finish before the bots. During the 10s results screen, bot rows must flip from "Racing..." to real times as they finish.
6. **Ramp loop:** free roam, crash deliberately halfway up a big ramp. Respawn must land on flat ground behind it, riding again — no crash loop.
7. **Customize retest (unverified bug):** host→pause→customize→back with a client connected; then host→lobby→customize→back. Report which path (if either) still kicks the client and what the client screen shows.

---

# PHASE 2 — PATTERN REFACTORS

### Task 8: RPC authority guards (SpawnManager + GamemodeManager)

Closes the April review's "authority holes", which have grown to ~8 `any_peer` RPCs.

**Files:**
- Modify: `managers/spawn_manager.gd`
- Modify: `managers/gamemodes/gamemode_manager.gd`
- Modify: `menus/pause_menu/pause_menu_state.gd:82-84`
- Modify: every direct `_rpc_transition_gamemode.rpc(` caller (grep; known: `types/street_race`, `types/road_race` `_return_to_free_roam`, plus `types/tutorial` and `types/challenge`)

**Interfaces:**
- Produces: `SpawnManager.request_respawn()` (client-callable). All broadcast RPCs reject non-server senders.

- [ ] **Step 1: SpawnManager sender guard helper** (private region, above the RPCs):

```gdscript
## True when the executing RPC came from the server or a local call — sender id is
## the local peer's own id for call_local execution (1 on the host) and 1 for
## server-sent RPCs. The broadcast RPCs below stay any_peer only because the server
## must call_local them; this closes them to clients.
func _sender_is_server() -> bool:
	return multiplayer.get_remote_sender_id() <= 1
```

Add `if !_sender_is_server(): return` as the first line of: `respawn_player`, `crash_player`, `respawn_player_at`, `respawn_player_in_place`, `set_respawn_point`, `reset_respawn_point`.

Caution: `get_remote_sender_id()` inside a call_local execution on a CLIENT returns that client's own id (>1) — that's exactly the block we want, but it means any legit client-side caller must be converted (next steps). Grep for `.rpc(` on all six names and confirm every remaining caller runs server-side; convert or wrap any that don't.

- [ ] **Step 2: Client request path**:

```gdscript
## Client-callable: ask the server to respawn YOU (pause-menu button). The server
## derives the target from the sender — a client can never respawn someone else.
@rpc("any_peer", "call_local", "reliable")
func request_respawn():
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# sender == 1 covers both the host's local call and (impossibly) server-sent.
	respawn_player.rpc(sender if sender > 1 else 1)
```

`pause_menu_state.gd:_on_respawn_pressed` becomes:

```gdscript
func _on_respawn_pressed():
	spawn_manager.request_respawn.rpc_id(1)
	_on_resume_pressed()
```

- [ ] **Step 3: GamemodeManager guards.**
  - `start_game`: first line `if multiplayer.get_remote_sender_id() > 1: return` with comment `# Only the server starts matches — a client RPCing this is misbehaving.`
  - `_sync_game_to_late_joiner`: change decorator `@rpc("any_peer", "reliable")` → `@rpc("reliable")` (authority mode — the server owns manager nodes, and only the server sends it).
  - `_request_late_spawn`: after the is_server guard add `if multiplayer.get_remote_sender_id() not in [0, peer_id]: return` with comment `# A peer may only request its own late spawn.`

- [ ] **Step 4: One entry point for gamemode transitions.** Grep `_rpc_transition_gamemode.rpc(`. Each direct call site runs server-side already; replace with the guarded entry point, e.g. street/road race:

```gdscript
func _return_to_free_roam():
	gamemode_manager.change_gamemode(GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id())
```

(direct call, not `.rpc_id(1, …)` — these sites are already on the server and `change_gamemode` re-broadcasts). Apply the same shape to the tutorial/challenge sites, preserving their target-mode + circle-path arguments.

- [ ] **Step 5: Verify** — diagnostics clean everywhere; grep confirms zero remaining direct `_rpc_transition_gamemode.rpc(` calls outside gamemode_manager.gd.

- [ ] **Step 6: Commit point.**

### Task 9: Late-join contract on GameModeType

The April review's contract, minimally: modes declare late-joinability and (optionally) ship state. Fixes the mid-race late-join **client crash** (null `ctx.event_start_circle`) by landing late joiners in free roam instead.

**Files:**
- Modify: `managers/gamemodes/gamemode.gd` (base `GameModeType`)
- Modify: `managers/gamemodes/types/free_roam/free_roam_gamemode.gd`
- Modify: `managers/gamemodes/gamemode_manager.gd:191-230`

- [ ] **Step 1: Base contract** in `gamemode.gd`:

```gdscript
## Whether a late joiner can be dropped straight into this mode. Modes needing
## mid-match context (races: start circle + runner state) return false; the late
## joiner free-roams the level instead and syncs up at the next mode change.
func is_late_joinable() -> bool:
	return false


## Ship/restore mid-match state to late joiners. Base: nothing to ship.
func serialize_state_for_late_joiner() -> Dictionary:
	return {}


func apply_state_from_host(_state: Dictionary) -> void:
	pass
```

FreeRoamGameMode override:

```gdscript
func is_late_joinable() -> bool:
	return true
```

- [ ] **Step 2: GamemodeManager ships it.** `_on_client_connection_succeeded`:

```gdscript
	if match_state == MatchState.IN_GAME:
		# Modes that can't take a late joiner mid-flight (races) sync the joiner
		# into free roam on the same level instead — they still spawn and ride.
		var sync_mode := current_game_mode
		if !_gamemode_map[current_game_mode].is_late_joinable():
			sync_mode = GameModeType.Kind.FREE_ROAM
		_sync_game_to_late_joiner.rpc_id(
			peer_id,
			current_level_name,
			sync_mode as int,
			_gamemode_map[sync_mode].serialize_state_for_late_joiner()
		)
```

`_sync_game_to_late_joiner` gains the param and applies it after the state change:

```gdscript
@rpc("reliable")
func _sync_game_to_late_joiner(
	level_name: LevelManager.LevelName,
	gamemode: GameModeType.Kind = GameModeType.Kind.FREE_ROAM,
	state: Dictionary = {}
):
	# ... existing body through state_machine.request_state_change ...
	_gamemode_map[current_game_mode].apply_state_from_host(state)
	# ... existing _request_late_spawn call ...
```

- [ ] **Step 3: Block race hijacks.** A late joiner free-roaming during a server-side race can drive into an event circle and request a mode change, nuking the live race. In `change_gamemode`, after the is_server guard:

```gdscript
	# A race is running — only a return to free roam (host cancel / race end) may
	# interrupt it. Blocks a free-roaming late joiner starting a second event.
	if (
		!_gamemode_map[current_game_mode].is_late_joinable()
		and gamemode != GameModeType.Kind.FREE_ROAM
	):
		return
```

- [ ] **Step 4: Verify** — diagnostics clean. Note in chat for the user: late joiner in free roam sees no race HUD while the race runs; when the race ends, everyone transitions to FREE_ROAM — the joiner's same-state transition is a no-op by design.

- [ ] **Step 5: Commit point.**

### Task 10: BoostController — boost state off PlayerEntity, combo state onto TrickController

The netfox constraint is *when* the code runs (rollback tick), not *where the state lives*. Restore the "controllers own their domain, synced as `%Controller:var`" pattern.

**Files:**
- Create: `player/controllers/boost_controller.gd`
- Modify: `player/player_entity.gd` (remove 9 vars; wire controller; respawn ordering)
- Modify: `player/player_entity.tscn` (new node, state_properties, node_paths)
- Modify: `player/controllers/movement_controller.gd` (delete `_boost_calc` + consts; re-point reads)
- Modify: `player/controllers/trick_controller.gd` (own combo vars; write boost via controller)
- Modify: `player/controllers/hud_controller.gd`, `player/controllers/camera_controller.gd`, `player/controllers/input_controller.gd`, `managers/trick_manager.gd`, `player/hud_elements/combo_counter.gd`, `player/hud_elements/boost_gauge.gd` (re-point reads)

**Interfaces:**
- Produces: `BoostController` with synced vars `boost_amount`, `boost_burn_target`, `boost_burn_rate`, `boost_prev_held`, `is_boosting`; consts `BOOST_SEGMENTS`, `BOOST_SEGMENT_SECS`, `BOOST_FULL_BURN_SECS`, `BOOST_ACCEL_MULT`, `BOOST_SPEED_MULT`; methods `on_movement_rollback_tick(delta)`, `apply_crash_void(earned: float)`, `do_reset()`.
- `TrickController` gains synced vars `combo_time`, `combo_grace`, `combo_multiplier`, `combo_boost_earned` (moved from PlayerEntity, semantics unchanged).
- `PlayerEntity` gains `@export var boost_controller: BoostController` (+ configuration warning).

- [ ] **Step 1: Create `player/controllers/boost_controller.gd`.** Move `MovementController._boost_calc` (movement_controller.gd:327-358) and the five `BOOST_*` consts (movement_controller.gd:69-73) here verbatim, de-prefixing `pe.` for the vars that now live on this controller and keeping `player_entity.is_crashed` / `input_controller.nfx_boost_held` reads. Preserve every existing comment:

```gdscript
@tool
## Owns the boost meter: commit-on-press burn mechanics + the synced meter state.
## Earned by TrickController's combo accrual, spent here, banked by TrickManager.
## Runs inside the rollback tick — see planning_docs/ComboAndBoost.md.
class_name BoostController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var trick_controller: TrickController

# (BOOST_* consts moved from MovementController, comments included)

# Netfox synced state — listed in player_entity.tscn's RollbackSynchronizer.
var boost_amount: float = 0.0
var boost_burn_target: float = -1.0
var boost_burn_rate: float = 0.0
var boost_prev_held: bool = false
var is_boosting: bool = false


## Called FIRST from PlayerEntity._rollback_tick — ahead of the crash bail-out so a
## crash mid-boost cancels the burn (and its camera FX) instead of latching it.
func on_movement_rollback_tick(delta: float):
	# (moved _boost_calc body)


## A crash voids only what the in-progress combo earned — boost banked by earlier
## completed combos survives. Called from PlayerEntity._apply_respawn_state BEFORE
## the do_reset loop clears trick_controller.combo_boost_earned.
func apply_crash_void(earned: float):
	boost_amount = maxf(boost_amount - earned, 0.0)


## Called from player_entity.gd's do_respawn. boost_amount deliberately survives —
## banked boost is yours across respawns; only the active burn resets.
func do_reset():
	boost_burn_target = -1.0
	boost_burn_rate = 0.0
	boost_prev_held = false
	is_boosting = false
```

Plus the standard `_get_configuration_warnings()` for the three exports.

- [ ] **Step 2: Move combo vars to TrickController.** Cut `combo_time`, `combo_grace`, `combo_multiplier`, `combo_boost_earned` (with their doc comments, player_entity.gd:106-115) into trick_controller.gd's var block. In `_accrue_combo`, replace `player_entity.combo_*` with `combo_*` and `player_entity.boost_amount` with `boost_controller.boost_amount` (add `@export var boost_controller: BoostController` + config warning). Extend TrickController's `do_reset()` to zero all four combo vars.

- [ ] **Step 3: PlayerEntity.** Delete the nine vars (keep `is_crashed`). Add the export + wiring. `_rollback_tick` order becomes:

```gdscript
	# Boost first — ahead of every controller AND evaluated even while crashed, so a
	# crash mid-boost cancels the burn (this was previously _boost_calc's first-line
	# position inside MovementController's tick).
	boost_controller.on_movement_rollback_tick(delta)
	movement_controller.on_movement_rollback_tick(delta)
	gearing_controller.on_movement_rollback_tick(delta)
	trick_controller.on_movement_rollback_tick(delta)
	crash_controller.on_movement_rollback_tick(delta)
```

`_apply_respawn_state` — the boost/combo lines collapse to:

```gdscript
	# Void order matters: read the combo's claim before TrickController.do_reset
	# (in the loop below) clears it.
	boost_controller.apply_crash_void(trick_controller.combo_boost_earned)
	is_crashed = false
	for child in controllers_node.get_children():
		...
```

(the burn/combo field resets now live in the two controllers' `do_reset`, which the existing loop already calls — verify BoostController sits under `_Controllers` so the loop reaches it).

- [ ] **Step 4: player_entity.tscn.**
  1. Add ext_resource near the other controller scripts: `[ext_resource type="Script" path="res://player/controllers/boost_controller.gd" id="11_boost"]`
  2. Add node after the InputController block under `_Controllers`:

```text
[node name="BoostController" type="Node" parent="_Controllers" node_paths=PackedStringArray("player_entity", "input_controller", "trick_controller")]
unique_name_in_owner = true
script = ExtResource("11_boost")
player_entity = NodePath("../..")
input_controller = NodePath("../InputController")
trick_controller = NodePath("../TrickController")
```

  (match the sibling nodes' NodePath style exactly — read a neighbor block first.)
  3. Rewrite line 1159's `state_properties`: remove `":boost_amount", ":boost_burn_target", ":boost_burn_rate", ":boost_prev_held", ":combo_time", ":combo_grace", ":combo_boost_earned", ":combo_multiplier", ":is_boosting"`; add `"%BoostController:boost_amount", "%BoostController:boost_burn_target", "%BoostController:boost_burn_rate", "%BoostController:boost_prev_held", "%BoostController:is_boosting", "%TrickController:combo_time", "%TrickController:combo_grace", "%TrickController:combo_boost_earned", "%TrickController:combo_multiplier"`. `:global_transform`, `:velocity`, `:up_direction`, `:is_crashed` and the existing `%MovementController`/`%GearingController` entries stay.
  4. Root `PlayerEntity` node: add `"boost_controller"` to its `node_paths` array and `boost_controller = NodePath("_Controllers/BoostController")` to its properties.
  5. TrickController and HUDController node entries: extend their `node_paths` + properties with `boost_controller = NodePath("../BoostController")` (TrickController) / whatever export name Step 5 adds (HUDController).

- [ ] **Step 5: Re-point every reader.** Run: `grep -rn "boost_amount\|is_boosting\|combo_multiplier\|combo_time\|boost_burn\|boost_prev_held\|combo_grace\|combo_boost_earned" --include="*.gd" player/ managers/ menus/ utils/` — fix ALL hits outside boost_controller/trick_controller:
  - movement_controller.gd: delete `_boost_calc` + the 5 consts + the `_boost_calc(delta)` call; `_speed_calc` reads become `player_entity.boost_controller.is_boosting`, `BoostController.BOOST_ACCEL_MULT`, `BoostController.BOOST_SPEED_MULT`.
  - input_controller.gd:114: `player_entity.is_boosting` → `player_entity.boost_controller.is_boosting`.
  - camera_controller.gd (2 hits), hud_controller.gd (7 hits, add a `boost_controller` export wired in tscn per Step 4.5), trick_manager.gd (4 hits → `player.trick_controller.*` / `player.boost_controller.*`), combo_counter.gd + boost_gauge.gd (1 hit each — follow how HUD pushes values into them).
  - The grep must end with zero hits referencing these vars via `player_entity.` or bare `pe.`.

- [ ] **Step 6: Verify** — diagnostics clean on every touched file; re-run the Step 5 grep; confirm state_properties count in tscn equals old count (nothing dropped, only re-pathed).

- [ ] **Step 7: Commit point** — this task is its own commit ("refactor: BoostController owns boost state, TrickController owns combo state").

### Task 11: NPC transform smoothing (the "laggy NPCs" TODO item)

**Files:**
- Modify: `entities/npc/npc_rider_entity.gd`
- Modify: `entities/npc/npc_rider_entity.tscn` (SceneReplicationConfig)

- [ ] **Step 1: Read first.** Read `npc_rider_entity.gd` fully and the tscn's `SceneReplicationConfig` sub-resource to see exactly which properties replicate today (expected: `.:transform` or `.:global_transform` + `.:npc_state`).

- [ ] **Step 2: Indirect the transform.** Add:

```gdscript
## Written by the server each physics tick and replicated; clients lerp toward it so
## replication-rate updates don't strobe at render framerate.
var sync_transform: Transform3D
## Distance beyond which a client snaps instead of lerping (teleport/recovery).
const NET_SNAP_DISTANCE: float = 25.0
const NET_LERP_SPEED: float = 12.0
```

Server: at the end of `_physics_process` (or the equivalent movement tick the file uses): `sync_transform = global_transform`. Also set it inside `teleport_to` so recoveries snap on the wire immediately.

Client: in `_process`:

```gdscript
	if multiplayer.multiplayer_peer != null and !multiplayer.is_server():
		if global_position.distance_to(sync_transform.origin) > NET_SNAP_DISTANCE:
			global_transform = sync_transform
		else:
			var w := 1.0 - exp(-NET_LERP_SPEED * delta)
			global_transform = global_transform.interpolate_with(sync_transform, w)
```

Guard the initial state: initialize `sync_transform = global_transform` at the end of `_ready` so clients don't lerp from the origin.

- [ ] **Step 3: Swap the replication property** in the tscn's SceneReplicationConfig: replace the transform property entry with `.:sync_transform` (same replication mode the old entry used); `npc_state` entry stays.

- [ ] **Step 4: Verify** — diagnostics clean; confirm no other code reads the replicated transform property name you removed.

- [ ] **Step 5: Commit point.**

## GATE B — human test checklist (STOP; ask the user to run)

1. Full boost regression, MP host + client: earn combo (wheelie chain), meter fills; tap-to-burn one segment; full-meter long burn; crash mid-combo voids only the in-progress earnings; respawn keeps banked boost; forced auto-shift during boost; HUD gauge + combo counter + camera FX all live on the client.
2. Pause-menu respawn button works for host AND client (now routed via `request_respawn`).
3. Late join during a running street race: joiner lands in free roam on the level, spawns, no client crash, race unaffected; joiner cannot start an event circle while the race runs; when the race ends everyone is in free roam together.
4. Traffic NPCs look smooth on the client (no 30 Hz strobing), and crash-recovery teleports snap rather than sliding across the map.
5. Quick sanity: tutorial + challenge modes still enter/exit (transition entry-point change).

---

# PHASE 3 — DOCS

### Task 12: Bring the docs back to reality

**Files:**
- Modify: `planning_docs/Architecture.md`
- Modify: `CLAUDE.md`
- Modify: `planning_docs/ComboAndBoost.md`
- Modify: `planning_docs/code-review-20260430.md`
- **Do NOT touch `planning_docs/TODO.md`.**

Rules: tunables by name + behavior only, never values. Keep each doc's existing voice/structure; surgical edits.

- [ ] **Step 1: CLAUDE.md** — Connection modes: delete Noray (only WebRTC + IP/Port exist). Add `BoostController` to the PlayerEntity controller list. Add `NPCTrafficManager`/`NPCRaceManager` one-liners under the Gamemode System section and `entities/` to Project Structure.
- [ ] **Step 2: Architecture.md** —
  - Player Entity: controller table gains `BoostController`; Synced State section: boost vars now `%BoostController:*`, combo vars `%TrickController:*`.
  - New "NPC Traffic Manager" subsection next to NPC Race Manager: route graph from the road network, per-map `TrafficSettings`, broadcast spawns gated client-side + `request_traffic_sync` pull (fresh start AND late join), recovery behavior.
  - Spawn Manager: full RPC list (`rpc_spawn_player`, `rpc_despawn_player`, `respawn_player`, `crash_player`, `respawn_player_at`, `respawn_player_in_place`, `set_respawn_point`, `reset_respawn_point`, `request_respawn`) with the sender-guard rule ("broadcast RPCs reject non-server senders; clients use request_respawn").
  - Gamemode Manager: late-join contract (`is_late_joinable`, `serialize_state_for_late_joiner`/`apply_state_from_host`, free-roam fallback, race-hijack guard); `change_gamemode` as the single transition entry point.
  - Multiplayer section: note Terrain3D server-side full collision + why (camera-tracked dynamic collision vs. server-authoritative physics).
  - Project Structure: add `entities/`.
- [ ] **Step 3: ComboAndBoost.md** — rewrite "Where the logic lives" table: earn = TrickController, spend = BoostController, bank = TrickManager, UI/FX unchanged. Correct the framing: netfox forces rollback-tick *execution*; state *location* is the controller-ownership pattern. Move the `BOOST_*` tunables rows under BoostController.
- [ ] **Step 4: code-review-20260430.md** — append a dated triage block: authority holes CLOSED (this plan Task 8), late-join contract BUILT (Task 9), BoostController split DONE (Task 10); `BikeSkinDefinition` split + `user://` path leak still OPEN (note the NPCTrafficManager path-shipping workaround as evidence it's getting more expensive).
- [ ] **Step 5: Verify** — re-read each edited section against the actual code you just wrote. No values in docs.
- [ ] **Step 6: Commit point** — final commit ("docs: sync Architecture/CLAUDE/ComboAndBoost with code").

---

## Self-review notes (already applied)

- Human rows cached before `runner.stop()` (Task 5) because `stop()` clears `_player_states` — verified in sequential_task_runner.gd:63.
- `%TrickController` addressable: `unique_name_in_owner = true` confirmed at player_entity.tscn:1216.
- `Physics_Update` exists on base State (state.gd:19).
- `RACE_DNF` key becomes unused after Task 5 — leave it in the CSV (localization keys are cheap; removing strings is not this plan's job).
- Known deliberate duplication: Tasks 3/5 edit road_race + street_race twice each — do not attempt to merge the files.
