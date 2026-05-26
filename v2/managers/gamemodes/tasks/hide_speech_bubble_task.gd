@tool
## Hides a SpeechBubble. Completes immediately. Drop sequentially after a
## ConcurrentTaskRunner that paired ShowSpeechBubbleTask with a gating task
## (e.g. PerformTrickTask) — the bubble stays visible during the trick and
## hides as soon as it finishes.
class_name HideSpeechBubbleTask extends GameModeTask

@export var speech_bubble: SpeechBubble


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	speech_bubble.rpc_hide.rpc()


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if speech_bubble == null:
		issues.append("speech_bubble must be set")
	return issues
