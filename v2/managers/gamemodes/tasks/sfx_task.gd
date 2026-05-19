@tool
## Plays an SFX from AudioManager on enter, then advances based on `advance_mode`.
##
## - IMMEDIATELY: advance the same tick (fire-and-forget).
## - AFTER_DURATION: hold for `duration_sec` then stop the sound and advance.
##   Use with a looping SoundEvent (its `loop` export) to loop for a fixed time.
## - WHEN_FINISHED: advance when the stream's natural length elapses.
class_name SFXTask extends GameModeTask

enum AdvanceMode { IMMEDIATELY, AFTER_DURATION, WHEN_FINISHED }

@export var sound: AudioManager.Sfx
@export var advance_mode: AdvanceMode = AdvanceMode.IMMEDIATELY
## Only used by AFTER_DURATION.
@export var duration_sec: float = 0.0


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	_rpc_play_sfx.rpc_id(int(player.name), sound)
	state["t"] = _get_wait_seconds()


func check(_player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	if advance_mode == AdvanceMode.IMMEDIATELY:
		return true
	state["t"] = state.get("t", 0.0) - delta
	return state["t"] <= 0.0


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	# AFTER_DURATION may have started a looping sound that needs to be cut off.
	# WHEN_FINISHED's stream is already done by definition.
	if advance_mode == AdvanceMode.AFTER_DURATION:
		_rpc_stop_sfx.rpc_id(int(player.name), sound)


func _get_wait_seconds() -> float:
	match advance_mode:
		AdvanceMode.AFTER_DURATION:
			return duration_sec
		AdvanceMode.WHEN_FINISHED:
			var ev := _runner.audio_manager.get_sound_event(sound)
			return ev.stream.get_length() if ev.stream != null else 0.0
	return 0.0


@rpc("call_local", "reliable")
func _rpc_play_sfx(id: int):
	_runner.audio_manager.play_sfx(id)


@rpc("call_local", "reliable")
func _rpc_stop_sfx(id: int):
	_runner.audio_manager.stop_sfx(id)
