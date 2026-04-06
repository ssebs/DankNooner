class_name PauseStateContext extends StateContext

var show_bg_tint: bool


static func NewFromPause(rs: MenuState, bg_tint: bool = false) -> PauseStateContext:
	var ctx = PauseStateContext.new()
	ctx.return_state = rs
	ctx.show_bg_tint = bg_tint
	return ctx
