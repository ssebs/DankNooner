@tool
class_name TreadmillRoad extends Node3D

@export var cars_to_spawn: Array[PackedScene] = [
    preload("res://assets/vehicles/Car01.glb"),
    preload("res://assets/vehicles/Police Car.glb")
]

@export var road_spawn_count = 6
@export var road_piece: PackedScene = preload("res://assets/LowPolyRoadPack/Models/Road Straight 2.dae")

var road_pieces: Array[Node3D]

func _ready():
    spawn_roads(road_spawn_count)

func spawn_roads(count: int):
    for i in range(count):
        var piece = road_piece.instantiate() as Node3D
        add_child(piece)
        piece.global_position.z -= i * 10
        road_pieces.append(piece)
