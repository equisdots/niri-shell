import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// AnimationsPage — BarEditor tab (grupo System): on/off, velocidad global y
// transiciones de workspace (estilo, curva, scratchpads y wraparound).
//
// Las 6 curvas y las animaciones base viven en animations.lua; el panel no
// redefine las curvas, solo elige sus nombres y regenera
// config/user-animations.lua (cargado al final de hyprland.lua → siempre gana)
// con la velocidad escalada (speed = base × multiplier) y recarga. El guardado
// es debounced en BarEditor: applyAnimations → persist-hypr.sh animations, 600 ms.
// Gate: el cuerpo se crea cuando `bar` ya está inyectado (initial property
// aplicada tras la creación del root), evitando bindings evaluados con null.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    readonly property var flickable: body.item ? body.item.flickable : null

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
                        text: "Animations"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    // ── General ─────────────────────────────────────────────
                    Text {
                        text: "General"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰔟"
                        label: "Enabled"
                        checked: root.bar.animationsCfg.enabled
                        onToggled: root.bar.applyAnimations({ enabled: !root.bar.animationsCfg.enabled })
                    }

                    // ── Velocidad ───────────────────────────────────────────
                    Text {
                        text: "Speed"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 4
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰒮"
                            label: "Snappy"
                            active: Math.abs(root.bar.animationsCfg.speed - 0.6) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 0.6 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰐊"
                            label: "Fast"
                            active: Math.abs(root.bar.animationsCfg.speed - 0.8) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 0.8 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰓅"
                            label: "Normal"
                            active: Math.abs(root.bar.animationsCfg.speed - 1.0) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 1.0 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰒲"
                            label: "Slow"
                            active: Math.abs(root.bar.animationsCfg.speed - 1.5) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 1.5 })
                        }
                    }
                    StepperCard {
                        width: parent.width
                        bar: root.bar
                        label: "Speed ×"
                        value: Number(root.bar.animationsCfg.speed).toFixed(1) + "×"
                        onDec: root.bar.applyAnimations({
                            speed: Math.max(0.5, Math.round((root.bar.animationsCfg.speed - 0.1) * 10) / 10)
                        })
                        onInc: root.bar.applyAnimations({
                            speed: Math.min(2.0, Math.round((root.bar.animationsCfg.speed + 0.1) * 10) / 10)
                        })
                    }

                    // ── Workspace transitions ───────────────────────────────
                    Text {
                        text: "Workspace transitions"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        visible: !Compositor.isNiri
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        Repeater {
                            model: [
                                { id: "slide",           label: "Slide",       icon: "󰒮" },
                                { id: "slidefade",       label: "Slide fade",  icon: "󰖌" },
                                { id: "slidevert",       label: "Slide vert",  icon: "󰁝" },
                                { id: "slidefadevert",   label: "Vert fade",   icon: "󰒲" },
                                { id: "fade",            label: "Fade",        icon: "󰔟" }
                            ]
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                bar: root.bar
                                icon: modelData.icon
                                label: modelData.label
                                active: root.bar.animationsCfg.workspaceStyle === modelData.id
                                onActivated: root.bar.applyAnimations({ workspaceStyle: modelData.id })
                            }
                        }
                    }

                    Text {
                        text: "Curve"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        Repeater {
                            model: [
                                { id: "smooth",         label: "Smooth",       icon: "󰒮" },
                                { id: "overshot",       label: "Overshot",     icon: "󰁝" },
                                { id: "easeOutExpo",    label: "Ease out expo", icon: "󰓅" },
                                { id: "easeOutQuint",   label: "Ease out quint", icon: "󰐊" },
                                { id: "easeInOutQuart", label: "Ease in-out",  icon: "󰒲" },
                                { id: "linear",         label: "Linear",       icon: "󰁔" }
                            ]
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                bar: root.bar
                                icon: modelData.icon
                                label: modelData.label
                                active: root.bar.animationsCfg.workspaceCurve === modelData.id
                                onActivated: root.bar.applyAnimations({ workspaceCurve: modelData.id })
                            }
                        }
                    }

                    Text {
                        text: "Special workspace"
                        visible: !Compositor.isNiri
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        visible: !Compositor.isNiri
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        Repeater {
                            model: [
                                { id: "slide",         label: "Slide",      icon: "󰒮" },
                                { id: "slidefade",     label: "Slide fade", icon: "󰖌" },
                                { id: "slidevert",     label: "Slide vert", icon: "󰁝" },
                                { id: "slidefadevert", label: "Vert fade",  icon: "󰒲" },
                                { id: "fade",          label: "Fade",       icon: "󰔟" }
                            ]
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                bar: root.bar
                                icon: modelData.icon
                                label: modelData.label
                                active: root.bar.animationsCfg.specialStyle === modelData.id
                                onActivated: root.bar.applyAnimations({ specialStyle: modelData.id })
                            }
                        }
                    }

                    ToggleCard {
                        width: parent.width
                        visible: !Compositor.isNiri
                        bar: root.bar
                        icon: "󰁔"
                        label: "Wrap around"
                        checked: root.bar.animationsCfg.workspaceWrap === true
                        onToggled: root.bar.applyAnimations({
                            workspaceWrap: !(root.bar.animationsCfg.workspaceWrap === true)
                        })
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Hyprland writes config/user-animations.lua (Lua) and niri writes generated/user-animations.kdl (KDL). The curve drives the workspace slide/window movement on Hyprland and the workspace-switch transition on niri. Workspace styles, special workspaces and wraparound are Hyprland-only: niri parses and ignores them. Higher speed value = slower animation."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
