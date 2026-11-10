@tool
## Root script of every level scene. Register the level in LevelManager (LevelName enum,
## possible_levels, level_name_map). Needs player_entity_scene and player_spawn (riders spawn as
## its children) unless no_player_spawn_needed; npc_nav_region only for levels with NPC races.
class_name LevelDefinition extends Node3D

## Hack - for ui background levels where the player doesn't need to spawn
@export var no_player_spawn_needed: bool
@export var player_entity_scene: PackedScene = preload("res://player/player_entity.tscn")
## Riders spawn as its children; FreeRoamGameMode spreads peers across its slots on entry.
@export var player_spawn: SpawnGrid
## Per-map traffic density. Swap in a different .tres to make this map busier,
## quieter, or car-heavy. Maps with no baked TrafficNetwork get no traffic regardless.
@export var traffic_settings: TrafficSettings = preload(
	"res://resources/traffic/settings/default_traffic_settings.tres"
)

## Road navmesh the race bots' racing line is baked on. Only levels with NPC races need one.
@export var npc_nav_region: NPCNavRegion

## Started as soon as the level loads, with no start circle to drive into (e.g. the tutorial).
@export var auto_start_event: GameModeEvent

## Set in level_manager
var level_manager: LevelManager
var level_name: LevelManager.LevelName


func _ready():
	if Engine.is_editor_hint():
		return
	for node: Node3D in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EditorHideable"]):
		node.visible = true
	# WebGL can't afford the post-process pass (glow + adjustments) or shadow maps. Neon edges still
	# draw, unbloomed. Runs in warmup too, so warmed shader variants match this.
	if OS.has_feature("web"):
		for world_env: WorldEnvironment in find_children("*", "WorldEnvironment", true, false):
			world_env.environment.glow_enabled = false
			world_env.environment.adjustment_enabled = false
		for light: Light3D in find_children("*", "Light3D", true, false):
			light.shadow_enabled = false

func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if no_player_spawn_needed:
		return issues

	if player_entity_scene == null:
		issues.append("player_entity_scene must not be empty")
	if player_spawn == null:
		issues.append("player_spawn must not be empty")

	return issues
