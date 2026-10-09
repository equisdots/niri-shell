pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: config

    Caching { id: paths }

    // =========================================================================
    // Core Paths & Environment
    // =========================================================================
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string hyprDir: homeDir + "/.config/hypr"
    readonly property string qsScriptsDir: hyprDir + "/scripts/quickshell"
    readonly property string cacheDir: paths.cacheDir

    readonly property string settingsJsonPath: hyprDir + "/settings.json"

    // State Tracking
    property bool dataReady: false
    property var rawSettings: ({})

    // =========================================================================
    // Generic Utilities (Use these in ANY widget!)
    // =========================================================================

    // Execute a background bash command easily
    function sh(cmd) {
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    // --- JSON Operations ---
    function getSetting(key, fallbackValue) {
        return rawSettings.hasOwnProperty(key) ? rawSettings[key] : fallbackValue;
    }

    // Uses a unique temp file per call (mktemp) so concurrent saves never
    // overwrite each other's temp file, preventing JSON corruption.
    // Bumped on every settings mutation: bindings that must react to
    // in-place rawSettings changes depend on this counter.
    property int rev: 0

    function setSetting(key, value) {
        rev++;
        rawSettings[key] = value;
        let safeValue = typeof value === "string" ? `"${value}"` : value;
        if (typeof value === "object") safeValue = JSON.stringify(value).replace(/'/g, "'\\''");

        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -f '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `tmp=$(mktemp '${settingsJsonPath}'.tmp.XXXXXX) && ` +
                  `jq '. + {"${key}": ${safeValue}}' '${settingsJsonPath}' > "$tmp" && ` +
                  `mv "$tmp" '${settingsJsonPath}'`;
        sh(cmd);
    }

    function updateJsonBulk(dataObj) {
        let jsonStr = JSON.stringify(dataObj).replace(/'/g, "'\\''");
        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -f '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `tmp=$(mktemp '${settingsJsonPath}'.tmp.XXXXXX) && ` +
                  `jq '. + ${jsonStr}' '${settingsJsonPath}' > "$tmp" && ` +
                  `mv "$tmp" '${settingsJsonPath}'`;
        sh(cmd);

        for (let key in dataObj) rawSettings[key] = dataObj[key];
    }

    // =========================================================================
    // General scalars (bound to the General tab)
    // =========================================================================
    property real uiScale: 1.0
    property real appScale: 1.0
    // ── Persist General-tab scalars when they change ───────────────────
    // The tab edits these properties directly; without this hook the values
    // only lived in memory (UI Scale / Workspaces / App scale did nothing).
    // Debounced and gated on dataReady so the initial load never re-saves.
    Timer {
        id: scalarSave
        interval: 300
        onTriggered: if (dataReady) saveAppSettings()
    }
    onUiScaleChanged: scalarSave.restart()
    onWorkspaceCountChanged: scalarSave.restart()
    onAppScaleChanged: scalarSave.restart()

    property int workspaceCount: 8
    property int initialWorkspaceCount: 8
    property string wallpaperDir: {
        const saved = getSetting("wallpaperDir", "");
        return saved !== "" ? saved : (Quickshell.env("WALLPAPER_DIR") || homeDir + "/.config/hypr/wallpapers");
    }
    property string language: ""
    property string kbOptions: "grp:alt_shift_toggle"

    property var keybindsData: []
    signal keybindsLoaded()

    property var startupData: []
    signal startupLoaded()

    // =========================================================================
    // Settings Save Functions
    // =========================================================================
    function saveAppSettings() {
        let configObj = {
            "uiScale": config.uiScale,
            "appScale": config.appScale,
            "wallpaperDir": config.wallpaperDir,
            "language": config.language,
            "kbOptions": config.kbOptions,
            "workspaceCount": config.workspaceCount
        };

        config.updateJsonBulk(configObj);
        sh("notify-send 'Quickshell' 'Settings Applied Successfully!'");

        if (config.workspaceCount !== config.initialWorkspaceCount) {
            sh(`qs -p "${qsScriptsDir}/Shell.qml" ipc call topbar queueReload`);
            config.initialWorkspaceCount = config.workspaceCount;
        }
    }

    // Keybind persistence is compositor-neutral: the active backend emits Lua
    // (Hyprland, config/user-keybinds.lua + `hyprctl reload`) or KDL (niri,
    // generated/user-binds.kdl + `niri msg action load-config-file`).
    function saveAllKeybinds(bindsArray) {
        config.keybindsData = bindsArray;
        config.setSetting("keybinds", bindsArray);
        Compositor.persistKeybinds(bindsArray);
        sh("notify-send 'Quickshell' 'Keybinds Saved Successfully!'");
    }

    function saveAllStartup(startupArray) {
        config.startupData = startupArray;
        config.setSetting("startup", startupArray);
        Compositor.persistStartup(startupArray);
        sh("notify-send 'Quickshell' 'Startup entries saved!'");
    }

    // =========================================================================
    // Monitor Management
    // =========================================================================
    property alias monitorsModel: _monitorsModel
    ListModel { id: _monitorsModel }
    property int monActiveEditIndex: 0
    property real monUiScale: 0.10
    property int monOriginalOriginX: 0
    property int monOriginalOriginY: 0

    function monIsOverlapping(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function monIsOverlappingAny(x, y, w, h, skipIdx) {
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === skipIdx) continue;
            let m = monitorsModel.get(i);
            let isP = m.transform === 1 || m.transform === 3;
            let mW = ((isP ? m.resH : m.resW) / m.sysScale) * config.monUiScale;
            let mH = ((isP ? m.resW : m.resH) / m.sysScale) * config.monUiScale;
            if (config.monIsOverlapping(x, y, w, h, m.uiX, m.uiY, mW, mH)) return true;
        }
        return false;
    }

    function monGetPerimeterSnap(pX, pY, sX, sY, sW, sH, mW, mH, snapT) {
        let edges = [
            { x1: sX - mW, x2: sX + sW, y1: sY - mH, y2: sY - mH },
            { x1: sX - mW, x2: sX + sW, y1: sY + sH, y2: sY + sH },
            { x1: sX - mW, x2: sX - mW, y1: sY - mH, y2: sY + sH },
            { x1: sX + sW, x2: sX + sW, y1: sY - mH, y2: sY + sH }
        ];
        let bestX = pX, bestY = pY, minDist = 999999;
        for (let i = 0; i < 4; i++) {
            let e = edges[i];
            let cx = Math.max(e.x1, Math.min(pX, e.x2));
            let cy = Math.max(e.y1, Math.min(pY, e.y2));
            if (Math.abs(cx - sX) < snapT) cx = sX;
            if (Math.abs(cx - (sX + sW - mW)) < snapT) cx = sX + sW - mW;
            if (Math.abs(cx - (sX + sW/2 - mW/2)) < snapT) cx = sX + sW/2 - mW/2;
            if (Math.abs(cy - sY) < snapT) cy = sY;
            if (Math.abs(cy - (sY + sH - mH)) < snapT) cy = sY + sH - mH;
            if (Math.abs(cy - (sY + sH/2 - mH/2)) < snapT) cy = sY + sH/2 - mH/2;
            let dist = Math.hypot(pX - cx, pY - cy);
            if (dist < minDist) { minDist = dist; bestX = cx; bestY = cy; }
        }
        return { x: bestX, y: bestY };
    }

    function monForceLayoutUpdate() {
        if (monitorsModel.count < 2) return;
        let mIdx = config.monActiveEditIndex;
        let mModel = monitorsModel.get(mIdx);
        let isP = mModel.transform === 1 || mModel.transform === 3;
        let mW = ((isP ? mModel.resH : mModel.resW) / mModel.sysScale) * config.monUiScale;
        let mH = ((isP ? mModel.resW : mModel.resH) / mModel.sysScale) * config.monUiScale;
        let bestX = mModel.uiX, bestY = mModel.uiY, bestDist = 999999;
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === mIdx) continue;
            let sModel = monitorsModel.get(i);
            let sIsP = sModel.transform === 1 || sModel.transform === 3;
            let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * config.monUiScale;
            let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * config.monUiScale;
            let snapped = config.monGetPerimeterSnap(mModel.uiX, mModel.uiY, sModel.uiX, sModel.uiY, sW, sH, mW, mH, 20);
            let dist = Math.hypot(snapped.x - mModel.uiX, snapped.y - mModel.uiY);
            if (dist < bestDist) { bestDist = dist; bestX = snapped.x; bestY = snapped.y; }
        }
        monitorsModel.setProperty(mIdx, "uiX", bestX);
        monitorsModel.setProperty(mIdx, "uiY", bestY);
    }

    // ── Exact mode resolution ─────────────────────────────────────────────
    // Hyprland only applies a mode that matches availableModes exactly
    // ("1920x1080@144.06Hz"); an integer rate does not apply and resets to the
    // preferred mode. Resolve the real string here (same for niri, whose modes
    // are normalised to the same "WxH@RHz" shape by the backend decoder).
    function monResolveMode(monitor, resW, resH, rate) {
        let modes = [];
        try { modes = JSON.parse(monitor.availableModes || "[]"); } catch (e) { modes = []; }
        let parsed = [];
        for (let i = 0; i < modes.length; i++) {
            let mm = String(modes[i]).match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
            if (!mm) continue;
            parsed.push({ s: modes[i], w: parseInt(mm[1]), h: parseInt(mm[2]), r: parseFloat(mm[3]) });
        }
        if (parsed.length === 0) return "highrr";
        let w = Math.round(resW), h = Math.round(resH);
        let target = parseFloat(rate);
        if (isNaN(target)) target = 60;
        // 1) same resolution -> closest rate
        let best = null;
        for (let i = 0; i < parsed.length; i++) {
            let pm = parsed[i];
            if (pm.w !== w || pm.h !== h) continue;
            let d = Math.abs(pm.r - target);
            if (!best || d < best.d) best = { d: d, s: pm.s };
        }
        if (best) return best.s;
        // 2) no resolution match -> closest resolution (closest rate within it)
        let best2 = null;
        for (let i = 0; i < parsed.length; i++) {
            let pm = parsed[i];
            let d = (Math.abs(pm.w - w) + Math.abs(pm.h - h)) * 1000 + Math.abs(pm.r - target);
            if (!best2 || d < best2.d) best2 = { d: d, s: pm.s };
        }
        return best2 ? best2.s : "highrr";
    }

    function monFindByName(name) {
        for (let i = 0; i < monitorsModel.count; i++) {
            let m = monitorsModel.get(i);
            if (m.name === name) return m;
        }
        return null;
    }

    // Neutral descriptor handed to the active backend. The backend turns it
    // into `hl.monitor({...})` (Hyprland) or an `output "..." {...}` KDL block
    // (niri).
    function monitorDescriptor(m, posX, posY) {
        let mirrorDesc = "";
        if (m.mirrorOf && m.mirrorOf !== "" && m.mirrorOf !== "none") {
            let mm = config.monFindByName(m.mirrorOf);
            mirrorDesc = mm ? ((mm.description && mm.description !== "") ? mm.description : mm.name) : "";
        }
        return {
            name: m.name,
            description: m.description || "",
            mode: config.monResolveMode(m, m.resW, m.resH, m.rate),
            x: posX,
            y: posY,
            scale: m.sysScale,
            transform: m.transform,
            vrr: (m.vrr === 2) ? 2 : (m.vrr ? 1 : 0),
            bitdepth: (m.bitdepth === 10) ? 10 : 8,
            cm: (m.cm && m.cm !== "") ? m.cm : "auto",
            mirrorDesc: mirrorDesc,
            disabled: m.disabled === true
        };
    }

    // Text of display-config for the given layout. `entries` = array of
    // { m, x, y } (m = monitorsModel item with its FINAL px position).
    // Format: desc|x|y|scale|mode|transform|vrr|bitdepth|cm|mirror|disabled
    // (extra fields are backwards tolerant: old readers use 1-5).
    function monDisplayConfigText(entries) {
        let lines = [];
        lines.push("# Monitor layout: desc|x|y|scale|mode|transform|vrr|bitdepth|cm|mirror|disabled");
        lines.push("#   desc = hyprctl description (EDID model+serial, survives connector renames)");
        lines.push("#   x,y  = logical position | scale = fractional scale");
        lines.push("#   mode = exact Hyprland mode, e.g. 1920x1080@144.11Hz (empty = highest RR)");
        lines.push("#   extra: transform | vrr(0/1/2) | bitdepth(8/10) | cm | mirror(desc) | disabled(0/1)");
        for (let i = 0; i < entries.length; i++) {
            let e = entries[i];
            let m = e.m;
            let desc = (m.description && m.description !== "") ? m.description : m.name;
            let mode = config.monResolveMode(m, m.resW, m.resH, m.rate);
            let mirrorDesc = "";
            if (m.mirrorOf && m.mirrorOf !== "" && m.mirrorOf !== "none") {
                let mm = config.monFindByName(m.mirrorOf);
                mirrorDesc = mm ? ((mm.description && mm.description !== "") ? mm.description : mm.name) : "";
            }
            let vrr = (m.vrr === 2) ? 2 : (m.vrr ? 1 : 0);
            let bitdepth = (m.bitdepth === 10) ? 10 : 8;
            let cm = (m.cm && m.cm !== "") ? m.cm : "auto";
            let disabled = (m.disabled === true) ? 1 : 0;
            lines.push([desc, Math.round(e.x), Math.round(e.y), m.sysScale, mode,
                        m.transform || 0, vrr, bitdepth, cm, mirrorDesc, disabled].join("|"));
        }
        return lines.join("\n") + "\n";
    }

    function applyMonitors() {
        if (monitorsModel.count === 0) return;
        let descriptors = [];
        let entries = [];
        let summaryString = "";
        let jsonArr = [];
        if (monitorsModel.count === 1) {
            let m = monitorsModel.get(0);
            descriptors.push(config.monitorDescriptor(m, 0, 0));
            entries.push({ m: m, x: 0, y: 0 });
            jsonArr.push({ name: m.name, resW: m.resW, resH: m.resH, rate: parseInt(m.rate), x: 0, y: 0, scale: m.sysScale, transform: m.transform, vrr: m.vrr, disabled: m.disabled === true, mirrorOf: m.mirrorOf, cm: m.cm, bitdepth: m.bitdepth });
            summaryString = m.name + " " + m.resW + "x" + m.resH + " @ " + m.rate + "Hz";
        } else {
            let rects = [];
            for (let i = 0; i < monitorsModel.count; i++) {
                let m = monitorsModel.get(i);
                let isP = m.transform === 1 || m.transform === 3;
                let physW = Math.round((isP ? m.resH : m.resW) / m.sysScale);
                let physH = Math.round((isP ? m.resW : m.resH) / m.sysScale);
                rects.push({ idx: i, x: m.uiX / config.monUiScale, y: m.uiY / config.monUiScale, w: physW, h: physH, name: m.name });
            }
            function getTightSnap(pX, pY, sX, sY, sW, sH, mW, mH, t) {
                let cx = pX; let cy = pY;
                if (Math.abs(cx - (sX - mW)) < t) cx = sX - mW;
                else if (Math.abs(cx - (sX + sW)) < t) cx = sX + sW;
                else if (Math.abs(cx - sX) < t) cx = sX;
                else if (Math.abs(cx - (sX + sW - mW)) < t) cx = sX + sW - mW;
                if (Math.abs(cy - (sY - mH)) < t) cy = sY - mH;
                else if (Math.abs(cy - (sY + sH)) < t) cy = sY + sH;
                else if (Math.abs(cy - sY) < t) cy = sY;
                else if (Math.abs(cy - (sY + sH - mH)) < t) cy = sY + sH - mH;
                return {x: cx, y: cy};
            }
            for (let i = 1; i < rects.length; i++) {
                let bestX = rects[i].x, bestY = rects[i].y, bestDist = 999999;
                for (let j = 0; j < i; j++) {
                    let r0 = rects[j];
                    let snapped = getTightSnap(rects[i].x, rects[i].y, r0.x, r0.y, r0.w, r0.h, rects[i].w, rects[i].h, 25);
                    let dist = Math.hypot(rects[i].x - snapped.x, rects[i].y - snapped.y);
                    if (dist < bestDist) { bestDist = dist; bestX = Math.round(snapped.x); bestY = Math.round(snapped.y); }
                }
                rects[i].x = bestX; rects[i].y = bestY;
            }
            let finalMinX = 999999, finalMinY = 999999;
            for (let i = 0; i < rects.length; i++) {
                if (rects[i].x < finalMinX) finalMinX = rects[i].x;
                if (rects[i].y < finalMinY) finalMinY = rects[i].y;
            }
            for (let i = 0; i < rects.length; i++) {
                let r = rects[i];
                r.x = Math.round(r.x - finalMinX);
                r.y = Math.round(r.y - finalMinY);
                let m = monitorsModel.get(r.idx);
                descriptors.push(config.monitorDescriptor(m, r.x, r.y));
                entries.push({ m: m, x: r.x, y: r.y });
                summaryString += r.name + " ";
                jsonArr.push({ name: m.name, resW: m.resW, resH: m.resH, rate: parseInt(m.rate), x: r.x, y: r.y, scale: m.sysScale, transform: m.transform, vrr: m.vrr, disabled: m.disabled === true, mirrorOf: m.mirrorOf, cm: m.cm, bitdepth: m.bitdepth });
            }
        }
        config.setSetting("monitors", jsonArr);
        // display-config DETERMINISTIC from the applied layout: the live state
        // is not re-read (avoids the race with restore-monitors.sh while
        // multi-monitor modesets settle). The Hyprland backend writes it
        // atomically + a .bak; the niri backend ignores it and writes KDL.
        let text = config.monDisplayConfigText(entries);
        Compositor.applyMonitors(descriptors, text);
        Quickshell.execDetached(["notify-send", "Display Update",
            monitorsModel.count === 1 ? ("Applied: " + summaryString)
                                      : ("Applied layout for: " + summaryString.trim())]);
    }

    // Sends all monitors back to auto-arrangement. The active backend removes
    // its persisted layout (display-config under Hyprland, generated/outputs.kdl
    // under niri) and reloads.
    function resetMonitorsToAuto() {
        Compositor.resetMonitors();
        Quickshell.execDetached(["notify-send", "Display Layout", "Saved layout deleted - monitors now auto-arrange"]);
    }

    property alias monDelayedLayoutUpdate: _monDelayedLayoutUpdate
    Timer {
        id: _monDelayedLayoutUpdate
        interval: 10; running: false; repeat: false
        onTriggered: config.monForceLayoutUpdate()
    }

    // The poller lives in the active backend (hyprctl monitors -j under
    // Hyprland, niri msg --json outputs under niri). It emits normalised
    // monitor entries that are applied to the model below.
    property var displayPoller: Compositor.displayPoller

    Connections {
        target: Compositor.backend
        function onMonitorsDecoded(data) {
            try {
                // vrr live is bool, but the panel needs 0/1/2 (2 =
                // fullscreen-only). With 2 the live value is false outside
                // fullscreen: keep the previous 2 for the same monitor.
                let prevVrr = {};
                for (let i = 0; i < config.monitorsModel.count; i++) {
                    let pm = config.monitorsModel.get(i);
                    prevVrr[pm.name] = pm.vrr;
                }
                config.monitorsModel.clear();
                let minX = 999999, minY = 999999;
                for (let i = 0; i < data.length; i++) {
                    if (data[i].x < minX) minX = data[i].x;
                    if (data[i].y < minY) minY = data[i].y;
                }
                config.monOriginalOriginX = minX !== 999999 ? minX : 0;
                config.monOriginalOriginY = minY !== 999999 ? minY : 0;
                for (let i = 0; i < data.length; i++) {
                    let scl = data[i].scale !== undefined ? data[i].scale : 1.0;
                    let tf = data[i].transform !== undefined ? data[i].transform : 0;
                    let normalizedX = (data[i].x - minX) * config.monUiScale;
                    let normalizedY = (data[i].y - minY) * config.monUiScale;
                    let prev = prevVrr[data[i].name];
                    let liveVrr = data[i].vrr === true;
                    let vrrVal = liveVrr ? (prev === 2 ? 2 : 1) : (prev === 2 ? 2 : 0);
                    config.monitorsModel.append({
                        name: data[i].name, resW: data[i].width, resH: data[i].height,
                        sysScale: scl, rate: Math.round(data[i].refreshRate).toString(),
                        uiX: normalizedX, uiY: normalizedY, transform: tf,
                        availableModes: JSON.stringify(data[i].availableModes || []),
                        description: data[i].description || "",
                        vrr: vrrVal,
                        disabled: data[i].disabled === true,
                        mirrorOf: data[i].mirrorOf || "none",
                        cm: data[i].colorManagementPreset || data[i].cm || "auto",
                        bitdepth: (String(data[i].currentFormat || "").indexOf("2101010") !== -1) ? 10 : (data[i].bitdepth === 10 ? 10 : 8),
                        sdrBrightness: data[i].sdrBrightness !== undefined ? data[i].sdrBrightness : 1,
                        sdrSaturation: data[i].sdrSaturation !== undefined ? data[i].sdrSaturation : 1
                    });
                    if (data[i].focused) config.monActiveEditIndex = i;
                }
                config.monForceLayoutUpdate();
            } catch(e) {}
        }
    }

    // =========================================================================
    // Boot Initialization (Runs once on start)
    // =========================================================================
    Component.onCompleted: {
        settingsReader.running = true;
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", `cat "${config.settingsJsonPath}" 2>/dev/null || echo '{}'`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        config.rawSettings = JSON.parse(this.text);

                        // Map explicitly defined properties
                        if (config.rawSettings.uiScale !== undefined) config.uiScale = config.rawSettings.uiScale;
                        if (config.rawSettings.appScale !== undefined) config.appScale = config.rawSettings.appScale;
                        if (config.rawSettings.wallpaperDir !== undefined) config.wallpaperDir = config.rawSettings.wallpaperDir;
                        if (config.rawSettings.language !== undefined && config.rawSettings.language !== "") config.language = config.rawSettings.language;
                        if (config.rawSettings.kbOptions !== undefined) config.kbOptions = config.rawSettings.kbOptions;
                        if (config.rawSettings.workspaceCount !== undefined) {
                            config.workspaceCount = config.rawSettings.workspaceCount;
                            config.initialWorkspaceCount = config.rawSettings.workspaceCount;
                        }

                        // Map Keybinds
                        if (config.rawSettings.keybinds !== undefined && Array.isArray(config.rawSettings.keybinds)) {
                            let tempBinds = [];
                            for (let k of config.rawSettings.keybinds) {
                                tempBinds.push({
                                    type: k.type || "bind",
                                    mods: k.mods || "",
                                    key: k.key || "",
                                    dispatcher: k.dispatcher || "exec",
                                    command: k.command || "",
                                    isEditing: false
                                });
                            }
                            config.keybindsData = tempBinds;
                        } else {
                            config.keybindsData = [];
                        }

                        // Map Startups
                        if (config.rawSettings.startup !== undefined && Array.isArray(config.rawSettings.startup)) {
                            let tempStartup = [];
                            for (let s of config.rawSettings.startup) {
                                tempStartup.push({ command: s.command || "" });
                            }
                            config.startupData = tempStartup;
                        } else {
                            config.startupData = [];
                        }
                    } else {
                        config.saveAppSettings();
                        config.keybindsData = [];
                        config.saveAllKeybinds([]);
                        config.startupData = [];
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                    // Overwrite the corrupted file with a fresh empty object so
                    // the bar can start and jq saves will work going forward.
                    config.sh("echo '{}' > '" + config.settingsJsonPath + "'");
                    config.rawSettings = {};
                    config.keybindsData = [];
                    config.startupData = [];
                }
                config.keybindsLoaded();
                config.startupLoaded();
                config.dataReady = true;
            }
        }
    }
}
