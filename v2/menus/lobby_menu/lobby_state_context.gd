class_name LobbyStateContext extends StateContext

enum Mode { FREEROAM, STORY, HOST, JOIN }

var mode: Mode
var ip_addr: String


static func NewHost(rs: MenuState, ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.HOST
	ctx.ip_addr = ip
	ctx.return_state = rs
	return ctx


static func NewJoin(rs: MenuState, ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.JOIN
	ctx.ip_addr = ip
	ctx.return_state = rs
	return ctx


static func NewFreeRoam(
	rs: MenuState,
) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.FREEROAM
	ctx.return_state = rs
	return ctx


static func NewStory(
	rs: MenuState,
) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.STORY
	ctx.return_state = rs
	return ctx
