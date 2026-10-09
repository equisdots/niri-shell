#!/usr/bin/env bash
# Compositor-aware keyboard-layout fetcher.
#
# Emits the first two letters of the active layout, uppercased, so the bar
# module (ui/bar/modules/KeyboardModule.qml) keeps its two-character contract.
#
#   Hyprland: hyprctl devices -j -> .keyboards[].active_keymap
#   niri:     niri msg --json keyboard-layouts -> .names[.current_idx]
#
# XDG_CURRENT_DESKTOP selects the branch; Hyprland is the fallback so a
# Hyprland user is unaffected by the niri meta.
set -u

desktop="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"

case "$desktop" in
    *niri*)
        raw="$(LC_ALL=C niri msg --json keyboard-layouts 2>/dev/null \
            | jq -r '.names[.current_idx] // empty' 2>/dev/null)"
        if [ -z "$raw" ] || [ "$raw" = "null" ]; then
            layout="us"
        else
            # "English (US)" -> "US"; "us" -> "us"; anything else -> first two.
            code="$(printf '%s' "$raw" | sed -n 's/.*(\([A-Za-z][A-Za-z]\)).*/\1/p')"
            [ -z "$code" ] && code="$(printf '%s' "$raw" | sed -n 's/^\([A-Za-z][A-Za-z]\).*/\1/p')"
            [ -z "$code" ] && code="$raw"
            layout="$code"
        fi
        ;;
    *)
        layout="$(LC_ALL=C hyprctl devices -j 2>/dev/null \
            | jq -r '(.keyboards[] | select(.main == true) | .active_keymap) // .keyboards[0].active_keymap // empty' \
            | head -n1)"
        [[ -z "$layout" || "$layout" == "null" ]] && layout="US"
        ;;
esac

echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
