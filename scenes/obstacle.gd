@tool
class_name Obstacle extends Area3D

@export var variant: int = 0
@export var variants: Array[PackedScene] = [
    preload("res://assets/vehicles/Car01.glb"),
    preload("res://assets/vehicles/Police Car.glb"),
    preload("res://assets/vehicles/SUV.glb")
]

@onready var timer: Timer = $Timer
@onready var mesh: Node3D = %Mesh
@onready var collision_shape: CollisionShape3D = %CollisionShape3D

func _ready():
    set_mesh()
    # collision_shape.
    body_entered.connect(on_body_entered)
    timer.timeout.connect(finish)
    timer.start()

func on_body_entered(body: Node3D):
    var msg = variants[variant].resource_path
    if "car" in msg.to_lower():
        msg = "Hit a Car!"
    elif "suv" in msg.to_lower():
        msg = "Hit an SUV💀"
    else:
        msg = "Hit something!"

    if body is Motorcycle:
        SignalBus.motorcycle_collision.emit(msg)

func finish():
    queue_free()

func set_mesh():
    for child in mesh.get_children():
        child.queue_free()
    
    var new_mesh = variants[variant].instantiate() as Node3D
    mesh.add_child(new_mesh)
    # new_mesh.rotate_y(PI)

    for child in new_mesh.get_children():
        if child is MeshInstance3D:
            # Update collision shape from mesh bounds
            var aabb = child.get_aabb()
            collision_shape.shape.size = aabb.size
            collision_shape.position = Vector3(0, aabb.size.y / 2, 0)
            break
