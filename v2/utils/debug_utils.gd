class_name DebugUtils extends RefCounted

static var prof_enabled := false  # PROF: temp - set from PlayerEntity.debug_prof
static var _prof: Dictionary[String, Vector3i] = {}  # key -> (total_usec, calls, max_usec)  # PROF: temp
static var _prof_window_start_ms := 0  # PROF: temp


## Print str only in debug build
static func DebugMsg(s: String, should_print: bool = true):
	if should_print:
		print(s)


## Print str only in debug build
static func DebugErrMsg(s: String, should_print: bool = true):
	if should_print:
		printerr(s)


#region PROF: temp physics profiling — grep "PROF:" to remove
## Accumulate the time since start_usec (a Time.get_ticks_usec()) under key; dumps every 5s.
static func Prof(key: String, start_usec: int) -> void:
	if !prof_enabled:
		return
	var dt := Time.get_ticks_usec() - start_usec
	var e: Vector3i = _prof.get(key, Vector3i.ZERO)
	_prof[key] = Vector3i(e.x + dt, e.y + 1, maxi(e.z, dt))
	var now := Time.get_ticks_msec()
	if _prof_window_start_ms == 0:
		_prof_window_start_ms = now
	elif now - _prof_window_start_ms >= 5000:
		_prof_dump(now)


static func _prof_dump(now: int) -> void:
	var secs := (now - _prof_window_start_ms) / 1000.0
	_prof_window_start_ms = now
	var lines := PackedStringArray()
	lines.append(
		(
			"[prof] %.1fs | fps %d | engine physics %.2fms (last frame) | tick budget %.2fms"
			% [
				secs,
				Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				1000.0 / NetworkTime.tickrate,
			]
		)
	)
	if Performance.has_custom_monitor(&"netfox/Rollback loop duration (ms)"):
		lines.append(
			(
				"  netfox rollback loop %.2fms | rb ticks %d (last sample)"
				% [
					Performance.get_custom_monitor(&"netfox/Rollback loop duration (ms)"),
					Performance.get_custom_monitor(&"netfox/Rollback ticks simulated"),
				]
			)
		)
	var keys := _prof.keys()
	keys.sort_custom(func(a, b): return _prof[a].x > _prof[b].x)
	for key in keys:
		var e: Vector3i = _prof[key]
		lines.append(
			(
				"  %-24s %7.3f ms/s | %6.0f calls/s | avg %7.1f us | max %6d us"
				% [key, e.x / 1000.0 / secs, e.y / secs, float(e.x) / e.y, e.z]
			)
		)
	_prof.clear()
	DebugMsg("\n".join(lines))
#endregion
