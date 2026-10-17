import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// GuidePage (About) — equisdots.
//
// Minimalist, symmetric layout: flat surfaces (no borders), a 3x2 stat grid,
// a 2x3 grid of equal-height info cards and a single-column repo list, so no
// row is left with uneven empty space. Palette-driven, accent used sparingly.
// ═══════════════════════════════════════════════════════════════════════════
Item {
    id: root
    anchors.fill: parent
    property var bar: null
    property var info: ({})
    property int tick: 0
    property string doctorOut: ""
    property bool copiedFlash: false
    property string infoScript: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/ui/bar/editor/sysinfo.sh"

    function val(key) {
        root.tick;
        let v = root.info[key];
        return (v !== undefined && v !== null && String(v).trim() !== "") ? String(v) : "—";
    }

    Process {
        id: sysinfoProc
        command: ["bash", root.infoScript]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = {};
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let p = lines[i].indexOf("=");
                    if (p > 0) out[lines[i].substring(0, p)] = lines[i].substring(p + 1);
                }
                root.info = out;
                root.tick++;
            }
        }
    }

    Process {
        id: doctorProc
        command: ["bash", "-c",
            "D=\"$HOME/.local/share/equisdots-niri/niri-meta/bin/dotsniri\"; " +
            "if [ -x \"$D\" ]; then bash \"$D\" doctor 2>&1; " +
            "else D=\"$HOME/.local/share/equisdots/dots/dots\"; " +
            "if [ -x \"$D\" ]; then bash \"$D\" doctor 2>&1; " +
            "else echo 'dotsniri is not installed (run: dotsniri install)'; fi; fi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.doctorOut = this.text.trim() !== "" ? this.text.trim() : "no output"
        }
    }

    Timer { id: copiedTimer; interval: 1600; onTriggered: root.copiedFlash = false }

    // ── Stat grid (3 x 2, uniform tiles) ──────────────────────────────────
    readonly property var stats: [
        { label: "Stack", k: "stack_ver" },
        { label: "Compositor", k: "hypr_ver" },
        { label: "Quickshell", k: "qs_ver" },
        { label: "Palette", k: "palette" },
        { label: "Bar", k: "bar_enabled" },
        { label: "Timex", k: "timex_provider" }
    ]

    // ── Info cards (2 x 3, equal height) ──────────────────────────────────
    readonly property var sections: [
        { title: "System", rows: [
            { k: "os", label: "OS" },
            { k: "host", label: "Host" },
            { k: "kernel", label: "Kernel" },
            { k: "uptime", label: "Uptime" },
            { k: "boot", label: "Boot" }
        ] },
        { title: "Session", rows: [
            { k: "user", label: "User" },
            { k: "shell", label: "Shell" },
            { k: "iface", label: "Interface" },
            { k: "ip", label: "IP" },
            { k: "ssid", label: "SSID" }
        ] },
        { title: "Hardware", rows: [
            { k: "cpu", label: "CPU" },
            { k: "gpu", label: "GPU" },
            { k: "memory", label: "Memory" },
            { k: "disk", label: "Disk" },
            { k: "battery", label: "Battery" }
        ] },
        { title: "Display", rows: [
            { k: "res", label: "Resolution" },
            { k: "refresh", label: "Refresh" },
            { k: "monitors", label: "Monitors" },
            { k: "scale", label: "Scale" }
        ] },
        { title: "Timex", rows: [
            { k: "timex_provider", label: "Provider" },
            { k: "timex_city", label: "City" },
            { k: "timex_unit", label: "Unit" },
            { k: "timex_updated", label: "Updated" },
            { k: "timex_error", label: "Error", opt: true }
        ] },
        { title: "Customization", rows: [
            { k: "palette", label: "Palette" },
            { k: "bar_enabled", label: "Bar enabled" },
            { k: "gtk_theme", label: "GTK theme" },
            { k: "stack_date", label: "Stack date" }
        ] }
    ]

    readonly property int maxSectionRows: {
        let m = 0;
        for (let i = 0; i < sections.length; i++) m = Math.max(m, sections[i].rows.length);
        return m;
    }

    readonly property var repos: [
        { label: "niri", icon: "󰣇", url: "https://github.com/equisdots/niri" },
        { label: "niri-shell", icon: "󰍜", url: "https://github.com/equisdots/niri-shell" },
        { label: "niri-meta", icon: "󰒓", url: "https://github.com/equisdots/niri-meta" },
        { label: "shell", icon: "󰍜", url: "https://github.com/equisdots/shell" },
        { label: "plugins", icon: "󰏗", url: "https://github.com/equisdots/plugins" },
        { label: "plugin-api", icon: "󰘦", url: "https://github.com/equisdots/plugin-api" },
        { label: "plugin-sdk", icon: "󰘦", url: "https://github.com/equisdots/plugin-sdk" },
        { label: "nyx", icon: "󰚩", url: "https://github.com/equisdots/nyx" },
        { label: "timex", icon: "󰖐", url: "https://github.com/equisdots/timex" },
        { label: "palettes", icon: "✦", url: "https://github.com/equisdots/palettes" },
        { label: "davincix", icon: "󰹑", url: "https://github.com/equisdots/davincix" },
        { label: "theme-sync", icon: "󰏘", url: "https://github.com/equisdots/theme-sync" }
    ]

    // Flat action button (no borders).
    component ActionButton: Rectangle {
        id: action
        property string icon: ""
        property string label: ""
        signal clicked()
        Layout.fillWidth: true
        height: root.bar.s(32)
        radius: root.bar.s(Theme.radiusMd)
        color: actionMa.containsMouse ? Theme.surfaceContainer : Theme.surfaceContainerLow
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            anchors.centerIn: parent
            spacing: root.bar.s(Theme.gapSm)
            Text {
                text: action.icon
                font.family: "Hack Nerd Font"; font.pixelSize: root.bar.s(13)
                color: root.bar.colors.subtext0
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: action.label
                font.family: "Hack Nerd Font"; font.pixelSize: root.bar.s(11)
                color: actionMa.containsMouse ? root.bar.colors.text : root.bar.colors.subtext0
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        MouseArea {
            id: actionMa
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
    }

    Loader { id: body; anchors.fill: parent; active: root.bar !== null; sourceComponent: pageBody }

    Component {
        id: pageBody
        Item {
            anchors.fill: parent

            Flickable {
                id: pageFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: pageCol.height + bar.s(Theme.gapLg)
                ScrollBar.vertical: ScrollBar {
                    width: bar.s(3)
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { radius: bar.s(Theme.radiusXs); color: Theme.surfaceContainerHighest; opacity: parent.active ? 0.8 : 0.35 }
                    background: Item {}
                }

                Column {
                    id: pageCol
                    x: bar.s(Theme.gapSm); y: bar.s(Theme.gapSm)
                    width: pageFlick.width - bar.s(Theme.gapLg)
                    spacing: bar.s(Theme.gapLg)

                    // ── Header ─────────────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: bar.s(Theme.gapSm)
                        topPadding: bar.s(Theme.gap2xs)
                        Row {
                            spacing: bar.s(Theme.gapSm)
                            Rectangle { width: bar.s(8); height: bar.s(8); radius: bar.s(Theme.radiusFull); color: bar.colors.mauve }
                            Rectangle { width: bar.s(8); height: bar.s(8); radius: bar.s(Theme.radiusFull); color: bar.colors.blue }
                            Rectangle { width: bar.s(8); height: bar.s(8); radius: bar.s(Theme.radiusFull); color: bar.colors.green }
                        }
                        Row {
                            spacing: 0
                            Text {
                                text: "equis"
                                font.family: "Hack Nerd Font"; font.weight: Font.Black
                                font.pixelSize: bar.s(38)
                                color: bar.colors.text
                            }
                            Text {
                                text: "dots"
                                font.family: "Hack Nerd Font"; font.weight: Font.Black
                                font.pixelSize: bar.s(38)
                                color: bar.colors.mauve
                            }
                        }
                        Text {
                            text: "shell · niri · plugins · timex · palettes · davincix"
                            font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12)
                            color: bar.colors.subtext0
                        }
                    }

                    // ── Stat tiles (3 x 2, uniform) ────────────────────────
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        Repeater {
                            model: root.stats
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                height: bar.s(58)
                                radius: bar.s(Theme.radiusMd)
                                color: Theme.surfaceContainerLow
                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: bar.s(Theme.gapMd)
                                    anchors.rightMargin: bar.s(Theme.gapMd)
                                    spacing: bar.s(Theme.gapXs)
                                    Text {
                                        text: modelData.label
                                        font.family: "Hack Nerd Font"; font.pixelSize: bar.s(10)
                                        color: Qt.alpha(bar.colors.subtext0, 0.75)
                                    }
                                    Text {
                                        width: parent.width
                                        text: root.val(modelData.k)
                                        font.family: "Hack Nerd Font"; font.weight: Font.Bold
                                        font.pixelSize: bar.s(15)
                                        color: bar.colors.text
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // ── Actions (one row, equal width) ─────────────────────
                    RowLayout {
                        width: parent.width
                        spacing: bar.s(Theme.gapMd)
                        ActionButton {
                            icon: "󰆏"; label: root.copiedFlash ? "Copied!" : "Copy debug info"
                            onClicked: {
                                Quickshell.execDetached(["bash", "-c", "bash '" + root.infoScript + "' | wl-copy"]);
                                root.copiedFlash = true;
                                copiedTimer.restart();
                            }
                        }
                        ActionButton {
                            icon: "󰒓"; label: "Run doctor"
                            onClicked: { root.doctorOut = "Running…"; doctorProc.running = false; doctorProc.running = true; }
                        }
                        ActionButton {
                            icon: "󰚰"; label: "Updates"
                            onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", "updater"])
                        }
                        ActionButton {
                            icon: "󰈙"; label: "Docs"
                            onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/equisdots"])
                        }
                        ActionButton {
                            icon: "󰈂"; label: "Report issue"
                            onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/equisdots/shell/issues/new"])
                        }
                    }

                    // ── Doctor output (flat) ───────────────────────────────
                    Rectangle {
                        width: parent.width
                        visible: root.doctorOut !== ""
                        height: visible ? doctorCol.implicitHeight + bar.s(Theme.gapMd) * 2 : 0
                        radius: bar.s(Theme.radiusMd)
                        color: Theme.surfaceContainerLow
                        Column {
                            id: doctorCol
                            x: bar.s(Theme.gapLg); y: bar.s(Theme.gapMd)
                            width: parent.width - bar.s(52)
                            spacing: bar.s(Theme.gapSm)
                            Text {
                                text: "dots doctor"
                                font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: bar.s(12)
                                color: bar.colors.subtext1
                            }
                            Text {
                                width: parent.width
                                text: root.doctorOut
                                font.family: "Hack Nerd Font"; font.pixelSize: bar.s(11)
                                color: bar.colors.subtext0
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                        MouseArea {
                            anchors.right: parent.right; anchors.top: parent.top
                            width: bar.s(28); height: bar.s(28)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.doctorOut = ""
                            Text {
                                anchors.centerIn: parent; text: "󰅖"
                                font.family: "Hack Nerd Font"; font.pixelSize: bar.s(13)
                                color: Qt.alpha(bar.colors.subtext0, 0.8)
                            }
                        }
                    }

                    // ── Info cards (2 x 3, all the same height) ────────────
                    GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        Repeater {
                            model: root.sections
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                radius: bar.s(Theme.radiusMd)
                                color: Theme.surfaceContainerLow
                                height: bar.s(52 + 24 * root.maxSectionRows)
                                Column {
                                    x: bar.s(Theme.gapLg); y: bar.s(Theme.gapLg)
                                    width: parent.width - bar.s(Theme.gapLg) * 2
                                    spacing: bar.s(Theme.gapSm)
                                    Row {
                                        spacing: bar.s(Theme.gapSm)
                                        Rectangle {
                                            width: bar.s(6); height: bar.s(6); radius: bar.s(Theme.radiusFull)
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Qt.alpha(bar.colors.mauve, 0.9)
                                        }
                                        Text {
                                            text: modelData.title
                                            font.family: "Hack Nerd Font"; font.weight: Font.Bold
                                            font.pixelSize: bar.s(13)
                                            color: bar.colors.subtext1
                                        }
                                    }
                                    Repeater {
                                        model: modelData.rows
                                        delegate: Row {
                                            required property var modelData
                                            visible: !modelData.opt || root.val(modelData.k) !== "—"
                                            // Explicit width: the value Text binds to
                                            // parent.width, and without it the Row
                                            // only had an implicit width built from
                                            // its children (circular binding -> the
                                            // value text collapsed to 0 px).
                                            width: parent.width
                                            height: bar.s(22)
                                            spacing: bar.s(Theme.gapMd)
                                            Text {
                                                width: bar.s(80)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.label
                                                font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12)
                                                color: Qt.alpha(bar.colors.subtext0, 0.8)
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                width: parent.width - bar.s(90)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.val(modelData.k)
                                                font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12)
                                                color: bar.colors.text
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Repositories (single column, uniform rows) ─────────
                    Text {
                        topPadding: bar.s(Theme.gapXs)
                        text: "Repositories"
                        font.family: "Hack Nerd Font"; font.weight: Font.Bold
                        font.pixelSize: bar.s(13)
                        color: bar.colors.subtext1
                    }
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusMd)
                        color: Theme.surfaceContainerLow
                        height: repoCol.implicitHeight + bar.s(Theme.gapSm) * 2
                        Column {
                            id: repoCol
                            x: bar.s(Theme.gapSm); y: bar.s(Theme.gapSm)
                            width: parent.width - bar.s(Theme.gapSm) * 2
                            Repeater {
                                model: root.repos
                                delegate: Rectangle {
                                    required property var modelData
                                    width: repoCol.width
                                    height: bar.s(40)
                                    radius: bar.s(Theme.radiusSm)
                                    color: repoMa.containsMouse ? Theme.surfaceContainer : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: bar.s(Theme.gapMd)
                                        anchors.rightMargin: bar.s(Theme.gapMd)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: bar.s(Theme.gapMd)
                                        Text {
                                            text: modelData.icon
                                            font.family: "Hack Nerd Font"; font.pixelSize: bar.s(15)
                                            color: bar.colors.subtext0
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Text {
                                            text: "equisdots/" + modelData.label
                                            font.family: "Hack Nerd Font"; font.pixelSize: bar.s(13)
                                            color: bar.colors.text
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: {
                                                root.tick;
                                                let rev = root.info["repo_" + modelData.label];
                                                return (rev !== undefined && rev !== "") ? rev : "not via dots";
                                            }
                                            font.family: "Hack Nerd Font"; font.pixelSize: bar.s(11)
                                            color: Qt.alpha(bar.colors.subtext0, 0.8)
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Text {
                                            text: "󰏌"
                                            font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12)
                                            color: repoMa.containsMouse ? bar.colors.mauve : Qt.alpha(bar.colors.subtext0, 0.55)
                                            Layout.alignment: Qt.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                    }
                                    MouseArea {
                                        id: repoMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["xdg-open", modelData.url])
                                    }
                                }
                            }
                        }
                    }

                    // ── Footer ─────────────────────────────────────────────
                    Text {
                        topPadding: bar.s(Theme.gapSm)
                        bottomPadding: bar.s(Theme.gapXs)
                        width: parent.width
                        text: "MIT licensed · built with Quickshell · wallpaper daemon: xwww (fork of awww) · base16 palettes"
                        font.family: "Hack Nerd Font"; font.pixelSize: bar.s(10)
                        color: Qt.alpha(bar.colors.subtext0, 0.7)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
