@tool
class_name ExhaustFlameParticles extends Node3D

## Self-contained exhaust flame flicker driven by its own AnimationPlayer. pop()/burble()
## strobe FlameMesh:visible — fire-and-forget, played on each exhaust pop / decel burble.

@export_tool_button("Play Pop") var _play_pop_btn = pop

@onready var _anim: AnimationPlayer = %AnimationPlayer


func pop() -> void:
	_anim.play("pop")


func burble() -> void:
	_anim.play("burble")


## Cut the sustained burble when its audio stops. RESET forces FlameMesh off (stopping mid-strobe
## could leave it stuck visible). Guarded so a short pop mid-flight isn't interrupted.
func stop_burble() -> void:
	if _anim.current_animation == "burble":
		_anim.play("RESET")
