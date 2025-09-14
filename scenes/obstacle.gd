@tool
class_name Obstacle extends AnimatableBody3D

@export var variant: int = 0
@export var variants: Array[PackedScene]

@onready var mesh: Node3D = %Mesh
@onready var collision_shape: CollisionShape3D = %CollisionShape3D


func _ready():
    set_mesh()

func set_mesh():
    for child in mesh.get_children():
        child.queue_free()
    
    var new_mesh = variants[variant].instantiate() as Node3D
    mesh.add_child(new_mesh)
    # new_mesh.rotate_y(PI)

    for child in new_mesh.get_children():
        if child is MeshInstance3D:
            # Update collision shape from mesh bounds
            # var aabb = child.mesh.get_aabb()
            var aabb = child.get_aabb()
            collision_shape.shape.size = aabb.size
            collision_shape.position = Vector3(0, aabb.size.y / 2, 0)
            break
