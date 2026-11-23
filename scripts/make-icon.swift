// Renders Resources/AppIcon.icns: a taskbar line with a small bloom above it.
// Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt body centred in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!
        .draw(in: squircle, angle: -90)

    // The bar.
    NSColor(white: 1, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: 252 * s, y: 300 * s, width: 520 * s, height: 44 * s),
                 xRadius: 22 * s, yRadius: 22 * s).fill()

    // The bloom: four soft petals around a centre.
    let c = NSPoint(x: 512 * s, y: 560 * s)
    let accent = NSColor(calibratedRed: 0.38, green: 0.70, blue: 1.0, alpha: 1)
    accent.withAlphaComponent(0.55).setFill()
    let r: CGFloat = 70 * s, d: CGFloat = 66 * s
    for (dx, dy) in [(0, d), (0, -d), (d, 0), (-d, 0)] as [(CGFloat, CGFloat)] {
        NSBezierPath(ovalIn: NSRect(x: c.x + dx - r, y: c.y + dy - r, width: 2 * r, height: 2 * r)).fill()
    }
    NSColor.white.setFill()
    let core: CGFloat = 34 * s
    NSBezierPath(ovalIn: NSRect(x: c.x - core, y: c.y - core, width: 2 * core, height: 2 * core)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! render(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! render(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
