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
LATE_JOIN_MARKER = OUT / "late_join.go"
TITLE_BAR = 32  # --position places the client area; leave room for the OS title bar
POLL_S = 0.25
# A host not listening by then is broken (it covers a fresh build's shader warmup)
HOST_READY_TIMEOUT_S = 180.0


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--peers", type=int, default=2, help="peers at the start; one more joins late")
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
    import ctypes
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


def launch(exe, peer, args):
    x, y, w, h = window_rect(peer, args.peers + 1)
    cmd = [exe, "--path", str(ROOT), "--log-file", str(OUT / f"peer{peer}.log")]
    # Dummy audio: the audio code still runs, nothing plays
    cmd += ["--audio-driver", "Dummy"]
    cmd += ["--position", f"{x},{y}", "--resolution", f"{w}x{h}"]
    cmd += [
        "res://tests/test_main.tscn", "--",
        "--peer", str(peer), "--peers", str(args.peers), "--out", str(OUT),
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_for(condition, deadline):
    while not condition():
        if time.monotonic() > deadline:
            return False
        time.sleep(POLL_S)
    return True


def summarize(procs, timed_out, total):
    """Prints the table + details. Returns the process exit code."""
    rows, details, failed = [], [], False
    for peer in range(total):
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
        for msg in result["warnings"] if result else []:
            details.append(f"  peer{peer} warning: {msg}")

    header = ("peer", "role", "exit", "errors", "violations", "result")
    widths = [max(len(r[i]) for r in rows + [header]) for i in range(len(header))]
    for row in [header] + rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)))
    if details:
        print("\n" + "\n".join(details))
    print(f"\nlogs + screenshots: {OUT}")
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
    ready_deadline = min(deadline, time.monotonic() + HOST_READY_TIMEOUT_S)
    host_up = wait_for(lambda: READY_MARKER.exists() or procs[0].poll() is not None, ready_deadline)
    if not host_up:
        procs[0].kill()
    elif procs[0].poll() is None:
        for peer in range(1, args.peers):
            procs[peer] = launch(exe, peer, args)

    def running():
        return any(p.poll() is None for p in procs.values())

    # The late joiner launches when the director asks, mid-activity
    late_peer = args.peers
    while running() and time.monotonic() < deadline:
        if late_peer not in procs and LATE_JOIN_MARKER.exists():
            procs[late_peer] = launch(exe, late_peer, args)
        time.sleep(POLL_S)

    timed_out = [peer for peer, p in procs.items() if p.poll() is None]
    for peer in timed_out:
        procs[peer].kill()
        procs[peer].wait()
    sys.exit(summarize(procs, timed_out, args.peers + 1))


if __name__ == "__main__":
    main()
