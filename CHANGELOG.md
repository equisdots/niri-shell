# Changelog

All notable changes to the `niri-shell` overlay are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ui/bar/editor/AnimationsPage.qml`: the Settings > Animations page from shell
  HEAD. Speed and curve are shared; workspace style, special-workspace style and
  wraparound are hidden on niri, and the footer documents the Hyprland Lua vs
  niri KDL output.
- Workspace animation options: the animation persistence contract is now
  `animations <enabled> <speed> <workspace_style> <curve> <special_style>
  <wrap>`. Hyprland emits the full Lua set (workspace/special styles,
  wraparound); niri emits valid KDL for enabled, speed and the
  `workspace-switch` duration/curve, mapping the Hyprland bezier names to
  niri cubic-bezier/linear/ease-out-expo. Style, special style and wrap are
  parsed and ignored on niri.
- Parity with the merged Hyprland plugin stack: the overlay is rebased on the
  current shell base (SDK `Settings`, MD3 `core/Theme.qml` tokens,
  `PluginPopup`/`PluginPositionRow`, the Plugins panel and catalog). New overlay
  files cover the plugin touch points: `ui/panels/plugins/PluginsPanel.qml` and
  `ui/bar/editor/PluginsPage.qml` reload through the backend, and
  `ui/plugins/screenshots/ui/ScreenshotOverlay.qml` honours
  `EQUISDOTS_SCREENSHOT_SCRIPT` exported by `niri_screenshot.sh`.
- `ui/bar/editor/GuidePage.qml`: the About page reports the niri stack repos,
  the niri doctor and compositor-neutral labels.
- `ui/bar/editor/sysinfo.sh`: niri/meta repo revisions and compositor-aware
  version/monitor output.
- `ui/bar/popups/updater/UpdaterPopup.qml`: the updater reads
  `niri-meta/updates.json`, the niri version state and runs `dotsniri update`
  instead of the Hyprland installer.
- First release of the compositor-neutral Quickshell overlay: a niri backend
  (`core/compositors/Niri.qml`) plus the KDL writers under
  `~/.config/niri/generated/`, selected at runtime from the environment. The
  exact same bar, popups, panels, widgets, settings editor and lock screen run
  on Hyprland and niri with no UI loss (`849d09d`).
- Neutral persistence through the backend seam: `core/Config.qml`,
  `core/Effects.qml`, the compositor-aware watcher `kb_fetch.sh` and
  `ui/bar/editor/persist-appearance.sh` so keybinds, startup, monitors,
  animations and input materialise as KDL on niri (`849d09d`).
- `ui/bar/Colors.qml` is now part of the overlay: `borderHex("active")` derives
  from the palette's muted `color8` instead of the loud accent, so the niri
  border is a neutral grey that stays harmonious across palettes (`8ae3d24`).
- Neutral session and display routing: `Compositor.idleMode`, `Compositor.quit`
  and `Compositor.applyMonitorScale` are called by the idle panel, the battery
  popups and the bar editor instead of the Hyprland-only session scripts
  (`ba9614a`).
- niri detection also accepts `NIRI_SOCKET`, in addition to
  `XDG_CURRENT_DESKTOP` (`6bfe2d7`).

### Changed

- Removed the screenshots overlay file: screenshots/recording moved to the
  separate `equisdots/plugins-niri` repository, whose plugin calls
  `niri_screenshot.sh` and `niri_record.sh` directly. `niri-meta` re-deploys
  the niri plugin after the shell overlays so the migration cannot restore the
  old Hyprland implementation.

- Rebased the overlay on shell `805a107` and the screenshots plugin `18e742e`:
  `BarEditor` (workspace animation defaults + four extra persist args),
  `AnimationsPage` (new), the battery popups, `DavincixPicker`, `Colors`,
  `appLauncher`, `UpdaterPopup` and `IdlePage` now carry only the niri deltas
  (`Compositor.quit`/`execApp`/`idleMode`/`applyMonitorScale`, neutral monitor
  list, `color8` border, niri-meta updater). `ScreenshotOverlay` keeps
  `EQUISDOTS_SCREENSHOT_SCRIPT` and the new `implicitWidth`/`implicitHeight`
  surface fix.
- Rebased every overlay file on the current shell base: the pre-SDK
  `core/Config.qml` (and the stale MD3/pre-plugin variants of `BarEditor`,
  `Colors`, `IdlePage`, `InputPage`, `appLauncher`, the battery popups,
  `DavincixPicker`, `IdlePopup`, `ScalePicker` and `KeybindTab`) are gone; only
  the compositor-specific deltas remain.
- The screenshots overlay moved with its plugin: the overlay now targets
  `ui/plugins/screenshots/ui/ScreenshotOverlay.qml` (the old root
  `ScreenshotOverlay.qml` is no longer deployed by the shell).
- Documented and split the border ownership: `ui/bar/Colors.qml` owns the
  border colour, `theme-effects.kdl` owns the border width, and
  `generated/borders.kdl` owns the colour block only (`8ae3d24`).

### Fixed

- `ui/panels/davincix/DavincixPicker.qml`: opening the wallpaper picker now
  starts `davincix thumbs` itself, so the grid populates even when the picker
  is opened directly (IPC/settings) instead of through `qs_manager.sh`.
- `ui/bar/editor/HyprlandPage.qml` + `ui/bar/BarEditor.qml`: on niri the page
  is relabeled **Effects** (nav and title), the description/footer reference the
  generated KDL instead of Hyprland Lua, and the unsupported Shadow Power knob
  is hidden. The effects singleton remains the same shim used by the Window
  Controls widget.
- `core/compositors/Niri.qml`: generated keybinds no longer mark every `exec`
  action `allow-when-locked=true`; only `bindl`/`bindel` (or an explicitly
  locked action) do. This closes the lock-screen app-launch hole and matches
  the Hyprland backend.
- `core/scripts/effects.sh`: the generated global opacity rules are only
  emitted when the user changes the static defaults (active 0.85 / inactive
  0.80 in `modules/window-rules.kdl`), so the per-app opacity window rules are
  no longer shadowed at defaults while an explicit change still wins. The blur
  fragment now uses the niri defaults (offset 3, saturation 1.1) unless the
  state sets `blur_offset`/`blur_size` or `blur_saturation`.
- `core/scripts/watchers/kb_fetch.sh` and `core/scripts/effects.sh` accept
  `NIRI_SOCKET` in addition to `XDG_CURRENT_DESKTOP`, matching
  `core/Compositor.qml`. Deleted the dead `kb_wait.sh` (the shell removed it and
  nothing consumes it).
- Rebased overlay consumers no longer produce the runtime warnings fixed in
  `a9c478b`/`fe9e2e2`: null defaults and guarded `Connections` targets in the
  battery popups, explicit `Settings.location`, `printErrors: false` on the
  palette `FileView`s, and arrow-function `Keys` handlers. `IdlePage` has a
  single core import; `IdlePopup`/`InputPage` labels are backend-neutral.
- The niri writers now keep the single-occurrence sections unique: `effects.sh`
  writes the global `blur {}` block to `generated/blur.kdl` (not inside
  `theme-effects.kdl`), and `persist-appearance.sh input` emits a complete
  `input {}` section (keyboard + pointer + focus-follows-mouse) because the
  generated file is now its sole owner. This removes the duplicate-section
  `niri validate` failure that appeared after using the Settings panel.
- `core/Compositor.qml` no longer declares `Connections { }` as a child of the
  `QtObject` singleton. A `QtObject` has no default property, so the shell
  failed to load the whole config under niri with "Cannot assign to non-existent
  default property" (no bar or panels, and panel shortcuts did nothing). The
  `Connections` is held in the `_backendConn` property instead (`13d8584`).
- `core/compositors/Niri.qml` emits valid multi-line KDL from
  `setWindowBorders`: the one-line `focus-ring { off }` produced an invalid file
  that niri rejected, so the block is written over multiple lines and
  `generated/borders.kdl` is the file the sibling `niri` repository includes
  (`8ae3d24`).
- Removed a committed `__pycache__` and added Python build artifacts
  (`__pycache__/`, `*.pyc`) to `.gitignore` (`b89d25b`).
