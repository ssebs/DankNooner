extends RigidBody2D

@onready var timer: Timer = %Timer

func _ready():
    timer.timeout.connect(on_timeout)

func shoot_bullet(dir: Vector2, force = 1000):
    self.apply_central_impulse(dir * force)
    timer.start()

func on_timeout():
    queue_free()

# TODO: Add hitcheck
