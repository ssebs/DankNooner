@tool
## Owns ambient traffic riders (NPCRiderEntity in NPCTrafficState): reads the
## level's baked TrafficNetwork, spawns riders spread across its road lanes, and
## recovers them when they crash.
##
## Count, car/bike mix, cruise speed and the vehicle rosters are all per-map — see
## LevelDefinition.traffic_settings.
##
## FreeRoamGameMode and RaceGameMode's TrafficComponent start/stop it — see start_traffic /
## stop_traffic. Kept standalone from NPCRaceManager on purpose (see the Traffic AI
## plan); the two share the spawn RPC shape but nothing else.
class_name NPCTrafficManager extends BaseManager

@export var level_manager: LevelManager
## Used to crash a player a traffic rider rammed.
@export var spawn_manager: SpawnManager
## Round-robin source of NPC names + character skins, same as NPCRaceManager.
## The bike itself is rolled per rider from the map's roster, not taken from here.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
## How long a crashed rider stays down before it's put back on the road. Deliberately
## longer than the player's own respawn (FreeRoamGameMode._respawn_delay, 2.5s): a rider
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
## Room a spawning or recovering rider needs at its drop point before it will take it.
## Without this a rider lands back on whoever it just crashed into and the pair loop forever.
const PLACEMENT_CLEARANCE: float = 5.0
## Random spots tried for a clear one before giving up (skipping a spawn, or waiting
## out another recovery delay).
const PLACEMENT_ATTEMPTS: int = 4

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Server-side copy of each rider's rolled vehicle dict, kept so a peer whose level
## loaded after the spawn broadcast can be resynced (see request_traffic_sync).
var _vehicles: Dictionary[int, Dictionary] = {}
## Client-side gate: false until this peer's gamemode Enter confirms the level is
## loaded. Spawn broadcasts arriving earlier would parent riders under the outgoing
## level and be freed with it — they're dropped here and recovered by the sync request.
var _accept_spawns: bool = false
## res:// paths of the vehicle skins this map rolls, refreshed each start_traffic.
var _bike_skin_paths: Array = []
var _car_skin_paths: Array = []
var _network: TrafficNetworkData
## Lanes riders spawn and recover on: road lanes only, turn lanes all cluster at junctions.
var _road_lanes: Array[int] = []
## One per baked junction, shared by every rider's NPCTrafficState.
var _junctions: Array[JunctionState] = []
var _next_id: int = FIRST_ID


#region Traffic lifecycle (server only)


## Populate the current level's traffic network with riders.
##
## `for_race` picks TrafficSettings.race_traffic_amount over traffic_count — a race
## through free-roam density is a wall rather than a challenge.
func start_traffic(for_race: bool = false) -> void:
	var network_node := _find_network_node()
	# Maps with no traffic network, or one never baked, simply get no traffic.
	if network_node == null or network_node.baked == null:
		return
	_network = network_node.baked
	_road_lanes.clear()
	for i in _network.lanes.size():
		if _network.lanes[i].junction < 0:
			_road_lanes.append(i)
	_junctions = []
	for _junction in _network.junctions:
		_junctions.append(JunctionState.new(_network))

	var settings := level_manager.current_level.traffic_settings
	_bike_skin_paths = _roster_paths(settings.bike_roster, BIKE_SKINS_DIR)
	_car_skin_paths = _roster_paths(settings.car_roster, CAR_SKINS_DIR)

	var count := settings.race_traffic_amount if for_race else settings.traffic_count

	# Round-robin over shuffled lanes — every lane gets a rider before any gets a second,
	# so traffic spreads over the whole network instead of stacking at one spot.
	var spawn_lanes := _road_lanes.duplicate()
	spawn_lanes.shuffle()
	for i in count:
		var follower := _clear_follower_on(spawn_lanes[i % spawn_lanes.size()])
		# Lane too crowded for another rider — skip rather than spawn on top of someone
		if follower == null:
			continue
		var lane_transform := follower.get_transform()
		var npc_id := _next_id
		_next_id -= 1
		var def := npc_definitions[(-npc_id + FIRST_ID) % npc_definitions.size()]
		var vehicle := _roll_vehicle(def, npc_id)
		_vehicles[npc_id] = vehicle
		rpc_spawn_npc.rpc(npc_id, vehicle, lane_transform.origin, lane_transform.basis)
		# call_local ran the spawn synchronously, so the rider exists now
		_traffic_state(npc_id).follower = follower
		_traffic_state(npc_id).junctions = _junctions


## Roll one rider's vehicle. The server rolls and ships the result — rolling on
## each peer would give the same rider a different car on every screen.
##
## Traffic skins all live in res:// and are byte-identical on every peer, so the
## resource paths ARE the serializer. Deliberately not PlayerDefinition.to_dict():
## that round-trips every loadout through BikeSkinDefinition.from_dict() per rider
## per peer.
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
	_vehicles.clear()
	_network = null


#endregion

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

#region Spawn / despawn (broadcast RPCs, mirrors NPCRaceManager)


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, vehicle: Dictionary, pos: Vector3, basis: Basis):
	# Our level isn't loaded yet (spawn broadcast raced our spawn_level) — dropped
	# here, recovered by request_traffic_sync once the gamemode enters.
	if !multiplayer.is_server() and !_accept_spawns:
		return
	# Broadcast and resync can both deliver the same rider — first one wins.
	if _npcs.has(npc_id):
		return
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
	# On every peer, or a predicting client would bump into a body the server rides through.
	# Traffic rides rails; its ContactArea reports hits instead.
	npc.collision_layer = 0
	npc.collision_mask = 0

	_find_network_node().add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	# Tagged on every peer, not just the server — the HUD runs client-side and uses this
	# to tell ambient traffic from actual competitors.
	npc.add_to_group(UtilsConstants.GROUPS["Traffic"])

	if !multiplayer.is_server():
		return
	var traffic_state := _traffic_state(npc_id)
	traffic_state.crashed.connect(_on_npc_crashed.bind(npc_id))
	npc.driving = true
	# StateMachine._ready defers its own transition into the idle state — queue
	# ours behind it so the rider isn't flipped straight back to idle.
	npc.state_machine.request_state_change.call_deferred(traffic_state)


@rpc("call_local", "reliable")
func rpc_despawn_npc(npc_id: int):
	# This peer may never have accepted the spawn (late join / level still loading) —
	# skip is intentional.
	if !_npcs.has(npc_id):
		return
	_npcs[npc_id].queue_free()
	_npcs.erase(npc_id)


## The current level's TrafficNetwork, which also parents its riders. Null on maps without one.
func _find_network_node() -> TrafficNetwork:
	var found := level_manager.current_level.find_children("*", "TrafficNetwork", true, false)
	return null if found.is_empty() else found[0]


func _traffic_state(npc_id: int) -> NPCTrafficState:
	return _npcs[npc_id].state_machine.get_state_by_name("NPCTrafficState") as NPCTrafficState


## A follower at a random point ALONG the lane rather than its start: lanes start at
## junctions, so starts would pile riders into intersections.
func _follower_on(lane: int) -> TrafficLaneFollower:
	return TrafficLaneFollower.new(_network, lane, randf() * _network.lane_curve(lane).get_baked_length())


## A follower at a clear random spot along the lane, or null if every spot tried was taken.
func _clear_follower_on(lane: int) -> TrafficLaneFollower:
	for _attempt in PLACEMENT_ATTEMPTS:
		var follower := _follower_on(lane)
		if _is_spot_clear(follower.get_transform().origin, null):
			return follower
	return null


#endregion

#region Recovery (server only)


func _on_npc_crashed(victim: Node3D, npc_id: int) -> void:
	# A wreck still reports contacts so it can take players down, but only goes down once
	if _npcs[npc_id].npc_state != NPCRiderEntity.NPCState.CRASHED:
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


## Drop the rider back onto its lane a little ahead of where it went wrong, or onto
## a random lane if that spot is taken.
func _place_on_lane(npc_id: int) -> void:
	# Rider may have been despawned while the respawn timer ran — skip is intentional
	if !_npcs.has(npc_id):
		return
	var npc := _npcs[npc_id]
	var traffic_state := _traffic_state(npc_id)
	traffic_state.follower.advance(RECOVER_AHEAD)
	var ahead := traffic_state.follower.get_transform()
	# Blocked here usually means whoever we crashed into hasn't moved — fall through
	# to a random lane instead of landing on them and starting the loop again.
	if _is_spot_clear(ahead.origin, npc):
		npc.teleport_to(ahead.origin, ahead.basis)
		return

	for _attempt in PLACEMENT_ATTEMPTS:
		var follower := _follower_on(_road_lanes.pick_random())
		var lane_transform := follower.get_transform()
		if !_is_spot_clear(lane_transform.origin, npc):
			continue
		traffic_state.follower = follower
		npc.teleport_to(lane_transform.origin, lane_transform.basis)
		return

	# Everything we sampled was occupied. Wait it out rather than teleporting onto someone.
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
