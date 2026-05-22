@tool
## Base for composite runners (Sequential, Concurrent).
##
## Holds the deps shared by every runner so leaf tasks can address them via
## `_runner.spawn_manager` / `_runner.task_hud` / `_runner.audio_manager`
## regardless of which runner type owns them.
##
## Subclasses override start/update/stop/notify_* to drive the per-peer walk.
class_name TaskRunner extends GameModeTask

## Notifies the host gamemode that a crashed peer should be respawned (gamemode
## owns the actual delay timer). Respawn target is read from the player's own
## persistent `rb_respawn_transform`, set by TeleportTask via SpawnManager.
signal respawn_requested(peer_id: int)

## Set by the host gamemode (or a parent runner, for nested cases) before
## `start()`. Not @exported because the runner lives in a level scene while the
## managers live in main_game.tscn — cross-scene NodePaths would be fragile.
var spawn_manager: SpawnManager
var task_hud: TutorialHUD
var audio_manager: AudioManager


## Wire `_runner` on every child task and propagate deps + recurse into nested
## runners. Runs on every peer (host gamemode calls this in Enter()) so RPCs
## targeting clients can resolve `_runner.audio_manager` etc — the per-peer
## `start()` only runs on the server and can't do this for clients.
func wire_task_refs() -> void:
	for c in get_children():
		if c is GameModeTask:
			c._runner = self
		if c is TaskRunner:
			c.spawn_manager = spawn_manager
			c.task_hud = task_hud
			c.audio_manager = audio_manager
			c.wire_task_refs()
