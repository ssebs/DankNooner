@tool
## Owns AI race riders (NPCRiderEntity): negative-id roster, spawn/despawn
## RPCs (mirrors SpawnManager's pattern), and the server-only AI tick that
## points each NPC at its next checkpoint from RaceTask.
##
## The race gamemodes set `race_task` while a race runs and call
## spawn_npc / register — see that gamemode for the lifecycle.
class_name NPCRaceManager extends BaseManager

@export var level_manager: LevelManager
## Round-robin source of NPC names + skins. Spawned NPCs get
## "<username> <n>" so reused definitions stay distinguishable in results.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
@export var respawn_delay: float = 3.0

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")

## Set by RoadRaceGameMode / StreetRaceGameMode while a race runs; null otherwise.
var race_task: RaceTask

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Server-side copy of each bot's PlayerDefinition dict for late-joiner resync.
var _defs: Dictionary[int, Dictionary] = {}
## Junction routing for the bots. RoadContainer never gives intersection lanes a
## lane_next, so without this they dead-end at every junction — fine on a closed-loop
## racetrack, fatal on a map with 3-way/4-way/roundabout containers.
var _route_graph: TrafficRouteGraph
## Grid-slot spawn transform per NPC — crash-respawn fallback until the NPC
## passes its first checkpoint.
var _spawn_transforms: Dictionary[int, Transform3D] = {}
var _next_id: int = -1


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
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		if npc.npc_state == NPCRiderEntity.NPCState.CRASHED:
			continue
		if race_task._peer_progress[npc_id].has("completion_time_ms"):
			if npc.npc_state != NPCRiderEntity.NPCState.FINISHED:
				npc.finish()
			continue

		# get_target_checkpoint is null during grid/countdown — the bot only
		# rides its lane while the race body is active. The lane curve, not the
		# checkpoint, decides where it steers.
		npc.driving = race_task.get_target_checkpoint(npc_id) != null


#region Spawn / despawn (server API + broadcast RPCs)


## Server only. Spawns an NPC on every peer at the given transform and
## returns its (negative) racer id.
func spawn_npc(pos: Vector3, basis: Basis) -> int:
	# Built once per race on the first spawn — the road network is up by now, and doing
	# it here keeps both race gamemodes from needing their own call. Cleared on despawn.
	if _route_graph == null:
		_route_graph = TrafficRouteGraph.new(
			TrafficRouteGraph.gather_lanes(get_tree(), _find_road_manager())
		)
	var npc_id := _next_id
	_next_id -= 1
	var def := npc_definitions[(-npc_id - 1) % npc_definitions.size()]
	var def_dict := def.to_dict()
	_defs[npc_id] = def_dict
	rpc_spawn_npc.rpc(npc_id, def_dict, pos, basis)
	return npc_id


## Server only. Despawns every NPC on every peer.
func despawn_all_npcs() -> void:
	for npc_id in _npcs.keys():
		rpc_despawn_npc.rpc(npc_id)
	_defs.clear()
	# Its lanes belong to the level being torn down; the next race rebuilds it.
	_route_graph = null


## Server only. A late joiner's level just loaded — resend every live bot at its
## current spot so their MultiplayerSynchronizers have a node to land on. Without
## this the newcomer takes a per-packet sync error for every bot, every tick.
func sync_npcs_to_peer(peer_id: int) -> void:
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		rpc_spawn_npc.rpc_id(peer_id, npc_id, _defs[npc_id], npc.global_position, npc.global_basis)


func get_npc_ids() -> Array[int]:
	var out: Array[int] = []
	for npc_id in _npcs:
		out.append(npc_id)
	return out


func get_npc(npc_id: int) -> NPCRiderEntity:
	return _npcs[npc_id]


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, def_dict: Dictionary, pos: Vector3, basis: Basis):
	# Broadcast and late-join resync can both deliver the same bot — first one wins.
	if _npcs.has(npc_id):
		return
	var def := PlayerDefinition.new()
	def.from_dict(def_dict)

	DebugUtils.DebugMsg("Adding NPC locally: %s - %s" % [npc_id, def.username])

	var npc := NPC_SCENE.instantiate() as NPCRiderEntity
	npc.name = str(npc_id)
	# Race bots are always riders — say so rather than inheriting whatever the
	# scene was last saved with. Must land before add_child (see _enter_tree).
	npc.vehicle_type = NPCRiderEntity.VehicleType.BIKE
	npc.bike_definition = def.bike_skin
	npc.character_definition = def.character_skin
	npc.username = "%s %d" % [def.username, -npc_id]
	# Paint pool lives on the level's TrafficSettings — race bots on this map paint
	# from the same one. Read per peer, like the rest of the level's settings.
	npc.paint_colors = level_manager.current_level.traffic_settings.paint_colors
	# Lane follower needs the level's RoadManager before _ready runs.
	npc.road_manager = _find_road_manager()

	level_manager.current_level.player_spawn_pos.add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	_spawn_transforms[npc_id] = Transform3D(basis, pos)

	if !multiplayer.is_server():
		return
	# StateMachine._ready defers its own transition into the idle state — queue
	# ours behind it so the bot isn't flipped straight back to idle.
	var race_state := npc.state_machine.get_state_by_name("NPCRaceState") as NPCRaceState
	race_state.route_graph = _route_graph
	race_state.race_task = race_task
	# Wedged on geometry the lanes don't model — same wipeout + checkpoint respawn a
	# crash gets, which is exactly the recovery we want.
	race_state.stuck.connect(crash_npc.bind(npc_id))
	npc.state_machine.request_state_change.call_deferred(race_state)


## The current level's RoadManager, whose lanes the NPCs follow.
func _find_road_manager() -> RoadManager:
	return level_manager.current_level.find_children("*", "RoadManager", true, false)[0]


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


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if npc_definitions.is_empty():
		issues.append("npc_definitions must not be empty")
	return issues
