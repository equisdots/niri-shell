# Overlay merge map

`niri-meta` copies every file in this repository over the shared shell tree at
`~/.config/hypr/scripts/quickshell/`, preserving the relative path. A Hyprland
session keeps working because the Hyprland backend and the Hyprland code paths
are the default.

## File-by-file map

Source (this repo) | Target (shell tree) | Kind | Notes
--- | --- | --- | ---
`core/Compositor.qml` | `core/Compositor.qml` | modified | Adds backend selection on `XDG_CURRENT_DESKTOP` **or** a set `NIRI_SOCKET`, the neutral persistence methods and the neutral monitor/version/launch/session helpers. The backend signal relay is held in the `_backendConn` property (a `QtObject` has no default property).
`core/compositors/Hyprland.qml` | `core/compositors/Hyprland.qml` | modified | Keeps every original command/script; adds the neutral persistence/monitor/version/launch surface.
`core/compositors/Niri.qml` | `core/compositors/Niri.qml` | **new** | niri backend over `niri msg`, implementing the same surface.
`core/Config.qml` | `core/Config.qml` | modified | Rebased on the SDK Settings façade; keybind/startup/monitor persistence route through `Compositor`, and the monitor poller is backend-owned.
`core/Effects.qml` | `core/Effects.qml` | **new** | Neutral effects singleton (same API as `HyprEffects`), backed by `effects.sh`.
`core/HyprEffects.qml` | `core/HyprEffects.qml` | modified | Compatibility shim: forwards to `Effects`.
`core/scripts/effects.sh` | `core/scripts/effects.sh` | **new** | Compositor-aware effects kernel. niri seeds active opacity 1.0 (no global override of per-app opacity), writes inactive opacity explicitly, and uses the niri blur defaults (offset 3, saturation 1.1) unless the state overrides them.
`core/scripts/niri-workspaces.sh` | `core/scripts/niri-workspaces.sh` | **new** | Workspace-state daemon for niri; writes the same `workspaces.json` shape.
`core/scripts/watchers/kb_fetch.sh` | same | modified | Compositor-aware layout fetch (`XDG_CURRENT_DESKTOP` or `NIRI_SOCKET`).
`ui/bar/BarEditor.qml` | same | modified | Rebased on shell HEAD; app-scale step calls `Compositor.applyMonitorScale` (no Hyprland-only script) and the animation persistence passes the 7-argument contract.
`ui/bar/Colors.qml` | same | modified | Muted `color8` active-border default (manual overrides still win); base `printErrors: false` kept.
`ui/bar/editor/AnimationsPage.qml` | same | **new** | Settings > Animations page from shell HEAD. Workspace style, special-workspace style and wrap are hidden when `Compositor.isNiri`; speed and curve stay. Footer documents Hyprland Lua vs niri KDL.
`ui/bar/editor/GuidePage.qml` | same | modified | About page shows the niri stack repos/doctor and compositor-neutral labels.
`ui/bar/editor/IdlePage.qml` | same | modified | Idle routing through `Compositor.idleMode`; duplicate core import removed.
`ui/bar/editor/InputPage.qml` | same | modified | The live `hyprctl getoption` seed is gated to Hyprland; footer no longer claims a Hyprland-only write path.
`ui/bar/editor/persist-appearance.sh` | same | **new** | Compositor-aware animations/input persistence. Animation CLI: `animations <0|1> <speed> <workspace_style> <curve> <special_style> <wrap>` (validated like `persist-hypr.sh`). Hyprland emits the full Lua animation set (workspace/special styles + wraparound); niri emits KDL for enabled, speed and the `workspace-switch` duration/curve, mapping `smooth/overshot/easeInOutQuart/easeOutExpo/easeOutQuint/linear` to cubic-bezier/linear/ease-out-expo. Style, special style and wrap are parsed and ignored on niri.
`ui/bar/editor/persist-hypr.sh` | same | modified | Forwarder to `persist-appearance.sh`.
`ui/bar/editor/PluginsPage.qml` | same | modified | Plugin enable/disable reload goes through `Compositor.reload()`.
`ui/bar/editor/sysinfo.sh` | same | modified | Compositor-aware version/monitors; niri/meta repo revisions.
`ui/bar/popups/applauncher/appLauncher.qml` | same | modified | Launches through `Compositor.execApp`.
`ui/bar/popups/battery/BatteryPopup.qml` | same | modified | Logout through `Compositor.quit()`.
`ui/bar/popups/battery/BatteryPopupAlt.qml` | same | modified | Logout through `Compositor.quit()`.
`ui/panels/davincix/DavincixPicker.qml` | same | modified | Monitor names from the neutral backend list.
`ui/panels/focustime/focus_daemon.py` | same | modified | Compositor-aware focus listener and lock detection.
`ui/panels/idle/IdlePopup.qml` | same | modified | Mode switch through `Compositor.idleMode`; backend-neutral timer label.
`ui/panels/plugins/PluginsPanel.qml` | same | modified | Plugin reload goes through `Compositor.reload()`.
`ui/bar/popups/updater/UpdaterPopup.qml` | same | modified | Reads `niri-meta/updates.json`, the niri version state and runs `dotsniri update`.
`ui/panels/scale/ScalePicker.qml` | same | modified | Reads/applies scale through the backend.
`ui/plugins/screenshots/ui/ScreenshotOverlay.qml` | same | modified | Prefers `EQUISDOTS_SCREENSHOT_SCRIPT` (niri launcher); the plugin resolver remains for Hyprland.
`ui/settings/tabs/KeybindTab.qml` | same | modified | Submap calls gated by `Compositor.hasSubmaps`; niri note.

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
| `idleMode(mode)` | `~/.config/hypr/scripts/idle-mode.sh <mode>` | `~/.config/niri/scripts/niri_idle_mode.sh <mode>` |
| `quit()` | `~/.config/hypr/scripts/exit.sh` | `niri msg action quit --skip-confirmation` |

Monitor entries use the neutral shape `{ name, description, width, height,
scale, focused, refreshRate, x, y, transform, modes }`; niri millihertz and
`logical.*` are normalised by the backend, so callers never see the difference.

Animations are persisted through the scripts rather than the backend object:
`BarEditor` calls `persist-hypr.sh animations <enabled> <speed> <workspace_style>
<curve> <special_style> <wrap>` (the forwarder keeps the base call site). The
script validates all seven arguments like the shell `persist-hypr.sh`. Hyprland
writes `config/user-animations.lua` with the workspace/special styles and
wraparound; niri writes `generated/user-animations.kdl` with `enabled`, the
speed-scaled durations and the `workspace-switch` curve. The Hyprland-only style
fields are parsed and ignored on niri. `ui/bar/editor/AnimationsPage.qml` hides
those controls when `Compositor.isNiri`.

### Why these files

The base shell has a set of compositor-coupled touch points: direct `hyprctl`
calls plus the session scripts (`idle-mode.sh`, `scale-menu.sh`, `exit.sh`) and
the plugin enable/disable reload. The overlay is rebased on the current shell
base (SDK `Settings`, MD3 tokens, plugin standard), so it does not regress those
features.
Every one that a user can reach from a widget is in this overlay: the seam
(`Compositor`, `Config`), the leaf scripts, and the consumers
(`ScalePicker`, `DavincixPicker`, `sysinfo.sh`, `appLauncher`, `KeybindTab`,
`focus_daemon.py`, `IdlePopup`, `IdlePage`, `AnimationsPage`, `BarEditor`,
`BatteryPopup`, `BatteryPopupAlt`, plus the `Colors` border-palette
derivation). They now call
the active backend or branch on `XDG_CURRENT_DESKTOP`; no widget calls
`hyprctl` directly. Base files that
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

A base consumer is copied only when a compositor-facing line has to change
(`BarEditor.qml`, `AnimationsPage.qml`, `InputPage.qml`, the two battery
popups, the two idle consumers, the updater and `appLauncher`); everywhere else
the shim keeps the overlay a pure drop-in, with no large consumer file to drift
from the base shell.

### Bring-up notes (niri)

- **Backend detection.** `isNiri` is true when `XDG_CURRENT_DESKTOP` contains
  `niri` or `NIRI_SOCKET` is set. niri exports both to its children, so either
  signal is sufficient and a session manager that drops `XDG_CURRENT_DESKTOP` no
  longer misroutes to the Hyprland backend.
- **`QtObject` has no default property.** `core/Compositor.qml` holds its
  backend signal relay in the `_backendConn` property; declaring `Connections
  { }` as a child made Quickshell fail to load the whole config under niri
  ("Cannot assign to non-existent default property"), which appears as a missing
  bar and panel shortcuts that do nothing. Hyprland was unaffected because it
  reads the original files.
- **One-line KDL blocks are invalid.** `Niri.qml` always writes multi-line
  blocks, because a block whose last node is not terminated before `}` (for
  example `focus-ring { off }`) made `generated/borders.kdl` invalid and niri
  fell back to its default config.
- **Neutral border colour.** `ui/bar/Colors.qml` is overlaid (see the map
  above): `borderHex("active")` uses the palette's muted `color8` instead of the
  loud accent, so the niri border is a neutral grey that is harmonious across
  palettes. Manual `borderFollowPalette=false` overrides and per-palette roles
  still win.
- **Notifications.** The shell owns `org.freedesktop.notifications`; unlike a
  standalone compositor setup, `mako`/`dunst` must not run alongside it.

## niri config include contract

The generated fragments live in `~/.config/niri/generated/` and must be included
by the niri base config (`~/.config/niri/config.kdl`, owned by the sibling
`niri` repo). Include them at the top level, after the base sections so they
win, and do not also define the same single-occurrence sections:

```kdl
include "generated/user-input.kdl"       // input { ... } (sole owner)
include "generated/user-animations.kdl"  // animations { ... } (sole owner)
include "generated/blur.kdl"             // blur { ... } (sole owner)
include "generated/theme-colors.kdl"     // palette border colours
include "generated/borders.kdl"          // layout { border { colors } } (after theme-effects)
include "generated/theme-effects.kdl"    // layout { gaps/border/shadow }, window-rule
include "generated/outputs.kdl"          // output "..." blocks (sole owner)
include "generated/user-binds.kdl"       // binds { ... }
include "generated/user-startup.kdl"     // spawn-sh-at-startup ...
```

Rules:

- `layout` and `binds` deep-merge, so `borders.kdl` (colours) and
  `theme-effects.kdl` (`border width`) compose; keep `borders.kdl` after
  `theme-effects.kdl` if colour should win per property.
- `input`, `animations` and `blur` are single-occurrence sections: each has its
  own generated fragment as the sole definition (never also in `config.kdl` or
  the modules). The installers seed them from `niri/config/niri/defaults/`. `output` blocks may repeat but each
  output name must be unique, so the base config must not define the same output
  names. A duplicate section is a `niri validate` error.
- Validate the assembled tree: `niri validate -c ~/.config/niri/config.kdl`.

## Rollback

Because nothing under `equisdots/shell` is modified, rollback is a file
restore:

1. Restore the modified base files from the shell repo (or re-run the shell's
   own deploy): `core/Compositor.qml`, `core/compositors/Hyprland.qml`,
   `core/Config.qml`, `core/HyprEffects.qml`,
   `core/scripts/watchers/kb_fetch.sh`,
   `ui/bar/editor/persist-hypr.sh`, `ui/panels/scale/ScalePicker.qml`,
   `ui/panels/davincix/DavincixPicker.qml`, `ui/bar/editor/sysinfo.sh`,
   `ui/bar/popups/applauncher/appLauncher.qml`,
   `ui/settings/tabs/KeybindTab.qml`,
   `ui/panels/focustime/focus_daemon.py`,
   `ui/panels/idle/IdlePopup.qml`, `ui/bar/editor/IdlePage.qml`,
   `ui/bar/editor/InputPage.qml`, `ui/bar/BarEditor.qml`,
   `ui/bar/editor/GuidePage.qml`, `ui/bar/editor/PluginsPage.qml`,
   `ui/panels/plugins/PluginsPanel.qml`,
   `ui/bar/popups/updater/UpdaterPopup.qml`,
   `ui/bar/popups/battery/BatteryPopup.qml`,
   `ui/bar/popups/battery/BatteryPopupAlt.qml`, `ui/bar/Colors.qml`,
   `ui/plugins/screenshots/ui/ScreenshotOverlay.qml`.
2. Remove the new files: `core/compositors/Niri.qml`, `core/Effects.qml`,
   `core/scripts/effects.sh`, `core/scripts/niri-workspaces.sh`,
   `ui/bar/editor/persist-appearance.sh`, `ui/bar/editor/AnimationsPage.qml`.
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
- No workspace transition style, special-workspace style or workspace
  wraparound: the animation options are parsed/validated and ignored on niri;
  only the workspace-switch duration and curve are emitted.
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
the file map above). The session script call sites are closed too: no widget
invokes `idle-mode.sh`, `scale-menu.sh` or `exit.sh` directly anymore. They go
through `Compositor.idleMode`, `Compositor.applyMonitorScale` and
`Compositor.quit`, which select the niri equivalents. The only base file still
calling `hyprctl` directly is:

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

