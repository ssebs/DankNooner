@tool
class_name Pickup extends Area3D

enum PickupType {FUEL, SPEED_BOOST}

@export var type: PickupType = PickupType.FUEL
@export var fuel_mesh: PackedScene
@export var boost_mesh: PackedScene

@onready var timer: Timer = $Timer
@onready var mesh: Node3D = %Mesh
@onready var collision_shape: CollisionShape3D = %CollisionShape3D

func _ready():
    set_mesh()

    if Engine.is_editor_hint():
        return
    body_entered.connect(on_body_entered)
    timer.timeout.connect(func():
        queue_free()
    )
    timer.start()

func on_body_entered(body: Node3D):
    print("Hit a thing")
    pass
    # var msg = variants[variant].resource_path
    # if "car" in msg.to_lower():
    #     msg = "Hit a Car!"
    # elif "suv" in msg.to_lower():
    #     msg = "Hit an SUV💀"
    # else:
    #     msg = "Hit something!"

    # if body is Motorcycle:
    #     SignalBus.motorcycle_collision.emit(msg)

func set_mesh():
    # if Engine.is_editor_hint():
    #     return
    for child in mesh.get_children():
        child.queue_free()
    
    var new_mesh: Node3D
    match type:
        PickupType.FUEL:
            new_mesh = fuel_mesh.instantiate() as Node3D
        PickupType.SPEED_BOOST:
            new_mesh = boost_mesh.instantiate() as Node3D
    mesh.add_child(new_mesh)

