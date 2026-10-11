@tool
class_name SteamManager extends BaseManager

## Null when Steam is unavailable (Web, no client). Via Engine: a static `Steam` ref won't parse on Web
var steam: Object


func _ready():
	if Engine.is_editor_hint():
		return

	_init_steam()


## Steam is up and connected to Steam's servers; each feature decides what false means
func is_logged_in() -> bool:
	return steam != null and steam.loggedOn()


func _init_steam():
	if !Engine.has_singleton("Steam"):
		DebugUtils.DebugMsg("Steam: not available on this build")
		return

	# App ID from project settings, embedded callbacks. No restartAppIfNecessary(): it blocks offline play
	var result: Dictionary = Engine.get_singleton("Steam").steamInitEx(0, true)
	if result["status"] != 0:
		DebugUtils.DebugMsg("Steam: init failed (%s): %s" % [result["status"], result["verbal"]])
		return

	steam = Engine.get_singleton("Steam")
