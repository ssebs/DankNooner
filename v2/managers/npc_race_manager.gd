@tool
## Owns AI race riders (NPCRiderEntity): negative-id roster, spawn/despawn
## RPCs (mirrors SpawnManager's pattern), and the server-only AI tick that
## points each NPC at its next checkpoint from RaceTask.
##
## StreetRaceGameMode sets `race_task` while a race runs and calls
## spawn_npc / register — see that gamemode for the lifecycle.
class_name NPCRaceManager extends BaseManager

@export var level_manager: LevelManager
## Round-robin source of NPC names + skins. Spawned NPCs get
## "<username> <n>" so reused definitions stay distinguishable in results.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
@export var respawn_delay: float = 3.0
## Per-physics-tick probability that an NPC on unstable ground (sand) wipes out.
## Penalizes bots that cut corners across the sand instead of following the track.
@export var sand_crash_chance: float = 0.02

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")

## Set by StreetRaceGameMode while a race is running; null otherwise.
var race_task: RaceTask

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Grid-slot spawn transform per NPC — crash-respawn fallback until the NPC
## passes its first checkpoint.
var _spawn_transforms: Dictionary[int, Transform3D] = {}
var _next_id: int = -1


## Server-only AI tick: retarget each NPC at the checkpoint RaceTask expects
## it to cross next. The same crossing that scores the lap retargets nav.
func _physics_process(_delta: float):
	if Engine.is_editor_hint() or !multiplayer.is_server():
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

		# Sand penalty: each tick on unstable ground has a chance to wipe the bot
		# out, so cutting corners across the sand costs it time (crash -> respawn
		# at last checkpoint via the shared crash flow).
		if npc.is_on_unstable_ground() and randf() < sand_crash_chance:
			crash_npc(npc_id)
			continue

		# Set nav target to target checkpoint
		var ckpt := race_task.get_target_checkpoint(npc_id)
		if ckpt == null:
			# Race body hasn't started yet (grid/countdown) — hold position.
			npc.clear_nav_target()
			continue
		# TODO : try to be more smart about next spot, aka not just direct path but try to follow exising track
		npc.set_nav_target(ckpt.global_position)


#region Spawn / despawn (server API + broadcast RPCs)


## Server only. Spawns an NPC on every peer at the given transform and
## returns its (negative) racer id.
func spawn_npc(pos: Vector3, basis: Basis) -> int:
	var npc_id := _next_id
	_next_id -= 1
	var def := npc_definitions[(-npc_id - 1) % npc_definitions.size()]
	rpc_spawn_npc.rpc(npc_id, def.to_dict(), pos, basis)
	return npc_id


## Server only. Despawns every NPC on every peer.
func despawn_all_npcs() -> void:
	for npc_id in _npcs.keys():
		rpc_despawn_npc.rpc(npc_id)


func get_npc_ids() -> Array[int]:
	var out: Array[int] = []
	for npc_id in _npcs:
		out.append(npc_id)
	return out


func get_npc(npc_id: int) -> NPCRiderEntity:
	return _npcs[npc_id]


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, def_dict: Dictionary, pos: Vector3, basis: Basis):
	var def := PlayerDefinition.new()
	def.from_dict(def_dict)

	DebugUtils.DebugMsg("Adding NPC locally: %s - %s" % [npc_id, def.username])

	var npc := NPC_SCENE.instantiate() as NPCRiderEntity
	npc.name = str(npc_id)
	npc.bike_definition = def.bike_skin
	npc.character_definition = def.character_skin
	npc.username = "%s %d" % [def.username, -npc_id]

	level_manager.current_level.player_spawn_pos.add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	_spawn_transforms[npc_id] = Transform3D(basis, pos)


@rpc("call_local", "reliable")
func rpc_despawn_npc(npc_id: int):
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
