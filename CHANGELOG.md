# Changelog

All notable changes to the `niri-shell` overlay are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First release of the compositor-neutral Quickshell overlay: a niri backend
  (`core/compositors/Niri.qml`) plus the KDL writers under
  `~/.config/niri/generated/`, selected at runtime from the environment. The
  exact same bar, popups, panels, widgets, settings editor and lock screen run
  on Hyprland and niri with no UI loss (`849d09d`).
- Neutral persistence through the backend seam: `core/Config.qml`,
  `core/Effects.qml`, the compositor-aware watchers (`kb_fetch.sh`,
  `kb_wait.sh`) and `ui/bar/editor/persist-appearance.sh` so keybinds, startup,
  monitors, animations and input materialise as KDL on niri (`849d09d`).
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

- Documented and split the border ownership: `ui/bar/Colors.qml` owns the
  border colour, `theme-effects.kdl` owns the border width, and
  `generated/borders.kdl` owns the colour block only (`8ae3d24`).

### Fixed

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
