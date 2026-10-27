@tool
## Per-level traffic density. Assign one to a LevelDefinition's `traffic_settings`
## to override NPCTrafficManager's own exports for that map; leave it null and the
## manager's values apply. Read on entry, in start_traffic().
class_name TrafficSettings extends Resource

## Riders to spawn across the level's whole TrafficNetwork. Spread over its road lanes by
## TrafficRoad.traffic_weight; only skips a rider when no clear spot turns up.
@export var traffic_count: int = 8
## Free roam: a player with fewer riders near than this gets far-off ones recycled toward
## them. Doesn't add riders — traffic_count is still the total.
@export var near_target: int = 6
## Free roam: how far beyond NPCTrafficManager.near_radius recycled riders land. Out of every
## player's view, so they drive in rather than pop in.
@export var recycle_band: float = 60.0
## Riders to spawn during a race event with enable_traffic instead of traffic_count. Racing
## through free-roam density tends to be a wall rather than a challenge, so this is
## usually the thinner number.
@export var race_traffic_amount: int = 4
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
