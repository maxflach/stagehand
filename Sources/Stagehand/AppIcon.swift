import AppKit

/// Draws the app icon in code so the repo needs no image files. `build.sh` calls `--write-icon <dir>`.
enum AppIcon {
    static func draw(in rect: CGRect, context ctx: CGContext) {
        let s = rect.width
        let inset = s * 0.1
        let body = rect.insetBy(dx: inset, dy: inset)
        let radius = body.width * 0.225
        let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Dark stage background
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bg = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.20, green: 0.16, blue: 0.40, alpha: 1),
            CGColor(red: 0.05, green: 0.04, blue: 0.12, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

        // Light beam from the top
        let top = CGPoint(x: body.midX, y: body.maxY + s * 0.02)
        let floorY = body.minY + body.height * 0.22
        let beam = CGMutablePath()
        beam.move(to: CGPoint(x: top.x - s * 0.05, y: top.y))
        beam.addLine(to: CGPoint(x: top.x + s * 0.05, y: top.y))
        beam.addLine(to: CGPoint(x: body.midX + body.width * 0.34, y: floorY))
        beam.addLine(to: CGPoint(x: body.midX - body.width * 0.34, y: floorY))
        beam.closeSubpath()
        ctx.saveGState()
        ctx.addPath(beam)
        ctx.clip()
        let light = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 0.75),
            CGColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 0.12),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(light, start: top, end: CGPoint(x: body.midX, y: floorY), options: [])
        ctx.restoreGState()

        // Pool of light on the floor
        let pool = CGRect(x: body.midX - body.width * 0.36, y: floorY - body.height * 0.07,
                          width: body.width * 0.72, height: body.height * 0.14)
        ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.55))
        ctx.fillEllipse(in: pool)

        // A screen standing in the light
        let screen = CGRect(x: body.midX - body.width * 0.2, y: floorY + body.height * 0.02,
                            width: body.width * 0.4, height: body.width * 0.27)
        let screenPath = CGPath(roundedRect: screen, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
        ctx.addPath(screenPath)
        ctx.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1))
        ctx.fillPath()
        let pane = screen.insetBy(dx: screen.width * 0.09, dy: screen.height * 0.13)
        ctx.setFillColor(CGColor(red: 0.30, green: 0.26, blue: 0.62, alpha: 1))
        ctx.fill(CGRect(x: pane.minX, y: pane.minY, width: pane.width * 0.62, height: pane.height))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1))
        ctx.fill(CGRect(x: pane.minX + pane.width * 0.68, y: pane.minY, width: pane.width * 0.32, height: pane.height))
        ctx.restoreGState()
    }

    static func writeIconset(to dir: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for base in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let px = base * scale
                    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                          let gc = NSGraphicsContext(bitmapImageRep: rep) else { return false }
                    draw(in: CGRect(x: 0, y: 0, width: px, height: px), context: gc.cgContext)
                    gc.flushGraphics()
                    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                    try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                }
            }
            return true
        } catch {
            return false
        }
    }
}
