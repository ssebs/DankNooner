class_name DebugUtils extends RefCounted


## Print str only in debug build
static func DebugMsg(s: String, should_print: bool = true):
	if should_print and OS.has_feature("debug"):
		print(s)


## Print str only in debug build
static func DebugErrMsg(s: String, should_print: bool = true):
	if should_print and OS.has_feature("debug"):
		printerr(s)
