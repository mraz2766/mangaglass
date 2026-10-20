// Vector source of the MangaGlass logo.
// Regenerate: swiftc -O scripts/draw_logo.swift -o /tmp/draw_logo && /tmp/draw_logo <out.png> <px> [tile|mark]
import AppKit

// Usage: draw <out.png> <size> [tile|mark]
let args = CommandLine.arguments
let out = args[1]
let size = CGFloat(Double(args[2]) ?? 1024)
let mode = args.count > 3 ? args[3] : "tile"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
// Work in a 1024 canvas, y down.
cg.scaleBy(x: size / 1024, y: size / 1024)
cg.translateBy(x: 0, y: 1024)
cg.scaleBy(x: 1, y: -1)

let tileRect = mode == "tile" ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: mode == "tile" ? 186 : 230, yRadius: mode == "tile" ? 186 : 230)

if mode == "tile" {
    // Soft drop shadow under the tile, like system icons.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x0A2A66, 0.28).cgColor)
    rgb(0x2F80F5).setFill(); tile.fill()
    cg.restoreGState()
}

// Blue gradient tile.
cg.saveGState()
tile.addClip()
NSGradient(colors: [rgb(0x5AA9FF), rgb(0x2C78F2), rgb(0x1858D6)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: tileRect, angle: 90)
// Glass: soft light falling from the top edge.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.26), NSColor.white.withAlphaComponent(0.0)])!
    .draw(in: CGRect(x: tileRect.minX, y: tileRect.minY, width: tileRect.width, height: tileRect.height * 0.55), angle: 90)
cg.restoreGState()
// Inner hairline highlight.
cg.saveGState()
let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
rim.lineWidth = 4
NSColor.white.withAlphaComponent(0.35).setStroke(); rim.stroke()
cg.restoreGState()

// --- Elephant (white, flat), shifted to sit optically centered.
cg.saveGState()
cg.translateBy(x: -8, y: 24)
cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x0B3B8C, 0.24).cgColor)
cg.beginTransparencyLayer(auxiliaryInfo: nil)

let white = rgb(0xFFFFFF)
let earTint = rgb(0xCFE2FF)

// Head + trunk as one silhouette.
let head = NSBezierPath(ovalIn: CGRect(x: 300, y: 330, width: 380, height: 380))
let trunk = NSBezierPath()
trunk.lineWidth = 92
trunk.lineCapStyle = .round
trunk.move(to: CGPoint(x: 600, y: 590))
trunk.curve(to: CGPoint(x: 742, y: 438), controlPoint1: CGPoint(x: 700, y: 640), controlPoint2: CGPoint(x: 760, y: 560))
white.setFill(); head.fill()
white.setStroke(); trunk.stroke()
cg.endTransparencyLayer()
cg.restoreGState()

// Ear sits on the head with a blue gap so it reads as a separate shape.
cg.saveGState()
cg.translateBy(x: -8, y: 24)
let ear = NSBezierPath()
ear.move(to: CGPoint(x: 452, y: 392))
ear.curve(to: CGPoint(x: 334, y: 540), controlPoint1: CGPoint(x: 380, y: 392), controlPoint2: CGPoint(x: 334, y: 456))
ear.curve(to: CGPoint(x: 444, y: 668), controlPoint1: CGPoint(x: 334, y: 616), controlPoint2: CGPoint(x: 384, y: 668))
ear.curve(to: CGPoint(x: 452, y: 392), controlPoint1: CGPoint(x: 506, y: 640), controlPoint2: CGPoint(x: 522, y: 432))
ear.close()
earTint.setFill(); ear.fill()

// Eye.
rgb(0x163B78).setFill()
NSBezierPath(ovalIn: CGRect(x: 552, y: 472, width: 40, height: 40)).fill()

// Sprout held by the trunk tip.
let green = rgb(0x34C759)
let stem = NSBezierPath()
stem.lineWidth = 16; stem.lineCapStyle = .round
stem.move(to: CGPoint(x: 744, y: 400))
stem.curve(to: CGPoint(x: 760, y: 300), controlPoint1: CGPoint(x: 748, y: 360), controlPoint2: CGPoint(x: 752, y: 330))
green.setStroke(); stem.stroke()
func leaf(from base: CGPoint, to tip: CGPoint, bulge: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
    let dx = tip.x - base.x, dy = tip.y - base.y
    let len = sqrt(dx * dx + dy * dy)
    let nx = -dy / len * bulge, ny = dx / len * bulge
    p.move(to: base)
    p.curve(to: tip, controlPoint1: CGPoint(x: mid.x + nx, y: mid.y + ny), controlPoint2: CGPoint(x: tip.x + nx * 0.2, y: tip.y + ny * 0.2))
    p.curve(to: base, controlPoint1: CGPoint(x: tip.x - nx * 0.2, y: tip.y - ny * 0.2), controlPoint2: CGPoint(x: mid.x - nx, y: mid.y - ny))
    p.close()
    return p
}
green.setFill()
leaf(from: CGPoint(x: 758, y: 318), to: CGPoint(x: 846, y: 250), bulge: 34).fill()
leaf(from: CGPoint(x: 754, y: 340), to: CGPoint(x: 672, y: 276), bulge: 30).fill()
cg.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
