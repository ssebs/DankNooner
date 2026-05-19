@tool
## Plays an SFX from AudioManager on enter, then auto-advances.
class_name SFXTask extends GameModeTask

@export var sound: AudioManager.Sfx


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	# Server-only path: only the server walks tasks, but play_sfx must run on
	# every peer. RPC into a local helper that calls the manager.
	_rpc_play_sfx.rpc_id(int(player.name), sound)


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


@rpc("call_local", "reliable")
func _rpc_play_sfx(id: int):
	_runner.audio_manager.play_sfx(id)
