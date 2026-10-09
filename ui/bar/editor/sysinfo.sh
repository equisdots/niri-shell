#!/usr/bin/env bash
# System + stack information for the About page (one KEY=VALUE per line).
. /etc/os-release 2>/dev/null

SETTINGS="$HOME/.config/hypr/settings.json"

# Compositor split: XDG_CURRENT_DESKTOP selects the branch (Hyprland fallback),
# matching core/Compositor.qml. The KEY=VALUE output contract is unchanged.
desktop="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
case "$desktop" in
    *niri*) NIRI=1 ;;
    *)      NIRI=0 ;;
esac

echo "os=${PRETTY_NAME:-unknown}"
echo "host=$(cat /etc/hostname 2>/dev/null || hostname)"
echo "kernel=$(uname -r)"
if [ "$NIRI" = "1" ]; then
    echo "wm=niri"
    echo "hypr_ver=$(niri msg --json version 2>/dev/null | jq -r '.compositor // "unknown"' 2>/dev/null || echo unknown)"
else
    echo "wm=$(hyprctl version 2>/dev/null | head -1 | cut -d' ' -f1 || echo unknown)"
    echo "hypr_ver=$(hyprctl version -j 2>/dev/null | jq -r '.tag // "unknown"' 2>/dev/null || echo unknown)"
fi
echo "qs_ver=$(qs --version 2>/dev/null | awk '{print $2}' || echo unknown)"
echo "user=${USER:-unknown}"
echo "shell=$(basename "${SHELL:-sh}")"
up="$(uptime -p 2>/dev/null)"; echo "uptime=${up#up }"
echo "boot=$(uptime -s 2>/dev/null || echo unknown)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
echo "gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d controller' | head -1 | sed 's/.*: //')"
echo "memory=$(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
echo "disk=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"

bat="$(upower -e 2>/dev/null | grep -m1 BAT)"
if [ -n "$bat" ]; then
    pct="$(upower -i "$bat" 2>/dev/null | awk '/percentage/ {print $2; exit}')"
    st="$(upower -i "$bat" 2>/dev/null | awk '/state/ {print $2; exit}')"
    echo "battery=${pct:-?} (${st:-?})"
else
    echo "battery=desktop"
fi

# Network
iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)"
echo "iface=${iface:-none}"
echo "ip=$(ip -4 addr show "${iface:-lo}" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
# SSID: iwgetid reads the current association instantly; the nmcli path only
# as a fallback (listing wifi with nmcli triggers a scan and took ~5s).
if command -v iwgetid >/dev/null 2>&1; then
    echo "ssid=$(iwgetid -r 2>/dev/null)"
else
    echo "ssid=$(timeout 2 nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')"
fi

# Monitors
if [ "$NIRI" = "1" ]; then
    mon="$(niri msg --json outputs 2>/dev/null)"
    echo "res=$(printf '%s' "$mon" | jq -r 'to_entries[0].value as $o | ($o.modes[$o.current_mode] // $o.modes[0]) | "\(.width)x\(.height)"' 2>/dev/null || echo unknown)"
    echo "refresh=$(printf '%s' "$mon" | jq -r 'to_entries[0].value as $o | (($o.modes[$o.current_mode] // $o.modes[0]).refresh_rate // 0) as $r | (($r / 1000) | round | tostring) + " Hz"' 2>/dev/null || echo unknown)"
    echo "monitors=$(printf '%s' "$mon" | jq -r 'length' 2>/dev/null || echo 0)"
    echo "scale=$(printf '%s' "$mon" | jq -r 'to_entries[0].value.logical.scale // 1' 2>/dev/null || echo 1)"
else
    mon="$(hyprctl monitors -j 2>/dev/null)"
    echo "res=$(echo "$mon" | jq -r '.[0] | "\(.width)x\(.height)"' 2>/dev/null || echo unknown)"
    echo "refresh=$(echo "$mon" | jq -r '.[0].refreshRate | round | tostring + " Hz"' 2>/dev/null || echo unknown)"
    echo "monitors=$(echo "$mon" | jq -r 'length' 2>/dev/null || echo 0)"
    echo "scale=$(echo "$mon" | jq -r '.[0].scale' 2>/dev/null || echo 1)"
fi

# equisdots customization summary
echo "palette=$(jq -r '.bar.palette // "x"' "$SETTINGS" 2>/dev/null || echo x)"
echo "bar_engine=$(jq -r '.barEngine // "bar"' "$SETTINGS" 2>/dev/null || echo bar)"
echo "gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

VER_FILE="$HOME/.local/state/equisdots-version"
if [ -f "$VER_FILE" ]; then
    . "$VER_FILE" 2>/dev/null
    echo "stack_ver=${LOCAL_VERSION:-n/a}"
    echo "stack_date=$(date -r "$VER_FILE" '+%Y-%m-%d' 2>/dev/null || echo n/a)"
else
    echo "stack_ver=n/a"
    echo "stack_date=n/a"
fi

# timex engine status (provider|city|unit|configured|key_set|last_update|error)
TX="$("$HOME/.local/bin/timex" status 2>/dev/null || timex status 2>/dev/null)"
if [ -n "$TX" ]; then
    IFS='|' read -r t_prov t_city t_unit _t_conf _t_key t_up t_err <<< "$TX"
    echo "timex_provider=${t_prov:-—}"
    echo "timex_city=${t_city:-—}"
    echo "timex_unit=${t_unit:-—}"
    if [ -n "$t_up" ] && [ "$t_up" != "0" ]; then
        echo "timex_updated=$(date -d "@$t_up" '+%H:%M' 2>/dev/null || echo n/a)"
    else
        echo "timex_updated=never"
    fi
    echo "timex_error=${t_err:-}"
else
    echo "timex_provider=—"; echo "timex_city=—"; echo "timex_unit=—"
    echo "timex_updated=—"; echo "timex_error="
fi

# Repo revisions (dots clones; empty when the system was not installed via dots).
# A trailing * marks a dirty working tree.
for r in shell hyprland palettes theme-sync davincix timex dots; do
    d="$HOME/.local/share/equisdots/$r"
    if [ -d "$d/.git" ]; then
        rev="$(git -C "$d" rev-parse --short HEAD 2>/dev/null)"
        [ -n "$rev" ] && git -C "$d" status --porcelain 2>/dev/null | grep -q . && rev="${rev}*"
        echo "repo_$r=$rev"
    else
        echo "repo_$r="
    fi
done
