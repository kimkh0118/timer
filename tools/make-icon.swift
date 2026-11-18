// 앱 아이콘 만들기: swift tools/make-icon.swift → app/AppIcon.icns
import Cocoa

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 0.1, r = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    // 바탕: 빨간 둥근 사각형
    NSColor(red: 0.88, green: 0.15, blue: 0.17, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225).fill()
    // 흰 원 테두리 + 남은 시간 부채꼴
    let c = NSPoint(x: s / 2, y: s / 2), rad = r.width * 0.32
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let ring = NSBezierPath(); ring.appendArc(withCenter: c, radius: rad, startAngle: 0, endAngle: 360); ring.lineWidth = r.width * 0.07; ring.stroke()
    NSColor.white.setFill()
    let pie = NSBezierPath(); pie.move(to: c)
    pie.appendArc(withCenter: c, radius: rad * 0.78, startAngle: 90, endAngle: -30, clockwise: true); pie.close(); pie.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set); try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "app/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ app/AppIcon.icns" : "iconutil 실패")
