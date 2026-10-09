pragma Singleton
// ═══════════════════════════════════════════════════════════════════════════
// shell · core — Compositor
//
// Single entry point to the compositor for the whole UI. Widgets must never
// call hyprctl/niri directly: they consume the command arrays (for their
// pollers) and the action functions exposed here.
//
// The implementation lives in core/compositors/<backend>.qml. The backend is
// selected from XDG_CURRENT_DESKTOP: anything containing "niri" selects the
// niri backend, every other value (and an unset variable) falls back to
// Hyprland, so a Hyprland user is never affected by the niri meta.
//
// Exposed surface (unchanged for widgets):
//   workspacesCommand, keyboardCommand, focusCommand,
//   setWindowBorders(active, inactive), switchWorkspace(name),
//   cycleKeyboardLayout()
// Plus the compositor-neutral persistence methods used by core/Config.qml:
//   persistKeybinds, persistStartup, applyMonitors, resetMonitors, reload.
// Plus the neutral monitor/launch helpers added for the panels:
//   monitorListCommand, refreshMonitorList(), monitorList(), monitorsFromOutput(),
//   applyMonitorScale(name, scale), applyMonitorConfig(descriptor),
//   compositorVersion(), refreshCompositorVersion(), execApp(command),
//   hasSubmaps, setSubmap(name).
// Plus the neutral session actions added for the idle panel and the battery
// popups: idleMode(mode), quit().
// ═══════════════════════════════════════════════════════════════════════════
import QtQuick
import Quickshell
import "compositors"

QtObject {
    id: root

    readonly property string desktop: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
    // niri sets XDG_CURRENT_DESKTOP=niri and NIRI_SOCKET for the processes it
    // spawns. Accept either signal so the backend is correct even under a
    // session manager that does not export XDG_CURRENT_DESKTOP.
    readonly property bool isNiri: root.desktop.indexOf("niri") !== -1
        || (Quickshell.env("NIRI_SOCKET") || "") !== ""

    // Both instances exist; only the selected one is read. QtObject instances
    // are cheap and this avoids a Loader's async gap in a singleton.
    readonly property Hyprland _hypr: Hyprland {}
    readonly property Niri _niri: Niri {}

    readonly property var backend: root.isNiri ? root._niri : root._hypr

    // Data sources for the bar pollers (same output shape as before the port).
    readonly property var workspacesCommand: root.backend.workspacesCommand
    readonly property var keyboardCommand: root.backend.keyboardCommand
    readonly property var focusCommand: root.backend.focusCommand
    readonly property var displayPoller: root.backend.displayPoller

    // ── neutral monitor / version / launch surface ─────────────────────────
    // Command array a widget runs in its own Process when it needs a one-shot
    // monitor snapshot; decode the collected stdout with monitorsFromOutput().
    readonly property var monitorListCommand: root.backend.monitorListCommand

    // Capability flags. niri has no submaps; widgets hide those controls.
    readonly property bool hasSubmaps: root.backend.hasSubmaps

    // Emitted whenever a background refresh (refreshMonitorList /
    // refreshCompositorVersion) lands. Widgets that want the cached form can
    // bind to these instead of owning a Process.
    signal monitorListReady(var list)
    signal compositorVersionReady(var version)

    Connections {
        target: root.backend
        function onMonitorListReady(list) { root.monitorListReady(list); }
        function onVersionReady(version) { root.compositorVersionReady(version); }
    }

    // Live actions. Each border spec is { hex, alpha, second, angle } (see
    // Colors.borderSpec); the backend translates it to its own notation.
    function setWindowBorders(activeSpec, inactiveSpec) {
        root.backend.setWindowBorders(activeSpec, inactiveSpec);
    }

    function switchWorkspace(name) {
        root.backend.switchWorkspace(name);
    }

    function cycleKeyboardLayout() {
        root.backend.cycleKeyboardLayout();
    }

    // ── neutral session actions (idle panel + battery popups) ──────────────
    // Idle mode: awake|normal|boot (same verbs in both stacks' scripts); the
    // backend owns the daemon (hypridle vs swayidle) and the state file.
    function idleMode(mode) {
        root.backend.idleMode(mode);
    }

    // Quit / logout the session. The backend keeps its own semantics
    // (Hyprland exit.sh vs `niri msg action quit`).
    function quit() {
        root.backend.quit();
    }

    // ── neutral persistence (Config.qml routes through these) ──────────────
    function persistKeybinds(bindsArray) {
        root.backend.persistKeybinds(bindsArray);
    }

    function persistStartup(startupArray) {
        root.backend.persistStartup(startupArray);
    }

    // descriptors: neutral array built by Config.qml; displayConfigText is the
    // Hyprland pipe file (ignored by the niri backend).
    function applyMonitors(descriptors, displayConfigText) {
        root.backend.applyMonitors(descriptors, displayConfigText);
    }

    function resetMonitors() {
        root.backend.resetMonitors();
    }

    function reload() {
        root.backend.reload();
    }

    // ── neutral monitor helpers (panels) ───────────────────────────────────
    // Last normalised snapshot: [{ name, description, width, height, scale,
    // focused, refreshRate, x, y, transform, modes }]. Empty until refreshed.
    function monitorList() {
        return root.backend.monitorList();
    }

    function refreshMonitorList() {
        root.backend.refreshMonitorList();
    }

    // Pure decoder for a monitorListCommand output; safe to call from a widget
    // Process without touching the backend cache.
    function monitorsFromOutput(text) {
        return root.backend.monitorsFromOutput(text);
    }

    // Global display scale (the scale picker). `name` is the anchor output; an
    // empty name keeps the backend's "all outputs" semantics.
    function applyMonitorScale(name, scale) {
        root.backend.applyMonitorScale(name, scale);
    }

    // Apply one neutral descriptor { name, description, mode, x, y, scale,
    // transform, vrr, disabled } without persisting (monitor manager helpers).
    function applyMonitorConfig(descriptor) {
        root.backend.applyMonitorConfig(descriptor);
    }

    // ── neutral version + launch ───────────────────────────────────────────
    function compositorVersion() {
        return root.backend.compositorVersion();
    }

    function refreshCompositorVersion() {
        root.backend.refreshCompositorVersion();
    }

    // Spawn a command with no compositor involvement.
    function execApp(commandString) {
        root.backend.execApp(commandString);
    }

    // Enter/leave the Hyprland passthru submap (used while recording a key).
    // A no-op on niri, which has no submaps.
    function setSubmap(name) {
        root.backend.setSubmap(name);
    }
}
