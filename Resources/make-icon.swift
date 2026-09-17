// Draws the app icon and writes Resources/AppIcon.icns.
//
//   swiftc -O Resources/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
//
// A blue macOS tile holding three checklist rows, the first two ticked, so
// the Finder icon reads the same as the boxes in the popover. Everything is
// drawn with AppKit at each pixel size the .icns needs, so small sizes stay
// crisp instead of being a blurry downsample of the 1024 one.

import AppKit

let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
let icns = resources.appendingPathComponent("AppIcon.icns")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Draws the icon into a unit square of `s` points (origin bottom-left).
/// Coordinates below are for a 1024-point canvas and scaled down.
func draw(size s: CGFloat) {
    let k = s / 1024
    func p(_ v: CGFloat) -> CGFloat { v * k }

    // Apple's macOS icon grid: the tile fills 824 of 1024 points, leaving a
    // transparent margin so the shadow and neighbours have room.
    let tile = NSRect(x: p(100), y: p(100), width: p(824), height: p(824))
    let radius = p(184)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // Soft shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -p(12))
    shadow.shadowBlurRadius = p(28)
    shadow.set()
    rgb(30, 110, 235).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Blue gradient, lighter at the top, close to the system accent blue.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [rgb(92, 176, 255), rgb(24, 118, 240), rgb(10, 88, 214)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -90)

    // A faint highlight fading in towards the top edge gives the tile some
    // glass. It spans the whole tile so there is no seam where it stops.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0),
                        NSColor.white.withAlphaComponent(0.2)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Rows: a box on the left, a text bar on the right. At 16 and 32 pixels
    // three rows turn to mush, so the small sizes get two bigger ones.
    let small = s <= 32
    let box = p(small ? 190 : 124)
    let boxRadius = p(small ? 44 : 30)
    let stroke = p(small ? 40 : 22)
    let barHeight = p(small ? 84 : 52)
    let left = p(small ? 168 : 178)
    let rightEdge = p(846)
    let gap = p(small ? 64 : 58)
    let rows: [(y: CGFloat, done: Bool, barEnd: CGFloat)] = small ? [
        (p(646), true,  rightEdge),
        (p(378), false, p(760)),
    ] : [
        (p(682), true,  rightEdge),
        (p(512), true,  p(720)),
        (p(342), false, p(800)),
    ]

    for row in rows {
        let boxRect = NSRect(x: left, y: row.y - box / 2, width: box, height: box)
        let boxPath = NSBezierPath(roundedRect: boxRect.insetBy(dx: stroke / 2, dy: stroke / 2),
                                   xRadius: boxRadius - stroke / 2, yRadius: boxRadius - stroke / 2)
        boxPath.lineWidth = stroke
        boxPath.lineJoinStyle = .round

        if row.done {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: boxRect, xRadius: boxRadius, yRadius: boxRadius).fill()

            // Checkmark in the tile's blue, same proportions as the popover's.
            let check = NSBezierPath()
            check.lineWidth = p(small ? 40 : 24)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            let x = boxRect.minX, y = boxRect.minY, w = boxRect.width, h = boxRect.height
            check.move(to: NSPoint(x: x + w * 0.27, y: y + h * 0.50))
            check.line(to: NSPoint(x: x + w * 0.44, y: y + h * 0.32))
            check.line(to: NSPoint(x: x + w * 0.75, y: y + h * 0.68))
            rgb(18, 104, 228).setStroke()
            check.stroke()
        } else {
            NSColor.white.withAlphaComponent(0.92).setStroke()
            boxPath.stroke()
        }

        let barX = boxRect.maxX + gap
        let bar = NSRect(x: barX, y: row.y - barHeight / 2, width: row.barEnd - barX, height: barHeight)
        NSColor.white.withAlphaComponent(row.done ? 0.62 : 0.92).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.cgContext.setShouldAntialias(true)
    draw(size: CGFloat(pixels))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try render(pixels: pixels).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
try fm.removeItem(at: iconset)
print("Wrote \(icns.path)")
