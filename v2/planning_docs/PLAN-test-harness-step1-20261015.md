# Test Harness Step 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `python tests/run.py` launches a host and a client tiled side by side, connects them through the real play/lobby menus over 127.0.0.1, enters free roam, samples invariants for a short window, quits both and prints a pass/fail summary.

**Architecture:** `tests/test_main.tscn` instances `main_game.tscn` (after pointing its save/settings at per-peer files) plus a `TestRunner` node. Peer 0's runner hosts and directs; the others drive. Every peer reports snapshots to the director over RPCs on `TestRunner`; the director judges them. A `Logger` subclass registered with `OS.add_logger` captures every error in-process. `run.py` launches, tiles, times out and summarizes from per-peer result JSON.

**Tech Stack:** Godot 4.7.2 GDScript (custom GodotSteam editor build), Python 3 stdlib.

**Spec:** `planning_docs/Testing.md` (Build order step 1)

## Verified before planning

- **Error capture:** 4.7.2 has `Logger` + `OS.add_logger`. Probed: `push_error` → `_log_error` type `ERROR_TYPE_ERROR`; a runtime null deref → `ERROR_TYPE_SCRIPT` (and the game keeps running, which is why capture matters); `printerr` → `_log_message(error=true)`; no double reporting. No log-parsing fallback needed.
- **Window placement:** the project boots **maximized** (`window/size/mode=2`), which ignores `--position`/`--resolution`/`--windowed` at boot. But the CLI rect is remembered as the windowed rect: once `window_set_mode(WINDOWED)` runs, the window lands exactly on it (probed). A per-peer settings file with `fullscreen_mode: "windowed"` makes `MainGame._apply_window_mode` do that switch. So the spec's mechanism holds, for a slightly different reason than "avoid the override".
- **Load ordering:** `SaveManager` and `SettingsManager` are `ManagerManager` children (not autoloads); both load in `deferred_init`, `call_deferred` from `_ready`. Setting `save_slot` / `settings_path` on the instanced scene before `add_child` is early enough.
- **Nesting:** no game code uses `current_scene` or `/root/` (only the `asset_placer` editor plugin).
- **UI path:** IP_PORT isn't the first `host_mode_opt` item (Steam, WebRTC, IP_PORT), so select by id. `code_entry.text = …` doesn't emit `text_changed`, so the runner emits it, as typing would. Lobby start is `level_select_panel.start_btn`; the lobby's default level is used (index 1, `LEVEL_STUNTTRACK_01`). Splash auto-advances, so it's waited out, not skipped.
- **Side effect:** the host's lobby copies the game ID to the clipboard (`LobbyMenuState._on_game_id_set`). Harmless; noted.

## Global Constraints

- Near-zero changes to existing game code. **This plan changes none** (only `export_presets.cfg`).
- Everything test-only lives in `v2/tests/`; `tests/*` in every preset's `exclude_filter`.
- No `class_name` in `tests/` (keeps test classes out of the shipped global class cache); use `preload` consts.
- Inputs via in-game APIs only; no external input injection.
- `run.py`: Python stdlib only; Godot exe from `.vscode/settings.json` (`godotTools.editorPath.godot4`).
- Director (peer 0, host) / driver (every other peer); RPCs on `TestRunner`, same path on every peer.
- RPC conventions (CLAUDE.md): client-callable = `request_*` deriving the sender; broadcasts reject non-server senders.
- Lint clean against `.gdlintrc`; headless editor load clean. No git/gh commands. Terse comments. Fail loudly.

## Review Focus

1. **Steam logged in** changes the `host_mode_opt` item order → select by `ConnectionMode.IP_PORT` id, never index. (Task 3)
2. **First launch after a build** runs `WarmupMenuState` shader warmup before the splash → step timeouts must allow it. (Task 1 constant, verified in Task 5)
3. **Host fails before listening** → clients are never launched; summary must show them `NOT LAUNCHED` and fail, not hang. (Task 2)
4. **A peer hangs or crashes** → `run.py`'s overall timeout kills it; row shows `timeout`/`NO RESULT` and points at its log. (Task 2, verified Task 5)
5. **Per-frame error spam** → errors and violations are deduped into `message → count`, capped, so output stays readable. (Task 1 / Task 4)

## File Structure

| File | Responsibility |
| --- | --- |
| `tests/test_main.tscn` | Root `TestMain` + child `%TestRunner` |
| `tests/test_main.gd` | Parse args, install logger, per-peer save/settings, instance `main_game`, start runner |
| `tests/error_logger.gd` | `Logger` subclass: thread-safe, deduped error capture |
| `tests/test_runner.gd` | Menu flow, director/driver roles, RPCs, snapshots, invariants, result file, quit |
| `tests/run.py` | Launch/tile/timeout/summarize |
| `tests/.gitignore` | Ignore `out/` |
| `export_presets.cfg` | Add `tests/*` to 4 `exclude_filter`s |
| `planning_docs/Testing.md` | Verified facts + step 1 status |

---

### Task 1: Wrapper scene, error logger, runner reaches the play menu

**Files:**
- Create: `tests/test_main.tscn`, `tests/test_main.gd`, `tests/error_logger.gd`, `tests/test_runner.gd` (skeleton), `tests/.gitignore`
- Modify: `export_presets.cfg` (lines 16, 62, 133, 182)

**Interfaces:**
- Produces: `TestRunner.run(logger: ErrorLogger, args: Dictionary) -> void` (coroutine). `args` keys: `peer: int`, `peers: int`, `duration: float`, `out: String` (absolute dir).
- Produces: `ErrorLogger.get_errors() -> Dictionary` (message → count), `ErrorLogger.get_error_count() -> int`.
- Produces: result file `<out>/peer<N>.result.json` = `{"role": "director"|"driver", "errors": {msg: count}, "error_count": int, "violations": {msg: count}}`.

- [ ] **Step 1: Exclude tests from every export preset**

In each of the 4 `exclude_filter=` lines of `export_presets.cfg`, append `, tests/*`:

```
exclude_filter="assets_excluded_from_export/*, resources/psd/*, planning_docs/*, dist/*, android/*, tmp/*, tests/*"
```

- [ ] **Step 2: `tests/.gitignore`**

```
out/
```

- [ ] **Step 3: `tests/error_logger.gd`**

```gdscript
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
```

(`printerr` counting is pending your answer — see the question at the end. If no, delete `_log_message`.)

- [ ] **Step 4: `tests/test_main.gd`**

```gdscript
extends Node
## Boots main_game on per-peer test save/settings files, then hands off to the TestRunner.
## Launched by tests/run.py — see planning_docs/Testing.md.

const ErrorLogger := preload("res://tests/error_logger.gd")
const TestRunner := preload("res://tests/test_runner.gd")
const MAIN_GAME_SCENE := preload("res://main_game.tscn")
## Far from real slots, so a run never touches the player's save
const SAVE_SLOT_BASE := 100

@onready var test_runner: TestRunner = %TestRunner


func _ready() -> void:
	var logger := ErrorLogger.new()
	OS.add_logger(logger)
	var args := _parse_args()
	var main_game := MAIN_GAME_SCENE.instantiate() as MainGame
	_use_test_files(main_game, args["peer"])
	add_child(main_game)
	test_runner.run(logger, args)


## `--peer N --peers N --duration S --out DIR`, as run.py passes them
func _parse_args() -> Dictionary:
	var raw := OS.get_cmdline_user_args()
	var flags := {}
	for i in range(0, raw.size(), 2):
		flags[raw[i].trim_prefix("--")] = raw[i + 1]
	return {
		"peer": int(flags["peer"]),
		"peers": int(flags["peers"]),
		"duration": float(flags["duration"]),
		"out": flags["out"],
	}


## Both managers load in deferred_init, so this runs before they read anything.
func _use_test_files(main_game: MainGame, peer: int) -> void:
	var settings_manager := main_game.settings_manager
	settings_manager.settings_path = "user://test_settings_%d.json" % peer
	# The project boots maximized; switching to windowed lands on run.py's --position/--resolution
	DictJSONSaverLoader.save_json_to_file(
		settings_manager.settings_path,
		{"version": settings_manager.settings_version, "fullscreen_mode": "windowed"}
	)
	for manager in settings_manager.get_parent().get_children():
		if manager is SaveManager:
			manager.save_slot = SAVE_SLOT_BASE + peer
			DirAccess.remove_absolute(manager.save_path)  # fresh save every run
```

- [ ] **Step 5: `tests/test_runner.gd` skeleton**

```gdscript
extends Node
## Drives one peer through the real game UI. Peer 0 hosts and directs: it judges the invariants
## from snapshots every peer reports. Same node path on every peer, so the RPCs land.

const ErrorLogger := preload("res://tests/error_logger.gd")
## Generous: a fresh build compiles shaders (WarmupMenuState) before the splash
const STEP_TIMEOUT_S := 120.0

var _logger: ErrorLogger
var _peer: int
var _peers: int
var _duration: float
var _out_dir: String
## message -> times seen, so a failure on every sample reads as one line
var _violations: Dictionary[String, int] = {}

var _menu_manager: MenuManager


func run(logger: ErrorLogger, args: Dictionary) -> void:
	_logger = logger
	_peer = args["peer"]
	_peers = args["peers"]
	_duration = args["duration"]
	_out_dir = args["out"]
	_menu_manager = _find_manager(MenuManager) as MenuManager

	await _reach_play_menu()
	_quit()


## Waits out warmup + splash, then presses Play
func _reach_play_menu() -> bool:
	var at_main_menu := func(): return _menu_manager.state_machine.current_state is MainMenuState
	if not await _wait_until(at_main_menu, "the main menu"):
		return false
	(_menu_manager.state_machine.current_state as MainMenuState).play_btn.pressed.emit()
	var at_play_menu := func(): return _menu_manager.state_machine.current_state is PlayMenuState
	return await _wait_until(at_play_menu, "the play menu")


## Polls `condition` every frame. On timeout records a violation and returns false.
func _wait_until(condition: Callable, what: String, timeout_s := STEP_TIMEOUT_S) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			_violate("timed out waiting for %s" % what)
			return false
		await get_tree().process_frame
	return true


func _violate(message: String) -> void:
	DebugUtils.DebugMsg("[test] VIOLATION: %s" % message)
	_violations[message] = _violations.get(message, 0) + 1


func _is_director() -> bool:
	return _peer == 0


func _find_manager(type: Script) -> Node:
	for mgr in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Managers"]):
		if is_instance_of(mgr, type):
			return mgr
	return null


func _quit() -> void:
	DictJSONSaverLoader.save_json_to_file(
		_out_dir.path_join("peer%d.result.json" % _peer),
		{
			"role": "director" if _is_director() else "driver",
			"errors": _logger.get_errors(),
			"error_count": _logger.get_error_count(),
			"violations": _violations,
		}
	)
	get_tree().quit(1 if _violations or _logger.get_error_count() else 0)
```

- [ ] **Step 6: `tests/test_main.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://tests/test_main.gd" id="1_main"]
[ext_resource type="Script" path="res://tests/test_runner.gd" id="2_runner"]

[node name="TestMain" type="Node"]
script = ExtResource("1_main")

[node name="TestRunner" type="Node" parent="."]
unique_name_in_owner = true
script = ExtResource("2_runner")
```

- [ ] **Step 7: Lint + parse check**

Run: `gdlint tests/` → expected: no problems.
Run: `timeout 280 "<godot4 exe>" --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" -A1` → expected: no output.

- [ ] **Step 8: Manual single-peer boot**

Run (bash): `"<godot4 exe>" --path . --position 100,100 --resolution 960x540 res://tests/test_main.tscn -- --peer 0 --peers 1 --duration 1 --out "$PWD/tests/out"` (create `tests/out` first).
Expected: window goes windowed at 960×540, reaches the play menu, quits; `tests/out/peer0.result.json` exists with no violations. If `main_game.settings_manager` were unresolved before `add_child`, this crashes loudly at `_use_test_files` (then resolve via the `ManagerManager` child loop for both managers instead).

---

### Task 2: `run.py` — launch, tile, timeout, summary

**Files:**
- Create: `tests/run.py`

**Interfaces:**
- Consumes: result JSON shape from Task 1; `<out>/peer0.ready` marker (written by the director in Task 3; until then clients never launch and show `NOT LAUNCHED` — that path is itself Review Focus #3).
- Produces: CLI `python tests/run.py [--peers N] [--duration S] [--timeout S] [--headless] [--godot EXE]`; exit 0 = pass.

- [ ] **Step 1: Write `tests/run.py`**

```python
"""Regression run: launches peers on res://tests/test_main.tscn, tiles their windows and prints a
summary. Stdlib only. See planning_docs/Testing.md."""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "out"
READY_MARKER = OUT / "peer0.ready"
TITLE_BAR = 32  # --position places the client area; leave room for the OS title bar
POLL_S = 0.25


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--peers", type=int, default=2)
    p.add_argument("--duration", type=float, default=10.0, help="invariant window, seconds")
    p.add_argument("--timeout", type=float, default=180.0, help="whole run, seconds")
    p.add_argument("--headless", action="store_true")
    p.add_argument("--godot", help="Godot exe; default from .vscode/settings.json")
    return p.parse_args()


def godot_exe(override):
    if override:
        return override
    settings = json.loads((ROOT / ".vscode" / "settings.json").read_text())
    return settings["godotTools.editorPath.godot4"]


def work_area():
    """Usable desktop rect (x, y, w, h) in physical pixels."""
    if sys.platform != "win32":
        return 0, 0, 1920, 1080
    import ctypes
    from ctypes import wintypes

    ctypes.windll.user32.SetProcessDPIAware()
    rect = wintypes.RECT()
    SPI_GETWORKAREA = 0x0030
    ctypes.windll.user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0)
    return rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top


def window_rect(peer, peers):
    left, top, width, height = work_area()
    w = width // peers
    h = min(w * 9 // 16, height - TITLE_BAR)
    return left + peer * w, top + TITLE_BAR, w, h


def launch(exe, peer, args):
    cmd = [exe, "--path", str(ROOT), "--log-file", str(OUT / f"peer{peer}.log")]
    if args.headless:
        cmd.append("--headless")
    else:
        x, y, w, h = window_rect(peer, args.peers)
        cmd += ["--position", f"{x},{y}", "--resolution", f"{w}x{h}"]
    cmd += [
        "res://tests/test_main.tscn", "--",
        "--peer", str(peer), "--peers", str(args.peers),
        "--duration", str(args.duration), "--out", str(OUT),
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_for(condition, deadline):
    while not condition():
        if time.monotonic() > deadline:
            return False
        time.sleep(POLL_S)
    return True


def summarize(procs, timed_out, peers):
    """Prints the table + details. Returns the process exit code."""
    rows, details, failed = [], [], False
    for peer in range(peers):
        proc = procs.get(peer)
        result_path = OUT / f"peer{peer}.result.json"
        result = json.loads(result_path.read_text()) if result_path.exists() else None
        role = result["role"] if result else ("director" if peer == 0 else "driver")
        if proc is None:
            exit_code, status = "-", "NOT LAUNCHED"
        elif peer in timed_out:
            exit_code, status = "timeout", "FAIL"
        else:
            exit_code = str(proc.returncode)
            status = "PASS" if proc.returncode == 0 and result else "FAIL"
        if proc is not None and result is None:
            status = "NO RESULT"
        errors = result["error_count"] if result else "-"
        violations = sum(result["violations"].values()) if result else "-"
        if result and (result["error_count"] or result["violations"]):
            status = "FAIL"
        failed |= status != "PASS"
        rows.append((f"peer{peer}", role, exit_code, str(errors), str(violations), status))
        for kind in ("violations", "errors"):
            for msg, count in (result[kind] if result else {}).items():
                details.append(f"  peer{peer} {kind[:-1]} x{count}: {msg}")

    header = ("peer", "role", "exit", "errors", "violations", "result")
    widths = [max(len(r[i]) for r in rows + [header]) for i in range(len(header))]
    for row in [header] + rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)))
    if details:
        print("\n" + "\n".join(details))
    print(f"\nlogs: {OUT}")
    print("FAILED" if failed else "PASSED")
    return 1 if failed else 0


def main():
    args = parse_args()
    exe = godot_exe(args.godot)
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    (OUT / ".gdignore").touch()  # keep logs/screenshots out of the editor's import

    deadline = time.monotonic() + args.timeout
    procs = {0: launch(exe, 0, args)}
    # Clients join through the menu, so the host must be listening first
    host_up = wait_for(lambda: READY_MARKER.exists() or procs[0].poll() is not None, deadline)
    if host_up and procs[0].poll() is None:
        for peer in range(1, args.peers):
            procs[peer] = launch(exe, peer, args)

    wait_for(lambda: all(p.poll() is not None for p in procs.values()), deadline)
    timed_out = [peer for peer, p in procs.items() if p.poll() is None]
    for peer in timed_out:
        procs[peer].kill()
        procs[peer].wait()
    sys.exit(summarize(procs, timed_out, args.peers))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify the launch/summary path with the Task 1 skeleton**

Run: `python tests/run.py --peers 2 --timeout 60`
Expected: one windowed host window at the left half; it reaches the play menu and quits; no ready marker → peer1 `NOT LAUNCHED`; table prints; `FAILED`, exit 1. (Review Focus #3.)

---

### Task 3: Host/join through the menus, into free roam

**Files:**
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Consumes: `run()`, `_wait_until`, `_violate`, `_find_manager`, `_quit` from Task 1.
- Produces: `_direct() -> void` (stops after every peer is in free roam; Task 4 appends sampling), `_drive() -> bool`, `_wait_in_game() -> bool`, RPC `request_mark_ready()`, writes `<out>/peer0.ready`.

- [ ] **Step 1: Add consts, manager refs, ready tracking**

```gdscript
const HOST_ADDR := "127.0.0.1"
## run.py launches the clients once this exists
const READY_MARKER := "peer0.ready"
```

```gdscript
## Director only: peers that reached free roam
var _ready_peers: Array[int] = []

var _menu_manager: MenuManager
var _connection_manager: ConnectionManager
var _lobby_manager: LobbyManager
var _gamemode_manager: GamemodeManager
var _hud_manager: HUDManager
```

- [ ] **Step 2: Replace `run()`'s tail with the role split**

```gdscript
func run(logger: ErrorLogger, args: Dictionary) -> void:
	_logger = logger
	_peer = args["peer"]
	_peers = args["peers"]
	_duration = args["duration"]
	_out_dir = args["out"]
	_menu_manager = _find_manager(MenuManager) as MenuManager
	_connection_manager = _find_manager(ConnectionManager) as ConnectionManager
	_lobby_manager = _find_manager(LobbyManager) as LobbyManager
	_gamemode_manager = _find_manager(GamemodeManager) as GamemodeManager
	_hud_manager = _find_manager(HUDManager) as HUDManager

	if not await _reach_play_menu():
		_quit()
		return
	if _is_director():
		await _direct()
		_quit()
	elif not await _drive():
		_quit()
	# A driver that got in idles until the director ends the run (Task 4)
```

- [ ] **Step 3: Director flow**

```gdscript
## Hosts via the play menu, starts the lobby's default level once every peer joined.
func _direct() -> void:
	var play := _menu_manager.state_machine.current_state as PlayMenuState
	# Steam, when logged in, comes first in the list
	play.host_mode_opt.select(
		play.host_mode_opt.get_item_index(ConnectionManager.ConnectionMode.IP_PORT)
	)
	play.host_btn.pressed.emit()
	if not await _wait_until(func(): return _connection_manager.conn_addr != "", "the host to listen"):
		return
	FileAccess.open(_out_dir.path_join(READY_MARKER), FileAccess.WRITE).store_string("")

	var lobby_full := func(): return _lobby_manager.lobby_players.size() == _peers
	if not await _wait_until(lobby_full, "%d players in the lobby" % _peers):
		return
	var start_btn := (
		(_menu_manager.state_machine.current_state as LobbyMenuState).level_select_panel.start_btn
	)
	if start_btn.disabled:
		_violate("lobby start button is disabled")
		return
	start_btn.pressed.emit()

	if not await _wait_in_game():
		return
	_ready_peers.append(multiplayer.get_unique_id())
	if not await _wait_until(func(): return _ready_peers.size() == _peers, "every peer in free roam"):
		return
```

- [ ] **Step 4: Driver flow + shared wait + RPC**

```gdscript
## Joins via the play menu. False if it never got into the game.
func _drive() -> bool:
	var play := _menu_manager.state_machine.current_state as PlayMenuState
	play.code_entry.text = HOST_ADDR
	# Assigning .text doesn't emit text_changed; typing does
	play.code_entry.text_changed.emit(HOST_ADDR)
	if play.join_btn.disabled:
		_violate("join button disabled for %s" % HOST_ADDR)
		return false
	if _connection_manager.connection_mode != ConnectionManager.ConnectionMode.IP_PORT:
		_violate("%s didn't auto-select IP_PORT" % HOST_ADDR)
		return false
	play.join_btn.pressed.emit()
	if not await _wait_in_game():
		return false
	request_mark_ready.rpc_id(1)
	return true


## HUD is left to the invariants, so a missing HUD fails as that, not as a timeout
func _wait_in_game() -> bool:
	var in_game := func():
		return (
			_gamemode_manager.state_machine.current_state == _gamemode_manager.free_roam_mode
			and not get_tree().get_nodes_in_group(UtilsConstants.GROUPS["LocalPlayer"]).is_empty()
		)
	return await _wait_until(in_game, "free roam with a local player")


@rpc("any_peer", "call_remote", "reliable")
func request_mark_ready() -> void:
	if !multiplayer.is_server():
		return
	_ready_peers.append(multiplayer.get_remote_sender_id())
```

- [ ] **Step 5: Lint + parse check** (commands as Task 1 Step 7). Expected: clean.

- [ ] **Step 6: Run**

Run: `python tests/run.py`
Expected: both windows tiled; host hosts, client joins via 127.0.0.1, both load into free roam. Host quits after everyone is in (PASS if clean); the client idles until `--timeout` kills it (row `timeout`, FAIL) — fixed in Task 4.

---

### Task 4: Snapshots, invariants, ordered shutdown

**Files:**
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Consumes: Task 3's `_direct()`, `_ready_peers`, manager refs.
- Produces: `_snapshot() -> Dictionary` (`players: Array` sorted peer ids, `gamemode: String`, `hud: String`, `hud_visible: bool`), `_judge(snapshots: Dictionary)`, RPCs `_take_snapshot(sample)`, `request_report_snapshot(sample, snapshot)`, `_end_run()`.

- [ ] **Step 1: Consts + state**

```gdscript
const SAMPLE_INTERVAL_S := 1.0
const DISCONNECT_TIMEOUT_S := 10.0
```

```gdscript
## Director only. sample -> {peer_id: snapshot}
var _snapshots: Dictionary[int, Dictionary] = {}
```

- [ ] **Step 2: Director runs the window and ends the run; drivers quit on its order**

At the end of `_direct()` (after the "every peer in free roam" wait) append:

```gdscript
	await _sample_invariants()
```

Replace the director branch in `run()`:

```gdscript
	if _is_director():
		await _direct()
		await _end_run_as_director()
```

Add:

```gdscript
## Drivers quit first: a host leaving first would drop them into the disconnect flow
func _end_run_as_director() -> void:
	_end_run.rpc()
	var drivers_gone := func(): return multiplayer.get_peers().is_empty()
	await _wait_until(drivers_gone, "drivers to disconnect", DISCONNECT_TIMEOUT_S)
	_quit()


@rpc("call_remote", "reliable")
func _end_run() -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_quit()
```

- [ ] **Step 3: Sampling + RPCs**

```gdscript
## Every peer snapshots on the same order; the director judges a sample one interval later.
func _sample_invariants() -> void:
	for sample in int(_duration / SAMPLE_INTERVAL_S):
		_snapshots[sample] = {multiplayer.get_unique_id(): _snapshot()}
		_take_snapshot.rpc(sample)
		await get_tree().create_timer(SAMPLE_INTERVAL_S).timeout
		_judge(_snapshots[sample])


func _snapshot() -> Dictionary:
	var players := []
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer is PlayerEntity:
			players.append(int(str(racer.name)))
	players.sort()
	var hud := _hud_manager.state_machine.current_state as HUDState
	return {
		"players": players,
		"gamemode": str(_gamemode_manager.state_machine.current_state.name),
		"hud": str(hud.name),
		"hud_visible": hud.ui.is_visible_in_tree(),
	}


@rpc("call_remote", "reliable")
func _take_snapshot(sample: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	request_report_snapshot.rpc_id(1, sample, _snapshot())


@rpc("any_peer", "call_remote", "reliable")
func request_report_snapshot(sample: int, snapshot: Dictionary) -> void:
	if !multiplayer.is_server():
		return
	_snapshots[sample][multiplayer.get_remote_sender_id()] = snapshot
```

- [ ] **Step 4: The judge**

```gdscript
## Step 1 invariants: peers agree on players + gamemode, and each shows the riding HUD.
func _judge(snapshots: Dictionary) -> void:
	if snapshots.size() != _peers:
		_violate("%d/%d peers reported a snapshot" % [snapshots.size(), _peers])
	var host: Dictionary = snapshots[1]
	var free_roam := str(_gamemode_manager.free_roam_mode.name)
	if host["gamemode"] != free_roam:
		_violate("host is in %s, expected %s" % [host["gamemode"], free_roam])
	var riding_hud := str(_hud_manager.riding_hud_state.name)
	for peer_id in snapshots:
		var snap: Dictionary = snapshots[peer_id]
		if snap["players"].size() != _peers:
			_violate("peer %d sees %d players, expected %d" % [peer_id, snap["players"].size(), _peers])
		if snap["players"] != host["players"]:
			_violate("peer %d sees players %s, host sees %s" % [peer_id, snap["players"], host["players"]])
		if snap["gamemode"] != host["gamemode"]:
			_violate("peer %d is in %s, host is in %s" % [peer_id, snap["gamemode"], host["gamemode"]])
		if snap["hud"] != riding_hud or not snap["hud_visible"]:
			_violate(
				"peer %d HUD is %s (visible: %s), expected a visible %s"
				% [peer_id, snap["hud"], snap["hud_visible"], riding_hud]
			)
```

- [ ] **Step 5: Lint + parse check.** Expected: clean.

- [ ] **Step 6: Run**

Run: `python tests/run.py`
Expected: tiled windows, connect, free roam, ~10 s window, client quits then host; table shows both `PASS`, exit 0, `tests/out/peer0.log`, `peer1.log`, both result JSONs. If real pre-existing errors appear, **stop and report them** (don't add ignore lists).

---

### Task 5: Break test, review-focus checks, docs

**Files:**
- Temporarily modify then revert: `managers/hud/hud_manager.gd` (`go_to_riding_hud`)
- Modify: `planning_docs/Testing.md`

- [ ] **Step 1: Break the riding HUD**

Temporarily make `HUDManager.go_to_riding_hud()` request `null_hud_state` instead of `riding_hud_state`.
Run: `python tests/run.py`
Expected: `FAIL`; violation line like `peer1 violation x10: peer 1 HUD is NullHUDState (visible: false), expected a visible RidingHUDState` for each peer; exit 1.

- [ ] **Step 2: Revert, rerun green**

Revert the edit exactly. Run `python tests/run.py` → PASS, exit 0.

- [ ] **Step 3: Timeout path (Review Focus #4)**

Run: `python tests/run.py --timeout 25`
Expected: run killed mid-flow; rows show `timeout` / `NO RESULT`, `FAILED`, no orphan Godot processes left (check Task Manager / `tasklist | grep -i godot`).

- [ ] **Step 4: Update `planning_docs/Testing.md`** (no concrete tunable values)

- Status line: step 1 built (wrapper, orchestrator, error capture, UI host/join, the agreement + HUD invariants).
- Wrapper: why the windowed settings file works (project boots maximized; the CLI rect applies once the game switches to windowed). Test save slot and settings are fresh each run.
- Orchestrator: host launched first, clients after the director's ready marker; per-peer `--log-file` (peers would otherwise share `user://` logs); per-peer result JSON; `tests/out/` has a `.gdignore`.
- Error capture: `Logger` via `OS.add_logger`, installed when the wrapper loads (autoload-init errors only reach the log); what counts as an error.
- Director/drivers: snapshot RPC protocol (director orders a sample, drivers report, judged one interval later).
- Remove the resolved "Error capture" and "Window placement" open questions.

- [ ] **Step 5: Final lint + parse check** over `tests/` and any touched file. Report.
