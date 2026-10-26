@tool
## Owns AI race riders (NPCRiderEntity): negative-id roster, spawn/despawn
## RPCs (mirrors SpawnManager's pattern), and the server-only AI tick that
## points each NPC at its next checkpoint from RaceTask.
##
## RaceGameMode's NPCRacersComponent sets `race_task` while a race runs and calls
## spawn_npc / register — see that component for the lifecycle.
class_name NPCRaceManager extends BaseManager

@export var level_manager: LevelManager
## Round-robin source of NPC names + skins. Spawned NPCs get
## "<username> <n>" so reused definitions stay distinguishable in results.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
@export var respawn_delay: float = 3.0
## Racing line bake (see NPCRacingLine): metres between samples, Laplacian smoothing passes, the
## lateral acceleration (m/s^2) the line's corner speeds allow, and how far road room is probed.
@export var line_sample_spacing: float = 4.0
@export var line_smoothing_passes: int = 6
@export var corner_grip: float = 16.0
@export var line_max_half_width: float = 12.0

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")
## dbg_racing_line drawings live until the next toggle or bake clears them
const DRAW_SECONDS := 1.0e9

## Set by NPCRacersComponent while a race runs; null otherwise.
var race_task: RaceTask

## Server only. The line every bot rides, baked by bake_racing_line; null until then.
var racing_line: NPCRacingLine

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Grid-slot spawn transform per NPC — crash-respawn fallback until the NPC
## passes its first checkpoint.
var _spawn_transforms: Dictionary[int, Transform3D] = {}
var _next_id: int = -1
## Bumped on despawn, so a bake still waiting on the nav map from a race that ended is dropped.
var _bake_generation: int = 0
var _draw_racing_line: bool = false


func _ready():
	super()
	if Engine.is_editor_hint():
		return
	Console.add_command("dbg_racing_line", _toggle_racing_line_debug, [], 0, "Toggle the NPC racing line debug draw")


## Server-only AI tick: retarget each NPC at the checkpoint RaceTask expects
## it to cross next. The same crossing that scores the lap retargets nav.
func _physics_process(_delta: float):
	# Peer is null in menus / after a session teardown (ConnectionManager nulls it on
	# disconnect) — is_server() errors on a null peer, so check it first.
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null:
		return
	if !multiplayer.is_server():
		return
	if race_task == null:
		return
	var t := Time.get_ticks_usec()  # PROF: temp
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		if npc.npc_state == NPCRiderEntity.NPCState.CRASHED:
			continue
		if race_task.peer_progress[npc_id].has("completion_time_ms"):
			if npc.npc_state != NPCRiderEntity.NPCState.FINISHED:
				npc.finish()
			continue

		# get_target_checkpoint is null during grid/countdown — the bot only
		# rides its lane while the race body is active. The lane curve, not the
		# checkpoint, decides where it steers.
		npc.driving = race_task.get_target_checkpoint(npc_id) != null
	DebugUtils.Prof("npc_race_manager", t)  # PROF: temp


#region Spawn / despawn (server API + broadcast RPCs)


## Server only. Spawns an NPC on every peer at the given transform and
## returns its (negative) racer id.
func spawn_npc(pos: Vector3, basis: Basis) -> int:
	var npc_id := _next_id
	_next_id -= 1
	rpc_spawn_npc.rpc(npc_id, pos, basis)
	return npc_id


## Server only. Despawns every NPC on every peer.
func despawn_all_npcs() -> void:
	for npc_id in _npcs.keys():
		rpc_despawn_npc.rpc(npc_id)
	# Its navmesh belongs to the level being torn down; the next race bakes its own.
	racing_line = null
	_bake_generation += 1


## Server only. Bakes the racing line through route's checkpoints. Bots hold on the grid until it
## lands, so callers don't await it.
func bake_racing_line(route: EventRoute) -> void:
	var region := level_manager.current_level.npc_nav_region
	var generation := _bake_generation
	# A level loaded this frame has no synced nav map yet, and paths on it come back empty
	while NavigationServer3D.map_get_iteration_id(region.get_navigation_map()) == 0:
		await NavigationServer3D.map_changed
	# The race ended (or restarted) while we waited — skip is intentional
	if generation != _bake_generation:
		return
	var checkpoints := route.get_checkpoints()
	var is_lap := RaceTask.is_lap_route(checkpoints)
	var positions := PackedVector3Array()
	# A point-to-point first checkpoint can sit far up the road, so start the line on the grid
	if !is_lap:
		var grid_markers := route.get_grid_markers()
		var grid_center := Vector3.ZERO
		for marker in grid_markers:
			grid_center += marker.global_position
		positions.append(grid_center / grid_markers.size())
	for checkpoint in checkpoints:
		positions.append(checkpoint.global_position)
	var region_rid := region.get_rid()
	var baked: Array[NPCRacingLine] = []
	# About a second of navmesh queries — off the main thread so the race start doesn't hitch
	var task := WorkerThreadPool.add_task(
		func():
			baked.append(
				NPCRacingLine.new(
					region_rid,
					positions,
					is_lap,
					line_sample_spacing,
					line_smoothing_passes,
					corner_grip,
					line_max_half_width
				)
			)
	)
	while !WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	# As above, the race ended while it baked
	if generation != _bake_generation:
		return
	racing_line = baked[0]
	DebugUtils.DebugMsg(
		"NPC racing line baked: %.0fm, closed=%s" % [racing_line.get_length(), racing_line.closed]
	)
	for npc_id in _npcs:
		_race_state(npc_id).racing_line = racing_line
	if _draw_racing_line:
		_draw_line()


## Server only. A late joiner's level just loaded — resend every live bot at its
## current spot so their MultiplayerSynchronizers have a node to land on. Without
## this the newcomer takes a per-packet sync error for every bot, every tick.
func sync_npcs_to_peer(peer_id: int) -> void:
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		rpc_spawn_npc.rpc_id(peer_id, npc_id, npc.global_position, npc.global_basis)


func get_npc_ids() -> Array[int]:
	var out: Array[int] = []
	for npc_id in _npcs:
		out.append(npc_id)
	return out


func get_npc(npc_id: int) -> NPCRiderEntity:
	return _npcs[npc_id]


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, pos: Vector3, basis: Basis):
	# Broadcast and late-join resync can both deliver the same bot — first one wins.
	if _npcs.has(npc_id):
		return
	# Same round-robin on every peer — the definitions ship with the game, so only the id is sent.
	var def := npc_definitions[(-npc_id - 1) % npc_definitions.size()]

	DebugUtils.DebugMsg("Adding NPC locally: %s - %s" % [npc_id, def.username])

	var npc := NPC_SCENE.instantiate() as NPCRiderEntity
	npc.name = str(npc_id)
	# Race bots are always riders — say so rather than inheriting whatever the
	# scene was last saved with. Must land before add_child (see _enter_tree).
	npc.vehicle_type = NPCRiderEntity.VehicleType.BIKE
	npc.bike_definition = def.bike_skin
	# Ride the bike's own numbers, so bots keep pace with players on the same bike
	npc.move_speed = def.bike_skin.max_speed
	npc.acceleration = def.bike_skin.acceleration
	npc.braking = def.bike_skin.brake_strength
	npc.character_definition = def.character_skin
	npc.username = "%s %d" % [def.username, -npc_id]
	# Paint pool lives on the level's TrafficSettings — race bots on this map paint
	# from the same one. Read per peer, like the rest of the level's settings.
	npc.paint_colors = level_manager.current_level.traffic_settings.paint_colors

	level_manager.current_level.player_spawn_pos.add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	_spawn_transforms[npc_id] = Transform3D(basis, pos)

	if !multiplayer.is_server():
		return
	# StateMachine._ready defers its own transition into the idle state — queue
	# ours behind it so the bot isn't flipped straight back to idle.
	var race_state := _race_state(npc_id)
	# Null while the bake waits on the nav map — the bake hands it over when it lands
	race_state.racing_line = racing_line
	# Wedged on geometry the lanes don't model — same wipeout + checkpoint respawn a
	# crash gets, which is exactly the recovery we want.
	race_state.stuck.connect(crash_npc.bind(npc_id))
	npc.state_machine.request_state_change.call_deferred(race_state)


func _race_state(npc_id: int) -> NPCRaceState:
	return _npcs[npc_id].state_machine.get_state_by_name("NPCRaceState") as NPCRaceState


@rpc("call_local", "reliable")
func rpc_despawn_npc(npc_id: int):
	# This peer may have joined after the race ended mid-teardown — skip is intentional.
	if !_npcs.has(npc_id):
		return
	_npcs[npc_id].queue_free()
	_npcs.erase(npc_id)
	_spawn_transforms.erase(npc_id)


#endregion

#region Crash / respawn (server only)


## Cosmetic wipeout + delayed teleport back to the last checkpoint passed
## (or the grid slot before any checkpoint) — mirrors the human crash flow.
func crash_npc(npc_id: int) -> void:
	_npcs[npc_id].crash()
	get_tree().create_timer(respawn_delay).timeout.connect(
		_respawn_npc.bind(npc_id), CONNECT_ONE_SHOT
	)


func _respawn_npc(npc_id: int) -> void:
	# NPC may have been despawned while the timer ran (race ended) — skip is intentional
	if !_npcs.has(npc_id):
		return
	var t := _spawn_transforms[npc_id]
	if race_task != null:
		var ckpt := race_task.get_npc_respawn_checkpoint(npc_id)
		if ckpt != null:
			t = ckpt.global_transform
	_npcs[npc_id].teleport_to(t.origin, t.basis)
	_race_state(npc_id).reset_line_progress()


#endregion

#region Debug draw (server only)


func _toggle_racing_line_debug() -> void:
	_draw_racing_line = !_draw_racing_line
	DebugDraw3D.clear_all()
	if _draw_racing_line and racing_line != null:
		_draw_line()


## The line coloured slow (red) to fast (green) by the first bot's braking profile, with the road
## room either side.
func _draw_line() -> void:
	var profile := racing_line.braking_profile(_npcs.values()[0].braking, 1.0)
	var cruise: float = _npcs.values()[0].move_speed
	var step := racing_line.sample_spacing
	DebugDraw3D.clear_all()
	# Seen through the road and props. Held only to keep the scope alive
	@warning_ignore("unused_variable")
	var cfg := DebugDraw3D.new_scoped_config().set_no_depth_test(true)
	var s := 0.0
	while s < racing_line.get_length():
		var a := racing_line.point_at(s) + Vector3.UP * 0.3
		var b := racing_line.point_at(s + step) + Vector3.UP * 0.3
		var color := Color.RED.lerp(Color.GREEN, clampf(racing_line.profile_speed(profile, s) / cruise, 0.0, 1.0))
		DebugDraw3D.draw_line(a, b, color, DRAW_SECONDS)
		var right := racing_line.right_at(s)
		DebugDraw3D.draw_line(a + right * racing_line.half_width_at(s, 1.0), a, Color.GRAY, DRAW_SECONDS)
		DebugDraw3D.draw_line(a - right * racing_line.half_width_at(s, -1.0), a, Color.DIM_GRAY, DRAW_SECONDS)
		s += step


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if npc_definitions.is_empty():
		issues.append("npc_definitions must not be empty")
	return issues
