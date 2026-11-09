@tool
## Crash on purpose, the way `crash_hint` names (a CrashController.trigger_crash hint_key, e.g.
## "FEED_BAILED_BRAKE_GRAB"). The runner skips a crashed rider and respawns them at their respawn
## point (the lesson's TeleportTask marker) as usual, so this passes once they're back up from
## that crash. Any other crash is just a retry.
class_name CrashTask extends GameModeTask

@export var crash_hint: String = "FEED_BAILED_BRAKE_GRAB"
@export var objective_key: String = ""


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	# The hint outlives its crash: drop an earlier one so only a crash during this step counts.
	player.crash_hint = ""


func check(player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return player.crash_hint == crash_hint


func get_objective_text() -> String:
	return tr(objective_key)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if crash_hint.is_empty():
		issues.append("crash_hint must be set")
	if objective_key.is_empty():
		issues.append("objective_key must be set")
	return issues
