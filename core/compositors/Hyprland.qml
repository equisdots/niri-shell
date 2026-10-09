// ═══════════════════════════════════════════════════════════════════════════
// shell · core/compositors — Hyprland backend
//
// Hyprland implementation of the Compositor surface. It keeps the exact
// commands and scripts used before the port (workspaces.sh, kb_fetch.sh,
// hyprctl) so Hyprland behaviour is unchanged, and extends the surface with
// the compositor-neutral persistence/monitor methods used by Config.qml and
// Effects.qml.
// ═══════════════════════════════════════════════════════════════════════════
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: backend

    // ── data sources for the bar pollers ──────────────────────────────────
    readonly property var workspacesCommand: ["bash", "-c", "~/.config/hypr/scripts/workspaces.sh"]
    readonly property var keyboardCommand: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/kb_fetch.sh"]

    readonly property var focusCommand: ["bash", "-c",
        "hyprctl activewindow -j 2>/dev/null | jq -r 'if (.class != null and .class != \"\" and .address != null and .address != \"\") then (.class + \"\\n\" + .title) else empty end' 2>/dev/null"]

    // ── focused-window-independent helpers ─────────────────────────────────
    function sh(cmd) { Quickshell.execDetached(["bash", "-c", cmd]); }

    function esc(str) { return String(str).replace(/'/g, "'\\''"); }

    // Spec to Lua value. Solid borders are 0xAARRGGBB numbers; gradients are
    // the table the 0.56 API expects: { colors = { 0x..., 0x... }, angle = N }.
    function borderLua(spec) {
        const alpha = (spec && spec.alpha) ? String(spec.alpha) : "ee";
        const hex = String((spec && spec.hex) || "#ffffff").replace("#", "");
        const first = "0x" + alpha + hex;
        const second = (spec && spec.second) ? String(spec.second).replace("#", "") : "";
        if (/^[0-9a-fA-F]{6}$/.test(second)) {
            const angle = Math.round(Number((spec && spec.angle) || 0));
            return "{ colors = { " + first + ", 0x" + alpha + second + " }, angle = " + angle + " }";
        }
        return first;
    }

    // Push the active/inactive window border specs live. Spec: { hex, alpha,
    // second, angle } (Colors.borderSpec).
    function setWindowBorders(activeSpec, inactiveSpec) {
        const lua = 'hl.config({ general = { col = { active_border = ' + borderLua(activeSpec)
                  + ', inactive_border = ' + borderLua(inactiveSpec) + ' } } })';
        Quickshell.execDetached(["bash", "-c", "hyprctl eval '" + lua + "' 2>/dev/null"]);
    }

    function switchWorkspace(name) {
        Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh " + name]);
    }

    function cycleKeyboardLayout() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
    }

    // ── stateful monitor poller ────────────────────────────────────────────
    // Emits the raw `hyprctl monitors -j` array once per read. Config.qml
    // receives it through `onMonitorsDecoded` and populates its model, so all
    // shape handling stays in one place.
    signal monitorsDecoded(var data)

    readonly property var displayPoller: Process {
        command: ["hyprctl", "monitors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let data = [];
                try { data = JSON.parse(this.text.trim()); } catch (e) { data = []; }
                backend.monitorsDecoded(data);
            }
        }
    }

    // ── keybind persistence (Hyprland 0.55+ Lua) ───────────────────────────
    // Maps the settings panel's legacy dispatcher names to the Lua API.
    function luaDispatcherFor(dispatcher, command) {
        command = (command || "").trim();
        let dir = { "l": "l", "r": "r", "u": "u", "d": "d" };
        switch (dispatcher) {
            case "exec":
            case "exec-once":
                return "hl.dsp.exec_cmd(" + JSON.stringify(command) + ")";
            case "workspace":
                return "hl.dsp.focus({ workspace = " + JSON.stringify(command) + " })";
            case "movetoworkspace":
                return "hl.dsp.window.move({ workspace = " + JSON.stringify(command) + " })";
            case "movewindow":
                return dir[command] ? "hl.dsp.window.move({ direction = \"" + command + "\" })" : "hl.dsp.window.move({ monitor = " + JSON.stringify(command) + " })";
            case "movefocus":
                return "hl.dsp.focus({ direction = \"" + (dir[command] || "l") + "\" })";
            case "resizeactive": {
                let parts = command.split(/[\s,]+/);
                let x = parseInt(parts[0]) || 0, y = parseInt(parts[1]) || 0;
                return "hl.dsp.window.resize({ x = " + x + ", y = " + y + ", relative = true })";
            }
            case "togglefloating":
                return "hl.dsp.window.float({ action = \"toggle\" })";
            case "killactive":
                return "hl.dsp.window.kill()";
            default:
                return null;
        }
    }

    function persistKeybinds(bindsArray) {
        let lines = [];
        lines.push("-- Auto-generated by the QuickShell settings panel.");
        lines.push("-- Bound to SUPER+SHIFT+S -> Keybindings. Do not edit manually.");
        lines.push("");
        for (let i = 0; i < bindsArray.length; i++) {
            let b = bindsArray[i];
            if (!b.key || !b.dispatcher) continue;
            let flags = [];
            if (b.type === "bindl") flags.push("locked = true");
            else if (b.type === "bindel") { flags.push("locked = true"); flags.push("repeating = true"); }
            else if (b.type === "bindm") flags.push("mouse = true");
            let keys = (b.mods ? b.mods.replace(/&/g, " ").trim() + " + " : "") + b.key;
            let dsp = backend.luaDispatcherFor(b.dispatcher, b.command);
            if (!dsp) {
                lines.push("-- [skipped] " + b.dispatcher + " " + (b.command || "") + " (no Lua equivalent)");
                continue;
            }
            if (flags.length > 0) {
                lines.push("hl.bind(\"" + keys + "\", " + dsp + ", { " + flags.join(", ") + " })");
            } else {
                lines.push("hl.bind(\"" + keys + "\", " + dsp + ")");
            }
        }
        lines.push("");
        let lua = lines.join("\n");
        backend.sh("mkdir -p ~/.config/hypr/config && cat > ~/.config/hypr/config/user-keybinds.lua << 'LUAEOF'\n" + lua + "LUAEOF\nhyprctl reload");
    }

    function persistStartup(startupArray) {
        let lines = [];
        lines.push("-- Auto-generated by the QuickShell settings panel.");
        lines.push("-- Extra startup commands run once at session start.");
        lines.push("");
        lines.push("hl.on(\"hyprland.start\", function()");
        for (let i = 0; i < startupArray.length; i++) {
            let s = startupArray[i];
            if (!s.command || !s.command.trim()) continue;
            lines.push("    hl.exec_cmd(" + JSON.stringify(s.command.trim()) + ")");
        }
        lines.push("end)");
        lines.push("");
        backend.sh("mkdir -p ~/.config/hypr/config && cat > ~/.config/hypr/config/user-startup.lua << 'LUAEOF'\n" + lines.join("\n") + "LUAEOF\nhyprctl reload");
    }

    // ── monitor apply / reset / reload ─────────────────────────────────────
    // descriptor: { name, description, mode, x, y, scale, transform, vrr,
    //               bitdepth, cm, mirrorDesc, disabled }
    function monitorLua(d) {
        let outName = (d.description && d.description !== "") ? ("desc:" + d.description) : d.name;
        let parts = ["output = \"" + outName + "\""];
        if (d.disabled === true) {
            parts.push("disabled = true");
        } else {
            parts.push("mode = \"" + d.mode + "\"");
            parts.push("position = \"" + d.x + "x" + d.y + "\"");
        }
        if (d.scale !== undefined) parts.push("scale = " + d.scale);
        if (d.transform !== undefined && d.transform !== 0) parts.push("transform = " + d.transform);
        parts.push("vrr = " + (d.vrr === 2 ? 2 : (d.vrr === 1 ? 1 : 0)));
        parts.push("bitdepth = " + (d.bitdepth === 10 ? 10 : 8));
        if (d.cm && d.cm !== "auto") parts.push("cm = \"" + d.cm + "\"");
        if (d.mirrorDesc && d.mirrorDesc !== "") parts.push("mirror = \"" + d.mirrorDesc + "\"");
        return "hl.monitor({ " + parts.join(", ") + " })";
    }

    // displayConfigText is the deterministic pipe file produced by Config.qml.
    function applyMonitors(descriptors, displayConfigText) {
        let cmds = [];
        for (let i = 0; i < descriptors.length; i++) {
            cmds.push("hyprctl eval '" + backend.esc(backend.monitorLua(descriptors[i])) + "'");
        }
        let writeCmd = "cat > \"$HOME/.config/hypr/display-config.tmp\" <<'XSC_DC_EOF'\n" + displayConfigText + "XSC_DC_EOF\n" +
                       "mv \"$HOME/.config/hypr/display-config.tmp\" \"$HOME/.config/hypr/display-config\" && " +
                       "cp \"$HOME/.config/hypr/display-config\" \"$HOME/.config/hypr/display-config.bak\"";
        backend.sh(writeCmd + " ; " + cmds.join(" ; ") + " ; pkill xwww-daemon 2>/dev/null || true; xwww-daemon &");
    }

    function resetMonitors() {
        backend.sh("rm -f \"$HOME/.config/hypr/display-config\" \"$HOME/.config/hypr/display-config.bak\" && hyprctl reload ; hyprctl eval 'hl.monitor({ output = \"\", mode = \"highrr\", position = \"auto\", scale = \"auto\" })'");
    }

    function reload() {
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    // ── neutral monitor / version / launch helpers ─────────────────────────
    readonly property bool hasSubmaps: true

    readonly property var monitorListCommand: ["hyprctl", "monitors", "-j"]
    readonly property var versionCommand: ["hyprctl", "version", "-j"]

    signal monitorListReady(var list)
    signal versionReady(var version)

    property var _monitorCache: []
    property string _versionCache: ""

    // Normalise `hyprctl -j monitors` to the neutral shape the panels consume.
    function monitorsFromOutput(text) {
        let data = [];
        try { data = JSON.parse(text); } catch (e) { return []; }
        let result = [];
        for (let i = 0; i < data.length; i++) {
            let m = data[i] || {};
            result.push({
                name: m.name || "",
                description: m.description || "",
                width: m.width || 0,
                height: m.height || 0,
                refreshRate: m.refreshRate || 0,
                scale: (m.scale !== undefined) ? m.scale : 1,
                x: m.x || 0,
                y: m.y || 0,
                transform: (m.transform !== undefined) ? m.transform : 0,
                focused: m.focused === true,
                modes: m.availableModes || [],
                availableModes: m.availableModes || []
            });
        }
        return result;
    }

    readonly property var _monitorProc: Process {
        command: backend.monitorListCommand
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let list = backend.monitorsFromOutput(this.text);
                backend._monitorCache = list;
                backend.monitorListReady(list);
            }
        }
    }

    function monitorList() { return backend._monitorCache; }
    function refreshMonitorList() { backend._monitorProc.running = true; }

    function versionFromOutput(text) {
        try {
            let d = JSON.parse(text);
            return String(d.tag || d.version || "");
        } catch (e) { return ""; }
    }

    readonly property var _versionProc: Process {
        command: backend.versionCommand
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                backend._versionCache = backend.versionFromOutput(this.text);
                backend.versionReady(backend._versionCache);
            }
        }
    }

    function compositorVersion() { return backend._versionCache; }
    function refreshCompositorVersion() { backend._versionProc.running = true; }

    // Global display scale: scale-menu.sh owns the exact pre-port behaviour
    // (settings.json record, per-output hl.monitor, display-config persist).
    function applyMonitorScale(name, scale) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/scale-menu.sh", String(scale)]);
    }

    // Apply one neutral descriptor live (no persistence): the same Lua the
    // monitor manager used before the port.
    function applyMonitorConfig(d) {
        if (!d || !d.name) return;
        backend.sh("hyprctl eval '" + backend.esc(backend.monitorLua(d)) + "' 2>/dev/null");
    }

    // Spawn with no compositor involvement.
    function execApp(commandString) {
        if (!commandString) return;
        Quickshell.execDetached(["bash", "-c", commandString]);
    }

    // Recording a key enters the passthru submap so Hyprland does not consume
    // the combination; leaving it resets. Byte-identical to the old call.
    function setSubmap(name) {
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.submap(\"" + String(name) + "\"))"]);
    }
}
