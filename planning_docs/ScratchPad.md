# Scratch Pad
---

- @export for other states so I can reference them in a state
    - ex
```
Option 2: Export typed references (hybrid approach)
Keep dynamic registration but expose specific states you reference often:
# state_machine.gd
var states: Dictionary = {}
var main_menu_state: MainMenuState
var settings_menu_state: SettingsMenuState

func _ready():
    for child in get_children():
        if child is State:
            states[child.name] = child
            
            # Cache typed references
            if child is MainMenuState:
                main_menu_state = child
            elif child is SettingsMenuState:
                settings_menu_state = child

func transition_to(state: State):
    # ... transition logic
```