// Draws the DocShot DMG window background in Quiet's light canvas: an arrow from the app
// to the Applications folder and one line saying what to do. Writes a 1x and a 2x PNG.
// Usage: swift make-background.swift <output folder>
import AppKit

let size = NSSize(width: 600, height: 380)
let canvas = NSColor(srgbRed: 0xFA / 255, green: 0xF9 / 255, blue: 0xF7 / 255, alpha: 1)
let inkMuted = NSColor(srgbRed: 0x5F / 255, green: 0x5B / 255, blue: 0x55 / 255, alpha: 1)
let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func draw() {
    canvas.setFill()
    NSRect(origin: .zero, size: size).fill()

    // The arrow, between the two icons (Finder places them at y = 180 from the top).
    let y = size.height - 180
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 248, y: y))
    arrow.line(to: NSPoint(x: 352, y: y))
    arrow.move(to: NSPoint(x: 340, y: y + 10))
    arrow.line(to: NSPoint(x: 352, y: y))
    arrow.line(to: NSPoint(x: 340, y: y - 10))
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    inkMuted.withAlphaComponent(0.55).setStroke()
    arrow.stroke()

    let line = "Drag DocShot into Applications" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: inkMuted,
    ]
    let textSize = line.size(withAttributes: attributes)
    line.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 48), withAttributes: attributes)
}

for scale in [1, 2] {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
