## State Machine manages transitions between States. 
## Auto-registers all child States
## Child states can transition by emitting transitioned()
class_name StateMachine extends Node

## After Enter() of new transition
signal state_transitioned(new_state: State)

@export var initial_state: State
@export var is_debug: bool = true

## When a new State is registered, add it to the dictionary
var states: Dictionary[String, State] = {}
var current_state: State

func _ready():
    for child in get_children():
        if child is State:
            if is_debug:
                print("Found %s, registering to this state machine", % child)
            register_state(child)
    
    if initial_state:
        _transition_to(initial_state)

#region Public API
## Add state to Dict & connect the transitioned signal
func register_state(new_state: State):
    var ok = states.set(new_state.state_name, new_state)
    if !ok:
        printerr("Failed to register state %s" % new_state)
        return
    new_state.transitioned.connect(_transition_to)

## Remove state from Dict & disconnect transitioned signal
func deregister_state(state: State):
    state.transitioned.disconnect(_transition_to)
    states.erase(state.state_name)

## TBD, but shouldn't be used
func request_state_change(new_state: State):
    print_debug("you should not be calling this! %s" % new_state)
    return

#endregion

## Updates current_state to new_state, runs Exit() on old and Enter() on new
func _transition_to(new_state: State):
    if is_debug:
        print("transition_to: %s", new_state)
    
    var ok = states.has(new_state)
    if !ok:
        printerr("Could not find %s in state machine" % new_state)
        return
    
    if new_state == current_state:
        if is_debug:
            print("transition_to: %s states match, not transitioning" % current_state)
        return
    
    if current_state:
        if is_debug:
            print("Leaving: ", current_state)
        current_state.Exit()

    current_state = new_state
    if is_debug:
        print("Entering: ", current_state.name)
    new_state.Enter()

    state_transitioned.emit(new_state)

## Runs current_state.Update()
func _process(delta):
    if current_state:
        current_state.Update(delta)

## Runs current_state.Physics_Update()
func _physics_process(delta):
    if current_state:
        current_state.Physics_Update(delta)
