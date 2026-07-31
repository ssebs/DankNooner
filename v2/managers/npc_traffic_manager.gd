@tool
## Owns free-roam traffic riders (NPCRiderEntity in NPCTrafficState): builds the
## level's TrafficRouteGraph, spawns riders spread across the road network, and
## recovers them when they crash or get wedged.
##
## FreeRoamGameMode starts/stops it — see start_traffic / stop_traffic. Kept
## standalone from NPCRaceManager on purpose (see the Traffic AI plan); the two
## share the spawn RPC shape but nothing else.
class_name NPCTrafficManager extends BaseManager

@export var level_manager: LevelManager
## Used to crash a player a traffic rider rammed.
@export var spawn_manager: SpawnManager
## Round-robin source of NPC names + character skins, same as NPCRaceManager.
## The bike itself is rolled per rider from BIKE_SKINS_DIR, not taken from here.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
@export var traffic_count: int = 8
## Odds a given traffic vehicle is a car rather than a bike + rider.
@export_range(0.0, 1.0, 0.05) var car_chance: float = 0.5
## Base move speed handed to every traffic rider (they ride slower than racers).
@export var cruise_speed: float = 22.0
@export var respawn_delay: float = 3.0

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")
## Traffic rolls its vehicle out of these — the same folders the customize menu
## lists, so a new .tres shows up in traffic with no wiring.
const BIKE_SKINS_DIR: String = "res://resources/bikes/skins/"
const CAR_SKINS_DIR: String = "res://resources/cars/skins/"
## Race NPCs count down from -1; traffic starts far below so the two can never
## produce the same node name under the level's spawn node.
const FIRST_ID: int = -1000
## How far along its lane a recovered rider is dropped back in.
const RECOVER_AHEAD: float = 4.0

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## res:// paths of every rollable vehicle skin, refreshed each start_traffic.
var _bike_skin_paths: Array = []
var _car_skin_paths: Array = []
var _route_graph: TrafficRouteGraph
var _graph_rebuild_queued: bool = false
var _next_id: int = FIRST_ID


#region Traffic lifecycle (server only)


## Build the route graph for the current level and populate it with riders.
func start_traffic() -> void:
	var road_manager := _find_road_manager()
	# Maps with no road network (the stunt map) simply get no traffic.
	if road_manager == null:
		return
	_route_graph = TrafficRouteGraph.new(_gather_lanes(road_manager))

	# Containers defer their first rebuild_segments(true) — which frees and
	# regenerates every lane — so the graph we just built goes stale moments
	# from now. Follow their updates and re-derive it in place.
	for container in road_manager.get_containers():
		if !container.on_road_updated.is_connected(_on_road_updated):
			container.on_road_updated.connect(_on_road_updated)

	# Only the paths matter here — the skin_name keys are the menu's concern.
	_bike_skin_paths = SkinScanner.scan_skin_dir(BIKE_SKINS_DIR).values()
	_car_skin_paths = SkinScanner.scan_skin_dir(CAR_SKINS_DIR).values()

	# Shuffled distinct lanes — spreads riders over the whole network instead of
	# stacking them all at one spawn point.
	var spawn_lanes := _route_graph.lanes.duplicate()
	spawn_lanes.shuffle()
	for i in mini(traffic_count, spawn_lanes.size()):
		var lane_transform := _route_graph.lane_start_transform(spawn_lanes[i])
		var npc_id := _next_id
		_next_id -= 1
		var def := npc_definitions[(-npc_id + FIRST_ID) % npc_definitions.size()]
		var vehicle := _roll_vehicle(def, npc_id)
		rpc_spawn_npc.rpc(npc_id, vehicle, lane_transform.origin, lane_transform.basis)


## Roll one rider's vehicle. The server rolls and ships the result — rolling on
## each peer would give the same rider a different car on every screen.
##
## Traffic skins all live in res:// and are byte-identical on every peer, so the
## resource paths ARE the serializer. Deliberately not PlayerDefinition.to_dict():
## that round-trips every loadout through BikeSkinDefinition.from_dict(), which
## writes a .tres into user://skins/ per rider per peer.
func _roll_vehicle(def: PlayerDefinition, npc_id: int) -> Dictionary:
	if !_car_skin_paths.is_empty() and randf() < car_chance:
		# No rider on a car, so no character skin and no name to label it with.
		return {
			"type": NPCRiderEntity.VehicleType.CAR,
			"skin": _car_skin_paths.pick_random(),
			"character": "",
			"username": "",
		}
	return {
		"type": NPCRiderEntity.VehicleType.BIKE,
		"skin": _bike_skin_paths.pick_random(),
		"character": def.character_skin.resource_path,
		"username": "%s %d" % [def.username, -npc_id],
	}


func stop_traffic() -> void:
	for npc_id in _npcs.keys():
		rpc_despawn_npc.rpc(npc_id)
	# The containers' on_road_updated connections die with them on level unload,
	# and start_traffic re-connects whatever survives.
	_route_graph = null


## A container finished (re)building. It fires per rebuild pass and there are
## several containers, so coalesce into one graph rebuild at the end of the frame.
func _on_road_updated(_segments: Array) -> void:
	if _graph_rebuild_queued:
		return
	_graph_rebuild_queued = true
	_rebuild_route_graph.call_deferred()


func _rebuild_route_graph() -> void:
	_graph_rebuild_queued = false
	# Traffic was stopped while the rebuild was queued — nothing to re-derive.
	if _route_graph == null:
		return
	_route_graph.rebuild(_gather_lanes(_find_road_manager()))


#endregion

#region Spawn / despawn (broadcast RPCs, mirrors NPCRaceManager)


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, vehicle: Dictionary, pos: Vector3, basis: Basis):
	DebugUtils.DebugMsg("Adding traffic NPC locally: %s - %s" % [npc_id, vehicle["skin"]])

	var npc := NPC_SCENE.instantiate() as NPCRiderEntity
	npc.name = str(npc_id)
	# vehicle_type must land before add_child — _enter_tree drops the other skins.
	npc.vehicle_type = vehicle["type"]
	if npc.vehicle_type == NPCRiderEntity.VehicleType.CAR:
		npc.car_definition = load(vehicle["skin"])
	else:
		npc.bike_definition = load(vehicle["skin"])
		npc.character_definition = load(vehicle["character"])
		npc.username = vehicle["username"]
	npc.move_speed = cruise_speed
	# Lane follower needs the level's RoadManager before _ready runs.
	npc.road_manager = _find_road_manager()

	level_manager.current_level.player_spawn_pos.add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc

	if !multiplayer.is_server():
		return
	var traffic_state := npc.state_machine.get_state_by_name("NPCTrafficState") as NPCTrafficState
	traffic_state.route_graph = _route_graph
	traffic_state.crashed.connect(_on_npc_crashed.bind(npc_id))
	traffic_state.stuck.connect(_place_on_lane.bind(npc_id))
	npc.driving = true
	# StateMachine._ready defers its own transition into the idle state — queue
	# ours behind it so the rider isn't flipped straight back to idle.
	npc.state_machine.request_state_change.call_deferred(traffic_state)


@rpc("call_local", "reliable")
func rpc_despawn_npc(npc_id: int):
	_npcs[npc_id].queue_free()
	_npcs.erase(npc_id)


## The current level's RoadManager, whose lanes the traffic follows. Null on
## maps that have no road network at all.
func _find_road_manager() -> RoadManager:
	var found := level_manager.current_level.find_children("*", "RoadManager", true, false)
	if found.is_empty():
		return null
	return found[0]


## Every AI lane under the manager. Containers may override the manager's lane
## group with their own, so check both (same sweep RoadLaneAgent does).
func _gather_lanes(road_manager: RoadManager) -> Array:
	var out: Array = []
	out.append_array(get_tree().get_nodes_in_group(road_manager.ai_lane_group))
	for container in road_manager.get_containers():
		if container.ai_lane_group == "":
			continue
		out.append_array(get_tree().get_nodes_in_group(container.ai_lane_group))
	return out


#endregion

#region Recovery (server only)


func _on_npc_crashed(victim: Node3D, npc_id: int) -> void:
	_npcs[npc_id].crash()
	_respawn_after_delay(npc_id)
	# We rode into a player — they never see that collision from their side, so
	# take them down with us (same broadcast CrashController uses).
	if victim is PlayerEntity:
		spawn_manager.crash_player.rpc(int(victim.name))


func _respawn_after_delay(npc_id: int) -> void:
	get_tree().create_timer(respawn_delay).timeout.connect(
		_place_on_lane.bind(npc_id), CONNECT_ONE_SHOT
	)


## Drop the rider back onto the road a little ahead of where it went wrong, or
## onto a random lane if it no longer has one under it.
func _place_on_lane(npc_id: int) -> void:
	# Rider may have been despawned while the respawn timer ran — skip is intentional
	if !_npcs.has(npc_id):
		return
	var npc := _npcs[npc_id]
	if is_instance_valid(npc.lane_agent.current_lane):
		var here := npc.lane_agent.test_move_along_lane(0.0)
		var ahead := npc.lane_agent.test_move_along_lane(RECOVER_AHEAD)
		var dir := ahead - here
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			npc.teleport_to(ahead, Basis.looking_at(dir))
			return

	var lane := _route_graph.random_lane()
	# Every cached lane was freed and the graph hasn't caught up yet (road
	# rebuild) — wait it out rather than teleporting the rider into the void.
	if lane == null:
		_respawn_after_delay(npc_id)
		return
	var lane_transform := _route_graph.lane_start_transform(lane)
	npc.teleport_to(lane_transform.origin, lane_transform.basis)


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if npc_definitions.is_empty():
		issues.append("npc_definitions must not be empty")
	return issues
