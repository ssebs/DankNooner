@tool
## Owns AI race riders (NPCRiderEntity): negative-id roster, spawn/despawn
## RPCs (mirrors SpawnManager's pattern), and the server-only AI tick that
## points each NPC at its next checkpoint from RaceTask.
##
## RaceGameMode's NPCRacersComponent sets `race_task` while a race runs and calls
## spawn_npc / register — see that component for the lifecycle.
class_name NPCRaceManager extends BaseManager

## Server: a bot joined / left the roster (TrickManager keeps a scoring row per bot).
signal npc_spawned(npc_id: int)
signal npc_despawned(npc_id: int)

@export var level_manager: LevelManager
@export var settings_manager: SettingsManager
@export var spawn_manager: SpawnManager
@export var item_manager: ItemManager
## Round-robin source of NPC names + skins. Spawned NPCs get
## "<username> <n>" so reused definitions stay distinguishable in results.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/npc_racer_definition.tres")
]
@export var respawn_delay: float = 3.0
## How far the host's Easy / Hard difficulty setting moves bot skill off its centre.
@export var difficulty_skill_shift: float = 0.5
## Bot item use: a held oil slick drops once a rider is within this many metres behind, and a held
## Rally Up goes off after this many seconds on average.
@export var oil_slick_trigger_distance: float = 15.0
@export var rally_up_hold_time: float = 8.0
## A bot boosts once its next checkpoint is within this many degrees of its heading, down a straight.
@export var boost_cone_deg: float = 10.0

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")
const RACING_LINE_SCENE: PackedScene = preload("res://levels/assets/props/racing_line.tscn")
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
## The level's road region while bake_racing_line has the race's own mesh swapped in, and the
## shared mesh despawn_all_npcs puts back. Null otherwise.
var _race_region: NPCNavRegion
var _shared_navmesh: NavigationMesh
var _draw_racing_line: bool = false

## Every peer: the line shown to players; null outside a race with bots.
var _shown_line: RacingLine


func _ready():
	super()
	if Engine.is_editor_hint():
		return
	Console.add_command("dbg_racing_line", _toggle_racing_line_debug, [], 0, "Toggle the NPC racing line debug draw")
	settings_manager.all_settings_changed.connect(_on_settings_changed)


## Server-only AI tick: retarget each NPC at the checkpoint RaceTask expects
## it to cross next. The same crossing that scores the lap retargets nav.
func _physics_process(delta: float):
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
		if npc.driving:
			_maybe_use_item(npc_id, npc, delta)
			_maybe_boost(npc_id, npc)
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
	rpc_hide_racing_line.rpc()
	_bake_generation += 1
	# Races without bots never swap a mesh in — skip is intentional
	if _race_region != null:
		_race_region.navigation_mesh = _shared_navmesh
		_race_region = null
		_shared_navmesh = null


## Server only. Bakes the racing line through event's checkpoints. Bots hold on the grid until it
## lands, so callers don't await it.
func bake_racing_line(event: GameModeEvent) -> void:
	var region := level_manager.current_level.npc_nav_region
	var generation := _bake_generation
	_race_region = region
	_shared_navmesh = region.navigation_mesh
	# The race's own props are cut into its mesh, so the line and rejoin paths steer round them
	await region.swap_navmesh(event.get_road_navmesh(_shared_navmesh))
	# The race ended (or restarted) while we waited — skip is intentional
	if generation != _bake_generation:
		return
	# Read here: scene nodes aren't safe to touch from the worker thread
	var positions := event.get_racing_route()
	var is_lap := RaceTask.is_lap_route(event.get_checkpoints())
	var region_rid := region.get_rid()
	var baked: Array[NPCRacingLine] = []
	# About a second of navmesh queries — off the main thread so the race start doesn't hitch
	var task := WorkerThreadPool.add_task(
		func(): baked.append(NPCRacingLine.bake(region_rid, positions, is_lap))
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
	rpc_show_racing_line.rpc(
		racing_line.get_points(), racing_line.closed
	)
	if _draw_racing_line:
		_draw_line()


## Server only. A late joiner's level just loaded — resend every live bot at its
## current spot so their MultiplayerSynchronizers have a node to land on. Without
## this the newcomer takes a per-packet sync error for every bot, every tick.
func sync_npcs_to_peer(peer_id: int) -> void:
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		rpc_spawn_npc.rpc_id(peer_id, npc_id, npc.global_position, npc.global_basis)
	# Still baking — the broadcast when it lands reaches them — skip is intentional
	if racing_line == null:
		return
	rpc_show_racing_line.rpc_id(
		peer_id, racing_line.get_points(), racing_line.closed
	)


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
	var def := _definition_for(npc_id)

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

	level_manager.current_level.player_spawn.add_child(npc, true)
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
	race_state.skill = _bot_skill()
	# Ids count down from -1, so consecutive bots think on consecutive frames
	race_state.think_slot = -npc_id % NPCRaceState.THINK_FRAMES
	# Wedged on geometry the lanes don't model — same wipeout + checkpoint respawn a
	# crash gets, which is exactly the recovery we want.
	race_state.stuck.connect(crash_npc.bind(npc_id))
	race_state.crashed.connect(_on_npc_crashed.bind(npc_id))
	# Only race bots shoot; traffic shares the scene and leaves its hitbox off
	npc.get_node("%GunCollisionArea").monitoring = true
	npc.state_machine.request_state_change.call_deferred(race_state)
	npc_spawned.emit(npc_id)


## Host's view: centred on the base tuning, shifted by its difficulty setting (0 = easy).
func _bot_skill() -> float:
	# TODO: centre on the host's player level once it exists
	var centre := 0.5
	var easy: bool = settings_manager.current_settings["difficulty"] == 0
	return clampf(centre + (-difficulty_skill_shift if easy else difficulty_skill_shift), 0.0, 1.0)


## Same round-robin on every peer — the definitions ship with the game, so only the id is sent.
func _definition_for(npc_id: int) -> PlayerDefinition:
	return npc_definitions[(-npc_id - 1) % npc_definitions.size()]


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
	if multiplayer.is_server():
		npc_despawned.emit(npc_id)


#endregion

#region Player racing line (every peer)


@rpc("call_local", "reliable")
func rpc_show_racing_line(points: PackedVector3Array, is_closed: bool) -> void:
	_hide_line()
	_shown_line = RACING_LINE_SCENE.instantiate()
	_shown_line.curve = NPCRacingLine.curve_through(points, is_closed)
	_shown_line.visible = settings_manager.current_settings["show_racing_line"]
	level_manager.current_level.add_child(_shown_line)
	# The curve is in world space
	_shown_line.global_transform = Transform3D.IDENTITY


@rpc("call_local", "reliable")
func rpc_hide_racing_line() -> void:
	_hide_line()


func _hide_line() -> void:
	if is_instance_valid(_shown_line):
		_shown_line.queue_free()
	_shown_line = null


func _on_settings_changed(settings: Dictionary) -> void:
	# No line outside a race with bots, or freed with the level on a mid-race disconnect — skip is
	# intentional
	if is_instance_valid(_shown_line):
		_shown_line.visible = settings["show_racing_line"]


#endregion

#region Items


## Every peer, from ItemManager's Rally Up: bots ride its skins too, then their own.
func set_rally_up(active: bool) -> void:
	for npc_id in _npcs:
		var def := _definition_for(npc_id)
		_npcs[npc_id].update_skins(
			ItemManager.RALLY_UP_BIKE if active else def.bike_skin,
			ItemManager.RALLY_UP_CHARACTER if active else def.character_skin
		)


## Server only. Simple rules for whatever the bot holds (ItemManager.BOT_ITEMS): bat or shotgun
## once a racer is in reach, an oil slick for a rider close behind, a Rally Up whenever.
func _maybe_use_item(npc_id: int, npc: NPCRiderEntity, delta: float) -> void:
	var held := item_manager.get_held(npc_id)
	if held == null:
		return
	match held.item_type:
		PickupItemDefinition.PickupItemType.BAT:
			if _rider_within(npc, SpawnManager.BAT_SWING_RANGE):
				item_manager.use_item(npc_id)
		PickupItemDefinition.PickupItemType.SHOTGUN:
			if _racer_in_sights(npc):
				item_manager.use_item(npc_id)
		PickupItemDefinition.PickupItemType.OIL_SLICK:
			if _rider_close_behind(npc):
				item_manager.use_item(npc_id)
		PickupItemDefinition.PickupItemType.RALLY_UP:
			if randf() < delta / rally_up_hold_time:
				item_manager.use_item(npc_id)


func _rider_within(npc: NPCRiderEntity, radius: float) -> bool:
	for rider in _riders_besides(npc):
		if npc.global_position.distance_to(rider.global_position) <= radius:
			return true
	return false


## Every upright player and race bot but npc. player_spawn holds more than riders.
func _riders_besides(npc: NPCRiderEntity) -> Array[Node3D]:
	var riders: Array[Node3D] = []
	for child in level_manager.current_level.player_spawn.get_children():
		var is_rider := child is PlayerEntity or child is NPCRiderEntity
		if is_rider and child != npc and !child.is_crashed:
			riders.append(child)
	return riders


## A player or race bot inside the bot's shotgun hitbox. Not traffic, which would waste the shot.
func _racer_in_sights(npc: NPCRiderEntity) -> bool:
	for body in npc.get_node("%GunCollisionArea").get_overlapping_bodies():
		var is_racer := body is PlayerEntity or (body is NPCRiderEntity and _npcs.has(int(body.name)))
		if is_racer and body != npc and !body.is_crashed:
			return true
	return false


func _rider_close_behind(npc: NPCRiderEntity) -> bool:
	var forward := -npc.global_basis.z
	for rider in _riders_besides(npc):
		var to_rider: Vector3 = rider.global_position - npc.global_position
		if to_rider.dot(forward) < 0.0 and to_rider.length() < oil_slick_trigger_distance:
			return true
	return false


## Server only. One segment when the next checkpoint is dead ahead down a straight; a burn into a
## corner is wasted.
func _maybe_boost(npc_id: int, npc: NPCRiderEntity) -> void:
	var tc := npc.trick_controller
	if tc.is_boosting or tc.boost_amount < 1.0:
		return
	var to_checkpoint := race_task.get_target_checkpoint(npc_id).global_position - npc.global_position
	var forward := -npc.global_basis.z
	var angle := Vector2(forward.x, forward.z).angle_to(Vector2(to_checkpoint.x, to_checkpoint.z))
	if absf(angle) <= deg_to_rad(boost_cone_deg) and _race_state(npc_id).is_straight_ahead():
		tc.boost()


#endregion

#region Crash / respawn (server only)


## Wipeout + delayed teleport back to the last checkpoint passed
## (or the grid slot before any checkpoint) — mirrors the human crash flow.
func crash_npc(npc_id: int) -> void:
	# A wall hit and a stuck report can land on the same tick — skip is intentional
	if _npcs[npc_id].npc_state == NPCRiderEntity.NPCState.CRASHED:
		return
	_npcs[npc_id].crash()
	get_tree().create_timer(respawn_delay).timeout.connect(
		_respawn_npc.bind(npc_id), CONNECT_ONE_SHOT
	)


## A racer we rode into never sees the collision from its side, so take it down with us (as
## CrashController does), credited to this bot like a player's ram.
func _on_npc_crashed(victim: Node3D, npc_id: int) -> void:
	crash_npc(npc_id)
	# null for a wall or a bad landing — nobody else goes down
	if victim != null:
		spawn_manager.knock_out_rider(victim, npc_id)


func _respawn_npc(npc_id: int) -> void:
	# NPC may have been despawned while the timer ran (race ended) — skip is intentional
	if !_npcs.has(npc_id):
		return
	var t := _spawn_transforms[npc_id]
	if race_task != null:
		var point := race_task.get_npc_respawn_point(npc_id)
		if point != null:
			t = point.global_transform
	_npcs[npc_id].trick_controller.do_reset()
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
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if item_manager == null:
		issues.append("item_manager must not be empty")
	if npc_definitions.is_empty():
		issues.append("npc_definitions must not be empty")
	return issues
