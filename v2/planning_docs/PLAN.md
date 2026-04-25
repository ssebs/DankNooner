# Plan: BikeMod system + ColorMod variants

Replace per-variant `BikeSkinDefinition` clones with a single base definition + composable `BikeMod` resources. First mod is `ColorMod`; future mods (suspension, exhaust, decals) plug into the same array.

## Goal

- One `BikeSkinDefinition` per bike model (e.g. `sport_default`) holds all positional/physics/pose data.
- Color variants become tiny standalone `ColorMod` `.tres` files (just `Array[Color]`).
- `BikeSkinDefinition.mods: Array[BikeMod]` applies on top of the base at spawn.
- Delete `sport_black_skin_definition.tres`; replace with `sport_black_color_mod.tres`.

## File layout

```
resources/bikes/
├── bike_skin_definition.gd       # add `mods` array
├── mods/
│   ├── bike_mod.gd               # base Resource
│   └── color_mod.gd              # overrides colors via SkinColor
└── skins/
    ├── sport_default_skin_definition.tres   # unchanged base
    └── color_mods/
        └── sport_black_color_mod.tres       # NEW — replaces sport_black skin def
```

## Steps

### 1. `resources/bikes/mods/bike_mod.gd` (new)

```gdscript
@tool
class_name BikeMod extends Resource

## Apply this mod's effect to a BikeSkin. Override in subclasses.
func apply(_bike_skin: BikeSkin) -> void:
    pass
```

### 2. `resources/bikes/mods/color_mod.gd` (new)

```gdscript
@tool
class_name ColorMod extends BikeMod

## Slot colors (use TRANSPARENT to skip a slot, same convention as BikeSkinDefinition.colors)
@export var colors: Array[Color] = []

func apply(bike_skin: BikeSkin) -> void:
    for i in colors.size():
        if colors[i] != Color.TRANSPARENT:
            bike_skin.mesh_skin.update_slot_color(i, colors[i])
```

Reuses `SkinColor.update_slot_color()` — no duplication.

### 3. `resources/bikes/bike_skin_definition.gd`

Add under the existing `Mesh` group (or new `Mods` group):

```gdscript
@export_group("Mods")
@export var mods: Array[BikeMod] = []
```

`colors` field stays as the base/default colors. `ColorMod` overrides per slot.

### 4. `player/bikes/scripts/bike_skin.gd`

Add a new step in `_apply_definition()` after `_set_mesh_colors()`:

```gdscript
func _apply_definition():
    _spawn_mesh()
    _set_mesh_colors()
    _apply_mods()
    _create_steering_handlebar_proxy()
    if Engine.is_editor_hint():
        mesh_skin.owner = self


func _apply_mods():
    for mod in skin_definition.mods:
        if mod == null:
            continue
        mod.apply(self)
```

Order matters: base colors first, then mods stack on top.

### 5. Migrate `sport_black`

- Create `resources/bikes/skins/color_mods/sport_black_color_mod.tres` as a `ColorMod` with:
  ```
  colors = [Color(0.03, 0.03, 0.03, 1), Color(0.185, 0.5087501, 0.74, 1)]
  ```
- Delete `resources/bikes/skins/sport_black_skin_definition.tres`.
- Anywhere referencing `sport_black_skin_definition.tres`, switch to `sport_default_skin_definition.tres` + push `sport_black_color_mod.tres` into a `mods` array (either on the definition itself for a fixed variant, or per-player at spawn — see follow-up).

### 6. Update docs

- `planning_docs/Skins.md`: add a "Mods" section under `BikeSkinDefinition` describing `mods: Array[BikeMod]`, document `ColorMod`, note that color variants now live as standalone `ColorMod` `.tres` files.

## Verification

- Open `player_entity.tscn`, set `bike_definition` to `sport_default` and add `sport_black_color_mod` to its `mods` array → bike renders black with default pose/markers/physics.
- Remove the mod → bike returns to default red.
- Editor reload of `bike_skin.gd` re-applies cleanly (the `skin_definition` setter already calls `_apply_definition` in editor).

## Out of scope (follow-ups)

- Player loadout plumbing (`PlayerDefinition`/`SaveManager`) so each player can pick their own `ColorMod` independent of the base definition. Today the plan only supports mods authored on the definition itself.
- Save/load of `BikeSkinDefinition` to disk — TODO already noted in the source; not blocked by this plan.
- Additional mods (`SuspensionMod`, `ExhaustMod`, `DecalMod`) — slot in by extending `BikeMod` and overriding `apply()`.
