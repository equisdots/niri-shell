pragma Singleton
import QtQuick

// ═══════════════════════════════════════════════════════════════════════════
// HyprEffects — compatibility shim.
//
// The compositor-neutral implementation is core/Effects.qml. The existing
// consumers still reference the `HyprEffects` name (ui/bar/editor/
// HyprlandPage.qml and ui/panels/window-controls/WindowControls.qml), so this
// shim forwards every member to `Effects` instead of duplicating the kernel.
// Consumers can migrate to `Effects` at any time; no UI change is required.
// ═══════════════════════════════════════════════════════════════════════════
QtObject {
    id: shim

    readonly property var values: Effects.values

    function get(key) { return Effects.get(key); }
    function set(key, v) { Effects.set(key, v); }
    function flush() { Effects.flush(); }
    function refresh() { Effects.refresh(); }
    function persist() { Effects.persist(); }
    function resetEffects() { Effects.resetEffects(); }
}
