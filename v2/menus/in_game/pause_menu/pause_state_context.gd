class_name PauseStateContext extends StateContext

var return_state: MenuState
var show_bg_tint: bool


static func NewFromPause(state: MenuState, bg_tint: bool = false) -> PauseStateContext:
	var ctx = PauseStateContext.new()
	ctx.return_state = state
	ctx.show_bg_tint = bg_tint
	return ctx
