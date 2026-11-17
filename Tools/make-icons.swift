// Draws the app icon and the Markdown document icon and writes them as .icns.
// Usage: swift Tools/make-icons.swift <output dir>
//
// The glyph is the Markdown Mark by Dustin Curtis (public domain, CC0):
// https://github.com/dcurtis/markdown-mark

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// The "M↓" glyph from the Markdown Mark, in its 208×128 design space (y down).
func markGlyph() -> CGPath {
    let p = CGMutablePath()
    // M
    p.move(to: CGPoint(x: 30, y: 98)); p.addLine(to: CGPoint(x: 30, y: 30)); p.addLine(to: CGPoint(x: 50, y: 30))
    p.addLine(to: CGPoint(x: 70, y: 55)); p.addLine(to: CGPoint(x: 90, y: 30)); p.addLine(to: CGPoint(x: 110, y: 30))
    p.addLine(to: CGPoint(x: 110, y: 98)); p.addLine(to: CGPoint(x: 90, y: 98)); p.addLine(to: CGPoint(x: 90, y: 59))
    p.addLine(to: CGPoint(x: 70, y: 84)); p.addLine(to: CGPoint(x: 50, y: 59)); p.addLine(to: CGPoint(x: 50, y: 98))
    p.closeSubpath()
    // ↓
    p.move(to: CGPoint(x: 155, y: 98)); p.addLine(to: CGPoint(x: 125, y: 65)); p.addLine(to: CGPoint(x: 145, y: 65))
    p.addLine(to: CGPoint(x: 145, y: 30)); p.addLine(to: CGPoint(x: 165, y: 30)); p.addLine(to: CGPoint(x: 165, y: 65))
    p.addLine(to: CGPoint(x: 185, y: 65)); p.closeSubpath()
    return p
}

/// Draws the full mark (rounded frame + glyph) centred at `center`, `width` wide.
func drawMark(_ ctx: CGContext, center: CGPoint, width: CGFloat, color fill: CGColor, frame: Bool = true) {
    let scale = width / 208
    ctx.saveGState()
    ctx.translateBy(x: center.x - width / 2, y: center.y + 64 * scale)
    ctx.scaleBy(x: scale, y: -scale) // design space is y-down
    ctx.setFillColor(fill)
    if frame {
        let outer = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 208, height: 128), cornerWidth: 15, cornerHeight: 15, transform: nil)
        let inner = CGPath(roundedRect: CGRect(x: 10, y: 10, width: 188, height: 108), cornerWidth: 6, cornerHeight: 6, transform: nil)
        let ring = CGMutablePath()
        ring.addPath(outer); ring.addPath(inner)
        ctx.addPath(ring)
        ctx.fillPath(using: .evenOdd)
    }
    ctx.addPath(markGlyph())
    ctx.fillPath()
    ctx.restoreGState()
}

/// macOS app icon: rounded-square body on the 1024 grid with a blue gradient and the white mark.
func drawAppIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x1d4ed8)); ctx.fillPath()
    ctx.restoreGState()

    // Body gradient
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x60a5fa), color(0x2563eb), color(0x1e3a8a)] as CFArray,
                              locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft highlight on the upper half
    let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xffffff, 0.22), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Inner edge
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(color(0xffffff, 0.25)); ctx.setLineWidth(4); ctx.strokePath()
    ctx.restoreGState()

    // Mark with a subtle shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x0b1f5c, 0.45))
    drawMark(ctx, center: CGPoint(x: 512, y: 512), width: 600, color: color(0xffffff))
    ctx.restoreGState()
}

/// Document icon: white page with a folded corner and the blue mark.
func drawDocumentIcon(_ ctx: CGContext) {
    let page = CGRect(x: 172, y: 64, width: 680, height: 896)
    let fold: CGFloat = 200
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: page.minX + 28, y: page.minY))
    outline.addLine(to: CGPoint(x: page.maxX - 28, y: page.minY))
    outline.addQuadCurve(to: CGPoint(x: page.maxX, y: page.minY + 28), control: CGPoint(x: page.maxX, y: page.minY))
    outline.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    outline.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    outline.addLine(to: CGPoint(x: page.minX + 28, y: page.maxY))
    outline.addQuadCurve(to: CGPoint(x: page.minX, y: page.maxY - 28), control: CGPoint(x: page.minX, y: page.maxY))
    outline.addLine(to: CGPoint(x: page.minX, y: page.minY + 28))
    outline.addQuadCurve(to: CGPoint(x: page.minX + 28, y: page.minY), control: CGPoint(x: page.minX, y: page.minY))
    outline.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0x000000, 0.28))
    ctx.addPath(outline); ctx.setFillColor(color(0xffffff)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(outline); ctx.clip()
    let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xffffff), color(0xeef2f7)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 512, y: page.maxY), end: CGPoint(x: 512, y: page.minY), options: [])
    // Blue band at the bottom, like a label
    ctx.setFillColor(color(0x2563eb))
    ctx.fill(CGRect(x: page.minX, y: page.minY, width: page.width, height: 150))
    ctx.restoreGState()

    ctx.addPath(outline); ctx.setStrokeColor(color(0x94a3b8, 0.8)); ctx.setLineWidth(4); ctx.strokePath()

    // Folded corner
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    corner.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold + 24))
    corner.addQuadCurve(to: CGPoint(x: page.maxX - fold + 24, y: page.maxY - fold), control: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    corner.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: -4), blur: 10, color: color(0x000000, 0.18))
    ctx.addPath(corner); ctx.setFillColor(color(0xdbe3ee)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(corner); ctx.setStrokeColor(color(0x94a3b8, 0.8)); ctx.setLineWidth(4); ctx.strokePath()

    drawMark(ctx, center: CGPoint(x: 512, y: 560), width: 470, color: color(0x1e3a8a))

    // "MD" on the band
    let text = NSAttributedString(string: "MD", attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: 6,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: 512 - bounds.width / 2 - bounds.minX, y: page.minY + 75 - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

func writeIcns(_ name: String, draw: (CGContext) -> Void) throws {
    let iconset = outDir.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
            ctx.interpolationQuality = .high
            draw(ctx)
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            let file = iconset.appendingPathComponent(scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png")
            try rep.representation(using: .png, properties: [:])!.write(to: file)
        }
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("\(name).icns").path]
    try task.run()
    task.waitUntilExit()
    // Keep the 1024 px PNG for the README, drop the rest
    try? FileManager.default.removeItem(at: outDir.appendingPathComponent("\(name).png"))
    try FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_512x512@2x.png"),
                                     to: outDir.appendingPathComponent("\(name).png"))
    try FileManager.default.removeItem(at: iconset)
    print("wrote \(name).icns")
}

try writeIcns("AppIcon", draw: drawAppIcon)
try writeIcns("MarkdownDocument", draw: drawDocumentIcon)
