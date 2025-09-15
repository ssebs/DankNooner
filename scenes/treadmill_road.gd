@tool
class_name TreadmillRoad extends Node3D

@export var debug = false
@export var cars_to_spawn: Array[PackedScene] = [
    preload("res://assets/vehicles/Car01.glb"),
    preload("res://assets/vehicles/Police Car.glb")
]

@export var road_spawn_count = 6
@export var road_piece: PackedScene = preload("res://assets/LowPolyRoadPack/Models/Road Straight 2.dae")
@export var obstacle_scn: PackedScene = preload("res://scenes/obstacle.tscn")

@onready var road_spawn: Marker3D = %RoadSpawn
@onready var lane1_spawn: Marker3D = %Lane1
@onready var lane2_spawn: Marker3D = %Lane2

var offset = 10
var road_pieces: Array[Node3D]

func _ready():
    spawn_roads(road_spawn_count)
    if debug:
        spawn_obstacle(lane1_spawn if randi() % 2 == 0 else lane2_spawn)

func spawn_obstacle(lane_spawn: Marker3D):
    if lane_spawn == null || obstacle_scn == null:
        print('something is null spawn_obstacle')
        return
    
    # Remove old obstacles if there are any 
    for child in lane_spawn.get_children():
        child.queue_free()
    
    var thing = obstacle_scn.instantiate() as Obstacle
    thing.variant = randi_range(0, thing.variants.size() - 1)
    lane_spawn.add_child(thing)
    

func spawn_roads(count: int):
    if road_spawn == null:
        return
    for i in range(count):
        var piece = road_piece.instantiate() as Node3D
        road_spawn.add_child(piece)
        road_pieces.append(piece)
        piece.global_position.z -= i * offset

func _physics_process(delta):
    if road_spawn == null || Engine.is_editor_hint():
        return
    if road_spawn.position.z > len(road_pieces) * offset:
        road_spawn.position.z = 0
        lane1_spawn.position.z = 0
        lane2_spawn.position.z = 0
        spawn_obstacle(lane1_spawn if randi() % 2 == 0 else lane2_spawn)
    
    var move_amount = lerpf(0, delta * (SignalBus.speed / 5), 0.5)
    road_spawn.position.z += move_amount
    lane1_spawn.position.z += move_amount
    lane2_spawn.position.z += move_amount
