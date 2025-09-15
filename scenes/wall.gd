@tool
class_name Wall extends Area3D


func _ready():
    body_entered.connect(on_body_entered)

func on_body_entered(body: Node3D):
    if body is Motorcycle:
        SignalBus.motorcycle_collision.emit("Hit the wall!")
