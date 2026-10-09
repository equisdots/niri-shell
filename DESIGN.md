# Design

This document records the design decisions behind the niri-shell overlay: the
two backends, the compositor-neutral persistence contract, and the UI rule that
governs every widget or panel that is ported or touched.

Baseline for all niri facts: niri 26.04 (2026-04-25), as vendored in
`recursos/niri` and `recursos/hyprland-niri`.

## 1. Two backends behind one seam

`core/Compositor.qml` is the only place that knows which compositor is running.
It exposes:

- the data-source command arrays the bar pollers run (`workspacesCommand`,
  `keyboardCommand`, `focusCommand`);
- the live actions (`setWindowBorders`, `switchWorkspace`,
  `cycleKeyboardLayout`);
- the neutral persistence methods (`persistKeybinds`, `persistStartup`,
  `applyMonitors`, `resetMonitors`, `reload`);
- `displayPoller`, the backend-owned monitor reader.

`core/compositors/Hyprland.qml` is the original backend plus the neutral
methods. Its command strings, scripts and `hyprctl` calls are unchanged, so a
Hyprland session behaves exactly as before.

`core/compositors/Niri.qml` implements the same surface with real niri
commands. It owns every KDL write and every `niri msg action` call; nothing
else in the shell does.

Selection is `XDG_CURRENT_DESKTOP`: a value containing `niri` chooses the niri
backend, anything else (including an unset variable) chooses Hyprland. The
Hyprland default is deliberate: installing the niri meta must not change a
Hyprland user's session.

## 2. The compositor-neutral persistence contract

`settings.json` remains the single source of truth and keeps every key it had
(`uiScale`, `appScale`, `wallpaperDir`, `language`, `kbOptions`,
`workspaceCount`, `keybinds`, `startup`, `monitors`, `animations`, `input`,
`launcher`, `bar`, `glass`, ...). The data root stays `~/.config/hypr`; only the
compositor-specific generated output moves.

The contract is: a UI mutation becomes a neutral descriptor list or settings
change, the active backend materialises it, and the backend reloads.

| Input | Neutral form | Hyprland materialisation | niri materialisation |
| --- | --- | --- | --- |
| Keybinds | `keybinds[]` (`type`, `mods`, `key`, `dispatcher`, `command`) | `config/user-keybinds.lua`, `hyprctl reload` | `generated/user-binds.kdl`, `load-config-file` |
| Startup | `startup[]` (`command`) | `config/user-startup.lua`, reload | `generated/user-startup.kdl`, reload |
| Animations | `{ enabled, speed }` | `config/user-animations.lua`, reload | `generated/user-animations.kdl`, reload |
| Input | `{ sensitivity, accelProfile, tapToClick, naturalScroll, disableWhileTyping }` | `config/user-input.lua`, reload | `generated/user-input.kdl`, reload |
| Effects | 12 numeric knobs | `hyprctl eval` + `window-effects.lua`/`gaps.lua` | `generated/theme-effects.kdl`, reload |
| Borders | `{ hex, alpha, second, angle }` | `hyprctl eval 'hl.config(...)'` | `generated/borders.kdl`, reload |
| Monitors | descriptor list + deterministic `display-config` text | `hl.monitor` + `display-config` + `xwww` restart | `generated/outputs.kdl`, reload |

Properties of the contract:

- **Every niri write is atomic** (temp file + `mv`) and lands under
  `~/.config/niri/generated/`.
- **Every niri write is followed by `niri msg action load-config-file`.**
  niri also watches included files, so a save alone would reload; the explicit
  call is deterministic.
- **Generated KDL fragments are deep-merged** where niri supports it (`layout`,
  `binds`), and are treated as the sole owner of the sections that appear a
  single time (`input`, `animations`, `blur`, `layout`) and of the output names
  they declare (`output` blocks are repeatable, but each output name is
  unique). The niri base config must include the fragments and must not redefine
  the same single-occurrence sections or output names. See
  [docs/overlay.md](docs/overlay.md).
- **No live-preview regression for the user:** Hyprland keeps its per-frame
  `hyprctl eval` preview; niri collapses preview to a state update and applies
  once on persist, because niri has no arbitrary runtime option patch. niri
  reloads of `layout` do not restart clients, so the single write is smooth.

## 3. Feature mapping decisions

- **Borders** map to `layout { border { ... } }` with `focus-ring { off }` so
  there is a single active indicator, matching the Hyprland look. `borders.kdl`
  sets colours only; `theme-effects.kdl` owns `border width`.
- **Gaps**: the UI exposes `gaps_in` and `gaps_out`; niri has one `gaps` value
  plus `struts`. The generated KDL uses `gaps = gaps_in` and equal `struts =
  max(0, gaps_out - gaps_in)`.
- **Blur / shadow**: `blur_passes` maps to `blur { passes }`; `shadow_range` and
  the offset map to `layout { shadow }`. `blur_size` and
  `shadow_render_power` have no niri equivalent and stay in the JSON state.
- **Opacity / rounding**: `active_opacity` maps to a match-less `window-rule {
  opacity }`; `rounding` maps to `geometry-corner-radius`.
  `inactive_opacity` has no niri equivalent.
- **Monitors**: `bitdepth`, `cm` (colour management) and output mirroring have
  no niri 26.04 equivalent and are dropped from the niri materialisation while
  remaining in `settings.json`; VRR collapses from `0/1/2` to on/off with an
  optional `on-demand=true` for `2`.
- **Workspaces**: niri workspaces are dynamic, so `niri-workspaces.sh` derives
  rows `1..N` where `N = max(settings.json -> workspaceCount, highest live idx)`
  and prefers the focused output when an `idx` repeats. This keeps the fixed
  pill row the UI already renders.
- **Keyboard layout switching** is global in niri (`switch-layout next`); there
  is no per-device selector.

## 4. Hard UI rule

**In widgets and panels, avoid blank or empty spaces. Use compact,
content-fitting layouts.**

When porting or touching any panel or widget:

- size containers to their content, not to a guessed fixed box;
- keep gaps and padding minimal;
- do not add filler rows, spacers or empty regions to reach a target size;
- if a value is unsupported on a backend, hide the control rather than leaving
  an empty slot (for example, hide niri-unsupported monitor knobs instead of
  rendering disabled rows).

This rule is a hard requirement: 100% of the UI/UX is preserved, and the layout
must look intentional and dense on both compositors. No widget may gain blank
space as a side effect of the port.

## 5. What is not in scope

The compositor config itself (`~/.config/niri/config.kdl` and its modules) lives
in the sibling `niri` repository. This overlay only produces the generated
fragments and documents the include contract. Idle, lock, portal and capture
tooling are covered by their own overlays.
