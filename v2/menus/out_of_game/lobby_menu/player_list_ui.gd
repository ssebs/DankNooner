@tool
class_name PlayerListUI extends VBoxContainer

@export var player_list_item_scene: PackedScene = preload(
	"res://menus/out_of_game/lobby_menu/player_list_item.tscn"
)


## Update the player list UI from a dictionary of player_id -> PlayerDefinition
func update_from_dict(players: Dictionary):
	# Remove players no longer in the dict
	for child in get_children():
		var child_id = int(child.name)
		if !players.has(child_id):
			child.queue_free()

	# Add or update players
	for player_id in players:
		var player_def: PlayerDefinition = players[player_id]
		var node_name = str(player_id)

		if has_node(node_name):
			# Update existing player
			var player_li = get_node(node_name) as PlayerListItem
			player_li.player_definition = player_def
			player_li.update_ui_from_player_definition()
		else:
			# Add new player
			_add_player_item(player_id, player_def)


## Clear all players from the list
func clear():
	for child in get_children():
		child.queue_free()


## Add a player item to the list
func _add_player_item(player_id: int, player_def: PlayerDefinition):
	var player_li = player_list_item_scene.instantiate() as PlayerListItem
	player_li.player_definition = player_def
	add_child(player_li)
	player_li.name = str(player_id)

	if player_id == 1:
		player_li.host_label.text = "PLAYER_IS_HOST_LABEL"
	elif player_id == multiplayer.get_unique_id():
		player_li.host_label.text = "YOU_LABEL"
	else:
		player_li.host_label.text = ""

	player_li.update_ui_from_player_definition()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_list_item_scene == null:
		issues.append("player_list_item_scene must not be empty")

	return issues
