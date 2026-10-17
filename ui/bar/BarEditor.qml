import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../core"
import "../../core/EditorNav.js" as EditorNav
import "../../core/WindowRegistry.js" as LayoutMath
import "BarLayout.js" as BarLayout
import "Colors.qml"
import "edit"
// Phase 3: pages load lazily via Loader.setSource("editor/<file>.qml", {bar})
// — no `import "editor"` needed (typed instancing caused a null-bar burst).

// ═══════════════════════════════════════════════════════════════════════════
// BarEditor — the bar mega menu (SUPER+SHIFT+D), visiblemente "Settings".
//
// Fase B: el rail agrupa dos familias de páginas:
//   · "Desktop"  → las 6 tabs compartidas settings/tabs/*.qml (host =
//                  settingsHost, el adaptador que replica la API del popup).
//   · "Bar / Bar" → las 7 páginas del editor bar/editor/*.qml (bar = root),
//                  expandible, subtabs indentados con línea de rail.
// Los Loaders son lazy (ensurePage/setSource con initial properties) y las
// páginas del editor exponen flickable + zonasCol para el DnD
// (chips en coordenadas del root vía mapToItem(bar,...)). Edits en vivo a
// settings.json; la barra viva no se toca.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var notifModel: null
    property var liveNotifs: null
    property int layoutWidth: 0
    property int layoutHeight: 0
    implicitWidth: layoutWidth > 0 ? layoutWidth : s(900)
    implicitHeight: layoutHeight > 0 ? layoutHeight : s(700)

    property real uiScale: 1.0
    readonly property real baseScale: LayoutMath.getScale(Screen.width, Screen.height, root.uiScale)
    function s(val) { return LayoutMath.s(val, baseScale); }

    Colors { id: themeColors }
    readonly property var colors: themeColors

    property var bar: BarLayout.defaultBar()
    property var palettes: ([])
    // Palette list helpers: entries carry `category` ("x" built-in, "custom"
    // community/terminal packs, "user" created here); missing = "x".
    function palettesOf(category, query) {
        let q = String(query || "").trim().toLowerCase();
        let out = [];
        for (let i = 0; i < root.palettes.length; i++) {
            let p = root.palettes[i];
            if (!p || String(p.category || "x") !== category) continue;
            if (q !== "" && String(p.name).toLowerCase().indexOf(q) === -1
                && String(p.slug).toLowerCase().indexOf(q) === -1) continue;
            out.push(p);
        }
        return out;
    }
    property bool _dirty: false
    // true solo tras cargar el estado real desde settings.json (dataReady):
    // impide persistir el bar por defecto si el panel se abre durante el
    // arranque/reload del shell (ver reload()).
    property bool _barReady: false
    property bool borderTargetActive: true

    // ════ FASE 4: INTRO/CIERRE (paridad con GuidePopup) ════
    // introBase = panel (opacity+scale), introSidebar = rail (opacity+slide x),
    // introContent = stage de páginas (opacity+scale+slide y). GP:214-287.
    property real introBase: 0.0
    property real introSidebar: 0.0
    property real introContent: 0.0

    // ════ BUSCADOR GLOBAL (overlay estilo Guide) ════
    // Migrado de settings/SettingsPopup.qml: `/` (o Ctrl+F) abre el overlay,
    // que cubre la stage con búsqueda de settings (cards + páginas d_*) y
    // keybinds. El overlay se carga lazy con setSource (patrón Fase 3, evita
    // el burst de null-bar de instanciarlo tipado).
    property bool searchOpen: false
    function ensureSearchOverlay() {
        if (!searchLoader.item)
            searchLoader.setSource("editor/SearchOverlay.qml", { bar: root });
    }
    function openSearch() {
        root.ensureSearchOverlay();
        root.searchOpen = true;
        if (searchLoader.item) searchLoader.item.open();
    }
    function closeSearch() {
        if (searchLoader.item) searchLoader.item.close();
    }
    // El overlay resalta una caja de una tab de settings a través del adapter
    // (settingsHost es un id local; los ficheros externos no pueden verlo).
    function highlightSettingsBox(boxIndex) {
        settingsHost.highlightedBox = boxIndex;
    }

    // ════ ACTIVE MODE (qs_manager.sh toggle bar-editor <mode>) ════
    // Mismo contrato que SettingsPopup.activeMode: Main.qml escribe esta
    // propiedad al abrir/togglear la ventana con argumento. Los modos de
    // settings abren su tab (s_*) y los del editor su página (d_*); si el
    // valor ya es un page id válido, se abre esa página.
    property string activeMode: ""
    property string activeModePage: ""
    onActiveModeChanged: root.applyActiveMode()
    function applyActiveMode() {
        if (root.activeMode === "") return;
        let map = {
            "general": "s_general", "keyboard": "s_keyboard",
            "monitors": "s_monitors", "startup": "s_startup", "topbar": "d_general",
            "bar": "d_general", "engine": "d_general", "launcher": "d_launcher",
            "hyprland": "d_hyprland", "idle": "d_idle", "gpu": "d_gpu",
            "notifications": "d_notifications", "guide": "d_guide", "about": "d_guide",
            "shadows": "d_shadows", "glass": "d_glass", "palette": "d_palette",
            "plugins": "d_plugins"
        };
        let page = map[root.activeMode] !== undefined ? map[root.activeMode] : root.activeMode;
        if (root.navIndex(page) === -1) {
            // Installed plugins are addressed by id: "<id>" -> "p_<id>".
            let pid = String(root.activeMode);
            let plist = PluginsCatalog.plugins || [];
            for (let i = 0; i < plist.length; i++) {
                let p = plist[i] || {};
                if (p.id === pid && p.settings && p.settings.page) { page = "p_" + pid; break; }
            }
        }
        if (root.navIndex(page) === -1) return;
        // Timer (220 ms, como el popup): la ventana acaba de abrirse y la
        // intro anima; el layout debe estar resuelto antes de navegar.
        root.activeModePage = page;
        activeModeTimer.restart();
    }
    Timer {
        id: activeModeTimer
        interval: 220
        onTriggered: if (root.activeModePage !== "") root.gotoPage(root.activeModePage);
    }

    Timer { id: saveTimer; interval: 220; onTriggered: flushSave() }
    function markDirty() { _dirty = true; saveTimer.restart(); }
    // Un único updateJsonBulk (un jq + un mv) en vez de dos setSetting
    // separados: dos procesos jq concurrentes sobre el mismo archivo se pisan
    // (read-modify-write) y podían perder la clave recién escrita.
    // Y nunca se guarda antes de haber cargado (dataReady): un panel abierto
    // durante el arranque no puede persistir el bar por defecto.
    function flushSave() {
        let patch = {};
        if (_dirty && root._barReady) { _dirty = false; patch.bar = root.bar; }
        if (Object.keys(patch).length > 0) Config.updateJsonBulk(patch);
    }
    function applyBar(bar) { root.bar = bar; root.markDirty(); }
    // El panel puede crearse antes de que Config acabe de leer settings.json
    // (p. ej. justo tras un reload del shell). reload() se pospone hasta
    // dataReady: si no, getBar({}) devolvía el bar por defecto y el primer
    // guardado (cambiar de paleta) lo persistía — el bar "volvía a su
    // posición inicial".
    function reload() {
        if (!Config.dataReady) return;
        root.bar = BarLayout.getBar(Config.rawSettings);
        root._barReady = true;
    }
    Connections {
        target: Config
        function onDataReadyChanged() {
            if (Config.dataReady) {
                root.reload();
                // Scale is known as soon as Config parses settings.json:
                // syncing it here too covers the cold start (editor opened
                // before the initial read finishes).
                root.uiScale = Config.uiScale;
            }
        }
    }

    // ════ LAUNCHER (applauncher, SUPER+D) ════
    // Config del launcher en la key "launcher" de settings.json. El merge con
    // los defaults vive aquí (merge simple); la normalización/clamps la hace
    // el propio launcher con LauncherLayout.normalize al abrirse.
    // NOTA: Config.setSetting muta rawSettings en memoria SIN reasignar la
    // propiedad, por lo que los bindings que leen Config.rawSettings no se
    // re-evalúan; este property local sí notifica y mantiene la UI en vivo.
    property var launcherCfg: (function() {
        let d = { position: "center", width: 800, maxApps: 8, margin: 24, avoidBar: true, showIcons: true, rowHeight: 60, align: "left", radius: 21, borderWidth: 1, borderColor: "surface1" };
        let raw = Config.rawSettings.launcher;
        return (raw && typeof raw === "object") ? Object.assign({}, d, raw) : d;
    })()
    function launcherConfig() { return root.launcherCfg; }
    function applyLauncher(partial) {
        root.launcherCfg = Object.assign({}, root.launcherCfg, partial);
        Config.setSetting("launcher", root.launcherCfg);
    }

    // ════ ANIMATIONS / INPUT (grupo System) ════
    // Overrides generados: el panel escribe config/user-animations.lua y
    // config/user-input.lua vía persist-hypr.sh (luac -p + reload). Mismo
    // patrón que launcherCfg: property local con merge de Config.rawSettings
    // para que la UI viva no dependa de rawSettings (setSetting no reasigna).
    property var animationsCfg: (function() {
        let d = { enabled: true, speed: 1.0 };
        let raw = Config.rawSettings.animations;
        return (raw && typeof raw === "object") ? Object.assign({}, d, raw) : d;
    })()
    property var inputCfg: (function() {
        let d = { sensitivity: 0, accelProfile: "flat", tapToClick: true, naturalScroll: true, disableWhileTyping: true };
        let raw = Config.rawSettings.input;
        return (raw && typeof raw === "object") ? Object.assign({}, d, raw) : d;
    })()
    function animationsConfig() { return root.animationsCfg; }
    function applyAnimations(partial) {
        root.animationsCfg = Object.assign({}, root.animationsCfg, partial);
        Config.setSetting("animations", root.animationsCfg);
        root._animDirty = true;
        hyprPersistTimer.restart();
    }
    function inputConfig() { return root.inputCfg; }
    function applyInput(partial) {
        root.inputCfg = Object.assign({}, root.inputCfg, partial);
        Config.setSetting("input", root.inputCfg);
        root._inputDirty = true;
        hyprPersistTimer.restart();
    }
    // Semilla de InputPage: solo si settings.json no tiene key "input" y solo
    // una vez por sesión del panel. NO persiste: rellena la UI con los valores
    // vivos de hyprctl hasta que el usuario cambie algo.
    property bool _inputSeeded: false
    function needsInputSeed() {
        return !root._inputSeeded && Config.rawSettings.input === undefined;
    }
    function seedInputCfg(obj) {
        if (!root.needsInputSeed()) return;
        root._inputSeeded = true;
        root.inputCfg = Object.assign({}, root.inputCfg, obj);
    }
    // Debounce 600 ms (igual que HyprlandPage): una ráfaga de cambios produce
    // una sola llamada por modo. persist-hypr.sh valida con luac -p y recarga.
    property bool _animDirty: false
    property bool _inputDirty: false
    Timer {
        id: hyprPersistTimer
        interval: 600
        onTriggered: root.persistHypr()
    }
    function persistHypr() {
        if (root._animDirty) {
            root._animDirty = false;
            Quickshell.execDetached(["bash",
                Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/ui/bar/editor/persist-hypr.sh",
                "animations",
                root.animationsCfg.enabled ? "1" : "0",
                Number(root.animationsCfg.speed).toFixed(1)
            ]);
        }
        if (root._inputDirty) {
            root._inputDirty = false;
            Quickshell.execDetached(["bash",
                Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/ui/bar/editor/persist-hypr.sh",
                "input",
                String(root.inputCfg.sensitivity),
                String(root.inputCfg.accelProfile),
                root.inputCfg.tapToClick ? "1" : "0",
                root.inputCfg.naturalScroll ? "1" : "0",
                root.inputCfg.disableWhileTyping ? "1" : "0"
            ]);
        }
    }

    // ════ BAR STYLE PRESETS (Phase D3) ════
    function applyStyle(preset) {
        root.applyBar(BarLayout.applyStylePreset(root.bar, preset));
    }

    // ════ MODULE CHIP DRAG & DROP (Phase D3, adapted Phase 2) ════
    // One editor-wide session: a chip MouseArea crosses its threshold and
    // calls startDnd(); we own the gesture — ghost at pointer,
    // dndActive + dndInsertIndex on the card under the cursor, auto-scroll of
    // the ACTIVE page's flickable, commit with BarLayout.moduleMoveTo on
    // release (drop outside every card = cancel). root.bar stays untouched
    // until the drop, so no-op drops never write settings.
    //
    // Phase 2: cards now live in the ZonesPage Flickable. The chips'
    // coordinate contract is unchanged — cards map
    // with mapToItem(bar,...)/mapFromItem(bar,...), points stay in root
    // coordinates and nested scrolls cancel out; only the auto-scroll target
    // becomes dynamic (dndFlick = the current page's flickable).
    property bool dndBusy: false
    property string dndModuleId: ""
    property string dndSourceZoneId: ""
    property point dndPointer: Qt.point(-10000, -10000)

    // Phase 2: page Flickable locked while a drag runs + auto-scrolled
    // (ZonesPage exposes its flickable).
    property var dndFlick: null

    // Phase 3: lazily-loaded page items (Loader.setSource initial props give
    // `bar` to the page BEFORE its inner bindings evaluate). Null until the
    // page has been opened once; DnD targets only exist while loaded, which is
    // exactly when their page is the visible one.
    property var zonesPage: null   // ZonesPage item (lazy; zone DnD targets)

    // Zone cards: children of the Zones page's zonasCol (isZoneEditorCard
    // marker skips the Repeater). Hidden pages keep valid geometry, so the
    // currentPage guard excludes them.
    function zoneCards() {
        if (root.currentPage !== "d_zones") return [];
        let out = [];
        let kids = root.zonesPage ? root.zonesPage.zonasCol.children : [];
        for (let i = 0; i < kids.length; i++) {
            let c = kids[i];
            if (c && c.isZoneEditorCard) out.push(c);
        }
        return out;
    }

    function dndTargets() {
        return root.zoneCards();
    }

    function startDnd(zoneId, moduleId) {
        if (root.dndBusy) return;
        root.dndBusy = true;
        root.dndModuleId = moduleId;
        root.dndSourceZoneId = zoneId;
        root.dndFlick = root.zonesPage ? root.zonesPage.flickable : null;
        if (root.dndFlick) root.dndFlick.interactive = false;
    }

    // Pointer moved (root/editor coordinates): repaint ghost + drop feedback
    // (dndActive / dndInsertIndex on the card under the cursor).
    function updateDnd(px, py) {
        if (!root.dndBusy) return;
        root.dndPointer = Qt.point(px, py);
        let targets = root.dndTargets();
        let target = null;
        for (let i = 0; i < targets.length; i++) {
            if (targets[i].containsRootPoint(px, py)) { target = targets[i]; break; }
        }
        for (let i = 0; i < targets.length; i++) {
            let c = targets[i];
            if (c === target) {
                if (!c.dndActive) c.dndActive = true;
                let idx = c.dropIndexAt(px, py);
                if (c.dndInsertIndex !== idx) c.dndInsertIndex = idx;
            } else {
                if (c.dndActive) { c.dndActive = false; c.dndInsertIndex = -1; }
            }
        }
    }

    // Drop: commit only when released over a card. Zone cards commit via
    // BarLayout.moduleMoveTo + applyBar; identical-result drops (JSON-equal)
    // never write settings.
    function endDnd(px, py) {
        if (!root.dndBusy) return;
        let target = null;
        let targets = root.dndTargets();
        for (let i = 0; i < targets.length; i++) {
            if (targets[i].containsRootPoint(px, py)) { target = targets[i]; break; }
        }
        let id = root.dndModuleId;
        let result = null;
        if (target && id !== "") {
            let idx = target.dropIndexAt(px, py);
            if (idx >= 0) {
                result = BarLayout.moduleMoveTo(root.bar, id, target.cardZoneId, idx);
                if (JSON.stringify(result) === JSON.stringify(root.bar)) result = null;
            }
        }
        root.clearDnd();
        if (result) root.applyBar(result);
    }

    // Release anywhere (or session abort): restore interactive scrolling.
    function cancelDnd() { root.clearDnd(); }
    function clearDnd() {
        let cards = root.dndTargets();
        for (let i = 0; i < cards.length; i++) {
            let c = cards[i];
            c.dndActive = false;
            c.dndInsertIndex = -1;
        }
        root.dndBusy = false;
        root.dndModuleId = "";
        root.dndSourceZoneId = "";
        root.dndPointer = Qt.point(-10000, -10000);
        if (root.dndFlick) root.dndFlick.interactive = true;
        root.dndFlick = null;
    }

    // Auto-scroll: keeps off-screen cards of the ACTIVE page reachable
    // (dndFlick null-guards a mid-session page switch).
    Timer {
        id: dndScrollTimer
        interval: 16
        repeat: true
        running: root.dndBusy
        onTriggered: {
            if (!root.dndFlick || !root.dndBusy) return;
            let local = root.dndFlick.mapFromItem(root, root.dndPointer.x, root.dndPointer.y);
            let band = root.s(26);
            if (local.y < band) {
                root.dndFlick.contentY = Math.max(0, root.dndFlick.contentY - root.s(5));
            } else if (local.y > root.dndFlick.height - band) {
                let maxY = Math.max(0, root.dndFlick.contentHeight - root.dndFlick.height);
                root.dndFlick.contentY = Math.min(maxY, root.dndFlick.contentY + root.s(5));
            }
        }
    }

    // ════ FASE B: RAIL CON GRUPOS ════
    // Grupos colapsables definidos en core/EditorNav.js (Shell, Bar, Theme,
    // Plugins, Behavior, Widgets, System): orden, visibilidad y estado vienen
    // de settings.editor. Los plugins instalados aportan su ítem (p_<id>).
    // currentPage usa ids prefijados:
    // s_* = settings/tabs/*.qml (host = settingsHost) · d_* = bar/editor/*.qml
    // p_* = plugin pages (ui/plugins/<id>/, loaded on demand; bar = root).
    // La píldora mauve sigue al item activo por su POSICIÓN REAL
    // (navItemMap + mapToItem) con scroll-follow por contentY.
    property string currentPage: "s_general"
    // Last plugin page loaded by dynamicPageLoader (p_<id>; see ensurePage).
    property string _dynamicPageId: ""

    // Panel width: doubled (2 x 1120) with a screen margin cap so it always
    // fits; Main follows this target live and animates the morph.
    property real targetMasterWidth: Math.min(root.s(1260), Screen.width - root.s(40))
    property real targetMasterHeight: root.s(760)
    // Outer radius for the host-drawn panel shadow (matches the panel bg).
    readonly property real shadowRadius: root.s(21)
    // Grupos de navegación: definidos en core/EditorNav.js (7 grupos
    // colapsables, orden/visibilidad/estado desde settings.editor).
    property var navGroups: EditorNav.configure(
        EditorNav.withPlugins(EditorNav.groups(), PluginsCatalog.plugins),
        Config.rawSettings.editor)
    // Colapsar/desplegar un grupo: persiste en settings.editor.collapsed.
    function toggleGroup(id) {
        let cfg = (Config.rawSettings.editor && typeof Config.rawSettings.editor === "object")
                  ? Config.rawSettings.editor : {};
        let collapsed = {};
        if (cfg.collapsed && typeof cfg.collapsed === "object")
            for (let k in cfg.collapsed) collapsed[k] = cfg.collapsed[k];
        collapsed[id] = !collapsed[id];
        let next = {};
        for (let k in cfg) next[k] = cfg[k];
        next.collapsed = collapsed;
        Config.setSetting("editor", next);
        // Config.setSetting muta rawSettings SIN reasignar la propiedad (los
        // bindings que leen Config.rawSettings no re-evaluan): refrescamos el
        // modelo de navegacion de forma imperativa para plegar/desplegar ya.
        root.navGroups = EditorNav.configure(
            EditorNav.withPlugins(EditorNav.groups(), PluginsCatalog.plugins), next);
        Qt.callLater(root.syncNavPill);
    }
    // Item del rail por id (lo registran los delegates): la píldora se coloca
    // con la y real del item, no con índices fijos.
    property var navItemMap: ({})
    // Animated pill slot (content px); Behavior lives here so scroll-follow
    // updates through the y binding never lag.
    property real navPillTargetY: 0

    // Items visibles de un grupo (lo que el rail renderiza).
    function groupItems(group) {
        return group.items;
    }
    // Lista plana (Desktop + Bar/Bar si expandido) para Tab/Shift+Tab.
    function navForEngine() {
        let out = [];
        for (let i = 0; i < root.navGroups.length; i++) {
            let g = root.navGroups[i];
            if (g.collapsed) continue;
            let items = root.groupItems(g);
            for (let j = 0; j < items.length; j++) out.push(items[j]);
        }
        return out;
    }
    function navIndex(id) {
        let nav = root.navForEngine();
        for (let i = 0; i < nav.length; i++) {
            if (nav[i].id === id) return i;
        }
        return -1;
    }
    function gotoPage(id) {
        if (root.navIndex(id) === -1) return;
        root.currentPage = id;
        root.syncNavPill();
    }
    // Recompute the pill's animated target from the ACTIVE ITEM's real y
    // (content px). Si la página activa no está en el rail (p.ej. grupo
    // colapsado) la píldora se oculta. Behavior 400 ms OutExpo (GP:440-456).
    function syncNavPill() {
        if (!navPill || !colNav) return;
        let item = root.navItemMap[root.currentPage];
        if (!item) { navPill.visible = false; return; }
        navPill.visible = true;
        root.navPillTargetY = item.mapToItem(colNav, 0, 0).y;
    }
    Behavior on navPillTargetY {
        NumberAnimation { duration: 400; easing.type: Easing.OutExpo }
    }

    // ════ PHASE 3: LAZY PAGE LOADING ════
    // Pages are Loaders in the content stage; opening a page (rail click, Tab
    // cycle, initial open) calls ensurePage(), which instantiates the page
    // component with setSource(file, { bar: root }) — initial properties are
    // applied BEFORE the page's internal bindings first evaluate, so `bar` is
    // never null during construction (kills the burst of TypeErrors the typed
    // always-instantiated children produced). Once loaded, the item persists;
    // hiding the page only toggles visible.
    // DnD hooks: zone items are mirrored into root.zonesPage from the Loader's
    // onLoaded (zoneCards() reads the property; Connections below retarget
    // automatically).
    function pageFile(id) {
        let map = {
            // Tabs compartidas de settings (host = settingsHost)
            "s_general":  "../settings/tabs/GeneralTab.qml",
            "s_keyboard": "../settings/tabs/KeybindTab.qml",
            "s_monitors": "../settings/tabs/MonitorsTab.qml",
            "s_startup":  "../settings/tabs/StartupTab.qml",
            // Páginas del editor (bar = root)
            "d_general":    "editor/GeneralPage.qml",
            "d_widgets":    "editor/WidgetsPage.qml",
            "d_position":   "editor/PositionPage.qml",
            "d_style":      "editor/BarStylePage.qml",
            "d_palette":    "editor/PalettePage.qml",
            "d_zones":      "editor/ZonesPage.qml",
            "d_modules":    "editor/ModulesPage.qml",
            "d_workspaces": "editor/WorkspacesPage.qml",
            "d_launcher":   "editor/LauncherPage.qml",
            "d_idle":          "editor/IdlePage.qml",
            "d_gpu":           "editor/GpuPage.qml",
            "d_notifications": "editor/NotificationsPage.qml",
            "d_guide":         "editor/GuidePage.qml",
            "d_hyprland":      "editor/HyprlandPage.qml",
            "d_animations":    "editor/AnimationsPage.qml",
            "d_input":         "editor/InputPage.qml",
            "d_shadows":       "editor/ShadowsPage.qml",
            "d_frame":         "editor/FramePage.qml",
            "d_glass":         "editor/GlassPage.qml",
            "d_plugins":       "editor/PluginsPage.qml",
            "d_appearance":    "editor/AppearancePage.qml"
        };
        return map[id] || "";
    }
    function pageLoader(id) {
        let map = {
            "s_general":  sGeneralLoader,
            "s_keyboard": sKeyboardLoader,
            "s_monitors": sMonitorsLoader,
            "s_startup":  sStartupLoader,
            "d_general":    dGeneralLoader,
            "d_widgets":    dWidgetsLoader,
            "d_position":   dPositionLoader,
            "d_style":      dStyleLoader,
            "d_palette":    dPaletteLoader,
            "d_zones":      dZonesLoader,
            "d_modules":    dModulesLoader,
            "d_workspaces": dWorkspacesLoader,
            "d_launcher":   launcherLoader,
            "d_idle":          idleLoader,
            "d_gpu":           gpuLoader,
            "d_notifications": notificationsLoader,
            "d_guide":         guidePageLoader,
            "d_hyprland":      hyprlandLoader,
            "d_animations":    animationsLoader,
            "d_input":         inputLoader,
            "d_shadows":       dShadowsLoader,
            "d_frame":         dFrameLoader,
            "d_glass":         dGlassLoader,
            "d_plugins":       dPluginsLoader,
            "d_appearance":    dAppearanceLoader
        };
        return map[id] || null;
    }
    // Plugin-contributed pages (p_<id>): loaded on demand. Managed plugins
    // load relatively (like every shell page: file:// loading changes
    // unqualified type resolution — QtQuick.Controls' Config would shadow the
    // core singleton). User plugins load via file:// and stay self-contained.
    function pluginPageFile(pid) {
        let list = PluginsCatalog.plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            let s = (p.settings && typeof p.settings === "object") ? p.settings : null;
            if (p.id !== pid || !s || !s.page) continue;
            let page = String(s.page).replace(/^\.\//, "");
            if (PluginsCatalog.isManaged(p)) return "../plugins/" + pid + "/" + page;
            return PluginsCatalog.uiUrl(p, page);
        }
        return "";
    }
    property var _dynamicPageEntry: null
    function ensurePage(id) {
        if (id.indexOf("p_") === 0) {
            let pid = id.substring(2);
            let file = root.pluginPageFile(pid);
            if (file === "" || root._dynamicPageId === pid) return;
            let entry = null;
            let list = PluginsCatalog.plugins || [];
            for (let i = 0; i < list.length; i++) if (list[i] && list[i].id === pid) { entry = list[i]; break; }
            root._dynamicPageEntry = entry;
            dynamicPageLoader.setSource(file, { bar: root });
            root._dynamicPageId = pid;
            return;
        }
        let loader = root.pageLoader(id);
        if (!loader) return;
        // NOTE: Loader.source is a QUrl — strict-compare its string form, a
        // bare `loader.source !== ""` is always true and would block loading.
        if (loader.item || String(loader.source) !== "") return;
        let file = root.pageFile(id);
        if (file === "") return;
        // s_* → tabs de settings (host) · d_* → páginas del editor (bar).
        if (id.indexOf("s_") === 0) loader.setSource(file, { host: settingsHost });
        else loader.setSource(file, { bar: root });
        // La pestaña Monitors necesita el poller de hyprctl que en el popup
        // arrancaba SettingsPopup al cargar su tab3; aquí lo arrancamos al
        // abrir la página (si no, monitorsModel queda vacío y no hay
        // resoluciones ni refrescos).
        if (id === "s_monitors" && !Config.displayPoller.running) {
            Config.displayPoller.running = true;
        }
    }
    onCurrentPageChanged: root.ensurePage(root.currentPage)
    // Plugin pages can be requested before the first scan finishes; retry
    // when the catalog updates.
    Connections {
        target: PluginsCatalog
        function onRevChanged() {
            if (root.currentPage.indexOf("p_") === 0) root.ensurePage(root.currentPage);
        }
    }


















    // ════ LIVE PALETTE EDITOR (Phase T) ════
    // Edits the ACTIVE palette file (dock/palettes/<slug>.json): validated hex
    // commits are debounced (~250 ms, grouped) and written atomically with jq
    // (tmp + mv, unknown keys preserved). First edit snapshots the file to
    // ~/.local/state/quickshell/palette_backup/<slug>.json; Reset restores it.
    // settings.json is never touched: the palette file IS the source and
    // Colors/Theme watchers re-apply edits live.
    property bool paletteEditOpen: false
    property bool _hasSessionBackup: false
    property var _slotRows: ([])
    property var _pendingWrite: null
    property var slotDescriptors: [
        { key: "color0", label: "color0" },
        { key: "color1", label: "color1" },
        { key: "color2", label: "color2" },
        { key: "color3", label: "color3" },
        { key: "color4", label: "color4" },
        { key: "color5", label: "color5" },
        { key: "color6", label: "color6" },
        { key: "color7", label: "color7" },
        { key: "color8", label: "color8" },
        { key: "color9", label: "color9" },
        { key: "color10", label: "color10" },
        { key: "color11", label: "color11" },
        { key: "color12", label: "color12" },
        { key: "color13", label: "color13" },
        { key: "color14", label: "color14" },
        { key: "color15", label: "color15" },
        { key: "background", label: "background" },
        { key: "foreground", label: "foreground" }
    ]

    Timer {
        id: paletteWriteTimer
        interval: 250
        onTriggered: root.flushPaletteWrite()
    }

    Process {
        id: backupProbe
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._hasSessionBackup = (this.text && this.text.trim() !== "")
        }
    }

    function activeSlug() {
        return String(themeColors.paletteName || "x").replace(/[^a-zA-Z0-9_-]/g, "");
    }
    // Resolve a palette file through the index (community palettes live in a
    // subfolder and carry an explicit `path`); falls back to the flat file.
    function paletteIndexEntry(slug) {
        for (let i = 0; i < root.palettes.length; i++) {
            if (root.palettes[i] && root.palettes[i].slug === slug) return root.palettes[i];
        }
        return null;
    }
    function paletteFilePath(slug) {
        let e = root.paletteIndexEntry(slug);
        let rel = (e && typeof e.path === "string" && e.path !== "") ? e.path : (slug + ".json");
        return themeColors.palettesDir + "/" + rel;
    }
    function backupDir() { return Quickshell.env("HOME") + "/.local/state/quickshell/palette_backup"; }
    function backupFilePath(slug) { return root.backupDir() + "/" + slug + ".json"; }

    // Display hex of a slot (base16 colorN or top-level background/foreground),
    // read from the local Colors instance that mirrors the active palette file.
    function slotColorHex(key) {
        if (key === "background") return themeColors.hexOf(themeColors.background);
        if (key === "foreground") return themeColors.hexOf(themeColors.foreground);
        let n = key.length > 5 ? key.substring(5) : "";
        return themeColors.hexOf(themeColors["color" + n]);
    }

    function registerSlot(key, field, chip) {
        for (let i = 0; i < root._slotRows.length; i++) {
            if (root._slotRows[i].key === key) return;
        }
        let hex = root.slotColorHex(key);
        root._slotRows.push({ key: key, field: field, chip: chip });
        field.text = hex;
        chip.color = hex;
    }

    // Re-read slots from themeColors (file watcher keeps it live); focused
    // rows keep their in-progress draft.
    function syncSlotValues() {
        for (let i = 0; i < root._slotRows.length; i++) {
            let s = root._slotRows[i];
            if (s.field.activeFocus) continue;
            let hex = root.slotColorHex(s.key);
            s.field.text = hex;
            s.chip.color = hex;
        }
    }

    // Valid hex commit: normalize, mirror in the row, queue the debounced
    // atomic file write (rapid edits of several slots share one jq).
    function commitPaletteSlot(key, hex) {
        hex = String(hex || "").toLowerCase();
        if (!/^#[0-9a-f]{6}$/.test(hex)) return;
        for (let i = 0; i < root._slotRows.length; i++) {
            if (root._slotRows[i].key === key) {
                root._slotRows[i].field.text = hex;
                root._slotRows[i].chip.color = hex;
                break;
            }
        }
        let slug = root.activeSlug();
        if (root._pendingWrite && root._pendingWrite.slug !== slug) root.flushPaletteWrite();
        if (!root._pendingWrite) root._pendingWrite = { slug: slug, edits: {} };
        root._pendingWrite.edits[key] = hex;
        paletteWriteTimer.restart();
    }

    // Hex-field commit entry (Enter / focus-out / blur): valid hexes are
    // committed live, anything else drops the draft and re-shows the color.
    function finishSlotEdit(field, key) {
        let t = field.text.trim();
        if (field.acceptableInput && /^#[0-9a-fA-F]{6}$/.test(t)) {
            root.commitPaletteSlot(key, t);
        } else {
            field.text = root.slotColorHex(key);
        }
    }

    function flushPaletteWrite() {
        let w = root._pendingWrite;
        if (!w) return;
        root._pendingWrite = null;
        let keys = Object.keys(w.edits);
        if (keys.length === 0) return;
        let slug = w.slug;
        let dir = themeColors.palettesDir;
        let file = root.paletteFilePath(slug);
        let backup = root.backupFilePath(slug);
        let args = [], parts = [];
        for (let i = 0; i < keys.length; i++) {
            let k = keys[i];
            args.push("--arg", "a" + i, w.edits[k]);
            parts.push(((k === "background" || k === "foreground") ? "." : ".base16.") + k + " = $a" + i);
        }
        // Chain: snapshot on the FIRST edit ([ ! -f backup ] guard, so a
        // snapshot from an earlier session is never overwritten).
        let cmd = "mkdir -p '" + root.backupDir() + "' && { [ ! -f '" + backup + "' ] && cp '" + file + "' '" + backup + "'; }; "
                + "tmp=$(mktemp '" + dir + "/palette.tmp.XXXXXX') && "
                + "jq " + args.join(" ") + " '" + parts.join(" | ") + "' '" + file + "' > \"$tmp\" && "
                + "mv \"$tmp\" '" + file + "'; rm -f \"$tmp\"";
        Quickshell.execDetached(["bash", "-c", cmd]);
        Qt.callLater(root.checkBackupExists);
    }

    // Restore the session snapshot of the ACTIVE palette (atomic, same
    // tmp + mv pattern), then delete it so the button disables again.
    function resetActivePalette() {
        if (!root._hasSessionBackup) return;
        let slug = root.activeSlug();
        let dir = themeColors.palettesDir;
        let file = root.paletteFilePath(slug);
        let backup = root.backupFilePath(slug);
        let cmd = "tmp=$(mktemp '" + dir + "/restore.tmp.XXXXXX') && "
                + "cp '" + backup + "' \"$tmp\" && "
                + "mv \"$tmp\" '" + file + "' && "
                + "rm -f '" + backup + "'; rm -f \"$tmp\"";
        Quickshell.execDetached(["bash", "-c", cmd]);
        root._hasSessionBackup = false;
        Qt.callLater(root.syncSlotValues);
        Qt.callLater(root.checkBackupExists);
    }

    // Async existence check of the CURRENT palette's session snapshot; drives
    // the Reset button's enabled look (open / write / reset).
    function checkBackupExists() {
        backupProbe.command = ["bash", "-c", "cat '" + root.backupFilePath(root.activeSlug()) + "' 2>/dev/null | head -c 1"];
        backupProbe.running = false;
        backupProbe.running = true;
    }

    // ════ CREADOR DE PALETAS (8 colores base) ════
    // Genera dock/palettes/<slug>.json con la estructura de las paletas
    // existentes (base16 0-15, background/foreground, roles) + entrada en
    // index.json, y aplica la nueva paleta (applyBar), lo que dispara el
    // resto del sync. El draft vive en el root para sobrevivir a los cambios
    // de página (el Loader de la página se destruye al navegar).
    property bool paletteCreateOpen: false
    property string paletteDraftName: ""
    property var paletteDraftColors: ["#000000", "#fc618d", "#7bd88f", "#fce566", "#fd9353", "#948ae3", "#5ad4e6", "#f7f1ff"]
    property string paletteCreateStatus: ""
    readonly property var paletteBaseLabels: ["Background", "Red", "Green", "Yellow", "Blue", "Purple", "Cyan", "Foreground"]

    // Slug desde el nombre: minúsculas, sin acentos, [a-z0-9-] (colapsado).
    function slugifyPaletteName(name) {
        let s = String(name || "").toLowerCase();
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        return s.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    }
    function paletteSlugTaken(slug) {
        for (let i = 0; i < root.palettes.length; i++) {
            if (root.palettes[i] && root.palettes[i].slug === slug) return true;
        }
        return false;
    }
    // Siembra el draft desde los 8 primeros colores de la paleta activa.
    function seedPaletteDraft() {
        let seed = [];
        for (let i = 0; i < 8; i++) seed.push(themeColors.hexOf(themeColors["color" + i]));
        root.paletteDraftColors = seed;
        root.paletteDraftName = "";
        root.paletteCreateStatus = "";
    }
    function setPaletteDraftColor(i, hex) {
        hex = String(hex || "").toLowerCase();
        if (!/^#[0-9a-f]{6}$/.test(hex)) return false;
        let arr = root.paletteDraftColors.slice();
        arr[i] = hex;
        root.paletteDraftColors = arr;
        return true;
    }
    // Commit de un campo hex del draft (Enter / blur): válido → draft,
    // inválido → restaura el valor vigente.
    function commitPaletteDraftColor(field, i) {
        let t = String(field.text || "").trim();
        if (/^#[0-9a-fA-F]{6}$/.test(t) && root.setPaletteDraftColor(i, t)) {
            field.text = t.toLowerCase();
        } else {
            field.text = root.paletteDraftColors[i];
        }
    }
    // Objeto paleta completo: color0..7 = base, color8 = muted derivado y
    // color9..15 = duplicados de color1..7 (convención de las paletas actuales).
    function buildPaletteObject(name, colors) {
        let base16 = {};
        for (let i = 0; i < 8; i++) base16["color" + i] = colors[i];
        base16.color8 = themeColors.mix(colors[7], colors[0], 0.45);
        for (let i = 1; i < 8; i++) base16["color" + (i + 8)] = colors[i];
        return {
            name: name,
            slug: root.slugifyPaletteName(name),
            author: "xscriptor",
            base16: base16,
            background: colors[0],
            foreground: colors[7],
            roles: { workspaceActive: themeColors.mix(colors[5], colors[7], 0.35) }
        };
    }
    function createPaletteFromDraft() {
        let name = String(root.paletteDraftName || "").trim();
        let slug = root.slugifyPaletteName(name);
        if (slug === "") {
            root.paletteCreateStatus = "Enter a palette name";
            return;
        }
        if (root.paletteSlugTaken(slug)) {
            root.paletteCreateStatus = "A palette with slug '" + slug + "' already exists";
            return;
        }
        for (let i = 0; i < 8; i++) {
            if (!/^#[0-9a-f]{6}$/.test(String(root.paletteDraftColors[i]))) {
                root.paletteCreateStatus = "Invalid color in '" + root.paletteBaseLabels[i] + "'";
                return;
            }
        }
        let pal = root.buildPaletteObject(name, root.paletteDraftColors.slice());
        let json = JSON.stringify(pal, null, 4);
        let entry = JSON.stringify({ slug: pal.slug, name: pal.name, category: "user", colors: root.paletteDraftColors.slice() });
        let dir = themeColors.palettesDir;
        let file = root.paletteFilePath(pal.slug);
        let index = dir + "/index.json";
        let esc = (v) => String(v).replace(/'/g, "'\\''");
        root.paletteCreateStatus = "Creating…";
        paletteCreator.pendingSlug = pal.slug;
        paletteCreator.command = ["bash", "-c",
            "set -e; test ! -f '" + file + "'; "
            + "tmp=$(mktemp '" + dir + "/palette.tmp.XXXXXX'); printf '%s\\n' '" + esc(json) + "' > \"$tmp\"; mv \"$tmp\" '" + file + "'; "
            + "tmp2=$(mktemp '" + dir + "/index.tmp.XXXXXX'); jq --argjson e '" + esc(entry) + "' '. += [$e]' '" + index + "' > \"$tmp2\"; mv \"$tmp2\" '" + index + "'; "
            + "echo OK"];
        paletteCreator.running = false;
        paletteCreator.running = true;
    }

    Process {
        id: paletteCreator
        property string pendingSlug: ""
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "OK") {
                    root.paletteCreateOpen = false;
                    root.paletteCreateStatus = "";
                    paletteReader.running = false;
                    paletteReader.running = true;
                    root.applyBar(Object.assign({}, root.bar, { palette: paletteCreator.pendingSlug }));
                } else {
                    root.paletteCreateStatus = "Could not create the palette (name/slug conflict?)";
                }
            }
        }
    }

    // ════ ELIMINAR PALETA (activa, con confirmación) ════
    // Borra el archivo de la paleta ACTIVA + su entrada de index.json + el
    // snapshot de sesión. "x" está protegida: es el fallback de Colors.qml.
    // Si la eliminada era la activa, se cambia a "x" (dispara el sync).
    property bool paletteDeleteConfirm: false
    property string paletteDeleteStatus: ""

    function paletteDisplayName(slug) {
        for (let i = 0; i < root.palettes.length; i++) {
            if (root.palettes[i] && root.palettes[i].slug === slug) return root.palettes[i].name;
        }
        return slug;
    }
    function requestDeletePalette() {
        root.paletteDeleteStatus = "";
        root.paletteDeleteConfirm = true;
    }
    function cancelDeletePalette() {
        root.paletteDeleteConfirm = false;
        root.paletteDeleteStatus = "";
    }
    function deleteActivePalette() {
        let slug = root.activeSlug();
        if (slug === "x") {
            root.paletteDeleteStatus = "'x' is the fallback palette and cannot be deleted";
            return;
        }
        if (!root.paletteSlugTaken(slug)) {
            root.paletteDeleteStatus = "Palette not found in index.json";
            return;
        }
        root.paletteDeleteStatus = "Deleting…";
        paletteDeleter.pendingSlug = slug;
        let dir = themeColors.palettesDir;
        let file = root.paletteFilePath(slug);
        let index = dir + "/index.json";
        let backup = root.backupFilePath(slug);
        paletteDeleter.command = ["bash", "-c",
            "set -e; tmp=$(mktemp '" + dir + "/index.tmp.XXXXXX'); "
            + "jq --arg s '" + slug + "' 'map(select(.slug != $s))' '" + index + "' > \"$tmp\"; mv \"$tmp\" '" + index + "'; "
            + "rm -f '" + file + "' '" + backup + "'; echo OK"];
        paletteDeleter.running = false;
        paletteDeleter.running = true;
    }

    Process {
        id: paletteDeleter
        property string pendingSlug: ""
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "OK") {
                    let wasActive = root.activeSlug() === paletteDeleter.pendingSlug;
                    root.paletteDeleteConfirm = false;
                    root.paletteDeleteStatus = "";
                    paletteReader.running = false;
                    paletteReader.running = true;
                    if (wasActive) root.applyBar(Object.assign({}, root.bar, { palette: "x" }));
                } else {
                    root.paletteDeleteStatus = "Could not delete the palette";
                }
            }
        }
    }

    // The instance is torn down right after closing (StackView clear): flush
    // any pending palette write and persist the effect knobs (previewed live
    // while dragging; the Lua write here causes one Hyprland auto-reload).
    Component.onDestruction: {
        root.flushPaletteWrite();
        HyprEffects.persist();
    }

    // Fallback: Config reads settings.json only once at shell start, so this
    // only covers a uiScale edited externally while the shell is running. It
    // must not reassign when the value already matches: doing so re-laid out
    // the panel after the first paint and displaced the nav pill on open.
    Process {
        id: scaleReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null | jq -r '.uiScale // 1'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseFloat(this.text.trim());
                if (!isNaN(v) && v > 0 && root.uiScale !== v) root.uiScale = v;
            }
        }
    }

    Process {
        id: paletteReader
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/dock/palettes/index.json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.palettes = JSON.parse(this.text.trim()); } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        // Scale from Config (synchronous, settings.json is already parsed when
        // the shell starts) BEFORE the first layout. The old flow started at
        // 1.0 and corrected itself when the async jq returned: the first open
        // was laid out at the wrong scale and then re-scaled, leaving the nav
        // pill displaced downwards (and the panel morphing).
        root.uiScale = Config.uiScale;
        startupSequence.start();
        reload();
        paletteReader.running = true;
        scaleReader.running = true;
        // Push window-border colors to Hyprland live on palette re-apply and
        // on settings.json changes (only this instance pushes).
        themeColors.paletteApplied.connect(function() { themeColors.syncWindowBorders(); });
        themeColors.settingsUpdated.connect(function() { themeColors.syncWindowBorders(); });
        // Live palette editor: mirror every palette re-apply into the slot
        // rows (own edits, palette switches and external changes all land here).
        themeColors.paletteApplied.connect(function() { root.syncSlotValues(); });
        themeColors.paletteNameChanged.connect(function() { root.checkBackupExists(); });
        root.syncSlotValues();
        Qt.callLater(root.syncNavPill);
        root.ensurePage(root.currentPage);
    }

    // ════ FASE 4: SECUENCIAS INTRO/CIERRE (GP:223-287) ════
    // Escalonado: base 900 ms OutExpo · sidebar +150 ms 1000 ms OutBack 1.05 ·
    // content +250 ms 1100 ms OutBack 1.02. El cierre colapsa content/sidebar
    // (150 ms InExpo), luego base (200 ms InQuart) y solo entonces flush+close.
    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introBase"; from: 0.0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introSidebar"; from: 0.0; to: 1.0; duration: 1000; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: root; property: "introContent"; from: 0.0; to: 1.0; duration: 1100; easing.type: Easing.OutBack; easing.overshoot: 1.02 }
        }
    }

    // Flush de ambos buffers antes de cerrar (mismo contrato que el ESC de la
    // Fase 1: nunca perder un debounce pendiente).
    function closeFlush() {
        flushSave();
        flushPaletteWrite();
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation {
            NumberAnimation { target: root; property: "introContent"; to: 0.0; duration: 150; easing.type: Easing.InExpo }
            NumberAnimation { target: root; property: "introSidebar"; to: 0.0; duration: 150; easing.type: Easing.InExpo }
        }
        NumberAnimation { target: root; property: "introBase"; to: 0.0; duration: 200; easing.type: Easing.InQuart }
        ScriptAction { script: root.closeFlush() }
        ScriptAction { script: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh close"]) }
    }

    // ════ FASE B: HOST DE LAS SETTINGS TABS ════
    // Las tabs compartidas (settings/tabs/*.qml) esperan la API del root de
    // SettingsPopup (host.*). Este adaptador invisible la replica desde el
    // editor: s(), los roles de la instancia local Colors, highlightedBox,
    // isLayoutDropdownOpen, los modelos keybinds/startup y las acciones que en
    // el popup resolvía el host (saveAllKeybinds/saveAllStartup/appScaleStep).
    // Los ListModel son ids: se exponen con `property alias` porque los ids no
    // son accesibles desde otros archivos (mismo motivo que en SettingsPopup).
    Item {
        id: settingsHost
        visible: false
        width: 0
        height: 0

        function s(val) { return root.s(val); }

        readonly property color base: themeColors.base
        readonly property color mantle: themeColors.mantle
        readonly property color crust: themeColors.crust
        readonly property color text: themeColors.text
        readonly property color subtext0: themeColors.subtext0
        readonly property color subtext1: themeColors.subtext1
        readonly property color surface0: themeColors.surface0
        readonly property color surface1: themeColors.surface1
        readonly property color surface2: themeColors.surface2
        readonly property color overlay0: themeColors.overlay0
        readonly property color overlay1: themeColors.overlay1
        readonly property color overlay2: themeColors.overlay2
        readonly property color mauve: themeColors.mauve
        readonly property color blue: themeColors.blue
        readonly property color green: themeColors.green
        readonly property color red: themeColors.red
        readonly property color yellow: themeColors.yellow
        readonly property color peach: themeColors.peach
        readonly property color sapphire: themeColors.sapphire
        readonly property color teal: themeColors.teal
        readonly property color pink: themeColors.pink

        // Estado de la navegación del popup: las tabs lo leen Y lo escriben
        // (hover/click sobre una fila); aquí solo se guarda el valor.
        property int highlightedBox: -1
        function clearHighlight() { highlightedBox = -1; }
        property bool isLayoutDropdownOpen: false

        ListModel { id: kbModelData }
        ListModel { id: startupModelData }
        property alias kbModel: kbModelData
        property alias startupModel: startupModelData

        // Poblar los modelos. Las señales keybindsLoaded()/startupLoaded() de
        // Config se emiten UNA vez al arrancar el shell (antes de que exista
        // este widget), así que además de escucharlas hay que poblar al crear
        // el adaptador y cuando Config termine de leer (dataReady).
        function populateKbModel() {
            kbModelData.clear();
            for (let i = 0; i < Config.keybindsData.length; i++) {
                let k = Config.keybindsData[i];
                kbModelData.append({
                    type: k.type || "bind",
                    mods: k.mods || "",
                    key: k.key || "",
                    dispatcher: k.dispatcher || "exec",
                    command: k.command || "",
                    isEditing: false
                });
            }
        }
        function populateStartupModel() {
            startupModelData.clear();
            for (let s of Config.startupData) {
                startupModelData.append({ command: s.command || "", isEditing: false });
            }
        }

        Component.onCompleted: {
            populateKbModel();
            populateStartupModel();
        }

        Connections {
            target: Config
            // Los handlers de Connections no ven los métodos del Item padre
            // (cadena de scope: Connections → root → global), por eso hay que
            // cualificar con el id: sin esto los modelos nunca se poblaban.
            function onKeybindsLoaded() { settingsHost.populateKbModel(); }
            function onKeybindsDataChanged() { settingsHost.populateKbModel(); }
            function onStartupLoaded() { settingsHost.populateStartupModel(); }
            function onStartupDataChanged() { settingsHost.populateStartupModel(); }
            function onDataReadyChanged() {
                if (Config.dataReady) {
                    settingsHost.populateKbModel();
                    settingsHost.populateStartupModel();
                }
            }
        }

        function saveAllKeybinds() {
            let bindsArray = [];
            for (let i = 0; i < kbModelData.count; i++) {
                let item = kbModelData.get(i);
                if (!item.key && !item.command) continue;
                bindsArray.push({
                    type: item.type,
                    mods: item.mods,
                    key: item.key,
                    dispatcher: item.dispatcher,
                    command: item.command,
                    isEditing: false // CRITICAL: evita que QML pierda el rol
                });
            }
            Config.saveAllKeybinds(bindsArray);
        }

        function saveAllStartup() {
            let startupArray = [];
            for (let i = 0; i < startupModelData.count; i++) {
                let cmd = startupModelData.get(i).command.trim();
                if (cmd.length > 0) startupArray.push({ command: cmd });
            }
            Config.saveAllStartup(startupArray);
        }

        // App scale (mismo comportamiento que el General tab del popup).
        function appScaleStep(dir) {
            let next = Math.max(0.75, Math.min(2.0, Config.appScale + dir * 0.25));
            Config.appScale = Math.round(next * 100) / 100;
            // Aplicar de verdad: escala global a traves del backend activo
            Compositor.applyMonitorScale("", Config.appScale);
        }
    }

    // ════ PANEL (Fase 4: paridad visual con GuidePopup) ════
    // Fondo base + borde surface0 1 px + radio s(21), SIN márgenes externos;
    // wrapper con intro (opacity/scale, GP:292-303). Interior: Row con
    // márgenes s(20) y spacing s(20) (GP:358-361).
    Item {
        anchors.fill: parent
        opacity: root.introBase
        scale: 0.95 + (0.05 * root.introBase)

        Rectangle {
            anchors.fill: parent
            radius: s(21)
            color: colors.base
            border.width: 1
            border.color: colors.surface0
            clip: true

            Row {
                anchors.fill: parent
                anchors.margins: s(20)
                spacing: s(20)

                // ── SIDEBAR (Fase 4: tokens del Guide) ──────────────────────
                Rectangle {
                    id: sidebar
                    width: s(220)
                    height: parent.height
                    radius: s(16)
                    color: Qt.alpha(colors.surface0, 0.4)
                    border.width: 1
                    border.color: colors.surface1
                    clip: true
                    opacity: root.introSidebar
                    transform: Translate { x: s(-30) * (1.0 - root.introSidebar) }

                    // Brand: base16 palette swatches (live — Colors watcher keeps them fresh)
                    Grid {
                        id: brandCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: s(15)
                        anchors.leftMargin: s(15)
                        anchors.rightMargin: s(15)
                        columns: 8
                        spacing: s(5)

                        Repeater {
                            model: 16
                            delegate: Rectangle {
                                required property int index
                                width: s(16); height: s(16); radius: s(4)
                                color: colors["color" + index]
                                border.width: 1
                                border.color: Qt.alpha(colors.text, 0.10)
                            }
                        }
                    }
                    Rectangle {
                        id: navHairline
                        anchors.top: brandCol.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: s(10)
                        anchors.leftMargin: s(15)
                        anchors.rightMargin: s(15)
                        height: 1
                        color: Qt.alpha(colors.surface1, 0.5)
                    }

                    // Nav zone: navPill (mauve) es overlay viewport-fixed — NO
                    // hija del Flickable: el contenido scrollea con contentY y
                    // la píldora debe quedar pegada al slot de la fila activa.
                    Item {
                        id: navArea
                        anchors.top: navHairline.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: footerCol.top
                        anchors.topMargin: s(10)
                        clip: true

                        Rectangle {
                            id: navPill
                            x: colNav.x
                            width: colNav.width
                            height: s(44)
                            radius: s(18)
                            color: colors.mauve
                            // y = y real del item activo (navPillTargetY, animada
                            // 400 ms OutExpo) − scroll de la nav (GP:440-456).
                            y: colNav.y + root.navPillTargetY - navFlick.contentY
                        }

                        Flickable {
                            id: navFlick
                            anchors.fill: parent
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            contentHeight: colNav.height + s(15)
                            ScrollBar.vertical: ScrollBar {
                                id: navScroll
                                width: s(4)
                                policy: ScrollBar.AsNeeded
                                hoverEnabled: true
                                active: navFlick.moving || navScroll.hovered
                                contentItem: Rectangle {
                                    radius: s(2)
                                    color: colors.surface2
                                    opacity: navScroll.active ? 1.0 : 0.45
                                }
                                background: Item {}
                            }

                            Column {
                                id: colNav
                                x: s(15)
                                width: navFlick.width - s(30)
                                spacing: 0

                                Repeater {
                                    model: root.navGroups
                                    delegate: Column {
                                        id: navGroupCol
                                        required property var modelData
                                        width: colNav.width

                                        // Cabecera del grupo (click = colapsar/desplegar)
                                        Item {
                                            width: parent.width
                                            height: s(30)
                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: s(6)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: navGroupCol.modelData.label
                                                font.family: "Hack Nerd Font"
                                                font.weight: Font.Bold
                                                font.pixelSize: s(10)
                                                color: colors.subtext0
                                            }
                                            Text {
                                                anchors.right: parent.right
                                                anchors.rightMargin: s(8)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "󰅀"
                                                font.family: "Hack Nerd Font"
                                                font.pixelSize: s(12)
                                                color: colors.subtext0
                                                rotation: navGroupCol.modelData.collapsed ? -90 : 0
                                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleGroup(navGroupCol.modelData.id)
                                            }
                                        }
                                        Item {
                                            width: parent.width
                                            height: navItemsCol.height
                                            visible: !navGroupCol.modelData.collapsed

                                            Column {
                                                id: navItemsCol
                                                x: 0
                                                width: parent.width
                                                spacing: 0
                                                Repeater {
                                                    model: root.groupItems(navGroupCol.modelData)
                                                    delegate: NavItem {
                                                        id: navRowItem
                                                        required property var modelData
                                                        readonly property string pageId: modelData.id
                                                        width: navItemsCol.width
                                                        bar: root
                                                        icon: modelData.icon
                                                        label: modelData.label
                                                        active: root.currentPage === modelData.id
                                                        onActivated: root.gotoPage(modelData.id)
                                                        Component.onCompleted: { root.navItemMap[navRowItem.pageId] = navRowItem; root.syncNavPill(); }
                                                        Component.onDestruction: delete root.navItemMap[navRowItem.pageId]
                                                        onYChanged: if (root.currentPage === modelData.id) root.syncNavPill()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Footer hints
                    Column {
                        id: footerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: s(15)
                        anchors.rightMargin: s(15)
                        anchors.bottomMargin: s(15)
                        spacing: s(8)
                        // Buscador global (botón lupa, misma acción que `/`).
                        EditorButton {
                            compact: true
                            bar: root
                            icon: "󰍉"
                            label: "Search"
                            accentRole: "sapphire"
                            width: parent.width
                            onActivated: root.openSearch()
                        }
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.alpha(colors.surface1, 0.5)
                        }
                        Column {
                            width: parent.width
                            spacing: s(2)
                            Text {
                                text: "TAB / SHIFT+TAB — switch page"
                                font.family: "Hack Nerd Font"
                                font.pixelSize: s(10)
                                color: colors.subtext0
                            }
                            Text {
                                text: "ESC — save & close"
                                font.family: "Hack Nerd Font"
                                font.pixelSize: s(10)
                                color: colors.subtext0
                            }
                            Text {
                                text: "/ — search settings"
                                font.family: "Hack Nerd Font"
                                font.pixelSize: s(10)
                                color: colors.subtext0
                            }
                        }
                    }
                }

                // ── CONTENT STAGE (Fase 3 lazy Loaders + Fase 4 transición) ──
                // Cada página se instancia UNA vez via ensurePage() (visible
                // false conserva el item). Transición tipo Guide (GP:655-664):
                // opacity 250 ms + slideY s(10) 250 ms OutQuart; el wrapper
                // aplica la intro (opacity/scale/translate y).
                Item {
                    // Ancho = Row − sidebar − spacing s(20) (evita el overflow
                    // que dejaba la stage 20 px fuera del panel).
                    width: parent.width - s(220) - s(20)
                    height: parent.height
                    opacity: root.introContent
                    scale: 0.95 + (0.05 * root.introContent)
                    transform: Translate { y: s(20) * (1.0 - root.introContent) }

                    Loader {
                        id: dWidgetsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_widgets"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dWidgetsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dShadowsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_shadows"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dShadowsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dFrameLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_frame"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dFrameLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dGlassLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_glass"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dGlassLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dAppearanceLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_appearance"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dAppearanceLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dPluginsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_plugins"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dPluginsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dynamicPageLoader
                        anchors.fill: parent
                        onLoaded: if (item && item.host !== undefined && root._dynamicPageEntry)
                            item.host = HostApi.forPlugin(root._dynamicPageEntry)
                        visible: root.currentPage.indexOf("p_") === 0
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dynamicPageLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dGeneralLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_general"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dGeneralLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dPositionLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_position"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dPositionLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dStyleLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_style"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dStyleLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dPaletteLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_palette"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dPaletteLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dZonesLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_zones"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dZonesLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        onLoaded: { if (dZonesLoader.item) root.zonesPage = dZonesLoader.item; }
                    }
                    Loader {
                        id: dModulesLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_modules"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dModulesLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: dWorkspacesLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_workspaces"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: dWorkspacesLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: launcherLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_launcher"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: launcherLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: idleLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_idle"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: idleLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: gpuLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_gpu"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: gpuLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: notificationsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_notifications"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: notificationsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }

                    Loader {
                        id: guidePageLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_guide"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: guidePageLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: animationsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_animations"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: animationsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: inputLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_input"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: inputLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: hyprlandLoader
                        anchors.fill: parent
                        visible: root.currentPage === "d_hyprland"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: hyprlandLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    // ── Tabs compartidas de settings (host = settingsHost) ──
                    Loader {
                        id: sGeneralLoader
                        anchors.fill: parent
                        visible: root.currentPage === "s_general"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: sGeneralLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: sKeyboardLoader
                        anchors.fill: parent
                        visible: root.currentPage === "s_keyboard"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: sKeyboardLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: sMonitorsLoader
                        anchors.fill: parent
                        visible: root.currentPage === "s_monitors"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: sMonitorsLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Loader {
                        id: sStartupLoader
                        anchors.fill: parent
                        visible: root.currentPage === "s_startup"
                        opacity: visible ? 1.0 : 0.0
                        property real slideY: visible ? 0 : root.s(10)
                        Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        transform: Translate { y: sStartupLoader.slideY }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }

                    // ── ADD FLOTANTE (Keyboard / Startup) ───────────────────
                    // El botón "+ Add" del popup vive en SU header (fuera de las
                    // tabs), por eso al embeberlas aquí hay que reponerlo: añade
                    // una fila nueva al modelo correspondiente y la deja en
                    // edición (misma semántica que SettingsPopup.qml:1000-1010).
                    EditorButton {
                        z: 100
                        compact: true
                        bar: root
                        label: "+ Add"
                        // The Keyboard/Startup tabs now render their own in-flow
                        // "+ Add" (as the last section row), so the floating
                        // button would duplicate it.
                        visible: false
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: s(18)
                        anchors.bottomMargin: s(18)
                        onActivated: {
                            if (root.currentPage === "s_startup") {
                                settingsHost.startupModel.append({ command: "", isEditing: true });
                                let l = root.pageLoader("s_startup");
                                if (l && l.item && l.item.scrollToBottom) Qt.callLater(() => l.item.scrollToBottom());
                            } else if (root.currentPage === "s_keyboard") {
                                settingsHost.kbModel.append({ type: "bind", mods: "", key: "", dispatcher: "exec", command: "", isEditing: true });
                                let l = root.pageLoader("s_keyboard");
                                if (l && l.item && l.item.scrollToBottom) Qt.callLater(() => l.item.scrollToBottom());
                            }
                        }
                    }

                    // ── BUSCADOR GLOBAL (overlay estilo Guide) ──────────────
                    // Cubre toda la stage (z por encima del "+ Add"). El item se
                    // crea en el primer openSearch() y persiste (setSource).
                    Loader {
                        id: searchLoader
                        anchors.fill: parent
                        z: 200
                        // Salvaguarda: si setSource cargase async, abrir al cargar.
                        onLoaded: if (root.searchOpen && item) item.open();
                    }
                    Connections {
                        target: searchLoader.item
                        function onClosed() {
                            root.searchOpen = false;
                            root.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // ════ PAGE SIGNAL ROUTING (Phase 2/3) ════
    // Pages never import BarLayout: they declare intent signals, this root
    // computes and commits through the shared helpers. Targets are the lazy
    // item properties (null until loaded): Connections follows the binding,
    // so the routes arm themselves when zonesPage gets assigned in the
    // Loader's onLoaded.
    Connections {
        target: root.zonesPage
        function onAddZone() { root.applyBar(BarLayout.addZone(root.bar, "start")); }
        function onCenterAll() { root.applyBar(BarLayout.arrangeAllInZone(root.bar, "center")); }
        function onResetBar() { root.applyBar(BarLayout.defaultBar()); }
    }

    // ════ DnD GHOST (Phase D3) ════
    // Floating chip following the pointer during a drag. Purely visual
    // (enabled: false) — input stays with the chip's MouseArea grab.
    Item {
        id: dndGhostLayer
        anchors.fill: parent
        visible: root.dndBusy
        z: 1000
        enabled: false

        Rectangle {
            id: dndGhost
            property var modInfo: BarLayout.getModule(root.dndModuleId)
            readonly property int ghostW: ghostRow.implicitWidth + root.s(24)
            height: root.s(30)
            width: ghostW
            x: root.dndPointer.x - width / 2
            y: root.dndPointer.y - height / 2 - root.s(8)
            radius: root.s(8)
            color: colors.mauve
            opacity: 0.95
            scale: 1.06
            Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Row {
                id: ghostRow
                anchors.centerIn: parent
                spacing: root.s(5)
                Text {
                    text: dndGhost.modInfo ? dndGhost.modInfo.icon : "?"
                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(12); color: colors.crust
                }
                Text {
                    text: dndGhost.modInfo ? dndGhost.modInfo.label : root.dndModuleId
                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11); font.weight: Font.Bold; color: colors.crust
                }
            }
        }
    }

    // Fase 4: ESC ya no cierra en seco — closeSequence flushea los buffers
    // pendientes (closeFlush) y anima la salida antes de qs_manager.sh close.
    // Buscador (Fase 5): si el overlay está abierto, ESC lo cierra primero y
    // NO cierra el panel (el overlay devuelve el foco con onClosed).
    Keys.onEscapePressed: {
        if (root.searchOpen) {
            root.closeSearch();
            event.accepted = true;
            return;
        }
        closeSequence.start();
        event.accepted = true;
    }
    // Phase 2: Tab / Shift+Tab cycle the visible pages (same list the rail
    // renders); ESC keeps the phase-1 contract.
    // Con el buscador abierto no cambian de página (el foco vive en el input).
    Keys.onTabPressed: {
        event.accepted = true;
        if (root.searchOpen) return;
        let nav = root.navForEngine();
        if (nav.length === 0) return;
        let idx = root.navIndex(root.currentPage);
        root.gotoPage(nav[(idx + 1) % nav.length].id);
    }
    Keys.onBacktabPressed: {
        event.accepted = true;
        if (root.searchOpen) return;
        let nav = root.navForEngine();
        if (nav.length === 0) return;
        let idx = root.navIndex(root.currentPage);
        if (idx < 0) idx = 0;
        root.gotoPage(nav[(idx - 1 + nav.length) % nav.length].id);
    }
    // Buscador global: `/` o Ctrl+F lo abren (misma semántica que el popup).
    // Los TextField consumen `/` al escribir, así que solo llega aquí cuando
    // el foco no está en un input.
    Keys.onPressed: {
        if (root.searchOpen) return;
        if (event.key === Qt.Key_Slash
            || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
            root.openSearch();
            event.accepted = true;
        }
    }
}
