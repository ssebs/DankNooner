## Base class
class_name StateContext extends RefCounted

var return_state: MenuState


static func NewWithReturn(rs: MenuState) -> StateContext:
	var ctx = StateContext.new()
	ctx.return_state = rs
	return ctx


static func NewWithReturnAndContext(rs: MenuState, ctx: StateContext) -> StateContext:
	ctx.return_state = rs
	return ctx
