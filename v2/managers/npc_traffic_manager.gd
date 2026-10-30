@tool
## Owns ambient traffic riders (NPCRiderEntity in NPCTrafficState): reads the
## level's baked TrafficNetwork, spawns riders spread across its road lanes, ticks them
## (riders far from every player tick coarsely and aren't synced), and recovers them when
## they crash.
##
## Count, car/bike mix, cruise speed and the vehicle rosters are all per-map — see
## LevelDefinition.traffic_settings.
##
## FreeRoamGameMode and RaceGameMode's TrafficComponent start/stop it — see start_traffic /
## stop_traffic. Kept standalone from NPCRaceManager on purpose (see the Traffic AI
## plan); the two share the spawn RPC shape but nothing else.
class_name NPCTrafficManager extends BaseManager

## Server: a player passed a traffic rider close without hitting it — TrickManager scores it.
signal player_near_missed(player: PlayerEntity)

@export var level_manager: LevelManager
## Host's traffic_density setting scales free-roam traffic_count.
@export var settings_manager: SettingsManager
## Used to crash a player a traffic rider rammed.
@export var spawn_manager: SpawnManager
## Round-robin source of bike riders' character skins, same as NPCRaceManager.
## The vehicle itself is rolled per rider from the map's roster, not taken from here.
@export var npc_definitions: Array[PlayerDefinition] = [
	load("res://resources/player/default_player_definition.tres")
]
## How long a crashed rider stays down before it's put back on the road. Deliberately
## longer than the player's own respawn (UtilsConstants.CRASH_RESPAWN_DELAY): a rider
## recovers roughly where it went down, so matching the player's timer drops it straight
## back onto the player it just took out — crash, respawn, crash. Randomized so a pile-up
## doesn't pop back all at once either.
@export var respawn_delay_min: float = 6.0
@export var respawn_delay_max: float = 8.0
## A rider within this of any player is near: full-rate tick, ContactArea on, and synced to
## and drawn by only the peers whose player it's near. Bigger = less pop-in, more cost and
## bandwidth.
@export var near_radius: float = 150.0
## Far riders tick once per this many physics ticks, with the time since their last one.
@export var far_tick_interval: int = 8

const NPC_SCENE: PackedScene = preload("res://entities/npc/npc_rider_entity.tscn")
## Fallback pools for maps whose TrafficSettings leave a roster empty — the same
## folders the customize menu lists, so a new .tres shows up in traffic with no wiring.
const BIKE_SKINS_DIR: String = "res://resources/bikes/skins/"
const CAR_SKINS_DIR: String = "res://resources/cars/skins/"
## Race NPCs count down from -1; traffic starts far below so the two can never
## produce the same node name under the level's spawn node.
const FIRST_ID: int = -1000
## Only BikeWreck masks this, so traffic shoves crashed bikes while riders still pass through.
const TRAFFIC_BODY_LAYER_MASK: int = 128 # 1 << 7 (layer 8 "traffic_body")
## How far along its lane a recovered rider is dropped back in.
const RECOVER_AHEAD: float = 4.0
## Room a spawning or recovering rider needs at its drop point before it will take it.
## Without this a rider lands back on whoever it just crashed into and the pair loop forever.
const PLACEMENT_CLEARANCE: float = 5.0
## Random spots tried for a clear one before giving up (skipping a spawn, or waiting
## out another recovery delay).
const PLACEMENT_ATTEMPTS: int = 4
## Gap between the spots riders spawn and recycle onto along each road lane.
const SPOT_SPACING: float = 10.0
## How often the server's LOD pass re-measures riders, and clients sweep for stale ones.
const LOD_INTERVAL_MS: int = 250
## A client hides a rider not synced for this long. Covers several missed packets at the
## synchronizer's replication_interval, or riders blink on lossy links.
const SYNC_STALE_MS: int = 500

var _npcs: Dictionary[int, NPCRiderEntity] = {}
## Server-side copy of each rider's rolled _skins index, kept so a peer whose level
## loaded after the spawn broadcast can be resynced (see request_traffic_sync).
var _skin_indices: Dictionary[int, int] = {}
## Client-side gate: false until this peer's gamemode Enter confirms the level is
## loaded. Spawn broadcasts arriving earlier would parent riders under the outgoing
## level and be freed with it — they're dropped here and recovered by the sync request.
var _accept_spawns: bool = false
## The vehicle skins this map rolls, cars first. Built on every peer, so spawns ship an index.
var _skins: Array = []
var _car_count: int = 0
var _network: TrafficNetworkData
## Lanes riders spawn and recover on: road lanes only, turn lanes all cluster at junctions.
var _road_lanes: Array[int] = []
## Server: every SPOT_SPACING along the road lanes, where riders spawn and recycle onto.
var _spots: Array[_Spot] = []
## Server: each spot's lane weight, indexed like _spots. Evenly spaced, so a pick is weight × length.
var _spot_weights := PackedFloat32Array()
## Server: road lane metres × weight, summed — riders spread exactly by weight would be
## _npcs.size() / this per weighted metre on every lane.
var _weighted_length := 0.0
var _rng := RandomNumberGenerator.new()
## One per baked junction, shared by every rider's NPCTrafficState.
var _junctions: Array[JunctionState] = []
## Traffic on each lane, indexed like TrafficNetworkData.lanes, shared by every NPCTrafficState.
var _lane_riders: Array[Array] = []
## Every racer but traffic, shared by every NPCTrafficState — only ever mutated in place.
var _other_racers: Array = []
var _next_id: int = FIRST_ID
## Server: peers whose player each rider was near on the last LOD pass.
var _near_peers: Dictionary[int, PackedInt32Array] = {}
## Server: time each far rider has gone without a tick.
var _pending_delta: Dictionary[int, float] = {}
var _tick_count: int = 0
var _next_lod_ms: int = 0
## Server: set_traffic's rider count, overriding the map's. -1 = the map's.
var _debug_count: int = -1
var _for_race: bool = false
## The traffic_density setting, kept in step by _on_all_settings_changed.
var _density: float = 1.0


func _ready():
	super()
	if Engine.is_editor_hint():
		return
	Console.add_command(
		"set_traffic", _set_debug_count, ["count"], 1, "Set the NPC traffic count, -1 for the map's (host only)"
	)
	settings_manager.all_settings_changed.connect(_on_all_settings_changed)


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
	_spots.clear()
	_spot_weights.clear()
	_weighted_length = 0.0
	for i in _network.lanes.size():
		if _network.lanes[i].junction < 0:
			_road_lanes.append(i)
			_add_spots(i)
	_junctions = []
	for _junction in _network.junctions:
		_junctions.append(JunctionState.new(_network))
	_lane_riders = []
	for _lane in _network.lanes:
		_lane_riders.append([])

	_build_skins()
	var settings := level_manager.current_level.traffic_settings
	var count := settings.race_traffic_amount if for_race else roundi(settings.traffic_count * _density)
	if _debug_count >= 0:
		count = _debug_count
	_for_race = for_race

	for i in count:
		var spot := _clear_spot(_spots, _spot_weights, null)
		# Network too crowded for another rider — skip rather than spawn on top of someone
		if spot == null:
			continue
		var follower := TrafficLaneFollower.new(_network, spot.lane, spot.offset)
		var lane_transform := spot.transform
		var npc_id := _next_id
		_next_id -= 1
		var skin_index := _roll_skin_index()
		_skin_indices[npc_id] = skin_index
		rpc_spawn_npc.rpc(npc_id, skin_index, lane_transform.origin, lane_transform.basis)
		# call_local ran the spawn synchronously, so the rider exists now
		var traffic_state := _traffic_state(npc_id)
		traffic_state.follower = follower
		traffic_state.junctions = _junctions
		traffic_state.lane_riders = _lane_riders
		traffic_state.other_racers = _other_racers
	DebugUtils.DebugMsg("Spawned %d traffic riders over %d spots" % [_npcs.size(), _spots.size()])


## Roll one rider's vehicle. The server rolls and ships the result — rolling on
## each peer would give the same rider a different car on every screen.
func _roll_skin_index() -> int:
	var chance := level_manager.current_level.traffic_settings.car_chance
	if _car_count > 0 and randf() < chance:
		return randi() % _car_count
	return randi_range(_car_count, _skins.size() - 1)


## The level's rosters if it named them, otherwise everything in the global folders.
## Skins ship with the game, so peers only need to agree on the order.
func _build_skins() -> void:
	var settings := level_manager.current_level.traffic_settings
	var cars := _roster(settings.car_roster, CAR_SKINS_DIR)
	_car_count = cars.size()
	_skins = []
	_skins.append_array(cars)
	_skins.append_array(_roster(settings.bike_roster, BIKE_SKINS_DIR))


func _roster(roster: Array, fallback_dir: String) -> Array:
	if !roster.is_empty():
		return roster
	var paths := SkinScanner.scan_skin_dir(fallback_dir).values()
	# Folder listing order can differ between editor and exported peers
	paths.sort()
	return paths.map(func(path: String) -> Resource: return load(path))


func stop_traffic() -> void:
	for npc_id in _npcs.keys():
		rpc_despawn_npc.rpc(npc_id)
	_skin_indices.clear()
	_network = null


func _set_debug_count(arg: String) -> void:
	# Null peer in menus — the count still applies to the next session
	if multiplayer.multiplayer_peer != null and !multiplayer.is_server():
		Console.print_line("set_traffic: host only")
		return
	if !arg.is_valid_int():
		Console.print_line("set_traffic: '%s' is not a number" % arg)
		return
	_debug_count = int(arg)
	# Running (_network is set) — respawn at the new count
	if _network != null:
		_restart_traffic()


func _on_all_settings_changed(current_settings: Dictionary) -> void:
	if is_equal_approx(current_settings["traffic_density"], _density):
		return
	_density = current_settings["traffic_density"]
	# Only the server sets _network. Race traffic ignores density, so it's left alone.
	if _network != null and !_for_race:
		_restart_traffic()


func _restart_traffic() -> void:
	var for_race := _for_race
	stop_traffic()
	start_traffic(for_race)


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
	_build_skins()
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
			peer_id, npc_id, _skin_indices[npc_id], npc.global_position, npc.global_basis
		)


#endregion

#region Spawn / despawn (broadcast RPCs, mirrors NPCRaceManager)


@rpc("call_local", "reliable")
func rpc_spawn_npc(npc_id: int, skin_index: int, pos: Vector3, basis: Basis):
	# Our level isn't loaded yet (spawn broadcast raced our spawn_level) — dropped
	# here, recovered by request_traffic_sync once the gamemode enters.
	if !multiplayer.is_server() and !_accept_spawns:
		return
	# Broadcast and resync can both deliver the same rider — first one wins.
	if _npcs.has(npc_id):
		return
	var skin: Resource = _skins[skin_index]

	var npc := NPC_SCENE.instantiate() as NPCRiderEntity
	npc.name = str(npc_id)
	# vehicle_type must land before add_child — _enter_tree drops the other skins.
	if skin is CarSkinDefinition:
		npc.vehicle_type = NPCRiderEntity.VehicleType.CAR
		npc.car_definition = skin
	else:
		npc.vehicle_type = NPCRiderEntity.VehicleType.BIKE
		npc.bike_definition = skin
		# Same round-robin on every peer, so only the id ships
		var def := npc_definitions[(-npc_id + FIRST_ID) % npc_definitions.size()]
		npc.character_definition = def.character_skin
	# Read per peer rather than shipped — every peer has the same level loaded.
	npc.move_speed = level_manager.current_level.traffic_settings.cruise_speed
	npc.paint_colors = level_manager.current_level.traffic_settings.paint_colors
	# On every peer, or a predicting client would bump into a body the server rides through.
	# Traffic rides rails; its ContactArea reports hits instead.
	npc.collision_layer = TRAFFIC_BODY_LAYER_MASK
	npc.collision_mask = 0

	_find_network_node().add_child(npc, true)
	npc.global_transform = Transform3D(basis, pos)
	_npcs[npc_id] = npc
	# Tagged on every peer, not just the server — the HUD runs client-side and uses this
	# to tell ambient traffic from actual competitors.
	npc.add_to_group(UtilsConstants.GROUPS["Traffic"])
	# Drawn once near: the LOD pass shows it on the host, its first sync on a client
	npc.set_drawn(false)

	if !multiplayer.is_server():
		return
	# Seeds the synced yaw ride_to eases from
	npc.teleport_to(pos, basis)
	# Ticked by our _physics_process instead; the follower, not the node, is its pose
	npc.state_machine.set_physics_process(false)
	npc.set_physics_process(false)
	# Synced only to the peers it's near, see _update_lod
	npc.synchronizer.public_visibility = false
	npc.synchronizer.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	_near_peers[npc_id] = PackedInt32Array()
	_pending_delta[npc_id] = 0.0
	_next_lod_ms = 0
	var traffic_state := _traffic_state(npc_id)
	traffic_state.crashed.connect(_on_npc_crashed.bind(npc_id))
	traffic_state.near_missed.connect(player_near_missed.emit)
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
	_near_peers.erase(npc_id)
	_pending_delta.erase(npc_id)


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


## Half a spacing in from each end, so no spot sits at a junction's stop line.
func _add_spots(lane: int) -> void:
	for k in floori(_network.lane_curve(lane).get_baked_length() / SPOT_SPACING):
		var spot := _Spot.new()
		spot.lane = lane
		spot.offset = (k + 0.5) * SPOT_SPACING
		spot.transform = TrafficLaneFollower.new(_network, lane, spot.offset).get_transform()
		_spots.append(spot)
		_spot_weights.append(_network.lanes[lane].weight)
		_weighted_length += SPOT_SPACING * _network.lanes[lane].weight


## A clear spot picked by weight, or null if every spot tried was taken.
func _clear_spot(spots: Array[_Spot], weights: PackedFloat32Array, mover: NPCRiderEntity) -> _Spot:
	for _attempt in PLACEMENT_ATTEMPTS:
		var spot := spots[_rng.rand_weighted(weights)]
		if _is_spot_clear(spot.transform.origin, mover):
			return spot
	return null


#endregion

#region LOD + network culling


## Server: ticks every rider's state, far ones round-robin every far_tick_interval-th tick.
## Clients: hides riders the server stopped syncing to us.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _npcs.is_empty() or multiplayer.multiplayer_peer == null:
		return
	var now := Time.get_ticks_msec()
	var lod_due := now >= _next_lod_ms
	if lod_due:
		_next_lod_ms = now + LOD_INTERVAL_MS
	if !multiplayer.is_server():
		if lod_due:
			_hide_stale_riders(now)
		return
	if lod_due:
		_update_lod()

	_tick_count += 1
	for npc_id in _npcs:
		var dt := _pending_delta[npc_id] + delta
		# Ids are consecutive, so this spreads far riders evenly over the ticks
		if _near_peers[npc_id].is_empty() and posmod(npc_id + _tick_count, far_tick_interval) != 0:
			_pending_delta[npc_id] = dt
			continue
		_pending_delta[npc_id] = 0.0
		var state := _npcs[npc_id].state_machine.current_state
		# Null until StateMachine._ready's deferred transition into idle runs — skip is intentional
		if state != null:
			state.Physics_Update(dt)


## Which peers' players each rider is near, applied only where that changed: the far tick,
## ContactArea, which peers get its sync stream, and whether the host draws it.
func _update_lod() -> void:
	_other_racers.assign(get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]).filter(
		func(racer: Node) -> bool: return !racer.is_in_group(UtilsConstants.GROUPS["Traffic"])
	))
	var players := _other_racers.filter(func(racer: Node) -> bool: return racer is PlayerEntity)
	# Remote peers only; the host (1) has no sync stream to cull, just drawing
	var remote_peers := multiplayer.get_peers()
	var radius_sq := near_radius * near_radius
	var near_counts: Dictionary[int, int] = {}
	for player in players:
		near_counts[int(player.name)] = 0
	for npc_id in _npcs:
		var npc := _npcs[npc_id]
		var near := PackedInt32Array()
		for player in players:
			if player.global_position.distance_squared_to(npc.global_position) < radius_sq:
				near.append(int(player.name))
				near_counts[int(player.name)] += 1
		var was := _near_peers[npc_id]
		if near == was:
			continue
		_near_peers[npc_id] = near
		if near.is_empty() != was.is_empty():
			_traffic_state(npc_id).set_contact(!near.is_empty())
		# A peer that just left still has a player for a frame; visibility for it would error
		for peer in remote_peers:
			if near.has(peer) != was.has(peer):
				npc.synchronizer.set_visibility_for(peer, near.has(peer))
		if near.has(1) != was.has(1):
			npc.set_drawn(near.has(1))
	# Races keep their even spread
	if !_for_race:
		_recycle(players, near_counts)
	_rebalance(players)


## Free roam: moves one far rider to just outside the view of the player with the fewest riders
## near, if that's under near_target, heading their way. One per LOD pass, so it never floods.
func _recycle(players: Array, near_counts: Dictionary[int, int]) -> void:
	var settings := level_manager.current_level.traffic_settings
	var target: PlayerEntity = null
	for player in players:
		var count := near_counts[int(player.name)]
		if count < settings.near_target and (target == null or count < near_counts[int(target.name)]):
			target = player
	if target == null:
		return
	var npc_id := _worst_far_rider()
	# Every rider is already near someone — skip is intentional
	if npc_id == 0:
		return

	var band_max_sq := pow(near_radius + settings.recycle_band, 2.0)
	var spots: Array[_Spot] = []
	var weights := PackedFloat32Array()
	for i in _spots.size():
		var pos := _spots[i].transform.origin
		var to_target := target.global_position - pos
		# Lanes leading away would just carry it off to be recycled again
		if to_target.length_squared() > band_max_sq or to_target.dot(-_spots[i].transform.basis.z) <= 0.0:
			continue
		if _out_of_view(pos, players):
			spots.append(_spots[i])
			weights.append(_spot_weights[i])
	# No road near the player (off-road, or the band misses the network) — skip is intentional
	if spots.is_empty():
		return
	_move_to(npc_id, spots, weights)


## Moves the far rider furthest over its lane's share to a weighted spot out of every player's view.
## Forks can only split the traffic reaching them, so without this the road layout, not
## traffic_weight, decides how busy each road is.
func _rebalance(players: Array) -> void:
	var npc_id := _worst_far_rider()
	# Every far rider is at or under its lane's share — skip is intentional
	if npc_id == 0 or _lane_share(_traffic_state(npc_id).follower.lane) <= _npcs.size() / _weighted_length:
		return
	var spots: Array[_Spot] = []
	var weights := PackedFloat32Array()
	for i in _spots.size():
		if _out_of_view(_spots[i].transform.origin, players):
			spots.append(_spots[i])
			weights.append(_spot_weights[i])
	# A map small enough for players to see all of it — skip is intentional
	if spots.is_empty():
		return
	_move_to(npc_id, spots, weights)


## Riders on a road lane per metre per unit of its weight. Above _npcs.size() / _weighted_length,
## the lane holds more than its share.
func _lane_share(lane: int) -> float:
	return _lane_riders[lane].size() / (_network.lane_curve(lane).get_baked_length() * _network.lanes[lane].weight)


## The far rider on the road lane furthest over its share, or 0 if there's none (ids are negative).
func _worst_far_rider() -> int:
	var worst_id := 0
	var worst_share := -1.0
	for npc_id in _npcs:
		var lane := _traffic_state(npc_id).follower.lane
		# Near someone, down, or inside a junction
		if !_near_peers[npc_id].is_empty() or _npcs[npc_id].npc_state == NPCRiderEntity.NPCState.CRASHED:
			continue
		if _network.lanes[lane].junction >= 0:
			continue
		var share := _lane_share(lane)
		if share > worst_share:
			worst_id = npc_id
			worst_share = share
	return worst_id


func _out_of_view(pos: Vector3, players: Array) -> bool:
	var radius_sq := near_radius * near_radius
	return !players.any(func(player: Node3D) -> bool: return player.global_position.distance_squared_to(pos) < radius_sq)


## Drops a far rider onto a clear weighted pick of `spots`, at cruise speed: it's out of view, so it
## drives in rather than pops in. Every spot tried taken means the next LOD pass tries again.
func _move_to(npc_id: int, spots: Array[_Spot], weights: PackedFloat32Array) -> void:
	var spot := _clear_spot(spots, weights, _npcs[npc_id])
	if spot == null:
		return
	_traffic_state(npc_id).follower = TrafficLaneFollower.new(_network, spot.lane, spot.offset)
	_npcs[npc_id].teleport_to(spot.transform.origin, spot.transform.basis)
	# teleport_to stops it
	_npcs[npc_id].current_speed = _npcs[npc_id].cruise_speed()


func _hide_stale_riders(now: int) -> void:
	for npc in _npcs.values():
		# Freed with an old level until request_traffic_sync purges it — skip is intentional
		if !is_instance_valid(npc):
			continue
		if npc.visible and now - npc.last_sync_ms > SYNC_STALE_MS:
			npc.set_drawn(false)


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


## A place on a road lane a rider can be dropped onto.
class _Spot:
	var lane: int
	var offset: float
	var transform: Transform3D


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if npc_definitions.is_empty():
		issues.append("npc_definitions must not be empty")
	return issues
