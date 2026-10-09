#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# niri-workspaces.sh — workspace-state daemon for the niri backend.
#
# Writes the SAME file the bar already reads
# (<runDir>/workspaces/workspaces.json) with the SAME shape:
#
#   [ { "id": 1, "state": "active"|"occupied"|"empty",
#       "tooltip": "name", "classes": "kitty,firefox" }, ... ]
#
# The Hyprland daemon polls hyprctl on every .socket2 event. niri's event
# stream already delivers a full snapshot on connect and then deltas, so this
# daemon builds the model once and re-renders on each relevant event.
#
# niri workspaces are dynamic, so the pill row is derived: ids 1..N where N is
# max(settings.json -> workspaceCount, highest live idx). Focusing id N works
# because `niri msg action focus-workspace <idx>` targets the focused output.
# Multi-monitor caveat: an idx can repeat across outputs; the row prefers the
# workspace on the focused output (see docs/overlay.md).
# ═══════════════════════════════════════════════════════════════════════════
set -u

source "$(dirname "${BASH_SOURCE[0]}")/../../../caching.sh" 2>/dev/null || true
qs_ensure_cache "workspaces" 2>/dev/null || true

RUN_DIR="${QS_RUN_WORKSPACES:-${XDG_RUNTIME_DIR:-/tmp}/quickshell/workspaces}"
mkdir -p "$RUN_DIR"
OUT="$RUN_DIR/workspaces.json"

# Zombie prevention (mirrors the Hyprland daemon).
for pid in $(pgrep -f "niri-workspaces.sh" 2>/dev/null); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT SIGTERM SIGINT

SETTINGS_FILE="$HOME/.config/hypr/settings.json"

python3 - "$OUT" "$SETTINGS_FILE" <<'PY'
import json
import os
import socket
import sys
import time

out = sys.argv[1]
settings = sys.argv[2]


def workspace_count():
    try:
        with open(settings) as fh:
            data = json.load(fh)
        n = int(data.get("workspaceCount", 8))
        return n if n > 0 else 8
    except Exception:
        return 8


def render(workspaces, windows):
    by_ws = {}
    for win in windows.values():
        wid = win.get("workspace_id")
        app = win.get("app_id") or win.get("title") or ""
        if wid is None or app == "":
            continue
        by_ws.setdefault(wid, [])
        if app not in by_ws[wid]:
            by_ws[wid].append(app)

    focused_output = None
    for ws in workspaces.values():
        if ws.get("is_focused"):
            focused_output = ws.get("output")
            break

    by_idx = {}
    for ws in sorted(workspaces.values(),
                     key=lambda w: (w.get("output") or "", w.get("idx") or 0)):
        idx = ws.get("idx")
        if idx is None:
            continue
        prev = by_idx.get(idx)
        if prev is None or (focused_output is not None
                            and ws.get("output") == focused_output):
            by_idx[idx] = ws

    active_idx = None
    for idx, ws in by_idx.items():
        if ws.get("is_focused"):
            active_idx = idx
            break
    if active_idx is None:
        for idx, ws in by_idx.items():
            if ws.get("is_active"):
                active_idx = idx
                break

    max_idx = workspace_count()
    if by_idx:
        max_idx = max(max_idx, max(by_idx.keys()))

    rows = []
    for idx in range(1, max_idx + 1):
        ws = by_idx.get(idx)
        classes = []
        tooltip = ""
        has_win = False
        if ws is not None:
            classes = by_ws.get(ws.get("id"), [])
            active_id = ws.get("active_window_id")
            if active_id is not None and active_id in windows:
                tooltip = windows[active_id].get("title") or ""
            if not tooltip:
                tooltip = ws.get("name") or ""
            has_win = ws.get("active_window_id") is not None or bool(classes)
        if idx == active_idx:
            state = "active"
        elif has_win:
            state = "occupied"
        else:
            state = "empty"
        rows.append({
            "id": idx,
            "state": state,
            "tooltip": tooltip or ("Empty" if not has_win else ""),
            "classes": ",".join(classes),
        })
    return rows


def write(rows):
    tmp = out + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(rows, fh)
    os.replace(tmp, out)


def handle(ev):
    dirty = False
    if "WorkspacesChanged" in ev:
        workspaces.clear()
        for ws in ev["WorkspacesChanged"]["workspaces"]:
            workspaces[ws["id"]] = ws
        dirty = True
    elif "WindowsChanged" in ev:
        windows.clear()
        for win in ev["WindowsChanged"]["windows"]:
            windows[win["id"]] = win
        dirty = True
    elif "WorkspaceActivated" in ev:
        a = ev["WorkspaceActivated"]
        for ws in workspaces.values():
            ws["is_active"] = ws["id"] == a["id"]
            if a["focused"]:
                ws["is_focused"] = ws["id"] == a["id"]
        dirty = True
    elif "WorkspaceUrgencyChanged" in ev:
        u = ev["WorkspaceUrgencyChanged"]
        if u["id"] in workspaces:
            workspaces[u["id"]]["is_urgent"] = u["urgent"]
        dirty = True
    elif "WorkspaceActiveWindowChanged" in ev:
        u = ev["WorkspaceActiveWindowChanged"]
        if u["workspace_id"] in workspaces:
            workspaces[u["workspace_id"]]["active_window_id"] = u["active_window_id"]
        dirty = True
    elif "WindowOpenedOrChanged" in ev:
        win = ev["WindowOpenedOrChanged"]["window"]
        windows[win["id"]] = win
        if win.get("is_focused"):
            for other in windows.values():
                if other["id"] != win["id"]:
                    other["is_focused"] = False
        dirty = True
    elif "WindowClosed" in ev:
        windows.pop(ev["WindowClosed"]["id"], None)
        dirty = True
    elif "WindowFocusChanged" in ev:
        fid = ev["WindowFocusChanged"]["id"]
        for win in windows.values():
            win["is_focused"] = win["id"] == fid
        dirty = True
    return dirty


workspaces = {}
windows = {}
sock_path = os.environ.get("NIRI_SOCKET")

# The stream ends on EOF or a malformed line: reconnect and rebuild from the
# fresh full snapshot niri sends on connect.
while True:
    if not sock_path:
        time.sleep(5)
        continue
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(sock_path)
            sock.sendall(b'"EventStream"\n')
            stream = sock.makefile("r")
            try:
                reply = json.loads(stream.readline())
            except Exception:
                reply = {}
            if not (isinstance(reply, dict) and reply.get("Ok") == "Handled"):
                time.sleep(1)
                continue
            for raw in stream:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    ev = json.loads(raw)
                except Exception:
                    break
                if handle(ev):
                    try:
                        write(render(workspaces, windows))
                    except Exception:
                        pass
    except Exception:
        pass
    time.sleep(1)
PY
