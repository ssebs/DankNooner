class_name SettingsStateContext extends StateContext

var show_bg_tint: bool


static func NewFromPause(rs: MenuState, bg_tint: bool = false) -> SettingsStateContext:
	var ctx = SettingsStateContext.new()
	ctx.return_state = rs
	ctx.show_bg_tint = bg_tint
	return ctx
