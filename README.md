# equisdots niri — niri-shell

A drop-in overlay that makes the shared equisdots Quickshell shell
compositor-neutral, so the exact same bar, popups, panels, widgets, settings
editor and lock screen run on **both Hyprland and niri** with no UI loss.

This repository does not contain the shell. It contains only the files that must
change or that are new. `niri-meta` deploys them over the shared shell tree at
`~/.config/hypr/scripts/quickshell/`, and the shell chooses a backend at runtime
from `XDG_CURRENT_DESKTOP`.

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

`core/Compositor.qml` reads `XDG_CURRENT_DESKTOP`:

- a value containing `niri` selects `core/compositors/Niri.qml`;
- any other value, or an unset variable, selects
  `core/compositors/Hyprland.qml`.

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
