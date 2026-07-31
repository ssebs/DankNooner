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
## The bike itself is rolled per rider from the map's roster, not taken from here.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
## Count, car/bike mix, cruise speed and the vehicle rosters are per-map — see
## LevelDefinition.traffic_settings.
## How long a crashed rider stays down before it's put back on the road. Deliberately
## longer than the player's own respawn (FreeRoamGameMode._respawn_delay, 3s): a rider
## recovers roughly where it went down, so matching the player's timer drops it straight
## back onto the player it just took out — crash, respawn, crash. Randomized so a pile-up
## doesn't pop back all at once either.
@export var respawn_delay_min: float = 5.0
@export var respawn_delay_max: float = 8.0

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")
## Fallback pools for maps whose TrafficSettings leave a roster empty — the same
## folders the customize menu lists, so a new .tres shows up in traffic with no wiring.
const BIKE_SKINS_DIR: String = "res://resources/bikes/skins/"
const CAR_SKINS_DIR: String = "res://resources/cars/skins/"
## Race NPCs count down from -1; traffic starts far below so the two can never
## produce the same node name under the level's spawn node.
const FIRST_ID: int = -1000
## How far along its lane a recovered rider is dropped back in.
const RECOVER_AHEAD: float = 4.0
## Room a recovering rider needs at its drop point before it will take it. Without this
## a rider lands back on whoever it just crashed into and the pair loop forever.
const PLACEMENT_CLEARANCE: float = 5.0
## Random lanes tried for a clear spot before giving up and waiting out another delay.
const PLACEMENT_ATTEMPTS: int = 4

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## res:// paths of the vehicle skins this map rolls, refreshed each start_traffic.
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

	var settings := level_manager.current_level.traffic_settings
	_bike_skin_paths = _roster_paths(settings.bike_roster, BIKE_SKINS_DIR)
	_car_skin_paths = _roster_paths(settings.car_roster, CAR_SKINS_DIR)

	var count := settings.traffic_count

	# Shuffled distinct lanes — spreads riders over the whole network instead of
	# stacking them all at one spawn point. Dropped at a random point ALONG each lane
	# rather than at its start: junction lanes all start within a few metres of each
	# other, so spawning at starts piles riders into intersections and leaves the roads
	# between them empty.
	var spawn_lanes := _route_graph.lanes.duplicate()
	spawn_lanes.shuffle()
	for i in mini(count, spawn_lanes.size()):
		var lane_transform := _route_graph.lane_transform_at(spawn_lanes[i], randf())
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
	var chance := level_manager.current_level.traffic_settings.car_chance
	if !_car_skin_paths.is_empty() and randf() < chance:
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


## res:// paths of the skins this map may roll: the level's roster if it named one,
## otherwise everything in the global folder. Paths, not the resources themselves —
## _roll_vehicle ships them across the wire.
func _roster_paths(roster: Array, fallback_dir: String) -> Array:
	if roster.is_empty():
		# Only the paths matter here — the skin_name keys are the menu's concern.
		return SkinScanner.scan_skin_dir(fallback_dir).values()
	var out: Array = []
	for skin in roster:
		out.append(skin.resource_path)
	return out


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
	# Read per peer rather than shipped — every peer has the same level loaded.
	npc.move_speed = level_manager.current_level.traffic_settings.cruise_speed
	npc.paint_colors = level_manager.current_level.traffic_settings.paint_colors
	# Lane follower needs the level's RoadManager before _ready runs.
	npc.road_manager = _find_road_manager()

	level_manager.current_level.player_spawn_pos.add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	# Tagged on every peer, not just the server — the HUD runs client-side and uses this
	# to tell ambient traffic from actual competitors.
	npc.add_to_group(UtilsConstants.GROUPS["Traffic"])

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
	get_tree().create_timer(randf_range(respawn_delay_min, respawn_delay_max)).timeout.connect(
		_place_on_lane.bind(npc_id), CONNECT_ONE_SHOT
	)


## Drop the rider back onto the road a little ahead of where it went wrong, or
## onto a random lane if that spot is taken or it no longer has a lane under it.
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
		# Blocked here usually means whoever we crashed into hasn't moved — fall through
		# to a random lane instead of landing on them and starting the loop again.
		if dir.length_squared() > 0.01 and _is_spot_clear(ahead, npc):
			npc.teleport_to(ahead, Basis.looking_at(dir))
			return

	# Random point along a random lane, same reason as spawning — otherwise every
	# recovered rider lands on the same handful of junction lane starts and stacks up.
	for _attempt in PLACEMENT_ATTEMPTS:
		var lane := _route_graph.random_lane()
		# Every cached lane was freed and the graph hasn't caught up yet (road rebuild).
		if lane == null:
			break
		var lane_transform := _route_graph.lane_transform_at(lane, randf())
		if !_is_spot_clear(lane_transform.origin, npc):
			continue
		npc.teleport_to(lane_transform.origin, lane_transform.basis)
		return

	# No lanes at all, or everything we sampled was occupied. Wait it out rather than
	# teleporting into the void or onto someone.
	_respawn_after_delay(npc_id)


## Nobody parked within PLACEMENT_CLEARANCE of a drop point. Linear over the Racers
## group, which is fine here — this runs on respawn, not per tick.
func _is_spot_clear(pos: Vector3, mover: NPCRiderEntity) -> bool:
	var clearance_sq := PLACEMENT_CLEARANCE * PLACEMENT_CLEARANCE
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == mover:
			continue
		if racer.global_position.distance_squared_to(pos) < clearance_sq:
			return false
	return true


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
