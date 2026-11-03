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
}

/// 창 위쪽 띠: 여기를 끌면 창이 움직여요(오른쪽 버튼 자리는 비워 둬요).
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class Bridge: NSObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    weak var window: NSWindow?
    private var onTop = false
    private var alarm: Timer?
    private var activity: NSObjectProtocol?
    private var sound: NSSound?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let type = b["type"] as? String else { return }
        switch type {
        case "onTop":
            onTop = b["on"] as? Bool ?? false
            applyTopLevel()
        case "alarm":
            scheduleAlarm(at: b["at"] as? Double)
        case "busy":
            setBusy(b["on"] as? Bool ?? false)
        case "badge":
            NSApp.dockTile.badgeLabel = b["text"] as? String
        case "play":
            play(b["name"] as? String ?? "Glass", loop: b["loop"] as? Bool ?? false)
        case "stopSound":
            sound?.stop(); sound = nil
        case "finish":
            NSApp.requestUserAttention(.criticalRequest)
            NSApp.dockTile.badgeLabel = "!"
            if let w = window, !w.isVisible { w.orderFrontRegardless() }
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

    /// 창이 가려져 있어도 정확한 시각에 화면에 "끝났어요"를 알려요.
    private func scheduleAlarm(at ms: Double?) {
        alarm?.invalidate(); alarm = nil
        guard let ms = ms else { return }
        let t = Timer(fire: Date(timeIntervalSince1970: ms / 1000), interval: 0, repeats: false) { [weak self] _ in
            self?.web?.evaluateJavaScript("window.__nativeAlarm && window.__nativeAlarm()")
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        alarm = t
    }

    /// 타이머가 도는 동안 macOS가 앱을 재우지 않게 해요.
    private func setBusy(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "타이머 진행 중")
        } else if !on, let a = activity {
            ProcessInfo.processInfo.endActivity(a); activity = nil
        }
    }

    private func play(_ name: String, loop: Bool) {
        sound?.stop()
        guard let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.loops = loop
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
        config.userContentController.add(bridge, name: "tm")
        config.userContentController.addUserScript(WKUserScript(source: "window.__NATIVE__ = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        window = MainPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                           styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        window.title = "타이머"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 420, height: 180))

        let root = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.appearance = NSAppearance(named: .vibrantDark)
        web.frame = root.bounds
        root.addSubview(web)
        let strip = DragStrip(frame: NSRect(x: 0, y: root.bounds.height - 16, width: root.bounds.width, height: 16))
        strip.autoresizingMask = [.width, .minYMargin]
        root.addSubview(strip)
        window.contentView = root

        window.center()
        window.setFrameAutosaveName("TimerSmall")
        bridge.web = web
        bridge.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        bridge.stopAll()
    }
}

func buildMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "타이머 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "타이머 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem(); main.addItem(editItem)
    let edit = NSMenu(title: "편집")
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
