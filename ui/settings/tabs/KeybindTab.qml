// ═══════════════════════════════════════════════════════════════════════════
// KeybindTab — pestaña "Keybind" de SettingsPopup, extraída del Component
// inline para poder compartirla (popup de settings + BarEditor).
//
// `host` = root de SettingsPopup: el cuerpo del tab quedó intacto y usa
// root.s(), root.<rol>, root.highlightedBox, etc. mediante el bloque de
// forwarding de abajo (mismos nombres que el root del popup).
//
// Layout (MD3): page header + dos tarjetas de sección (`surfaceContainerLow`,
// `radiusLg`, `outlineVariant`). Las filas de keybind viven DENTRO de la
// tarjeta, en su ColumnLayout interno: el ListView está dimensionado a su
// contenido (displayMargin 0 → nunca dibuja fuera de su caja), así que no
// puede solaparse con la tarjeta de Workspaces de arriba.
// ═══════════════════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../../core"

Item {
    id: root

    // ════ Forwarding al host (SettingsPopup) ════
    // El cuerpo de este tab quedó intacto y sigue usando root.s(),
    // root.<rol>, root.highlightedBox… vía estos proxies.
    property var host: null
    readonly property color base: host ? host.base : "#363537"
    readonly property color green: host ? host.green : "#7bd88f"
    readonly property color overlay0: host ? host.overlay0 : "#f7f1ff"
    readonly property color peach: host ? host.peach : "#fd9353"
    readonly property color red: host ? host.red : "#fc618d"
    readonly property color subtext0: host ? host.subtext0 : "#f7f1ff"
    readonly property color surface0: host ? host.surface0 : "#363537"
    readonly property color surface1: host ? host.surface1 : "#363537"
    readonly property color surface2: host ? host.surface2 : "#363537"
    readonly property color text: host ? host.text : "#f7f1ff"
    function s(val) { return host ? host.s(val) : val; }
    // highlightedBox se escribe desde este tab y desde el host: proxy bidireccional
    // (re-arma el binding tras cada escritura local para no desincronizar).
    property int highlightedBox: host ? host.highlightedBox : -1
    onHighlightedBoxChanged: {
        if (host && host.highlightedBox !== highlightedBox) {
            host.highlightedBox = highlightedBox;
            highlightedBox = Qt.binding(function() { return host ? host.highlightedBox : -1; });
        }
    }

    function clearHighlight() { if (host) host.clearHighlight(); }

    property var dynamicKeybindsModel: host ? host.kbModel : null
    function saveAllKeybinds() { if (host) host.saveAllKeybinds(); }


    // ════ Movidos desde SettingsPopup.qml (exclusivos de este tab) ════

    property var bindTypes: ["bind", "binde", "bindl", "bindel", "bindm"]
    property var dispatchers: ["exec", "exec-once", "dispatch", "workspace", "movetoworkspace", "movewindow", "resizeactive", "movefocus", "togglefloating", "killactive"]

    function validateKeybind(index, mods, key, dispatcher, command) {
        let validMods = ["SHIFT", "SHIFT_L", "SHIFT_R", "CAPS", "CTRL", "CONTROL", "ALT", "MOD2", "MOD3", "SUPER", "WIN", "LOGO", "MOD4", "MOD5", "$mainMod"];
        let modArray = mods ? mods.replace(/&/g, " ").split(" ").filter(x => x !== "") : [];
        
        for (let i = 0; i < modArray.length; i++) {
            if (!validMods.includes(modArray[i])) {
                return "Invalid modifier: " + modArray[i] + ".\nKeys like SPACE cannot be used as modifiers.";
            }
        }

        let currentModsNormalized = modArray.slice().sort().join(" ");
        let currentKeyNormalized = key.trim().toLowerCase();

        for (let i = 0; i < dynamicKeybindsModel.count; i++) {
            if (i === index) continue;

            let item = dynamicKeybindsModel.get(i);
            if (!item.key) continue;

            let itemModsNormalized = item.mods ? item.mods.replace(/&/g, " ").split(" ").filter(x => x !== "").sort().join(" ") : "";
            let itemKeyNormalized = item.key.trim().toLowerCase();

            if (itemModsNormalized === currentModsNormalized && itemKeyNormalized === currentKeyNormalized) {
                return "Duplicate keybind!\nThis exact combination already exists.";
            }
        }

        return "VALID";
    }

    // ════ Cuerpo original del tab ════

    function scrollToBottom() {
        keybindFlickable.contentY = Math.max(0, keybindsColLayout.implicitHeight - keybindFlickable.height + root.s(100));
    }
    function scrollTo(y) {
        let maxY = Math.max(0, keybindFlickable.contentHeight - keybindFlickable.height);
        keybindFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
    }
    function scrollToBox(approxItemY) {
        let viewH = keybindFlickable.height;
        let itemTop = approxItemY;
        let itemBottom = approxItemY + root.s(56);
        let curY = keybindFlickable.contentY;
        let maxY = Math.max(0, keybindFlickable.contentHeight - viewH);
        if (itemTop < curY + root.s(10)) {
            keybindFlickable.contentY = Math.max(0, itemTop - root.s(20));
        } else if (itemBottom > curY + viewH - root.s(10)) {
            keybindFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
        }
    }

    Flickable {
        id: keybindFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: keybindsColLayout.implicitHeight + root.s(Theme.gapXl)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ScrollBar.vertical: ScrollBar {
            id: kbScroll
            width: root.s(Theme.gapXs)
            policy: ScrollBar.AsNeeded
            hoverEnabled: true
            active: keybindFlickable.moving || kbScroll.hovered
            contentItem: Rectangle {
                radius: root.s(Theme.radiusXs)
                color: Theme.surfaceContainerHighest
                opacity: kbScroll.active ? 1.0 : 0.45
            }
            background: Item {}
        }

        MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

        ColumnLayout {
            id: keybindsColLayout
            x: root.s(Theme.gapLg)
            y: root.s(Theme.gapLg)
            width: parent.width - root.s(Theme.gapLg) * 2
            spacing: root.s(Theme.gapXl)

            // ════════ Page header ════════
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(Theme.gapXs)

                Text {
                    Layout.fillWidth: true
                    text: "Keybinds"
                    font.family: "Hack Nerd Font"
                    font.weight: Font.Black
                    font.pixelSize: root.s(24)
                    color: root.text
                }
                Text {
                    Layout.fillWidth: true
                    text: "Compositor keyboard shortcuts. Saving rewrites the active compositor's generated bindings (Lua on Hyprland, KDL on niri) and reloads it; hover a row for the full command and use the pencil to edit it."
                    font.family: "Hack Nerd Font"
                    font.pixelSize: root.s(11)
                    color: root.subtext0
                    wrapMode: Text.WordWrap
                }
            }

            // ════════ Workspaces card ════════
            Rectangle {
                id: wsCard
                Layout.fillWidth: true
                implicitHeight: wsCol.implicitHeight + root.s(Theme.gapLg) * 2
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant

                ColumnLayout {
                    id: wsCol
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Workspaces (SUPER + 1-9)"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Medium
                        font.pixelSize: root.s(12)
                        color: root.text
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: root.s(Theme.gapSm)

                        Repeater {
                            model: 9
                            delegate: Rectangle {
                                id: wsChip
                                property int wsNum: index + 1
                                width: root.s(30); height: root.s(30)
                                radius: root.s(Theme.radiusFull)
                                color: wsMa.containsMouse ? root.peach : Theme.surfaceContainerHigh
                                border.color: wsMa.containsMouse ? root.peach : Theme.outlineVariant
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                Behavior on border.color { ColorAnimation { duration: Theme.durShort } }

                                Text {
                                    anchors.centerIn: parent
                                    text: wsChip.wsNum
                                    font.family: "Hack Nerd Font"
                                    font.weight: Font.Bold
                                    font.pixelSize: root.s(11)
                                    color: wsMa.containsMouse ? root.base : root.peach
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                }

                                MouseArea {
                                    id: wsMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", wsChip.wsNum.toString()])
                                }
                            }
                        }
                    }
                }
            }

            // ════════ Keybinds card ════════
            Rectangle {
                id: kbCard
                Layout.fillWidth: true
                implicitHeight: kbCol.implicitHeight + root.s(Theme.gapLg) * 2
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant

                ColumnLayout {
                    id: kbCol
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Keybinds"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Medium
                        font.pixelSize: root.s(12)
                        color: root.text
                    }

                    // Lista de filas dimensionada a su CONTENIDO: sin
                    // displayMargin (0) el ListView no dibuja delegados fuera
                    // de su propia caja, y su alto sigue a contentHeight, así
                    // que la tarjeta nunca queda corta ni invade la de arriba.
                    ListView {
                        id: kbListView
                        // Alto = contenido exacto. El suelo de una fila evita el
                        // caso límite de viewport 0 en el primer pase de layout
                        // (ListView aún sin delegados → contentHeight 0).
                        property int minRowHeight: root.s(44)
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(contentHeight, (dynamicKeybindsModel && dynamicKeybindsModel.count > 0) ? minRowHeight : 0)
                        implicitHeight: Layout.preferredHeight
                        model: dynamicKeybindsModel
                        interactive: false
                        cacheBuffer: root.s(2000)
                        displayMarginBeginning: 0
                        displayMarginEnd: 0
                        spacing: root.s(Theme.gapSm)
                        clip: true

                        delegate: Rectangle {
                            id: kbRowRect
                            property int outerIndex: index
                            property bool isJumpHighlighted: root.highlightedBox === outerIndex

                            property bool layoutReady: false
                            Component.onCompleted: Qt.callLater(() => layoutReady = true)

                            width: kbListView.width
                            height: Math.max(root.s(44), root.s(48) + (model.isEditing ? editPanel.implicitHeight + root.s(Theme.gapMd) : 0))
                            radius: root.s(Theme.radiusMd)
                            clip: true

                            HoverHandler { id: rowHover }
                            property bool isHovered: rowHover.hovered || model.isEditing || isJumpHighlighted
                            property bool isTypeOpen: false
                            property bool isDispOpen: false

                            color: isJumpHighlighted
                                ? Theme.surfaceContainerHigh
                                : (isHovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: isJumpHighlighted
                                ? root.peach
                                : (isHovered ? Theme.stateLayer(root.peach, 0.5) : Theme.outlineVariant)
                            border.width: isJumpHighlighted ? 2 : 1

                            Behavior on height { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuart } }
                            Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                            Behavior on border.width { NumberAnimation { duration: Theme.durShort } }

                            MouseArea { anchors.fill: parent; z: -2; onClicked: root.highlightedBox = outerIndex; }

                            ColumnLayout {
                                id: rowBody
                                anchors.fill: parent
                                anchors.margins: root.s(Theme.gapMd)
                                spacing: root.s(Theme.gapMd)

                                // ── Fila: mods + tecla + comando + editar ──
                                Item {
                                    id: rowHeaderWrap
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(24)
                                    clip: true

                                    RowLayout {
                                        id: rowHeader
                                        anchors.fill: parent
                                        spacing: root.s(Theme.gapSm)

                                        Row {
                                            id: modKeyContainer
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: root.s(Theme.gapXs)

                                            Rectangle {
                                                width: k1Text.implicitWidth + root.s(Theme.gapMd)
                                                height: root.s(24)
                                                radius: root.s(Theme.radiusFull)
                                                color: Theme.surfaceContainerHigh
                                                border.color: Theme.outlineVariant
                                                border.width: 1
                                                visible: model.mods !== ""
                                                Text {
                                                    id: k1Text; anchors.centerIn: parent; text: model.mods
                                                    font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                                    color: root.peach
                                                }
                                            }
                                            Text {
                                                text: "+"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                                color: root.overlay0
                                                visible: model.mods !== "" && model.key !== ""; anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Rectangle {
                                                width: k2Text.implicitWidth + root.s(Theme.gapMd)
                                                height: root.s(24)
                                                radius: root.s(Theme.radiusFull)
                                                color: Theme.surfaceContainerHigh
                                                border.color: Theme.outlineVariant
                                                border.width: 1
                                                visible: model.key !== ""
                                                Text {
                                                    id: k2Text; anchors.centerIn: parent; text: model.key
                                                    font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                                    color: root.peach
                                                }
                                            }
                                        }

                                        Item {
                                            id: cmdClipRect
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true

                                            property int marqueeSpacing: root.s(60)
                                            property bool shouldMarquee: kbRowRect.isHovered && cmdTextMain.implicitWidth > width

                                            Item {
                                                id: marqueeContainer
                                                height: parent.height
                                                width: cmdClipRect.shouldMarquee ? cmdTextMain.implicitWidth * 2 + cmdClipRect.marqueeSpacing : parent.width
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.right: cmdClipRect.shouldMarquee ? undefined : parent.right
                                                anchors.left: cmdClipRect.shouldMarquee ? parent.left : undefined

                                                Row {
                                                    spacing: cmdClipRect.marqueeSpacing; anchors.verticalCenter: parent.verticalCenter
                                                    anchors.right: cmdClipRect.shouldMarquee ? undefined : parent.right
                                                    Text {
                                                        id: cmdTextMain; text: (model.dispatcher + " " + model.command).trim()
                                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                                        color: root.subtext0
                                                    }
                                                    Text {
                                                        id: cmdTextClone; text: cmdTextMain.text; font: cmdTextMain.font; color: cmdTextMain.color
                                                        visible: cmdClipRect.shouldMarquee
                                                    }
                                                }

                                                SequentialAnimation on x {
                                                    id: cmdAnim; loops: Animation.Infinite
                                                    running: cmdClipRect.shouldMarquee && kbRowRect.layoutReady
                                                    PauseAnimation { duration: 1500 }
                                                    NumberAnimation { from: 0; to: -(cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing); duration: (cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing) * 25 }
                                                    PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                                }
                                                onXChanged: { if (!cmdClipRect.shouldMarquee && x !== 0) x = 0; }
                                            }

                                            onShouldMarqueeChanged: {
                                                if (shouldMarquee) { marqueeContainer.anchors.right = undefined; marqueeContainer.anchors.left = parent.left; marqueeContainer.x = 0; cmdAnim.restart(); }
                                                else { cmdAnim.stop(); marqueeContainer.x = 0; marqueeContainer.anchors.left = undefined; marqueeContainer.anchors.right = parent.right; }
                                            }
                                        }

                                        // Edit button
                                        Rectangle {
                                            id: editButtonSlide
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: root.s(24)
                                            Layout.preferredHeight: root.s(24)
                                            radius: root.s(Theme.radiusFull)
                                            color: model.isEditing
                                                ? root.peach
                                                : (editMa.containsMouse ? root.peach : Theme.surfaceContainerHighest)

                                            Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: model.isEditing ? "▴" : "󰏫"
                                                font.family: model.isEditing ? "Inter" : "Hack Nerd Font"
                                                font.pixelSize: root.s(13)
                                                color: model.isEditing
                                                    ? root.base
                                                    : (editMa.containsMouse ? root.base : root.subtext0)
                                                Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                                            }
                                            MouseArea {
                                                id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                                onClicked: {
                                                    dynamicKeybindsModel.setProperty(outerIndex, "isEditing", !model.isEditing);
                                                    kbRowRect.isTypeOpen = false;
                                                    kbRowRect.isDispOpen = false;
                                                    if (!model.isEditing) {
                                                        root.forceActiveFocus();
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: bindMa
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                        anchors.right: parent.right; anchors.rightMargin: root.s(24) + root.s(Theme.gapSm)
                                        z: -1
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton; enabled: !model.isEditing
                                        onClicked: {
                                            if (model.dispatcher.startsWith("exec")) { Quickshell.execDetached(["bash", "-c", model.command]); }
                                            // NOTE: Hyprland 0.55+ has no string dispatchers; dynamic keybinds are
                                            // configured in keybinds.lua. The live-preview click is a no-op now.
                                        }
                                    }
                                }

                                // ── Edit panel ───────────────────────────────
                                ColumnLayout {
                                    id: editPanel
                                    Layout.fillWidth: true; visible: model.isEditing; spacing: root.s(Theme.gapSm); clip: true

                                    // Record shortcut
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(Theme.radiusFull)
                                        color: recordMa.pressed || captureTrap.activeFocus
                                            ? Theme.stateLayer(root.red, Theme.statePress)
                                            : Theme.surfaceContainerHigh
                                        border.color: recordMa.pressed || captureTrap.activeFocus
                                            ? root.red
                                            : Theme.outlineVariant
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                        Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                        Text {
                                            anchors.centerIn: parent; font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: captureTrap.activeFocus ? root.red : root.text
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                            text: captureTrap.activeFocus ? "Press Keys (Esc to confirm)..." : (model.mods ? model.mods + " + " : "") + (model.key || "[Click to Record Shortcut]")
                                        }
                                        MouseArea {
                                            id: recordMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { captureTrap.accumulatedMods = []; captureTrap.accumulatedKey = ""; captureTrap.forceActiveFocus(); }
                                        }
                                        Item {
                                            id: captureTrap
                                            focus: false
                                            property var accumulatedMods: []
                                            property string accumulatedKey: ""
                                            Keys.onTabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onBacktabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onReturnPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEnterPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEscapePressed: (event) => { captureTrap.focus = false; event.accepted = true; }
                                            Keys.onShortcutOverride: (event) => { event.accepted = true; }
                                            Keys.onReleased: (event) => { event.accepted = true; }
                                            Keys.onPressed: (event) => { event.accepted = true; processKey(event); }
                                            function processKey(event) {
                                                if (event.key === Qt.Key_Escape) return;
                                                let newMods = [];
                                                if (event.modifiers & Qt.MetaModifier) newMods.push("$mainMod");
                                                if (event.modifiers & Qt.ControlModifier) newMods.push("CTRL");
                                                if (event.modifiers & Qt.AltModifier) newMods.push("ALT");
                                                if (event.modifiers & Qt.ShiftModifier) newMods.push("SHIFT_L");
                                                let isModifierOnly = (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R ||
                                                                      event.key === Qt.Key_Meta || event.key === Qt.Key_Control ||
                                                                      event.key === Qt.Key_Alt || event.key === Qt.Key_Shift ||
                                                                      event.key === Qt.Key_CapsLock);
                                                if (isModifierOnly) {
                                                    let mergedMods = [...captureTrap.accumulatedMods];
                                                    for (let m of newMods) { if (!mergedMods.includes(m)) mergedMods.push(m); }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", mergedMods.join(" "));
                                                    captureTrap.accumulatedMods = mergedMods;
                                                    return;
                                                }
                                                let k = "";
                                                if (event.key === Qt.Key_Space) k = "SPACE";
                                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) k = "RETURN";
                                                else if (event.key === Qt.Key_Tab) k = "TAB";
                                                else if (event.key === Qt.Key_Print) k = "Print";
                                                else if (event.key === Qt.Key_Left) k = "left";
                                                else if (event.key === Qt.Key_Right) k = "right";
                                                else if (event.key === Qt.Key_Up) k = "up";
                                                else if (event.key === Qt.Key_Down) k = "down";
                                                else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) { k = "F" + (event.key - Qt.Key_F1 + 1); }
                                                else if (event.text && event.text.length > 0) k = event.text.toUpperCase();
                                                else k = event.key.toString();
                                                if (captureTrap.accumulatedKey !== "") {
                                                    let prevMods = model.mods ? model.mods.split(" ").filter(x => x !== "") : [];
                                                    if (!prevMods.includes(captureTrap.accumulatedKey)) prevMods.push(captureTrap.accumulatedKey);
                                                    for (let m of newMods) { if (!prevMods.includes(m)) prevMods.push(m); }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", prevMods.join(" "));
                                                    captureTrap.accumulatedMods = prevMods;
                                                } else {
                                                    let allMods = [...captureTrap.accumulatedMods];
                                                    for (let m of newMods) { if (!allMods.includes(m)) allMods.push(m); }
                                                    captureTrap.accumulatedMods = allMods;
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", allMods.join(" "));
                                                }
                                                captureTrap.accumulatedKey = k;
                                                dynamicKeybindsModel.setProperty(outerIndex, "key", k);
                                            }
                                            onActiveFocusChanged: {
                                                if (!activeFocus) {
                                                    accumulatedMods = []; accumulatedKey = "";
                                                    if (Compositor.hasSubmaps) Compositor.setSubmap("reset");
                                                } else {
                                                    if (Compositor.hasSubmaps) Compositor.setSubmap("passthru");
                                                }
                                            }
                                        }
                                    }

                                    // niri has no submaps: the compositor keeps its own
                                    // bindings active while recording. Hidden on
                                    // Hyprland; shown only on backends without submap
                                    // support, in its own content height (no blank slot).
                                    Text {
                                        Layout.fillWidth: true
                                        visible: !Compositor.hasSubmaps
                                        wrapMode: Text.WordWrap
                                        text: "niri has no submaps: compositor bindings stay active while recording."
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: root.s(10)
                                        color: root.subtext0
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: root.s(Theme.gapSm); Layout.alignment: Qt.AlignTop; z: 2
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(Theme.gapSm)) * 0.4; Layout.alignment: Qt.AlignTop; spacing: root.s(Theme.gapXs)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(Theme.radiusFull)
                                                scale: kbRowRect.isTypeOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isTypeOpen
                                                    ? Theme.stateLayer(root.peach, Theme.statePress)
                                                    : Theme.surfaceContainerHigh
                                                border.color: kbRowRect.isTypeOpen ? root.peach : Theme.outlineVariant
                                                border.width: kbRowRect.isTypeOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: Theme.durMedium } }
                                                Behavior on border.width { NumberAnimation { duration: Theme.durShort } }
                                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(Theme.gapSm)
                                                    Text {
                                                        text: model.type; font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isTypeOpen ? "▴" : "▾"; font.pixelSize: root.s(10)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kbRowRect.isTypeOpen = !kbRowRect.isTypeOpen; kbRowRect.isDispOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isTypeOpen ? root.bindTypes.length * root.s(26) : 0
                                                radius: root.s(Theme.radiusMd); color: Theme.surfaceContainerHighest; clip: true
                                                border.color: Theme.outlineVariant; border.width: kbRowRect.isTypeOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.bindTypes; interactive: false
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: typeItemMa.containsMouse ? Theme.stateLayer(root.peach, Theme.statePress) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(Theme.gapSm); text: modelData
                                                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                            color: model.type === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: typeItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "type", modelData); kbRowRect.isTypeOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(Theme.gapSm)) * 0.6; Layout.alignment: Qt.AlignTop; spacing: root.s(Theme.gapXs)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(Theme.radiusFull)
                                                scale: kbRowRect.isDispOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isDispOpen
                                                    ? Theme.stateLayer(root.peach, Theme.statePress)
                                                    : Theme.surfaceContainerHigh
                                                border.color: kbRowRect.isDispOpen ? root.peach : Theme.outlineVariant
                                                border.width: kbRowRect.isDispOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: Theme.durMedium } }
                                                Behavior on border.width { NumberAnimation { duration: Theme.durShort } }
                                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(Theme.gapSm)
                                                    Text {
                                                        text: model.dispatcher; font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isDispOpen ? "▴" : "▾"; font.pixelSize: root.s(10)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kbRowRect.isDispOpen = !kbRowRect.isDispOpen; kbRowRect.isTypeOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isDispOpen ? Math.min(root.s(140), root.dispatchers.length * root.s(26)) : 0
                                                radius: root.s(Theme.radiusMd); color: Theme.surfaceContainerHighest; clip: true
                                                border.color: Theme.outlineVariant; border.width: kbRowRect.isDispOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.dispatchers; interactive: true
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: dispItemMa.containsMouse ? Theme.stateLayer(root.peach, Theme.statePress) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(Theme.gapSm); text: modelData
                                                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                            color: model.dispatcher === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: dispItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "dispatcher", modelData); kbRowRect.isDispOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Command input
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(Theme.radiusFull)
                                        color: cmdInput.activeFocus ? Theme.stateLayer(root.peach, Theme.stateHover) : Theme.surfaceContainerHigh
                                        border.color: cmdInput.activeFocus ? root.peach : Theme.outlineVariant
                                        border.width: 1; z: 1
                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                        Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                        TextInput {
                                            id: cmdInput
                                            anchors.fill: parent; anchors.leftMargin: root.s(Theme.gapMd); anchors.rightMargin: root.s(Theme.gapMd)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: model.command
                                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                            color: root.text; clip: true; selectByMouse: true
                                            onTextChanged: dynamicKeybindsModel.setProperty(outerIndex, "command", text)
                                            Text {
                                                text: "Command arguments..."
                                                color: root.subtext0
                                                visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: root.s(Theme.gapSm); z: 0
                                        Item { Layout.fillWidth: true }
                                        // Delete button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(Theme.radiusFull)
                                            color: delMa.containsMouse ? root.red : Theme.surfaceContainerHigh
                                            border.color: delMa.containsMouse ? root.red : Theme.stateLayer(root.red, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(Theme.gapXs)
                                                Text {
                                                    text: "󰆴"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(14)
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                                Text {
                                                    text: "Delete"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); font.weight: Font.Medium
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                            }
                                            MouseArea {
                                                id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                                onClicked: {
                                                    root.forceActiveFocus();
                                                    dynamicKeybindsModel.remove(outerIndex);
                                                    root.saveAllKeybinds();
                                                }
                                            }
                                        }
                                        // Save button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(Theme.radiusFull)
                                            color: rowSaveMa.containsMouse ? root.green : Theme.surfaceContainerHigh
                                            border.color: rowSaveMa.containsMouse ? root.green : Theme.stateLayer(root.green, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(Theme.gapXs)
                                                Text {
                                                    text: "󰆓"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(14)
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                                Text {
                                                    text: "Save"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); font.weight: Font.Medium
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                            }
                                            MouseArea {
                                                id: rowSaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let validationResult = root.validateKeybind(outerIndex, model.mods, model.key, model.dispatcher, model.command);
                                                    if (validationResult !== "VALID") {
                                                        Quickshell.execDetached(["notify-send", "-u", "critical", "Keybind Error", validationResult]);
                                                        return;
                                                    }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "isEditing", false);
                                                    root.forceActiveFocus();
                                                    root.saveAllKeybinds();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // "+ Add" — última fila de la tarjeta, en flujo (no flotante)
                    Rectangle {
                        id: addBindBtn
                        Layout.alignment: Qt.AlignRight
                        Layout.preferredWidth: addBindText.implicitWidth + root.s(Theme.gapXl)
                        Layout.preferredHeight: root.s(32)
                        radius: root.s(Theme.radiusFull)
                        color: addBindMa.containsMouse
                            ? Theme.stateLayer(root.peach, Theme.statePress)
                            : Theme.surfaceContainerHigh
                        border.color: addBindMa.containsMouse ? root.peach : Theme.outlineVariant
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durShort } }

                        Text {
                            id: addBindText
                            anchors.centerIn: parent
                            text: "+ Add"
                            font.family: "Hack Nerd Font"
                            font.weight: Font.Medium
                            font.pixelSize: root.s(11)
                            color: addBindMa.containsMouse ? root.peach : root.text
                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                        }
                        MouseArea {
                            id: addBindMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!dynamicKeybindsModel) return;
                                dynamicKeybindsModel.append({ type: "bind", mods: "", key: "", dispatcher: "exec", command: "", isEditing: true });
                                Qt.callLater(() => root.scrollToBottom());
                            }
                        }
                    }
                }
            }
        }
    }
}
