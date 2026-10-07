import AppKit

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func canvas(opaque: Bool, _ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    c.setShouldAntialias(true)
    draw(c)
    return c.makeImage()!
}
func arrowPath(cx: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, up: Bool) -> CGPath {
    let sw = w * 0.42, headH = h * 0.48
    let p = CGMutablePath()
    let tipY = up ? y + h : y, baseY = up ? y + h - headH : y + headH, endY = up ? y : y + h
    p.move(to: CGPoint(x: cx, y: tipY))
    p.addLine(to: CGPoint(x: cx + w / 2, y: baseY))
    p.addLine(to: CGPoint(x: cx + sw / 2, y: baseY))
    p.addLine(to: CGPoint(x: cx + sw / 2, y: endY))
    p.addLine(to: CGPoint(x: cx - sw / 2, y: endY))
    p.addLine(to: CGPoint(x: cx - sw / 2, y: baseY))
    p.addLine(to: CGPoint(x: cx - w / 2, y: baseY))
    p.closeSubpath()
    return p
}
/// Arrow with rounded corners and a soft top-to-bottom shade.
func arrow(_ c: CGContext, cx: CGFloat, up: Bool, top: UInt32, bottom: UInt32) {
    let w: CGFloat = 262, h: CGFloat = 360, y: CGFloat = 332
    let rounded = arrowPath(cx: cx, y: y, w: w, h: h, up: up).copy(strokingWithWidth: w * 0.10, lineCap: .round, lineJoin: .round, miterLimit: 2)
    let g = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    // Fill the shape, then its rounded edge, each with the same shade.
    for part in [arrowPath(cx: cx, y: y, w: w, h: h, up: up), rounded] {
        c.saveGState()
        c.addPath(part); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: y + h + 20), end: CGPoint(x: 0, y: y - 20), options: [])
        c.restoreGState()
    }
}
let board = CGRect(x: 138, y: 242, width: 748, height: 540)
let boardPath = CGPath(roundedRect: board, cornerWidth: 96, cornerHeight: 96, transform: nil)

enum Style { case standard, dark, tinted }
func icon(_ style: Style) -> CGImage {
    canvas(opaque: style == .standard) { c in
        if style == .standard {
            // Pitch: green gradient with mowing stripes.
            let g = CGGradient(colorsSpace: space, colors: [rgb(0x24974C), rgb(0x0D4F23)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
            c.setFillColor(rgb(0xFFFFFF, 0.05))
            for i in stride(from: 0, to: 8, by: 2) { c.fill(CGRect(x: 0, y: CGFloat(i) * S / 8, width: S, height: S / 8)) }
        }
        // The substitution board.
        c.saveGState()
        if style != .tinted { c.setShadow(offset: CGSize(width: 0, height: -16), blur: 48, color: rgb(0x000000, 0.5)) }
        c.addPath(boardPath)
        c.setFillColor(style == .tinted ? rgb(0x000000, 0) : rgb(0x141819))
        c.fillPath()
        c.restoreGState()
        if style != .tinted {
            // A faint sheen across the top of the board.
            c.saveGState(); c.addPath(boardPath); c.clip()
            let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(sheen, start: CGPoint(x: 0, y: board.maxY), end: CGPoint(x: 0, y: board.midY), options: [])
            c.restoreGState()
        }
        c.addPath(boardPath)
        c.setStrokeColor(style == .tinted ? rgb(0xFFFFFF) : rgb(0xF4F6F5, style == .dark ? 0.75 : 0.95))
        c.setLineWidth(24); c.strokePath()
        switch style {
        case .tinted:
            arrow(c, cx: 352, up: true, top: 0xFFFFFF, bottom: 0xE6E6E6)
            arrow(c, cx: 672, up: false, top: 0xA8A8A8, bottom: 0x8C8C8C)
        default:
            arrow(c, cx: 352, up: true, top: 0x4BE070, bottom: 0x22B04A)
            arrow(c, cx: 672, up: false, top: 0xFF6259, bottom: 0xE0352B)
        }
    }
}

func write(_ img: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let out = CommandLine.arguments[1], previewPath = CommandLine.arguments[2]
let std = icon(.standard), dark = icon(.dark), tinted = icon(.tinted)
write(std, out + "/AppIcon.png"); write(dark, out + "/AppIcon-Dark.png"); write(tinted, out + "/AppIcon-Tinted.png")

// Preview roughly as iOS shows each style: dark gets a near-black backdrop, tinted is recolored.
let W: CGFloat = 1500, H: CGFloat = 640
let sheet = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(rgb(0x2C2C2E)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
func put(_ draw: (CGContext, CGRect) -> Void, x: CGFloat, size: CGFloat, y: CGFloat) {
    let r = CGRect(x: x, y: y, width: size, height: size)
    sheet.saveGState()
    sheet.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.2237, cornerHeight: size * 0.2237, transform: nil)); sheet.clip()
    draw(sheet, r)
    sheet.restoreGState()
}
let darkBG = CGGradient(colorsSpace: space, colors: [rgb(0x2B2B2E), rgb(0x0B0B0C)] as CFArray, locations: [0, 1])!
let styles: [(CGContext, CGRect) -> Void] = [
    { c, r in c.draw(std, in: r) },
    { c, r in c.drawLinearGradient(darkBG, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: []); c.draw(dark, in: r) },
    { c, r in
        c.setFillColor(rgb(0x0B0B0C)); c.fill(r)
        c.saveGState(); c.clip(to: r, mask: tinted)
        c.setFillColor(rgb(0x64B5F6)); c.fill(r) // a sample blue tint
        c.restoreGState()
    },
]
for (i, s) in styles.enumerated() {
    let x = 60 + CGFloat(i) * 480
    put(s, x: x, size: 300, y: 260)
    put(s, x: x + 320, size: 120, y: 440)
    put(s, x: x + 320, size: 60, y: 340)
}
write(sheet.makeImage()!, previewPath)
