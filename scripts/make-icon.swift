// Draws the app icon as vector art and writes Resources/AppIcon.icns plus docs/icon.png.
// Usage: swift scripts/make-icon.swift   (from the repository root)
import AppKit

let canvas: CGFloat = 1024
let bladeCount = 7

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// One blade in fan coordinates (hub at the origin, pointing up), sized for a 1024 canvas.
func bladePath() -> NSBezierPath {
    let path = NSBezierPath()
    // Narrow at the root, wide and blunt at the tip, swept clockwise: reads as a fan, not a flower.
    path.move(to: NSPoint(x: -14, y: 78))
    path.curve(to: NSPoint(x: 40, y: 306), controlPoint1: NSPoint(x: -58, y: 170), controlPoint2: NSPoint(x: -30, y: 270))
    path.curve(to: NSPoint(x: 176, y: 252), controlPoint1: NSPoint(x: 100, y: 318), controlPoint2: NSPoint(x: 150, y: 296))
    path.curve(to: NSPoint(x: 36, y: 68), controlPoint1: NSPoint(x: 160, y: 168), controlPoint2: NSPoint(x: 92, y: 96))
    path.close()
    return path
}

func drawIcon(in context: CGContext) {
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Drop shadow under the tile, as on standard macOS icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35).cgColor)
    color(0x0F1A2E).setFill()
    tilePath.fill()
    context.restoreGState()

    // Background: deep navy, slightly lighter at the top.
    NSGradient(starting: color(0x24375E), ending: color(0x0B1324))!.draw(in: tilePath, angle: -90)

    let center = NSPoint(x: 512, y: 512)

    // Shroud ring, cool at the top and warm at the bottom: the fan sits between "cold" and "hot".
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 343, y: center.y - 343, width: 686, height: 686))
    ring.append(NSBezierPath(ovalIn: NSRect(x: center.x - 317, y: center.y - 317, width: 634, height: 634)).reversed)
    context.saveGState()
    ring.addClip()
    NSGradient(colors: [color(0xFF6B3D), color(0xFFB13B), color(0x4FC3F7), color(0x2F80ED)])!
        .draw(in: NSRect(x: center.x - 343, y: center.y - 343, width: 686, height: 686), angle: 90)
    context.restoreGState()

    // Seven swept blades with a soft white-to-ice gradient.
    for index in 0..<bladeCount {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -CGFloat(index) * 2 * .pi / CGFloat(bladeCount))
        context.scaleBy(x: 0.9, y: 0.9)  // leave a gap between the blade tips and the ring
        let blade = bladePath()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x000000, 0.35).cgColor)
        color(0xE8F1FF).setFill()
        blade.fill()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        NSGradient(starting: color(0xFFFFFF), ending: color(0xB9D3F5))!.draw(in: blade, angle: -60)
        context.restoreGState()
    }

    // Hub: a warm core, like the temperature the fan is fighting.
    let hubRect = NSRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0x000000, 0.4).cgColor)
    color(0x1A2744).setFill()
    NSBezierPath(ovalIn: hubRect).fill()
    context.restoreGState()
    NSGradient(starting: color(0xFFB13B), ending: color(0xFF5A36))!
        .draw(in: NSBezierPath(ovalIn: hubRect.insetBy(dx: 22, dy: 22)), relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try! render(pixels: 512).write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
