#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# effects.sh — shared kernel for the window-effect knobs
# (BarEditor -> appearance tab and Window Controls, SUPER+SHIFT+B).
#
# Same CLI and JSON state contract as the Hyprland-only hypr-effects.sh:
#
#   read                prints key=value (live values under Hyprland)
#   preview KEY=VAL ... updates the JSON state (source of truth)
#   persist             materialises the state for the compositor
#   apply KEY=VAL ...   preview + persist
#
# Compositor split (selected by XDG_CURRENT_DESKTOP, Hyprland fallback):
#
#   Hyprland: live read via `hyprctl -j getoption`, live preview via
#             `hyprctl eval`, persist writes config/window-effects.lua and
#             config/gaps.lua (one Hyprland auto-reload).
#   niri:     no getoption and no arbitrary runtime patch, so `read` returns the
#             stored state, `preview` only updates the JSON, and `persist`
#             writes generated/theme-effects.kdl and reloads. niri reloads of
#             `layout` do not restart clients, so a single write is smooth.
#
# State lives in config/window-effects.json (Hyprland) or
# generated/theme-effects.json (niri) and is seeded from the defaults the first
# time. A partial change can never clobber the other knobs.
#
# Environment:
#   HYPR_CONFIG_DIR    Hyprland output dir (default ~/.config/hypr/config)
#   NIRI_GENERATED_DIR niri output dir   (default ~/.config/niri/generated)
#   HYPR_NO_EVAL=1     do not call hyprctl (tests)
#   NIRI_NO_RELOAD=1   do not call niri   (tests)
# ═══════════════════════════════════════════════════════════════════════════
set -u

desktop="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
case "$desktop" in
    *niri*) NIRI=1 ;;
    *)      NIRI=0 ;;
esac

if [[ "$NIRI" == "1" ]]; then
    CONF_DIR="${NIRI_GENERATED_DIR:-$HOME/.config/niri/generated}"
    STATE="$CONF_DIR/theme-effects.json"
    KDL_OUT="$CONF_DIR/theme-effects.kdl"
else
    CONF_DIR="${HYPR_CONFIG_DIR:-$HOME/.config/hypr/config}"
    STATE="$CONF_DIR/window-effects.json"
fi
mkdir -p "$CONF_DIR" || exit 1

# join with ", " (for the Lua snippets and tables)
join() { local IFS=', '; printf '%s' "$*"; }

# ═══════════════════════════════════════════════════════════════════════════
# Hyprland path (verbatim behaviour of the previous hypr-effects.sh)
# ═══════════════════════════════════════════════════════════════════════════

# key · option · kind (float|int|cssgap|vec2x|vec2y)
SPECS=(
    "active_opacity decoration:active_opacity float"
    "inactive_opacity decoration:inactive_opacity float"
    "rounding decoration:rounding int"
    "blur_size decoration:blur:size int"
    "blur_passes decoration:blur:passes int"
    "gaps_in general:gaps_in cssgap"
    "gaps_out general:gaps_out cssgap"
    "border_size general:border_size int"
    "shadow_range decoration:shadow:range int"
    "shadow_render_power decoration:shadow:render_power int"
    "shadow_offset_x decoration:shadow:offset vec2x"
    "shadow_offset_y decoration:shadow:offset vec2y"
)

read_one() {
    local key="$1" opt="$2" kind="$3" json v
    json="$(hyprctl -j getoption "$opt" 2>/dev/null)" || return 0
    case "$kind" in
        float)  v="$(jq -r '.float // empty' <<<"$json")" ;;
        int)    v="$(jq -r '.int // empty' <<<"$json")" ;;
        # Hyprland 0.55+ returns "css gap data: 48 48 48 48" (.css field);
        # the UI is scalar, so take the first side.
        cssgap) v="$(jq -r '.css // empty' <<<"$json" | awk '{print $1}')" ;;
        vec2x)  v="$(jq -r '.vec2[0] // empty' <<<"$json")" ;;
        vec2y)  v="$(jq -r '.vec2[1] // empty' <<<"$json")" ;;
    esac
    if [[ -n "$v" && "$v" != "null" ]]; then
        printf '%s=%s\n' "$key" "$v"
    fi
}

cmd_read() {
    local spec
    for spec in "${SPECS[@]}"; do
        read_one $spec
    done
}

seed_state() {
    local json='{}' line k v tmp
    while IFS='=' read -r k v; do
        [[ -z "$k" ]] && continue
        json="$(jq -c --arg k "$k" --argjson v "$v" '. + {($k): $v}' <<<"$json")" || return 1
    done < <(cmd_read)
    tmp="$(mktemp "$CONF_DIR/.we-state.XXXXXX")" || return 1
    printf '%s\n' "$json" > "$tmp" && mv "$tmp" "$STATE"
}

write_lua() {
    local state="$1" tmp
    local ao io ro bs bp gr go bw sr sp ox oy
    ao="$(jq -r '.active_opacity // 0.85'       <<<"$state")"
    io="$(jq -r '.inactive_opacity // 0.80'     <<<"$state")"
    ro="$(jq -r '.rounding // 20'               <<<"$state")"
    bs="$(jq -r '.blur_size // 8'               <<<"$state")"
    bp="$(jq -r '.blur_passes // 3'             <<<"$state")"
    gr="$(jq -r '.gaps_in // 16'                <<<"$state")"
    go="$(jq -r '.gaps_out // 25'               <<<"$state")"
    bw="$(jq -r '.border_size // 2'             <<<"$state")"
    sr="$(jq -r '.shadow_range // 35'           <<<"$state")"
    sp="$(jq -r '.shadow_render_power // 5'     <<<"$state")"
    ox="$(jq -r '.shadow_offset_x // 0'         <<<"$state")"
    oy="$(jq -r '.shadow_offset_y // 10'        <<<"$state")"

    tmp="$(mktemp "$CONF_DIR/.we-lua.XXXXXX")" || return 1
    cat > "$tmp" <<LUA
-- Auto-generated by core/scripts/effects.sh — do not edit manually
hl.config({
    decoration = {
        active_opacity   = $ao,
        inactive_opacity = $io,
        rounding         = $ro,

        blur = {
            size   = $bs,
            passes = $bp,
        },

        shadow = {
            range        = $sr,
            render_power = $sp,
            offset       = { $ox, $oy },
        },
    },
})
LUA
    if command -v luac >/dev/null 2>&1 && ! luac -p "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "error: window-effects.lua does not compile" >&2
        return 1
    fi
    mv "$tmp" "$CONF_DIR/window-effects.lua"

    tmp="$(mktemp "$CONF_DIR/.we-lua.XXXXXX")" || return 1
    cat > "$tmp" <<LUA
-- Auto-generated by core/scripts/effects.sh — do not edit manually
hl.config({
    general = {
        gaps_in     = $gr,
        gaps_out    = $go,
        border_size = $bw,
    },
})
LUA
    if command -v luac >/dev/null 2>&1 && ! luac -p "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "error: gaps.lua does not compile" >&2
        return 1
    fi
    mv "$tmp" "$CONF_DIR/gaps.lua"
}

# Applies LIVE only the patched keys (hl.config merges partial tables:
# it does not touch the rest of general/decoration).
apply_live() {
    local state pair k v
    state="$(cat "$STATE")"
    local -A patch=()
    for pair in "$@"; do
        patch["${pair%%=*}"]="${pair#*=}"
    done

    local general=() dec=() blur=() shadow=()
    [[ -n "${patch[gaps_in]:-}"     ]] && general+=("gaps_in = ${patch[gaps_in]}")
    [[ -n "${patch[gaps_out]:-}"    ]] && general+=("gaps_out = ${patch[gaps_out]}")
    [[ -n "${patch[border_size]:-}" ]] && general+=("border_size = ${patch[border_size]}")

    [[ -n "${patch[active_opacity]:-}"   ]] && dec+=("active_opacity = ${patch[active_opacity]}")
    [[ -n "${patch[inactive_opacity]:-}" ]] && dec+=("inactive_opacity = ${patch[inactive_opacity]}")
    [[ -n "${patch[rounding]:-}"         ]] && dec+=("rounding = ${patch[rounding]}")
    [[ -n "${patch[blur_size]:-}"   ]] && blur+=("size = ${patch[blur_size]}")
    [[ -n "${patch[blur_passes]:-}" ]] && blur+=("passes = ${patch[blur_passes]}")
    [[ -n "${patch[shadow_range]:-}"        ]] && shadow+=("range = ${patch[shadow_range]}")
    [[ -n "${patch[shadow_render_power]:-}" ]] && shadow+=("render_power = ${patch[shadow_render_power]}")
    if [[ -n "${patch[shadow_offset_x]:-}" || -n "${patch[shadow_offset_y]:-}" ]]; then
        shadow+=("offset = { $(jq -r '.shadow_offset_x' <<<"$state"), $(jq -r '.shadow_offset_y' <<<"$state") }")
    fi

    local top=()
    [[ ${#general[@]} -gt 0 ]] && top+=("general = { $(join "${general[@]}") }")
    [[ ${#blur[@]}    -gt 0 ]] && dec+=("blur = { $(join "${blur[@]}") }")
    [[ ${#shadow[@]}  -gt 0 ]] && dec+=("shadow = { $(join "${shadow[@]}") }")
    [[ ${#dec[@]}     -gt 0 ]] && top+=("decoration = { $(join "${dec[@]}") }")
    [[ ${#top[@]} -eq 0 ]] && return 0

    hyprctl eval "hl.config({ $(join "${top[@]}") })" >/dev/null 2>&1
}

# Merge the given key=values into the JSON state and print the new state.
update_state() {
    [[ $# -eq 0 ]] && { cat "$STATE" 2>/dev/null || echo '{}'; return 0; }
    [[ -f "$STATE" ]] || seed_state
    local state pair k v
    state="$(cat "$STATE")"
    for pair in "$@"; do
        k="${pair%%=*}"
        v="${pair#*=}"
        state="$(jq -c --arg k "$k" --argjson v "$v" '.[$k] = $v' <<<"$state")" || return 1
    done
    printf '%s\n' "$state"
}

save_state() {
    local tmp
    tmp="$(mktemp "$CONF_DIR/.we-state.XXXXXX")" || return 1
    printf '%s\n' "$1" > "$tmp" && mv "$tmp" "$STATE"
}

cmd_preview() {
    [[ $# -eq 0 ]] && return 0
    local state
    state="$(update_state "$@")" || return 1
    save_state "$state" || return 1
    [[ "${HYPR_NO_EVAL:-0}" == "1" ]] || apply_live "$@"
    printf 'effects: previewed %s\n' "$*"
}

cmd_persist() {
    [[ -f "$STATE" ]] || seed_state
    write_lua "$(cat "$STATE")" || return 1
    # The two Lua writes can race Hyprland's auto-reload (it may read one file
    # before the other lands): re-apply the full state after writing so the
    # live values always match the JSON, whatever the reload read.
    if [[ "${HYPR_NO_EVAL:-0}" != "1" ]]; then
        local args=()
        while IFS= read -r kv; do args+=("$kv"); done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$STATE")
        apply_live "${args[@]}"
    fi
    printf 'effects: persisted\n'
}

cmd_apply() {
    cmd_preview "$@" || return 1
    cmd_persist
}

# ═══════════════════════════════════════════════════════════════════════════
# niri path
# ═══════════════════════════════════════════════════════════════════════════

# Defaults mirror core/Effects.qml -> values.
NIRI_DEFAULTS='{"active_opacity":0.85,"inactive_opacity":0.80,"rounding":20,"blur_size":8,"blur_passes":3,"gaps_in":16,"gaps_out":25,"border_size":2,"shadow_range":35,"shadow_render_power":5,"shadow_offset_x":0,"shadow_offset_y":10}'

niri_seed_state() {
    [[ -f "$STATE" ]] && return 0
    local tmp
    tmp="$(mktemp "$CONF_DIR/.we-state.XXXXXX")" || return 1
    printf '%s\n' "$NIRI_DEFAULTS" > "$tmp" && mv "$tmp" "$STATE"
}

niri_read() {
    niri_seed_state
    jq -r 'to_entries[] | "\(.key)=\(.value)"' "$STATE" 2>/dev/null
}

niri_update_state() {
    [[ $# -eq 0 ]] && { cat "$STATE" 2>/dev/null || echo '{}'; return 0; }
    niri_seed_state
    local state pair k v
    state="$(cat "$STATE")"
    for pair in "$@"; do
        k="${pair%%=*}"
        v="${pair#*=}"
        state="$(jq -c --arg k "$k" --argjson v "$v" '.[$k] = $v' <<<"$state")" || return 1
    done
    printf '%s\n' "$state"
}

niri_preview() {
    [[ $# -eq 0 ]] && return 0
    local state
    state="$(niri_update_state "$@")" || return 1
    save_state "$state" || return 1
    # niri has no per-frame runtime patch: the visible change lands on persist.
    printf 'effects: previewed %s (niri applies on persist)\n' "$*"
}

niri_write_kdl() {
    local state="$1" tmp
    local ao io ro bs bp gr go bw sr sp ox oy
    ao="$(jq -r '.active_opacity // 0.85'     <<<"$state")"
    io="$(jq -r '.inactive_opacity // 0.80'   <<<"$state")"
    ro="$(jq -r '.rounding // 20'             <<<"$state")"
    bp="$(jq -r '.blur_passes // 3'           <<<"$state")"
    gr="$(jq -r '.gaps_in // 16'              <<<"$state")"
    go="$(jq -r '.gaps_out // 25'             <<<"$state")"
    bw="$(jq -r '.border_size // 2'           <<<"$state")"
    sr="$(jq -r '.shadow_range // 35'         <<<"$state")"
    sp="$(jq -r '.shadow_render_power // 5'   <<<"$state")"
    ox="$(jq -r '.shadow_offset_x // 0'       <<<"$state")"
    oy="$(jq -r '.shadow_offset_y // 10'      <<<"$state")"

    # niri has a single `gaps` value (inner and outer). Reproduce the split the
    # UI exposes with `gaps` = gaps_in and equal struts = gaps_out - gaps_in.
    local strut
    strut="$(awk -v o="$go" -v i="$gr" 'BEGIN { d = o - i; if (d < 0) d = 0; printf "%g", d }')"

    # Shadow range <= 0 turns the shadow off.
    local shadow_line="off"
    local shadow_body=""
    if awk -v s="$sr" 'BEGIN { exit !(s > 0) }'; then
        shadow_line="on"
        shadow_body="        softness $sr
        offset x=$ox y=$oy"
    fi

    tmp="$(mktemp "$CONF_DIR/.niri-effects.XXXXXX")" || return 1
    cat > "$tmp" <<KDL
// Auto-generated by core/scripts/effects.sh. Do not edit manually.
layout {
    gaps $gr
    struts {
        left $strut
        right $strut
        top $strut
        bottom $strut
    }
    border {
        on
        width $bw
    }
    shadow {
        $shadow_line
$shadow_body
    }
}
blur {
    passes $bp
    offset 3
    noise 0.02
    saturation 1.5
}
window-rule {
    geometry-corner-radius $ro
    opacity $ao
}
KDL
    # `inactive_opacity` and `blur_size`/`shadow_render_power` have no global
    # niri equivalent; they are kept in the JSON state only.
    if command -v niri >/dev/null 2>&1 && ! niri validate -c "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "error: theme-effects.kdl did not validate" >&2
        return 1
    fi
    mv "$tmp" "$KDL_OUT"
}

niri_persist() {
    niri_seed_state
    niri_write_kdl "$(cat "$STATE")" || return 1
    if [[ "${NIRI_NO_RELOAD:-0}" != "1" ]]; then
        niri msg action load-config-file >/dev/null 2>&1 || true
    fi
    printf 'effects: persisted\n'
}

niri_apply() {
    niri_preview "$@" || return 1
    niri_persist
}

# ═══════════════════════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════════════════════
if [[ "$NIRI" == "1" ]]; then
    case "${1:-}" in
        read)    niri_read ;;
        preview) shift; niri_preview "$@" ;;
        persist) niri_persist ;;
        apply)   shift; niri_apply "$@" ;;
        *)       echo "usage: effects.sh read | preview KEY=VAL ... | persist | apply KEY=VAL ..." >&2; exit 1 ;;
    esac
else
    case "${1:-}" in
        read)    cmd_read ;;
        preview) shift; cmd_preview "$@" ;;
        persist) cmd_persist ;;
        apply)   shift; cmd_apply "$@" ;;
        *)       echo "usage: effects.sh read | preview KEY=VAL ... | persist | apply KEY=VAL ..." >&2; exit 1 ;;
    esac
fi
