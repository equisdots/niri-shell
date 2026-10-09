# Overlay merge map

`niri-meta` copies every file in this repository over the shared shell tree at
`~/.config/hypr/scripts/quickshell/`, preserving the relative path. A Hyprland
session keeps working because the Hyprland backend and the Hyprland code paths
are the default.

## File-by-file map

Source (this repo) | Target (shell tree) | Kind | Notes
--- | --- | --- | ---
`core/Compositor.qml` | `core/Compositor.qml` | modified | Adds `XDG_CURRENT_DESKTOP` backend selection, the neutral persistence methods and the neutral monitor/version/launch helpers (`monitorListCommand`, `refreshMonitorList`, `monitorsFromOutput`, `applyMonitorScale`, `applyMonitorConfig`, `compositorVersion`, `execApp`, `hasSubmaps`, `setSubmap`). Existing surface unchanged.
`core/compositors/Hyprland.qml` | `core/compositors/Hyprland.qml` | modified | Keeps every original command/script; adds `displayPoller`, `persistKeybinds`, `persistStartup`, `applyMonitors`, `resetMonitors`, `reload`, plus `monitorList`/`applyMonitorScale`/`applyMonitorConfig`/`compositorVersion`/`execApp`/`setSubmap` and `hasSubmaps = true`.
`core/compositors/Niri.qml` | `core/compositors/Niri.qml` | **new** | niri backend over `niri msg`, implementing the same surface (`hasSubmaps = false`).
`core/Config.qml` | `core/Config.qml` | modified | Keybind/startup/monitor persistence routes through `Compositor`. Same `settings.json` contract and monitor canvas math.
`core/Effects.qml` | `core/Effects.qml` | **new** | Neutral effects singleton (same API as the old `HyprEffects`), backed by `effects.sh`.
`core/HyprEffects.qml` | `core/HyprEffects.qml` | modified | Compatibility shim: forwards to `Effects` so `HyprlandPage.qml`/`WindowControls.qml` need no edit.
`core/scripts/effects.sh` | `core/scripts/effects.sh` | **new** | Compositor-aware effects kernel (replaces the call site of `hypr-effects.sh`).
`core/scripts/niri-workspaces.sh` | `core/scripts/niri-workspaces.sh` | **new** | Workspace-state daemon for niri; writes the same `workspaces.json` shape.
`core/scripts/watchers/kb_fetch.sh` | `core/scripts/watchers/kb_fetch.sh` | modified | Compositor-aware layout fetch.
`core/scripts/watchers/kb_wait.sh` | `core/scripts/watchers/kb_wait.sh` | modified | Compositor-aware layout event wait.
`ui/bar/editor/persist-appearance.sh` | `ui/bar/editor/persist-appearance.sh` | **new** | Compositor-aware animations/input persistence (port of `persist-hypr.sh`).
`ui/bar/editor/persist-hypr.sh` | `ui/bar/editor/persist-hypr.sh` | modified | Forwarder to `persist-appearance.sh` so `BarEditor.qml` needs no edit.
`ui/panels/scale/ScalePicker.qml` | `ui/panels/scale/ScalePicker.qml` | modified | Reads the anchor monitor through `Compositor.monitorListCommand` + `Compositor.monitorsFromOutput`; applies through `Compositor.applyMonitorScale`. No `hyprctl` in the panel.
`ui/panels/davincix/DavincixPicker.qml` | `ui/panels/davincix/DavincixPicker.qml` | modified | Monitor names come from `Compositor.monitorListCommand` + `Compositor.monitorsFromOutput` instead of `hyprctl monitors -j`.
`ui/bar/editor/sysinfo.sh` | `ui/bar/editor/sysinfo.sh` | modified | Compositor-aware version and monitor block (`hyprctl` under Hyprland, `niri msg` under niri). Same `KEY=VALUE` contract.
`ui/bar/popups/applauncher/appLauncher.qml` | `ui/bar/popups/applauncher/appLauncher.qml` | modified | Launches through `Compositor.execApp` (`Quickshell.execDetached`) instead of `hyprctl eval 'hl.dsp.exec_cmd(...)'`.
`ui/settings/tabs/KeybindTab.qml` | `ui/settings/tabs/KeybindTab.qml` | modified | Submap enter/reset goes through `Compositor.setSubmap` and is skipped when `Compositor.hasSubmaps` is false; a short note is shown on niri. No crash without submap support.
`ui/panels/focustime/focus_daemon.py` | `ui/panels/focustime/focus_daemon.py` | modified | Compositor-aware focus listener (`niri msg --json event-stream` under niri, `.socket2.sock` under Hyprland) and lock detection. Output contract (`focustime.db` schema + `focustime_state.json`) unchanged, so `FocusModule.qml`/`FocusTimePopup.qml` need no edit.

### Neutral backend surface

`core/Compositor.qml` forwards these to the selected backend; both backends
implement every one.

| Signature | Hyprland | niri |
| --- | --- | --- |
| `monitorListCommand` (array) | `["hyprctl","monitors","-j"]` | `bash` envelope of `niri msg --json outputs` + `focused-output` |
| `monitorsFromOutput(text)` → array | parses `hyprctl -j monitors` | parses the outputs+focused envelope (`decodeNiri`) |
| `monitorList()` → array | last normalised snapshot | last normalised snapshot |
| `refreshMonitorList()` / `signal monitorListReady(list)` | re-runs the snapshot Process | re-runs the snapshot Process |
| `applyMonitorScale(name, scale)` | `scale-menu.sh <scale>` (unchanged global path) | `niri msg output <name> scale` for every output + records `scale` in `settings.json` |
| `applyMonitorConfig(descriptor)` | `hyprctl eval 'hl.monitor({...})'` | `niri msg output <name> mode/scale/position/transform/vrr/off` |
| `versionCommand` / `compositorVersion()` / `refreshCompositorVersion()` | `hyprctl version -j` → `.tag` | `niri msg --json version` → `.compositor` |
| `execApp(command)` | `Quickshell.execDetached(["bash","-c", …])` | same (no compositor involvement) |
| `hasSubmaps` | `true` | `false` |
| `setSubmap(name)` | `hyprctl eval 'hl.dispatch(hl.dsp.submap(name))'` | no-op |

Monitor entries use the neutral shape `{ name, description, width, height,
scale, focused, refreshRate, x, y, transform, modes }`; niri millihertz and
`logical.*` are normalised by the backend, so callers never see the difference.

### Why these files

The base shell has a set of direct `hyprctl` touch points. Every one that a
user can reach from a widget is in this overlay: the seam (`Compositor`,
`Config`), the leaf scripts, and the panels/settings/daemon consumers
(`ScalePicker`, `DavincixPicker`, `sysinfo.sh`, `appLauncher`, `KeybindTab`,
`focus_daemon.py`). They now call the active backend or branch on
`XDG_CURRENT_DESKTOP`; no widget calls `hyprctl` directly. Base files that
already work unchanged under niri (the QML widgets, palettes, `WlrLayershell`,
`WlSessionLock`, the other watchers) are **not** shipped. The one remaining read
that has no niri equivalent is documented below.

### Compatibility shims (no base-file edits)

Two base consumers reference legacy names:

- `ui/bar/editor/HyprlandPage.qml` and `ui/panels/window-controls/WindowControls.qml`
  call `HyprEffects.*`. The `core/HyprEffects.qml` shim keeps that name
  resolving to `core/Effects.qml`.
- `ui/bar/BarEditor.qml` calls `persist-hypr.sh`. The `ui/bar/editor/persist-hypr.sh`
  forwarder delegates to `persist-appearance.sh`.

This keeps the overlay a pure drop-in: no large consumer file is copied, so it
cannot drift from the base shell.

## niri config include contract

The generated fragments live in `~/.config/niri/generated/` and must be included
by the niri base config (`~/.config/niri/config.kdl`, owned by the sibling
`niri` repo). Include them at the top level, after the base sections so they
win, and do not also define the same single-occurrence sections:

```kdl
include "generated/outputs.kdl"          // output "..." blocks (sole owner)
include "generated/theme-effects.kdl"    // layout { gaps/border/shadow }, blur, window-rule
include "generated/borders.kdl"          // layout { border { colors } } (after theme-effects)
include "generated/user-binds.kdl"       // binds { ... }
include "generated/user-startup.kdl"     // spawn-sh-at-startup ...
include "generated/user-animations.kdl"  // animations { ... } (sole owner)
include "generated/user-input.kdl"       // input { ... } (sole owner)
```

Rules:

- `layout` and `binds` deep-merge, so `borders.kdl` (colours) and
  `theme-effects.kdl` (`border width`) compose; keep `borders.kdl` after
  `theme-effects.kdl` if colour should win per property.
- `input`, `animations` and `blur` are single-occurrence sections: the generated
  fragments are their sole definition. `output` blocks may repeat but each
  output name must be unique, so the base config must not define the same output
  names. A duplicate section is a `niri validate` error.
- Validate the assembled tree: `niri validate -c ~/.config/niri/config.kdl`.

## Rollback

Because nothing under `equisdots/shell` is modified, rollback is a file
restore:

1. Restore the modified base files from the shell repo (or re-run the shell's
   own deploy): `core/Compositor.qml`, `core/compositors/Hyprland.qml`,
   `core/Config.qml`, `core/HyprEffects.qml`,
   `core/scripts/watchers/kb_fetch.sh`, `core/scripts/watchers/kb_wait.sh`,
   `ui/bar/editor/persist-hypr.sh`, `ui/panels/scale/ScalePicker.qml`,
   `ui/panels/davincix/DavincixPicker.qml`, `ui/bar/editor/sysinfo.sh`,
   `ui/bar/popups/applauncher/appLauncher.qml`,
   `ui/settings/tabs/KeybindTab.qml`,
   `ui/panels/focustime/focus_daemon.py`.
2. Remove the new files: `core/compositors/Niri.qml`, `core/Effects.qml`,
   `core/scripts/effects.sh`, `core/scripts/niri-workspaces.sh`,
   `ui/bar/editor/persist-appearance.sh`.
3. Optionally remove the generated niri fragments:
   `rm -rf ~/.config/niri/generated`.
4. `settings.json` and `~/.config/hypr/` are never touched by the rollback, so
   a Hyprland session resumes with its full state.

A Hyprland session is unaffected even with the overlay deployed and no rollback
performed, because it selects the Hyprland backend.

## Not fully ported (documented gaps)

These are inherent niri 26.04 limitations, not overlay bugs:

- No reportable HDR / colour-management preset or bit depth in
  `niri msg --json outputs`: those monitor fields stay in `settings.json` but are
  not written to KDL.
- No output mirroring: `mirrorOf` is not materialised under niri.
- No live per-frame `hyprctl`-style option patch: the effects preview is a state
  update and materialises on persist.
- No per-device keyboard layout switch: `switch-layout` is global.
- Dynamic workspaces: the pill row is derived (`1..N`) rather than backed by
  static workspace ids; multi-monitor `idx` collisions prefer the focused
  output.
- `switchWorkspace` under niri calls `niri msg action focus-workspace` directly
  instead of `qs_manager.sh`, which is Hyprland-specific and is not part of this
  overlay. Hyprland keeps the `qs_manager.sh` path.
- niri is not installed on the authoring machine; the shims are `bash -n` and
  brace-balance clean, but the niri runtime paths must be confirmed in a live
  session with `niri validate` and a visual pass.

## Remaining direct `hyprctl` call sites

The five call sites that were previously listed here are now in the overlay (see
the file map above). The only base file still calling `hyprctl` directly is:

- `ui/bar/editor/InputPage.qml` — seeds the live `input:*` values with
  `hyprctl getoption` (read-only). The write path already goes through the
  compositor-aware `persist-appearance.sh`, so niri keeps its stored values; the
  live seed has no niri equivalent (`hyprctl getoption` is the one query niri
  does not expose). Port it by reading the stored `settings.json`/`effects`
  state instead, in a follow-up.

`ui/bar/modules/FocusModule.qml` is clean: it reads the focused window through
`Compositor.focusCommand` (`Bar.qml`), which this overlay makes
compositor-neutral. The remaining `hyprctl` mentions in base files are comments.

## Genuinely unsupported on niri (not overlay bugs)

- **Submaps**: niri has none. `Compositor.hasSubmaps` is `false`, the keybind
  editor skips the passthru/reset calls and shows a short note; nothing crashes.
- **Output mirroring**: `mirrorOf` / `hyprctl ... mirror` has no niri 26.04
  equivalent and is dropped from the niri materialisation.
- **Live option query/patch** (`hyprctl getoption` / `hyprctl eval`): no
  equivalent; niri applies generated KDL on reload and `niri msg output` is the
  only runtime setter.
- **Per-device keyboard layout switch**: `switch-layout` is global.
- **HDR / colour-management preset and bit depth**: not reportable in
  `niri msg --json outputs`.

