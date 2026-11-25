import Cocoa
import WebKit

// 타이머 — 작은 맥용 타이머 앱
// 화면은 index.html(웹)로 그리고, 창 고정·알람·소리 같은 맥 기능은 여기서 맡아요.

/// 패널 창: 압정(항상 위에)을 켜면 다른 앱의 전체 화면 위에도 뜰 수 있어요.
final class MainPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        hidesOnDeactivate = false
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // 패널은 기본으로 Esc를 누르면 창이 닫혀요. Esc는 화면(설정 닫기·알람 끄기)에서 쓰도록 막아요.
    override func cancelOperation(_ sender: Any?) {}
}

/// 창 위쪽 띠: 여기를 끌면 창이 움직여요(오른쪽 버튼 자리는 비워 둬요).
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    weak var web: WKWebView?
    override func mouseDown(with event: NSEvent) {
        web?.evaluateJavaScript("window.__closeSheet && window.__closeSheet()")
        window?.performDrag(with: event)
    }
}

/// 창이 비활성일 때도 첫 클릭이 바로 버튼에 먹히게 해요.
final class ClickWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Bridge: NSObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    weak var window: NSWindow?
    private var onTop = false
    private var alarm: Timer?
    private var tickTimers: [Timer] = []
    private var activity: NSObjectProtocol?
    private var sound: NSSound?
    private var normalFrame: NSRect?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let type = b["type"] as? String else { return }
        switch type {
        case "onTop":
            onTop = b["on"] as? Bool ?? false
            applyTopLevel()
        case "fitHeight":
            fitHeight(b["h"] as? Double)
        case "compact":
            setCompact(b["on"] as? Bool ?? false)
        case "alarm":
            scheduleAlarm(at: b["at"] as? Double, ticks: b["ticks"] as? [Double] ?? [])
        case "busy":
            setBusy(b["on"] as? Bool ?? false)
        case "badge":
            NSApp.dockTile.badgeLabel = b["text"] as? String
        case "play":
            play(b["name"] as? String ?? "Glass", loop: b["loop"] as? Bool ?? false, volume: Float(b["vol"] as? Double ?? 1))
        case "volume":
            sound?.volume = Float(max(0, min(1, b["vol"] as? Double ?? 0)))
        case "stopSound":
            sound?.stop(); sound = nil
        case "finish":
            NSApp.requestUserAttention(.criticalRequest)
            NSApp.dockTile.badgeLabel = "!"
            if let w = window {
                if w.isMiniaturized { w.deminiaturize(nil) }
                if !w.isVisible { w.orderFrontRegardless() }
            }
        default: break
        }
    }

    /// 압정 켜면 모든 데스크탑·전체 화면 위에 떠 있고, 끄면 보통 창이에요.
    func applyTopLevel() {
        guard let w = window else { return }
        if onTop {
            w.styleMask.insert(.nonactivatingPanel)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.level = .floating
            if w.isVisible { w.orderFrontRegardless() }
        } else {
            w.styleMask.remove(.nonactivatingPanel)
            w.collectionBehavior = []
            w.level = .normal
        }
    }

    /// 간소화: 화면 오른쪽 위 작은 창으로 줄이고, 다시 누르면 원래대로.
    func setCompact(_ on: Bool) {
        guard let w = window else { return }
        if on {
            guard normalFrame == nil else { return }
            normalFrame = w.frame
            w.contentMinSize = NSSize(width: 240, height: 110)
            w.styleMask.remove(.resizable)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { w.standardWindowButton($0)?.isHidden = true }
            let size = NSSize(width: 310, height: 120)
            let vf = (w.screen ?? NSScreen.main)?.visibleFrame ?? w.frame
            var origin = NSPoint(x: vf.maxX - size.width - 20, y: vf.maxY - size.height - 20)
            if let a = UserDefaults.standard.array(forKey: "compactOrigin") as? [Double], a.count == 2 {
                let r = NSRect(x: a[0], y: a[1], width: size.width, height: size.height)
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r.insetBy(dx: 40, dy: 40)) }) { origin = r.origin }
            }
            w.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
        } else {
            guard let nf = normalFrame else { return }
            UserDefaults.standard.set([Double(w.frame.minX), Double(w.frame.minY)], forKey: "compactOrigin")
            normalFrame = nil
            w.styleMask.insert(.resizable)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { w.standardWindowButton($0)?.isHidden = false }
            w.contentMinSize = NSSize(width: 360, height: 300)
            w.setFrame(nf, display: true, animate: true)
        }
        applyTopLevel()
    }

    var restoreFrame: NSRect? { normalFrame ?? sheetFrame }

    /// 설정 창이 다 보이도록 창을 잠깐 아래로 늘렸다가, 닫으면 원래 크기로 돌려요.
    private var sheetFrame: NSRect?
    func fitHeight(_ h: Double?) {
        guard let w = window, normalFrame == nil else { return }
        if let h = h {
            let cur = w.contentRect(forFrameRect: w.frame).height
            guard CGFloat(h) > cur else { return }
            if sheetFrame == nil { sheetFrame = w.frame }
            var f = w.frame
            let extra = CGFloat(h) - cur
            f.origin.y -= extra; f.size.height += extra
            if let vf = (w.screen ?? NSScreen.main)?.visibleFrame, f.minY < vf.minY {   // 화면 아래로 넘치면 위로 올려요
                f.origin.y = vf.minY
                f.size.height = min(f.size.height, vf.height)
            }
            w.setFrame(f, display: true, animate: true)
        } else if let sf = sheetFrame {
            sheetFrame = nil
            w.setFrame(sf, display: true, animate: true)
        }
    }

    /// 창이 가려져 있어도 정확한 시각에 화면에 "끝났어요"를 알려요.
    private func scheduleAlarm(at ms: Double?, ticks: [Double]) {
        alarm?.invalidate(); alarm = nil
        tickTimers.forEach { $0.invalidate() }; tickTimers = []
        guard let ms = ms else { return }
        alarm = fire(at: ms, js: "window.__nativeAlarm && window.__nativeAlarm()")
        // 마지막 5초 소리도 창이 가려져 있을 때 늦지 않게 깨워요.
        tickTimers = ticks.map { fire(at: $0 + 20, js: "window.__nativeTick && window.__nativeTick()") }
    }

    private func fire(at ms: Double, js: String) -> Timer {
        let t = Timer(fire: Date(timeIntervalSince1970: ms / 1000), interval: 0, repeats: false) { [weak self] _ in
            self?.web?.evaluateJavaScript(js)
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    /// 타이머가 도는 동안 macOS가 앱을 재우지 않게 해요.
    private func setBusy(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "타이머 진행 중")
        } else if !on, let a = activity {
            ProcessInfo.processInfo.endActivity(a); activity = nil
        }
    }

    private func play(_ name: String, loop: Bool, volume: Float) {
        sound?.stop()
        guard let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.loops = loop
        s.volume = volume
        s.play()
        sound = s
    }

    func stopAll() { sound?.stop(); setBusy(false) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    let bridge = Bridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(bridge, name: "tm")
        config.userContentController.addUserScript(WKUserScript(source: "window.__NATIVE__ = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let web = ClickWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        window = MainPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        window.title = "타이머"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 360, height: 300)

        let root = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.appearance = NSAppearance(named: .vibrantDark)
        web.frame = root.bounds
        root.addSubview(web)
        let strip = DragStrip(frame: NSRect(x: 0, y: root.bounds.height - 26, width: root.bounds.width - 130, height: 26))
        strip.autoresizingMask = [.width, .minYMargin]
        strip.web = web
        root.addSubview(strip)
        window.contentView = root

        window.center()
        window.setFrameAutosaveName("TimerMain2")
        // 작게 보기 상태에서 강제 종료됐으면 작은 크기가 저장돼 있어요. 켤 때는 항상 보통 크기로.
        let f = window.frame
        if f.width < 360 || f.height < 300 {
            window.setFrame(NSRect(x: f.minX, y: f.maxY - 320, width: 400, height: 320), display: false)
        }
        bridge.web = web
        bridge.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 화면을 그리는 프로세스가 죽으면 빈 창이 되니 다시 불러와요.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        bridge.setCompact(false)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.dockTile.badgeLabel == "!" { NSApp.dockTile.badgeLabel = nil }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
    @objc func showMainWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        NSApp.dockTile.badgeLabel = nil
        if let nf = bridge.restoreFrame { window.setFrame(nf, display: false) }
        bridge.stopAll()
    }
}

func buildMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "타이머에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "타이머 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "타이머 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem(); main.addItem(editItem)
    let edit = NSMenu(title: "편집")
    edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit

    let winItem = NSMenuItem(); main.addItem(winItem)
    let win = NSMenu(title: "윈도우")
    win.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    win.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    win.addItem(.separator())
    win.addItem(withTitle: "타이머 창 보기", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "0")
    winItem.submenu = win
    return main
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = buildMenu()
app.run()
