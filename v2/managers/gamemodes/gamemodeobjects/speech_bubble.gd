@tool
## In-world 2D billboard for challenge prompts. Lives in level scenes as a
## GameModeObject; tasks drive its text/visibility via RPC so all peers see
## the same thing (host-only task hooks would otherwise leave clients dark).
##
## Use with `ShowSpeechBubbleTask` to set text + show, or call the rpc_*
## methods directly from any host-side gamemode code.
class_name SpeechBubble extends GameModeObject

## Editor-visible preview text. Tasks call `rpc_set_text` at runtime to override.
@export var text: String = "...":
	set(value):
		text = value
		_apply_text()


func _ready() -> void:
	super._ready()
	_apply_text()


func _apply_text() -> void:
	var label := get_node_or_null("Label3D") as Label3D
	if label != null:
		label.text = text


@rpc("call_local", "reliable")
func rpc_set_text(s: String) -> void:
	text = s


@rpc("call_local", "reliable")
func rpc_show() -> void:
	is_active = true


@rpc("call_local", "reliable")
func rpc_hide() -> void:
	is_active = false
