class_name LobbyStateContext extends StateContext

enum Mode { FREEROAM, STORY, HOST, JOIN }

var mode: Mode
var ip_addr: String


static func NewHost(ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.HOST
	ctx.ip_addr = ip
	return ctx


static func NewJoin(ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.JOIN
	ctx.ip_addr = ip
	return ctx


static func NewFreeRoam() -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.FREEROAM
	return ctx


static func NewStory() -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.STORY
	return ctx
