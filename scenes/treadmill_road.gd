@tool
class_name TreadmillRoad extends Node3D

@export var cars_to_spawn: Array[PackedScene] = [
    preload("res://assets/vehicles/Car01.glb"),
    preload("res://assets/vehicles/Police Car.glb")
]

@export var road_spawn_count = 6
@export var road_piece: PackedScene = preload("res://assets/LowPolyRoadPack/Models/Road Straight 2.dae")

@onready var road_spawn: Marker3D = %RoadSpawn

var offset = 10
var road_pieces: Array[Node3D]

func _ready():
    spawn_roads(road_spawn_count)

func spawn_roads(count: int):
    if road_spawn == null:
        return
    for i in range(count):
        var piece = road_piece.instantiate() as Node3D
        road_spawn.add_child(piece)
        road_pieces.append(piece)
        piece.global_position.z -= i * offset

func _physics_process(delta):
    if road_spawn == null || SignalBus.speed == null:
        return
    if road_spawn.position.z > len(road_pieces) * offset:
        road_spawn.position.z = 0
    
    road_spawn.position.z += lerpf(0, delta * (SignalBus.speed / 5), 0.5)
