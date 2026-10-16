extends Logger
## Captures every error in-process so a run can fail on it. Called from any thread.

## Distinct messages kept; more are only counted
const MAX_DISTINCT := 50

var _mutex := Mutex.new()
var _errors: Dictionary[String, int] = {}
var _count := 0


func _log_error(
	function: String, file: String, line: int, code: String, rationale: String,
	_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_record("%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function])


## printerr (DebugUtils.DebugErrMsg) lands here
func _log_message(message: String, error: bool) -> void:
	if error:
		_record(message.strip_edges())


func get_errors() -> Dictionary:
	_mutex.lock()
	var errors := _errors.duplicate()
	_mutex.unlock()
	return errors


func get_error_count() -> int:
	_mutex.lock()
	var count := _count
	_mutex.unlock()
	return count


func _record(message: String) -> void:
	_mutex.lock()
	_count += 1
	if _errors.has(message) or _errors.size() < MAX_DISTINCT:
		_errors[message] = _errors.get(message, 0) + 1
	_mutex.unlock()
