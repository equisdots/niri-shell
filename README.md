# equisdots niri — niri-shell

A drop-in overlay that makes the shared equisdots Quickshell shell
compositor-neutral, so the exact same bar, popups, panels, widgets, settings
editor and lock screen run on **both Hyprland and niri** with no UI loss.

This repository does not contain the shell. It contains only the files that must
change or that are new. `niri-meta` deploys them over the shared shell tree at
`~/.config/hypr/scripts/quickshell/`, and the shell chooses a backend at runtime
from `XDG_CURRENT_DESKTOP` / `NIRI_SOCKET`.

## The overlay model

```
equisdots/shell/            (read-only base, unchanged)
        +
equisdots-niri/niri-shell/  (this overlay)
        =
~/.config/hypr/scripts/quickshell/   (deployed, compositor-neutral)
```

Every file here is either new or a modified version of a base file. Nothing is
shipped that would work unchanged: if a base file already works under niri, it
is not in this repository. A Hyprland user who installs the niri meta keeps the
same behaviour, because the Hyprland backend and the Hyprland code paths are the
default.

The merge is file-by-file (same relative path as the shell tree). See
[docs/overlay.md](docs/overlay.md) for the exact source -> target map and the
rollback procedure.

## Backend selection

`core/Compositor.qml` selects the backend from the environment:

- `XDG_CURRENT_DESKTOP` containing `niri`, or a set `NIRI_SOCKET`, selects
  `core/compositors/Niri.qml`;
- any other value, or both unset, selects `core/compositors/Hyprland.qml`.

niri sets both `XDG_CURRENT_DESKTOP=niri` and `NIRI_SOCKET` for the processes it
spawns, so accepting either signal keeps the backend correct under a session
manager that does not export `XDG_CURRENT_DESKTOP`.

Both backends exist at once; only the selected one is read. Widgets never branch
on the compositor: they consume `Compositor.workspacesCommand`,
`keyboardCommand`, `focusCommand`, `setWindowBorders`, `switchWorkspace` and
`cycleKeyboardLayout` exactly as before. `core/Config.qml` adds the neutral
persistence calls (`persistKeybinds`, `persistStartup`, `applyMonitors`,
`resetMonitors`, `reload`) and routes them through the active backend.

| Concern | Hyprland | niri |
| --- | --- | --- |
| Workspaces JSON | `workspaces.sh` daemon (`hyprctl` + `.socket2.sock`) | `niri-workspaces.sh` daemon (`niri msg --json event-stream`) |
| Keyboard layout | `hyprctl devices -j` | `niri msg --json keyboard-layouts` |
| Focused window | `hyprctl activewindow -j` | `niri msg --json focused-window` |
| Borders | `hyprctl eval 'hl.config(...)'` | `generated/borders.kdl` + reload |
| Keybinds | `config/user-keybinds.lua` + `hyprctl reload` | `generated/user-binds.kdl` + reload |
| Startup | `config/user-startup.lua` + reload | `generated/user-startup.kdl` + reload |
| Appearance | `config/*.lua` + reload | `generated/user-animations.kdl`, `generated/user-input.kdl` + reload |
| Effects | `hyprctl getoption/eval` + Lua | `generated/theme-effects.kdl` + reload |
| Monitors | `hl.monitor` + `display-config` | `generated/outputs.kdl` + reload |

All niri writes land in `~/.config/niri/generated/` and are applied with
`niri msg action load-config-file`. The niri config must include them (see
[docs/overlay.md](docs/overlay.md)).

## Known QML gotchas

Three bring-up issues are worth knowing before touching the overlay:

- **`QtObject` has no default property.** A `Connections { }` (or any child
  item) declared directly inside the `core/Compositor.qml` singleton makes
  Quickshell fail to load the whole config with "Cannot assign to non-existent
  default property", which presents as a missing bar and dead panel shortcuts.
  Hold it in a property instead (see `_backendConn`). Hyprland was unaffected
  because it uses the original, unmodified files.
- **niri rejects one-line KDL blocks.** A block whose last node is not
  terminated before `}` (for example `focus-ring { off }`) makes the generated
  file invalid and niri falls back to its default config. `Niri.qml` writes
  multi-line blocks (`focus-ring {`, `off`, `}`) into
  `generated/borders.kdl`.
- **Palette accent vs muted border.** `ui/bar/Colors.qml` is shipped by this
  overlay: `borderHex("active")` derives from the palette's muted `color8`
  rather than the loud accent, so the niri border stays a neutral grey that is
  harmonious across palettes. Manual overrides (`borderFollowPalette=false`)
  and per-palette roles still win.

## Data root

The shell's data root stays `~/.config/hypr` on both compositors: `settings.json`,
`dock/palettes`, wallpapers and the shell install path do not move. Only the
compositor-specific output moves to `~/.config/niri/`. See
[DESIGN.md](DESIGN.md) for the persistence contract.

## Documentation

- [DESIGN.md](DESIGN.md) — backends, the compositor-neutral persistence
  contract, and the hard UI rule for compact, content-fitting widgets.
- [docs/overlay.md](docs/overlay.md) — file-by-file merge map and rollback.

## Validation

niri is not installed on the machine this overlay was authored on, so the niri
paths are validated against the vendored `recursos/niri` and
`recursos/hyprland-niri` references (niri 26.04) rather than a live session.
Shell scripts pass `bash -n`; QML is checked for brace balance. Before shipping
to a niri machine, assemble the config and run `niri validate`, then verify the
bar, palette and monitor canvas live.

## License

MIT. See [LICENSE](LICENSE).
