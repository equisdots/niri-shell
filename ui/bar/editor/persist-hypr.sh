#!/usr/bin/env bash
# Compatibility forwarder.
#
# The Settings panel (ui/bar/BarEditor.qml) still invokes `persist-hypr.sh`.
# The real, compositor-neutral implementation is persist-appearance.sh; this
# shim forwards every argument to it so existing callers keep working after the
# niri overlay is deployed. Hyprland keeps its Lua output, niri gets KDL.
exec bash "$(dirname "${BASH_SOURCE[0]}")/persist-appearance.sh" "$@"
