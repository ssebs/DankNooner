extends RigidBody2D

@onready var timer: Timer = %Timer

const FORCE = 1000

func _ready():
    timer.timeout.connect(on_timeout)
    timer.start()
    self.apply_central_impulse(Vector2.UP * FORCE)

func on_timeout():
    queue_free()

# func _physics_process(delta):