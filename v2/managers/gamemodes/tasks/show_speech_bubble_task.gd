@tool
## Shows a SpeechBubble with given text. Completes immediately by default so it
## can ride in a ConcurrentTaskRunner next to a PerformTrickTask (or any other
## gating task) without blocking. Set `duration > 0` to make it block in a
## sequential runner for a delay (e.g. an outro "Nice!" beat).
##
## Does NOT hide the bubble — pair with a `HideSpeechBubbleTask` placed
## sequentially after the trick task to clean up.
class_name ShowSpeechBubbleTask extends GameModeTask

@export var speech_bubble: SpeechBubble
## Localization key. Falls back to the raw string if no translation exists.
@export var text_key: String = ""
## How long to keep this task active before it reports done. 0 = complete next
## frame (passive display alongside parallel tasks).
@export var duration: float = 0.0


func on_enter(_player: PlayerEntity, state: Dictionary) -> void:
	state["t"] = 0.0
	speech_bubble.rpc_set_text.rpc(tr(text_key))
	speech_bubble.rpc_show.rpc()


func check(_player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	state["t"] = state.get("t", 0.0) + delta
	return state["t"] >= duration


func get_objective_text() -> String:
	if text_key == "":
		return ""
	return tr(text_key)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if speech_bubble == null:
		issues.append("speech_bubble must be set")
	return issues
