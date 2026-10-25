import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// HyprlandPage — BarEditor tab (System group): the 12 window-effect / layout
// knobs of the window-controls widget (SUPER+SHIFT+B).
//
//   · Read/save: core/HyprEffects.qml (singleton) + core/scripts/
//     hypr-effects.sh — SAME kernel as WindowControls. Reads the live values
//     with `hyprctl -j getoption` (gaps arrive as "css gap data") and applies
//     PARTIAL changes live (`hyprctl eval`, no reload).
// Gate: the body is created once `bar` has been injected.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    // The 12 knobs live in the shared HyprEffects singleton (same kernel as
    // Window Controls): moving one knob no longer rewrites the rest — the old
    // bug rewrote all 12 with misread gaps (16/25).
    readonly property var fx: HyprEffects.values

    // Gate: el cuerpo se crea cuando bar ya está inyectado (initial
    // property aplicada tras la creación del root). Evita bindings
    // evaluados con bar null que quedaban muertos en negro.
    readonly property var flickable: body.item ? body.item.flickable : null

    // Re-read the live values when the page opens (the singleton also
    // refreshes itself when the shell starts).
    Component.onCompleted: HyprEffects.refresh()

    // Reset: opacities/blur/rounding/shadow only (gaps and border untouched,
    // same as WindowControls.resetDefaults). Applied by the singleton.
    function resetDefaults() { HyprEffects.resetEffects(); }

    Loader {
        id: body
        anchors.fill: parent
        active: root.bar !== null
        sourceComponent: pageBody
    }

    Component {
        id: pageBody
        Item {
            anchors.fill: parent
            property alias flickable: pageFlick

            Flickable {
                id: pageFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: pageCol.height + bar.s(Theme.gapLg)
                ScrollBar.vertical: ScrollBar {
                    id: vScroll
                    width: bar.s(4)
                    policy: ScrollBar.AsNeeded
                    hoverEnabled: true
                    active: pageFlick.moving || vScroll.hovered
                    contentItem: Rectangle {
                        radius: bar.s(Theme.radiusXs)
                        color: Theme.surfaceContainerHighest
                        opacity: vScroll.active ? 1.0 : 0.45
                    }
                    background: Item {}
                }

                Column {
                    id: pageCol
                    x: bar.s(Theme.gapSm)
                    y: bar.s(Theme.gapSm)
                    width: pageFlick.width - bar.s(Theme.gapLg)
                    spacing: bar.s(Theme.gapLg)

                    // Título de página (GP:1007-1014)
                    Text {
                        text: Compositor.isNiri ? "Effects" : "Hyprland"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: Compositor.isNiri
                            ? "Window effects, layout and borders. Applies through the niri effects writer and persists in generated KDL (same knobs as SUPER+SHIFT+B)."
                            : "Window effects, layout and borders. Applies live, no reload (same knobs as SUPER+SHIFT+B)."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    // ── Opacity ─────────────────────────────────────────────
                    Text {
                        text: "Opacity"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF06E"
                        label: "Active Opacity"
                        from: 0.3; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.mauve
                        value: fx.active_opacity
                        onEdited: (v) => HyprEffects.set("active_opacity", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF070"
                        label: "Inactive Opacity"
                        from: 0.3; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.blue
                        value: fx.inactive_opacity
                        onEdited: (v) => HyprEffects.set("inactive_opacity", v)
                    }

                    // ── Rounding ────────────────────────────────────────────
                    Text {
                        text: "Rounding"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF192"
                        label: "Rounding"
                        from: 0; to: 35; step: 1
                        suffix: "px"
                        accentColor: bar.colors.green
                        value: fx.rounding
                        onEdited: (v) => HyprEffects.set("rounding", v)
                    }

                    // ── Blur ────────────────────────────────────────────────
                    Text {
                        text: "Blur"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF0EB"
                        label: "Blur Size"
                        from: 0; to: 24; step: 1
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: fx.blur_size
                        onEdited: (v) => HyprEffects.set("blur_size", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF2C8"
                        label: "Blur Passes"
                        from: 0; to: 10; step: 1
                        accentColor: bar.colors.sapphire
                        value: fx.blur_passes
                        onEdited: (v) => HyprEffects.set("blur_passes", v)
                    }

                    // ── Layout ──────────────────────────────────────────────
                    Text {
                        text: "Layout"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF239"
                        label: "Gaps In"
                        from: 0; to: 50; step: 2
                        suffix: "px"
                        accentColor: bar.colors.mauve
                        value: fx.gaps_in
                        onEdited: (v) => HyprEffects.set("gaps_in", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF108"
                        label: "Gaps Out"
                        from: 0; to: 50; step: 2
                        suffix: "px"
                        accentColor: bar.colors.blue
                        value: fx.gaps_out
                        onEdited: (v) => HyprEffects.set("gaps_out", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF358"
                        label: "Border Width"
                        from: 0; to: 20; step: 1
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: fx.border_size
                        onEdited: (v) => HyprEffects.set("border_size", v)
                    }

                    // ── Shadow ──────────────────────────────────────────────
                    Text {
                        text: "Shadow"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF042"
                        label: "Shadow Range"
                        from: 0; to: 50; step: 1
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: fx.shadow_range
                        onEdited: (v) => HyprEffects.set("shadow_range", v)
                    }
                    EffectSlider {
                        width: parent.width
                        visible: !Compositor.isNiri
                        bar: root.bar
                        icon: "\uF0E7"
                        label: "Shadow Power"
                        from: 0; to: 10; step: 1
                        accentColor: bar.colors.sapphire
                        value: fx.shadow_render_power
                        onEdited: (v) => HyprEffects.set("shadow_render_power", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF061"
                        label: "Shadow Offset X"
                        from: -30; to: 30; step: 1
                        suffix: "px"
                        accentColor: bar.colors.mauve
                        value: fx.shadow_offset_x
                        onEdited: (v) => HyprEffects.set("shadow_offset_x", v)
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF063"
                        label: "Shadow Offset Y"
                        from: -30; to: 30; step: 1
                        suffix: "px"
                        accentColor: bar.colors.green
                        value: fx.shadow_offset_y
                        onEdited: (v) => HyprEffects.set("shadow_offset_y", v)
                    }

                    // ── Window borders (shared component, also in Bar → Style) ──
                    WindowBordersSection {
                        width: parent.width
                        bar: root.bar
                        titlePx: 16
                    }

                    // Acciones: Reset (defaults del widget) + Refresh de lectura.
                    Row {
                        width: parent.width
                        spacing: bar.s(Theme.gapMd)
                        EditorButton {
                            bar: root.bar
                            compact: true
                            icon: "\uF0E2"
                            label: "Reset"
                            onActivated: root.resetDefaults()
                        }
                        EditorButton {
                            bar: root.bar
                            compact: true
                            icon: "\uF021"
                            label: "Refresh"
                            onActivated: root.loadCurrent()
                        }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: Compositor.isNiri
                            ? "Border colors follow the active palette. Gaps, blur and shadows persist in ~/.config/niri/generated/theme-effects.kdl."
                            : "Border colors follow the active palette. Gaps, blur and shadows persist via config/gaps.lua and config/window-effects.lua."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
