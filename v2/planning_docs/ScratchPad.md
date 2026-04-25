# Scratch Pad
---



using this context @planning_docs\AnimationController.md @planning_docs\Skins.md @planning_docs\PlayerController.md player/bikes/scripts/bike_skin.gd player/controllers/animation_controller.gd player/player_entity.gd resources/bikes/bike_skin_definition.gd, help solve this problem in my game:

@resources\bikes\bike_skin_definition should have a new `mods` Array that contains a new `BikeMod` Resources that i can add to a `BikeSkin`.

One of these mods, `ColorMod`, should overrite the colors. my current color system is a pain since i need to duplicate positional data, etc. e.g. @resources\bikes\skins\sport_default_skin_definition.tres @resources\bikes\skins\sport_black_skin_definition.tres 

I want to use the same `skin_color.gd` system, so i can create a new colormod, and assign a Array[Color] like i can now.

follow  @claude.md best practices/patterns.