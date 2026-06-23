@tool
class_name CurvedRoad extends Node3D

@export_range(1, 4) var sharpness: int = 1

@export var meshes: Dictionary[int,ArrayMesh]
