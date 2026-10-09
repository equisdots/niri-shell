#!/usr/bin/env bash
# Compositor-aware keyboard-layout event waiter.
#
# Blocks until the active keyboard layout changes, then exits. The shell
# restarts it after each fetch (see KeyboardModule/Bar poller pattern).
#
#   Hyprland: .socket2.sock, "activelayout>>" events
#   niri:     niri msg --json event-stream, "KeyboardLayoutSwitched" events
#
# Hyprland is the fallback, so its behaviour is unchanged.
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"

PIPE="$QS_RUN_DIR/qs_kb_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

desktop="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"

if [ -n "${NIRI_SOCKET:-}" ] || printf '%s' "$desktop" | grep -q niri; then
    # niri sends the full snapshot on connect, then deltas; grep keeps only the
    # active-layout switch so the waiter does not fire on unrelated events.
    niri msg --json event-stream 2>/dev/null \
        | grep --line-buffered -E '"KeyboardLayoutSwitched"' > "$PIPE" &
elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    LC_ALL=C socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock 2>/dev/null \
        | grep --line-buffered "activelayout>>" > "$PIPE" &
else
    sleep 10 > "$PIPE" &
fi

read -r _ < "$PIPE"
sleep 0.05
