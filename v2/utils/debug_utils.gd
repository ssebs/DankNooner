class_name DebugUtils extends RefCounted


## Print str only in debug build
static func DebugMsg(s: String, should_print: bool = true):
	if should_print:
		print(s)


## Print str only in debug build
static func DebugErrMsg(s: String, should_print: bool = true):
	if should_print:
		printerr(s)
