class_name LobbyStateContext extends StateContext

enum Mode { FREEROAM, STORY, HOST, JOIN }

var mode: Mode
var ip_addr: String
## STORY: start the Advanced tutorial instead of the main one.
var advanced_tutorial: bool


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
	advanced: bool = false,
) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.STORY
	ctx.advanced_tutorial = advanced
	ctx.return_state = rs
	return ctx
