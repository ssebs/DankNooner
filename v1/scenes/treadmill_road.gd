@tool
class_name TreadmillRoad extends Node3D

@export var debug = false

@export var road_spawn_count = 10
@export var road_piece: PackedScene = preload("res://assets/LowPolyRoadPack/Models/Road Straight 2.dae")
@export var obstacle_scn: PackedScene = preload("res://scenes/obstacle.tscn")
@export var pickup_scn: PackedScene = preload("res://scenes/pickup.tscn")

@onready var road_spawn: Marker3D = %RoadSpawn
@onready var lane1_spawn: Marker3D = %Lane1
@onready var lane2_spawn: Marker3D = %Lane2
@onready var hazard_spawn: Marker3D = %HazardPos

var offset = 10
var amount_moved = 0.0
var road_pieces: Array[Node3D]

var spawn_chance_base = 0.25 # 15% base chance
var difficulty_modifier = 1.0 # Increases over time

func _ready():
    spawn_roads(road_spawn_count)
    if debug:
        # spawn_obstacle(lane1_spawn if randi() % 2 == 0 else lane2_spawn)
        SignalBus.speed = 120

func spawn_roads(count: int):
    if road_spawn == null:
        return
    for i in range(count):
        var piece = road_piece.instantiate() as Node3D
        road_spawn.add_child(piece)
        road_pieces.append(piece)
        piece.global_position.z += i * offset

func _physics_process(delta):
    if road_spawn == null || Engine.is_editor_hint():
        return
    var move_amount = lerpf(0, delta * (SignalBus.speed / 5), 0.5)
    
    # Move all road pieces forward
    for piece in road_pieces:
        piece.global_position.z += move_amount
    
    var last_piece = road_pieces[-1]
    
    if last_piece.global_position.z > offset:
        # Calculate new position: in front of the current first piece
        var first_piece = road_pieces[0]
        last_piece.global_position.z = first_piece.global_position.z - offset
        
        # Move the piece from end to beginning of array (a=>b=>c becomes c=>a=>b)
        road_pieces.pop_back() # Remove from end
        road_pieces.push_front(last_piece) # Add to beginning
        
        # Spawn obstacles when a piece cycles
        var current_spawn_chance = spawn_chance_base * difficulty_modifier
        if randf() < current_spawn_chance:
            var is_left_lane := randi() % 2 == 0
            spawn_obstacle(first_piece, lane1_spawn if is_left_lane else lane2_spawn, false, is_left_lane)
        
        if randf() < current_spawn_chance:
            # TODO: random chance to spawn pickup
            spawn_obstacle(first_piece, hazard_spawn, true)
            # spawn_pickup(first_piece, hazard_spawn, 0 if randi() % 2 else 1)
        
        # clear old obstacles
        for child in last_piece.get_children():
            if child is Obstacle:
                child.queue_free()

func spawn_pickup(parent_node: Node3D, lane_spawn: Marker3D, type: Pickup.PickupType):
    if Engine.is_editor_hint():
        return
    var pickup_item = pickup_scn.instantiate() as Pickup
    pickup_item.type = type

    pickup_item.global_position = lane_spawn.global_position
    parent_node.add_child(pickup_item)

func spawn_obstacle(parent_node: Node3D, lane_spawn: Marker3D, is_hazard := false, should_flip := false):
    if lane_spawn == null || obstacle_scn == null || Engine.is_editor_hint():
        print('something is null spawn_obstacle')
        return
    
    var thing = obstacle_scn.instantiate() as Obstacle
    if is_hazard:
        thing.variant = randi_range(thing.variant_split_idx, thing.variants.size() - 1)
    else:
        thing.variant = randi_range(0, thing.variant_split_idx)
    thing.global_position = lane_spawn.global_position
    parent_node.add_child(thing)
    if should_flip:
        thing.rotate_y(deg_to_rad(180))
