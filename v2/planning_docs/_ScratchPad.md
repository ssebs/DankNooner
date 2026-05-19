# Scratch Pad
---


## Cleanup gamemode objective / events

**Problems**:

- Move GameModeTask logic from tutorial_gamemode.gd to the event_start_circle.gd
  - Enter()
  	_tasks = _start_circle.get_tasks()
  	for task in _tasks:
  		task._gamemode = self
  - _wire_objective_signals() 
  - _on_trigger_entered()

- managers\gamemodes\tasks\stoppie_duration_task.gd
  - How does the state: Dictionary work?