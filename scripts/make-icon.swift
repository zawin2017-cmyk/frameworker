// Renders the app icon (dark plate, three glass tiles) at every size macOS wants and packs it into an .icns.
// Usage: swiftc -O scripts/make-icon.swift -o build/make-icon && build/make-icon build/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = NSTemporaryDirectory() + "Frameworker-\(ProcessInfo.processInfo.processIdentifier).iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func draw(size s: CGFloat) {
    let plate = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.09, dy: s * 0.09)
    let plateRadius = plate.width * 0.225
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.21, green: 0.23, blue: 0.31, alpha: 1),
               ending: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1))!
        .draw(in: platePath, angle: -90)
    NSColor.white.withAlphaComponent(0.14).setStroke()
    platePath.lineWidth = max(1, s * 0.006)
    platePath.stroke()

    let area = plate.insetBy(dx: plate.width * 0.17, dy: plate.width * 0.17)
    let gap = plate.width * 0.045
    let columnWidth = (area.width - gap) / 2
    let rowHeight = (area.height - gap) / 2
    let tileRadius = plate.width * 0.06

    func tile(_ rect: NSRect, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: tileRadius, yRadius: tileRadius)
        NSGradient(starting: NSColor.white.withAlphaComponent(alpha * 0.7),
                   ending: NSColor.white.withAlphaComponent(alpha))!
            .draw(in: path, angle: 90)
        NSColor.white.withAlphaComponent(min(1, alpha + 0.2)).setStroke()
        path.lineWidth = max(1, s * 0.005)
        path.stroke()
    }

    tile(NSRect(x: area.minX, y: area.minY, width: columnWidth, height: area.height), alpha: 0.88)
    tile(NSRect(x: area.minX + columnWidth + gap, y: area.minY + rowHeight + gap, width: columnWidth, height: rowHeight), alpha: 0.58)
    tile(NSRect(x: area.minX + columnWidth + gap, y: area.minY, width: columnWidth, height: rowHeight), alpha: 0.36)
}

func render(pixels: Int, name: String) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
for (name, pixels) in sizes { try render(pixels: pixels, name: name) }

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
exit(iconutil.terminationStatus)
