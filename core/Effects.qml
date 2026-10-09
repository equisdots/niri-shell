pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// Effects — shared state for the window-effect knobs.
//
// Single source for the BarEditor appearance tab and the Window Controls
// widget (SUPER+SHIFT+B). Talks to core/scripts/effects.sh, which is
// compositor-aware (XDG_CURRENT_DESKTOP, Hyprland fallback):
//   · refresh()  reads the current values.
//   · set(k,v)   updates the shared state and schedules a debounced preview.
//   · persist()  materialises the state (Lua under Hyprland, KDL under niri).
//
// The API is byte-compatible with the old HyprEffects singleton so the
// existing consumers (ui/bar/editor/HyprlandPage.qml and
// ui/panels/window-controls/WindowControls.qml) keep working unchanged; a
// compatibility shim keeps the `HyprEffects` name resolving to this one.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/core/scripts/effects.sh"

    // Same keys as the generated state (see SPECS in the script).
    property var values: ({
        active_opacity: 0.85,
        inactive_opacity: 0.80,
        rounding: 20,
        blur_size: 8,
        blur_passes: 3,
        gaps_in: 16,
        gaps_out: 25,
        border_size: 2,
        shadow_range: 35,
        shadow_render_power: 5,
        shadow_offset_x: 0,
        shadow_offset_y: 10
    })

    function get(key) { return root.values[key]; }

    // Re-read the values (when each UI opens and on demand).
    function refresh() { reader.running = true; }

    Process {
        id: reader
        command: ["bash", root.scriptPath, "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!this.text) return;
                let next = {};
                for (let k in root.values) next[k] = root.values[k];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let eq = lines[i].indexOf("=");
                    if (eq < 0) continue;
                    let key = lines[i].slice(0, eq).trim();
                    let num = parseFloat(lines[i].slice(eq + 1).trim());
                    if (key in next && !isNaN(num)) next[key] = num;
                }
                root.values = next;
            }
        }
    }

    // Preview with drag debounce: touched keys accumulate and 200 ms later a
    // single `preview key=val ...` is sent. Under Hyprland that applies live;
    // under niri it only updates the state (niri has no runtime patch and the
    // KDL is written once on persist).
    property var _pending: ({})
    property var _changed: ({})
    Timer {
        id: flushTimer
        interval: 200
        onTriggered: root.flush()
    }
    function set(key, v) {
        if (typeof v !== "number" || isNaN(v)) return;
        if (root.values[key] === v) return;
        let next = {};
        for (let k in root.values) next[k] = root.values[k];
        next[key] = v;
        root.values = next;
        root._pending[key] = v;
        root._changed[key] = v;
        flushTimer.restart();
    }
    // Apply pending previews now.
    function flush() {
        let args = [];
        for (let k in root._pending) args.push(k + "=" + root._pending[k]);
        root._pending = {};
        if (args.length === 0) return;
        Quickshell.execDetached(["bash", root.scriptPath, "preview"].concat(args));
    }
    // Write the persisted output once (called when the UI closes / Save).
    function persist() {
        let args = [];
        for (let k in root._changed) args.push(k + "=" + root._changed[k]);
        root._pending = {};
        root._changed = {};
        if (args.length === 0) return;
        Quickshell.execDetached(["bash", root.scriptPath, "apply"].concat(args));
    }

    // Reset defaults: effects only (gaps and border untouched, same as the
    // original reset of both UIs).
    function resetEffects() {
        root.set("active_opacity", 0.85);
        root.set("inactive_opacity", 0.80);
        root.set("rounding", 20);
        root.set("blur_size", 8);
        root.set("blur_passes", 3);
        root.set("shadow_range", 35);
        root.set("shadow_render_power", 5);
        root.set("shadow_offset_x", 0);
        root.set("shadow_offset_y", 10);
        root.flush();
    }

    Component.onCompleted: root.refresh()
}
