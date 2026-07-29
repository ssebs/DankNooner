@tool
## Free-roam traffic behavior: circulate the road network forever. Follows the
## lane like the race state, but picks a random exit at junctions (via
## TrafficRouteGraph, since the road generator can't link through them), tucks
## in behind whatever is ahead instead of overtaking, and reports crashes /
## getting wedged to NPCTrafficManager, which owns the recovery.
class_name NPCTrafficState extends State

## Hit another racer — the manager wipes the rider out, respawns it, and takes
## the racer we hit down with us if it's a player.
signal crashed(victim: Node3D)
## No meaningful progress for a while — the manager relocates the rider.
signal stuck

@export var npc: NPCRiderEntity
## A racer within this range and forward cone that's slower than us gets
## followed rather than passed (traffic doesn't overtake in v1).
@export var follow_detect_range: float = 12.0
@export var follow_detect_angle: float = 0.7
## How close to the end of an unlinked lane before picking the next one.
@export var junction_proximity: float = 4.0
## Speed difference (m/s) that makes contact an actual impact — riders queueing
## nose-to-tail brush at matched speed and shouldn't both wipe out for it.
@export var contact_min_speed_delta: float = 6.0
## Report stuck after moving less than this (metres) over this window (seconds).
@export var stuck_window: float = 3.0
@export var stuck_min_progress: float = 2.0

## Set by NPCTrafficManager right after spawn — junction routing needs it.
var route_graph: TrafficRouteGraph

var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position
	npc.hit_by_racer.connect(_on_hit_by_racer)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.hit_by_racer.disconnect(_on_hit_by_racer)


func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return

	var can_drive := npc.driving and npc.npc_state != NPCRiderEntity.NPCState.CRASHED
	if !can_drive:
		npc.coast_to_stop(delta)
		npc.apply_gravity_and_move(delta)
		return

	# Lanes may not have been built yet at spawn, or we just got teleported.
	if !is_instance_valid(npc.lane_agent.current_lane):
		npc.lane_agent.assign_nearest_lane()

	_pick_next_lane_at_junction()

	var target := npc.lane_point_ahead(npc.steer_lookahead())
	var target_speed := npc.lane_speed()
	# Match the rider ahead so we queue up behind it instead of ramming it.
	var blocker := npc.nearest_racer_ahead(follow_detect_range, follow_detect_angle)
	if blocker != null:
		target_speed = minf(target_speed, npc.horizontal_speed(blocker))
	npc.steer_toward(target, target_speed, delta)
	npc.apply_gravity_and_move(delta)

	_check_contact()
	_check_stuck(delta)


## close_to_lane_end only reports true for lanes with no lane_next — exactly the
## junction (and road-narrowing) case the route graph exists to cover.
func _pick_next_lane_at_junction() -> void:
	if !npc.lane_agent.close_to_lane_end(junction_proximity, RoadLaneAgent.MoveDir.FORWARD):
		return
	var successors := route_graph.next_lanes(npc.lane_agent.current_lane)
	if successors.is_empty():
		# Dead end the graph didn't cover — grab whatever lane is nearest.
		npc.lane_agent.assign_nearest_lane()
		return
	npc.lane_agent.assign_lane(successors.pick_random())


## Someone rode into us. Nothing to pass along — the hitter already took itself
## out on its own side of the collision.
func _on_hit_by_racer(_hitter: Node3D) -> void:
	if npc.npc_state == NPCRiderEntity.NPCState.CRASHED:
		return
	crashed.emit(null)


## Riding into another racer wipes us out — the manager handles the recovery.
func _check_contact() -> void:
	for i in npc.get_slide_collision_count():
		# Every physics collider is a Node3D, so this cast is just for typing.
		var collider := npc.get_slide_collision(i).get_collider() as Node3D
		if !collider.is_in_group(UtilsConstants.GROUPS["Racers"]):
			continue
		if absf(npc.current_speed - npc.horizontal_speed(collider)) < contact_min_speed_delta:
			continue
		crashed.emit(collider)
		return


## Wedged against geometry (or spinning in place) — ask for a relocate.
func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < stuck_window:
		return
	var progress := npc.global_position.distance_to(_stuck_anchor)
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position
	if progress < stuck_min_progress:
		stuck.emit()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
