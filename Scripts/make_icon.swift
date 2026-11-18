// Draws the Pandulipi app icon (1024×1024 PNG).
// Usage: swift Scripts/make_icon.swift out.png
import AppKit
import CoreText

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid: 824pt body, centred, continuous-corner squircle.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(rgb(0x1B1F4A)); ctx.fillPath()
ctx.restoreGState()

// Background gradient: deep indigo → teal
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x1E1B5E), rgb(0x23408E), rgb(0x0E8A8A)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 150, y: 924), end: CGPoint(x: 874, y: 100), options: [])
// Soft radial glow behind the book
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0x7FE7FF, 0.35), rgb(0x7FE7FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 430, options: [])
ctx.restoreGState()

// Open book
func page(left: Bool) -> CGPath {
    let p = CGMutablePath()
    let spineX: CGFloat = 512, outer: CGFloat = left ? 210 : 814
    let bottom: CGFloat = 270, top: CGFloat = 720
    p.move(to: CGPoint(x: spineX, y: bottom))
    p.addCurve(to: CGPoint(x: outer, y: bottom + 30),
               control1: CGPoint(x: spineX + (left ? -110 : 110), y: bottom - 40),
               control2: CGPoint(x: outer + (left ? 80 : -80), y: bottom + 10))
    p.addLine(to: CGPoint(x: outer, y: top))
    p.addCurve(to: CGPoint(x: spineX, y: top - 30),
               control1: CGPoint(x: outer + (left ? 90 : -90), y: top + 30),
               control2: CGPoint(x: spineX + (left ? -100 : 100), y: top + 20))
    p.closeSubpath()
    return p
}

// Book block shadow / thickness
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: rgb(0x000000, 0.45))
let base = CGMutablePath()
base.addPath(page(left: true)); base.addPath(page(left: false))
ctx.addPath(base); ctx.setFillColor(rgb(0xE9DFC6)); ctx.fillPath()
ctx.restoreGState()

for left in [true, false] {
    ctx.saveGState()
    ctx.addPath(page(left: left)); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: left
                       ? [rgb(0xFFFBF0), rgb(0xF3E9D2)] as CFArray
                       : [rgb(0xF3E9D2), rgb(0xFFFBF0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: left ? 210 : 512, y: 0), end: CGPoint(x: left ? 512 : 814, y: 0), options: [])
    ctx.restoreGState()
}
// Spine
ctx.setStrokeColor(rgb(0xC9B88F)); ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: 512, y: 275)); ctx.addLine(to: CGPoint(x: 512, y: 690)); ctx.strokePath()

// Left page: Bangla letter অ in ink
func drawText(_ s: String, font: String, size: CGFloat, color: CGColor, center: CGPoint) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: center.x - b.midX, y: center.y - b.midY)
    CTLineDraw(line, ctx)
}
drawText("অ", font: "KohinoorBangla-Bold", size: 225, color: rgb(0x26215E), center: CGPoint(x: 366, y: 492))

// Right page: digital text lines
let lineColor = rgb(0x2F5FA8, 0.85)
let rows: [(CGFloat, CGFloat)] = [(620, 170), (570, 195), (520, 150), (470, 185), (420, 120), (370, 175)]
ctx.setLineCap(.round); ctx.setLineWidth(22)
for (y, w) in rows {
    ctx.setStrokeColor(lineColor)
    ctx.move(to: CGPoint(x: 578, y: y)); ctx.addLine(to: CGPoint(x: 578 + w, y: y)); ctx.strokePath()
}

// Scan beam across the book
ctx.saveGState()
let beamY: CGFloat = 497
let beamGlow = CGGradient(colorsSpace: cs, colors: [rgb(0x5CF2FF, 0), rgb(0x5CF2FF, 0.55), rgb(0x5CF2FF, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
ctx.addRect(CGRect(x: 170, y: beamY - 60, width: 684, height: 120)); ctx.clip()
ctx.drawLinearGradient(beamGlow, start: CGPoint(x: 0, y: beamY - 60), end: CGPoint(x: 0, y: beamY + 60), options: [])
ctx.restoreGState()
ctx.setStrokeColor(rgb(0xB8FBFF)); ctx.setLineWidth(8)
ctx.move(to: CGPoint(x: 180, y: beamY)); ctx.addLine(to: CGPoint(x: 844, y: beamY)); ctx.strokePath()

// AI sparkle (top right)
func sparkle(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: rgb(0xFFD36E, 0.9))
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
    ctx.restoreGState()
}
sparkle(CGPoint(x: 790, y: 805), 70, rgb(0xFFD36E))
sparkle(CGPoint(x: 700, y: 850), 30, rgb(0xFFE7A8))

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
