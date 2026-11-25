// 타이머 — 윈도우판
// 화면은 맥판과 같은 index.html을 쓰고, 맥에서 Swift가 하던 일(창 고정·작게 보기·알람·포커스)을 여기서 해요.
const { app, BrowserWindow, ipcMain, screen, powerSaveBlocker, Tray, Menu, nativeImage } = require("electron");
const path = require("path"), fs = require("fs");

const WEB = path.join(__dirname, "web");
const NORMAL = { width: 400, height: 320, minWidth: 360, minHeight: 300 };
const MINI = { width: 280, height: 120 };

if (!app.requestSingleInstanceLock()) { app.quit(); }

// ── 창 위치 기억 ──
const statePath = () => path.join(app.getPath("userData"), "window.json");
const loadState = () => { try { return JSON.parse(fs.readFileSync(statePath(), "utf8")); } catch (e) { return {}; } };
const saveState = s => { try { fs.writeFileSync(statePath(), JSON.stringify({ ...loadState(), ...s })); } catch (e) {} };

let win = null, tray = null, creditsWin = null;
let onTop = false, normalBounds = null, sheetBounds = null;
let alarm = null, ticks = [], blocker = null;
let wantsKey = false;

function visibleOn(b) { return screen.getAllDisplays().some(d => { const a = d.workArea; return b.x < a.x + a.width - 40 && b.x + b.width > a.x + 40 && b.y < a.y + a.height - 40 && b.y + b.height > a.y + 40; }); }

function createWindow() {
  const saved = loadState().bounds;
  win = new BrowserWindow({
    ...NORMAL,
    ...(saved && saved.width >= NORMAL.minWidth && saved.height >= NORMAL.minHeight && visibleOn(saved) ? saved : {}),
    frame: false,
    resizable: true,
    backgroundColor: "#3a3a3c",
    title: "타이머",
    icon: path.join(__dirname, "icon.png"),
    show: false,
    // 눌러도 다른 앱(PPT 등)의 키보드 포커스를 뺏지 않아요. 시간 직접 입력할 때만 잠깐 포커스를 받아요.
    focusable: false,
    webPreferences: { preload: path.join(__dirname, "preload.js"), backgroundThrottling: false },
  });
  win.loadFile(path.join(WEB, "index.html"));
  win.once("ready-to-show", () => win.showInactive());
  win.on("moved", () => { if (!normalBounds && !sheetBounds) saveState({ bounds: win.getBounds() }); else if (normalBounds) saveState({ miniPos: win.getPosition() }); });
  win.on("resized", () => { if (!normalBounds && !sheetBounds) saveState({ bounds: win.getBounds() }); });
  win.on("closed", () => { win = null; });
  // 오른쪽 클릭 메뉴(새로고침 등)는 화면에서 이미 막아요. 새 창 열기는 크레딧 미리보기 말고는 막아요.
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
}

function js(code) { if (win && !win.isDestroyed()) win.webContents.executeJavaScript(code).catch(() => {}); }

// ── 항상 위에 고정: PPT 전체 화면(슬라이드 쇼) 위에도 떠 있게 ──
function applyTop() {
  if (!win) return;
  win.setAlwaysOnTop(onTop, onTop ? "screen-saver" : "normal");
}

// ── 작게 보기 ──
function setCompact(on) {
  if (!win) return;
  if (on) {
    if (normalBounds) return;
    normalBounds = win.getBounds();
    win.setMinimumSize(240, 110);
    win.setResizable(false);
    const wa = screen.getDisplayMatching(normalBounds).workArea;
    let pos = loadState().miniPos;
    const b = pos ? { x: pos[0], y: pos[1], ...MINI } : null;
    if (!b || !visibleOn(b)) pos = [wa.x + wa.width - MINI.width - 20, wa.y + 20];
    win.setBounds({ x: pos[0], y: pos[1], ...MINI });
  } else {
    if (!normalBounds) return;
    saveState({ miniPos: win.getPosition() });
    const nb = normalBounds; normalBounds = null;
    win.setResizable(true);
    win.setMinimumSize(NORMAL.minWidth, NORMAL.minHeight);
    win.setBounds(nb);
  }
  applyTop();
}

// ── 설정이 다 보이게 창을 아래로만 늘렸다가, 닫으면 원래대로 ──
function fitHeight(h) {
  if (!win || normalBounds) return;
  if (h) {
    const [cw, ch] = win.getContentSize();
    if (h <= ch) return;
    const b = win.getBounds(), wa = screen.getDisplayMatching(b).workArea;
    const extra = Math.max(0, Math.min(h - ch, wa.y + wa.height - (b.y + b.height)));
    if (!extra) return;
    if (!sheetBounds) sheetBounds = b;
    win.setBounds({ ...b, height: b.height + Math.round(extra) });
  } else if (sheetBounds) {
    const sb = sheetBounds; sheetBounds = null;
    win.setBounds(sb);
  }
}

// ── 정확한 알람: 창이 가려져 있어도 정해진 시각에 화면을 깨워요 ──
function scheduleAlarm(at, tickTimes) {
  clearTimeout(alarm); alarm = null;
  ticks.forEach(clearTimeout); ticks = [];
  if (at == null) return;
  alarm = setTimeout(() => js("window.__nativeAlarm && window.__nativeAlarm()"), Math.max(0, at - Date.now()));
  ticks = (tickTimes || []).map(t => setTimeout(() => js("window.__nativeTick && window.__nativeTick()"), Math.max(0, t + 20 - Date.now())));
}

// ── 키보드가 필요할 때(시간 직접 입력)만 포커스를 받아요 ──
function needKey() { if (!win) return; wantsKey = true; win.setFocusable(true); win.focus(); }
function releaseKey() {
  if (!win) return; wantsKey = false;
  win.blur();
  win.setFocusable(false);
}

// ── 엔딩 크레딧: 화면 전체 ──
function showCredits(vol) {
  if (creditsWin) return;
  const d = win ? screen.getDisplayMatching(win.getBounds()) : screen.getPrimaryDisplay();
  creditsWin = new BrowserWindow({
    ...d.bounds, frame: false, backgroundColor: "#000000", show: false, skipTaskbar: true,
    alwaysOnTop: true, fullscreen: true, resizable: false,
    webPreferences: { preload: path.join(__dirname, "credits-preload.js"), backgroundThrottling: false },
  });
  creditsWin.setAlwaysOnTop(true, "screen-saver");
  creditsWin.loadFile(path.join(WEB, "credits.html"), { query: { vol: String(vol), ver: app.getVersion() } });
  creditsWin.once("ready-to-show", () => { creditsWin.show(); creditsWin.focus(); });
  creditsWin.on("closed", () => { creditsWin = null; });
}

// ── 화면에서 오는 말 처리 (맥판 Bridge와 같은 이름) ──
ipcMain.on("tm", (_e, b) => {
  if (!b || !win) return;
  switch (b.type) {
    case "onTop": onTop = !!b.on; applyTop(); break;
    case "compact": setCompact(!!b.on); break;
    case "fitHeight": fitHeight(b.h); break;
    case "alarm": scheduleAlarm(b.at, b.ticks); break;
    case "needKey": needKey(); break;
    case "releaseKey": releaseKey(); break;
    case "startDrag": break;   // 윈도우에서는 빈 곳 끌기를 CSS(app-region)로 처리해요
    case "busy":
      if (b.on && blocker == null) blocker = powerSaveBlocker.start("prevent-app-suspension");
      else if (!b.on && blocker != null) { powerSaveBlocker.stop(blocker); blocker = null; }
      break;
    case "badge":   // 맥의 Dock 숫자 대신: 알림 영역 아이콘에 남은 시간을 보여 줘요
      if (tray) tray.setToolTip(b.text ? `타이머 · ${b.text}` : "타이머");
      win.setTitle(b.text ? `${b.text} · 타이머` : "타이머");
      break;
    case "finish":
      if (win.isMinimized()) win.restore();
      if (!win.isVisible()) win.showInactive();
      win.flashFrame(true);
      break;
    case "credits": showCredits(b.vol ?? 0.6); break;
    // play / volume / stopSound: 맥 기본 소리 전용이라 윈도우에서는 쓰지 않아요 (목록에서도 숨겨요)
  }
});
ipcMain.on("version", e => { e.returnValue = app.getVersion(); });
ipcMain.on("win", (_e, what) => {
  if (!win) return;
  if (what === "close") app.quit();
  else if (what === "minimize") win.minimize();
});
ipcMain.on("credits-close", () => { if (creditsWin) creditsWin.close(); });

// ── 알림 영역(시계 옆) 아이콘: 창 보이기 · 종료 ──
function createTray() {
  const img = nativeImage.createFromPath(path.join(__dirname, "icon.png")).resize({ width: 16, height: 16 });
  tray = new Tray(img);
  tray.setToolTip("타이머");
  const show = () => { if (!win) return; if (win.isMinimized()) win.restore(); win.showInactive(); };
  tray.on("click", show);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "타이머 보기", click: show },
    { type: "separator" },
    { label: "종료", click: () => app.quit() },
  ]));
}

app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.showInactive(); } });
app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  createWindow();
  createTray();
});
app.on("before-quit", () => {
  if (win && normalBounds) saveState({ bounds: normalBounds });
  else if (win && sheetBounds) saveState({ bounds: sheetBounds });
});
app.on("window-all-closed", () => app.quit());
