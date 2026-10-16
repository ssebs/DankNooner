"""Regression run: launches peers on res://tests/test_main.tscn, tiles their windows and prints a
summary. Stdlib only. See planning_docs/Testing.md."""

import argparse
import ctypes
import json
import shutil
import subprocess
import sys
import time
import winsound
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "out"
READY_MARKER = OUT / "peer0.ready"
LATE_JOIN_MARKER = OUT / "late_join.go"
MOUSE_MARKER = OUT / "mouse.busy"
TITLE_BAR = 32  # --position places the client area; leave room for the OS title bar
POLL_S = 0.05  # fast enough to catch an Esc tap
# Tiles are sized for this many peers even when fewer run, so a solo window stays small
TILE_SLOTS = 3
VK_ESCAPE = 0x1B
ESC_TWICE_S = 1.0
# A host not listening by then is broken (it covers a fresh build's shader warmup)
HOST_READY_TIMEOUT_S = 180.0
DONE_BANNER_MS = 3000
# A topmost strip that hands focus straight back, so no peer loses it
BANNER_SRC = """
import ctypes, sys, tkinter as tk
text, bg, geometry, close_ms = sys.argv[1:5]
user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
focused = user32.GetForegroundWindow()
root = tk.Tk()
root.overrideredirect(True)
root.attributes("-topmost", True)
root.geometry(geometry)
tk.Label(root, text=text, bg=bg, fg="white", font=("Segoe UI", 28, "bold")).pack(fill="both", expand=True)
root.update()
user32.SetForegroundWindow(focused)
if int(close_ms):
    root.after(int(close_ms), root.destroy)
root.mainloop()
"""


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--peers", type=int, default=2, help="peers at the start (1 = solo)")
    p.add_argument("--late-join", action="store_true", help="one more peer joins late, then rejoins")
    p.add_argument("--timeout", type=float, default=420.0, help="whole run, seconds")
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
    from ctypes import wintypes

    ctypes.windll.user32.SetProcessDPIAware()
    rect = wintypes.RECT()
    SPI_GETWORKAREA = 0x0030
    ctypes.windll.user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0)
    return rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top


def window_rect(peer, total):
    left, top, width, height = work_area()
    w = width // total
    h = min(w * 9 // 16, height - TITLE_BAR)
    return left + peer * w, top + TITLE_BAR, w, h


def total_peers(args):
    return args.peers + (1 if args.late_join else 0)


def launch(exe, peer, args):
    x, y, w, h = window_rect(peer, max(total_peers(args), TILE_SLOTS))
    cmd = [exe, "--path", str(ROOT), "--log-file", str(OUT / f"peer{peer}.log")]
    # Dummy audio: the audio code still runs, nothing plays
    cmd += ["--audio-driver", "Dummy"]
    cmd += ["--position", f"{x},{y}", "--resolution", f"{w}x{h}"]
    cmd += [
        "res://tests/test_main.tscn", "--",
        "--peer", str(peer), "--peers", str(args.peers),
        "--late-join", "1" if args.late_join else "0", "--out", str(OUT),
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def banner(text, color, args, close_ms=0):
    """Topmost strip under the tiled windows, so it never covers what a peer clicks."""
    left, _, width, _ = work_area()
    _, y, _, h = window_rect(0, max(total_peers(args), TILE_SLOTS))
    geometry = f"{width}x90+{left}+{y + h + 40}"
    return subprocess.Popen([sys.executable, "-c", BANNER_SRC, text, color, geometry, str(close_ms)])


class Aborted(Exception):
    pass


class AbortWatch:
    """Esc twice (from any window) or a peer closed without a result (Alt+F4) stops the run."""

    def __init__(self, procs):
        self.procs = procs
        self.esc_down = False
        self.last_esc = -ESC_TWICE_S

    def check(self):
        state = ctypes.windll.user32.GetAsyncKeyState(VK_ESCAPE)
        down = bool(state & 0x8000)
        # Low bit: pressed since the last poll, so a tap between polls still counts
        if (down and not self.esc_down) or (not down and state & 1):
            now = time.monotonic()
            if now - self.last_esc < ESC_TWICE_S:
                raise Aborted("Esc pressed twice")
            self.last_esc = now
        self.esc_down = down
        for peer, proc in self.procs.items():
            if proc.poll() is not None and not (OUT / f"peer{peer}.result.json").exists():
                raise Aborted(f"peer{peer} exited without a result (closed or crashed)")


def wait_for(condition, deadline, abort):
    while not condition():
        if time.monotonic() > deadline:
            return False
        abort.check()
        time.sleep(POLL_S)
    return True


def summarize(procs, killed, total, aborted):
    """Prints the table + details. Returns the process exit code."""
    rows, details, failed = [], [], False
    for peer in range(total):
        proc = procs.get(peer)
        result_path = OUT / f"peer{peer}.result.json"
        result = json.loads(result_path.read_text()) if result_path.exists() else None
        role = result["role"] if result else ("director" if peer == 0 else "driver")
        if proc is None:
            exit_code, status = "-", "NOT LAUNCHED"
        elif peer in killed:
            exit_code, status = ("killed" if aborted else "timeout"), "FAIL"
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
        for msg in result["warnings"] if result else []:
            details.append(f"  peer{peer} warning: {msg}")

    header = ("peer", "role", "exit", "errors", "violations", "result")
    widths = [max(len(r[i]) for r in rows + [header]) for i in range(len(header))]
    for row in [header] + rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)))
    if details:
        print("\n" + "\n".join(details))
    print(f"\nlogs + screenshots: {OUT}")
    print(f"ABORTED: {aborted}" if aborted else ("FAILED" if failed else "PASSED"))
    return 1 if failed else 0


def main():
    args = parse_args()
    exe = godot_exe(args.godot)
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    (OUT / ".gdignore").touch()  # keep logs/screenshots out of the editor's import

    deadline = time.monotonic() + args.timeout
    procs = {0: launch(exe, 0, args)}
    abort = AbortWatch(procs)
    hands_off = None
    aborted = None

    def mouse_free():
        hands_off.kill()
        banner("Done: the mouse is yours again", "#2e7d32", args, DONE_BANNER_MS)

    try:
        # Clients join through the menu, so the host must be listening first
        ready_deadline = min(deadline, time.monotonic() + HOST_READY_TIMEOUT_S)
        host_up = wait_for(
            lambda: READY_MARKER.exists() or procs[0].poll() is not None, ready_deadline, abort
        )
        if not host_up:
            procs[0].kill()
            procs[0].wait()
        elif procs[0].poll() is None:
            for peer in range(1, args.peers):
                procs[peer] = launch(exe, peer, args)

        # The late joiner launches when the director asks, mid-activity
        late_peer = args.peers
        while any(p.poll() is None for p in procs.values()) and time.monotonic() < deadline:
            if late_peer not in procs and LATE_JOIN_MARKER.exists():
                procs[late_peer] = launch(exe, late_peer, args)
            # Fuel-up warps the real cursor: a human moving it breaks the pump
            if MOUSE_MARKER.exists() and hands_off is None:
                winsound.MessageBeep()
                hands_off = banner("HANDS OFF THE MOUSE NOW: the bot is using it", "#c62828", args)
            elif not MOUSE_MARKER.exists() and hands_off is not None:
                mouse_free()
                hands_off = None
            abort.check()
            time.sleep(POLL_S)
    except Aborted as e:
        aborted = str(e)
    except KeyboardInterrupt:
        aborted = "Ctrl+C"
    if hands_off is not None:
        mouse_free()

    killed = [peer for peer, p in procs.items() if p.poll() is None]
    for peer in killed:
        procs[peer].kill()
        procs[peer].wait()
    sys.exit(summarize(procs, killed, total_peers(args), aborted))

if __name__ == "__main__":
    main()
