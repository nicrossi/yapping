import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: iconsmith <output-dir>
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let violet = CGColor(red: 0x7C/255, green: 0x5C/255, blue: 1.0, alpha: 1)
let pink   = CGColor(red: 1.0, green: 0x5C/255, blue: 0xA8/255, alpha: 1)
let deep   = CGColor(red: 0x4B/255, green: 0x2E/255, blue: 0xD6/255, alpha: 1)

func context(_ px: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func write(_ ctx: CGContext, _ name: String) {
    let img = ctx.makeImage()!
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func barPath(in rect: CGRect, count: Int, heights: [CGFloat], barW: CGFloat, gap: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let total = CGFloat(count) * barW + CGFloat(count - 1) * gap
    var x = rect.midX - total / 2
    for i in 0..<count {
        let h = rect.height * heights[i]
        let r = CGRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
        p.addRoundedRect(in: r, cornerWidth: barW / 2, cornerHeight: barW / 2)
        x += barW + gap
    }
    return p
}

// MARK: App icon (1024 canvas, 824 squircle per Apple's macOS grid)
func appIcon(_ px: Int) {
    let ctx = context(px)
    let s = CGFloat(px) / 1024
    let size = 824 * s
    let inset = (CGFloat(px) - size) / 2
    let shape = CGRect(x: inset, y: inset, width: size, height: size)
    let radius = 186 * s
    let squircle = CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow like system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(squircle); ctx.setFillColor(deep); ctx.fillPath()
    ctx.restoreGState()

    // Gradient body.
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [violet, pink] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: shape.minX, y: shape.maxY),
                           end: CGPoint(x: shape.maxX, y: shape.minY), options: [])
    // Top-left light.
    let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: shape.minX + size * 0.25, y: shape.maxY - size * 0.15), startRadius: 0,
                           endCenter: CGPoint(x: shape.minX + size * 0.25, y: shape.maxY - size * 0.15), endRadius: size * 0.9, options: [])
    // Bottom vignette for depth.
    let vig = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.18)] as CFArray, locations: [0.55, 1])!
    ctx.drawLinearGradient(vig, start: CGPoint(x: 0, y: shape.maxY), end: CGPoint(x: 0, y: shape.minY), options: [])
    ctx.restoreGState()

    // Glass rim: inner hairline.
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    ctx.addPath(CGPath(roundedRect: shape.insetBy(dx: 1.5 * s, dy: 1.5 * s), cornerWidth: radius - 1.5 * s, cornerHeight: radius - 1.5 * s, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35)); ctx.setLineWidth(3 * s); ctx.strokePath()
    ctx.restoreGState()

    // Waveform: 5 bars.
    let wave = shape.insetBy(dx: size * 0.22, dy: size * 0.26)
    let bars = barPath(in: wave, count: 5, heights: [0.34, 0.62, 1.0, 0.62, 0.34], barW: size * 0.075, gap: size * 0.052)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 18 * s, color: CGColor(gray: 0, alpha: 0.22))
    ctx.addPath(bars); ctx.setFillColor(CGColor(gray: 1, alpha: 0.96)); ctx.fillPath()
    ctx.restoreGState()
    // Glass sheen across bars: upper half slightly brighter.
    ctx.saveGState(); ctx.addPath(bars); ctx.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [CGColor(gray: 1, alpha: 0.0), CGColor(red: 0.98, green: 0.93, blue: 1, alpha: 0.35)] as CFArray, locations: [0.5, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: wave.minY), end: CGPoint(x: 0, y: wave.maxY), options: [])
    ctx.restoreGState()

    write(ctx, "icon_\(px).png")
}

// MARK: Menu bar template glyph (black, alpha only). pt = 18, scale 1x/2x.
func menuGlyph(scale: Int, filled: Bool, name: String) {
    let pt: CGFloat = 18
    let px = Int(pt) * scale
    let ctx = context(px)
    let s = CGFloat(scale)
    let box = CGRect(x: 1.5 * s, y: 1.5 * s, width: 15 * s, height: 15 * s)
    let r = 4.5 * s
    let rounded = CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil)
    let bars = barPath(in: box.insetBy(dx: 3.5 * s, dy: 4 * s), count: 3, heights: [0.5, 1.0, 0.5], barW: 1.6 * s, gap: 1.7 * s)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    if filled {
        ctx.addPath(rounded); ctx.fillPath()
        ctx.setBlendMode(.clear)
        ctx.addPath(bars); ctx.fillPath()
    } else {
        ctx.addPath(rounded); ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(1.5 * s); ctx.strokePath()
        ctx.addPath(bars); ctx.fillPath()
    }
    write(ctx, "\(name)@\(scale)x.png")
}

for px in [16, 32, 64, 128, 256, 512, 1024] { appIcon(px) }
for scale in [1, 2] {
    menuGlyph(scale: scale, filled: false, name: "MenuBarIdle")
    menuGlyph(scale: scale, filled: true, name: "MenuBarActive")
}
print("ok")
