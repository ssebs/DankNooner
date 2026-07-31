@tool
## Per-level traffic density. Assign one to a LevelDefinition's `traffic_settings`
## to override NPCTrafficManager's own exports for that map; leave it null and the
## manager's values apply. Read on entry, in start_traffic().
class_name TrafficSettings extends Resource

## Riders to spawn. Still capped by the number of distinct lanes in the level's
## road network — traffic spreads one rider per lane.
@export var traffic_count: int = 8
## Odds a given vehicle is a car rather than a bike + rider.
@export_range(0.0, 1.0, 0.05) var car_chance: float = 0.5
## Base move speed handed to every rider on this map.
@export var cruise_speed: float = 22.0
## Bikes traffic may roll on this map. Leave empty and every bike skin in
## res://resources/bikes/skins/ is fair game.
@export var bike_roster: Array[BikeSkinDefinition] = []
## Cars traffic may roll on this map. Leave empty and every car skin in
## res://resources/cars/skins/ is fair game. A roster only limits what rolls —
## car_chance still decides how often a car comes up at all.
@export var car_roster: Array[CarSkinDefinition] = []
## Paint pool for spawned NPCs — each rider repaints its skin's first color slot
## with one of these. Empty keeps whatever color the skin was authored with.
## Applies to race bots on this map too, not just traffic.
@export var paint_colors: Array[Color] = []
