// Frames raw App Store screenshots with a headline on the app's green.
// Usage: swift make-screenshots.swift <raw dir> <out dir>
import AppKit

/// Headlines by screen; raw files are named "<order>-<screen>.png", e.g. "3-gameday.png".
let captions: [String: (title: String, sub: String)] = [
    "lineup": ("Fair rotations\nin one tap", "Even playing time, longer bench stretches"),
    "attendance": ("Plan for who's\nactually there", "Tick off who made it to the game"),
    "gameday": ("Know exactly\nwhen to sub", "Who goes on, who comes off"),
    "lock": ("Sub alerts on\nyour lock screen", "Keep your phone in your pocket"),
    "roster": ("The positions each\nplayer can play", "Auto-fill only uses what you turn on"),
    "settings": ("Any team size,\nany formation", "4 to 11 players, any half length"),
]
let args = CommandLine.arguments
let rawDir = args[1], outDir = args[2]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let files = (try! FileManager.default.contentsOfDirectory(atPath: rawDir)).filter { $0.hasSuffix(".png") }.sorted()
for name in files {
    let file = String(name.dropLast(4))
    guard let screen = file.split(separator: "-", maxSplits: 1).last, let c = captions[String(screen)] else {
        print("no headline for \(name), skipped"); continue
    }
    guard let src = NSImage(contentsOfFile: "\(rawDir)/\(name)"),
          let shot = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let W = CGFloat(shot.width), H = CGFloat(shot.height)
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let g = CGGradient(colorsSpace: space, colors: [rgb(0x24974C), rgb(0x0D4F23)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
    ctx.setFillColor(rgb(0xFFFFFF, 0.04))
    for i in stride(from: 0, to: 10, by: 2) { ctx.fill(CGRect(x: 0, y: CGFloat(i) * H / 10, width: W, height: H / 10)) }

    // Headline and subhead.
    // 1 on iPhone (1320 x 2868); a little larger on iPad's wider page.
    let scale = (W / 1320 + H / 2868) / 2
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4 * scale
    let title = NSAttributedString(string: c.title, attributes: [
        .font: NSFont.systemFont(ofSize: 112 * scale, weight: .heavy),
        .foregroundColor: NSColor.white, .paragraphStyle: para])
    let sub = NSAttributedString(string: c.sub, attributes: [
        .font: NSFont.systemFont(ofSize: 52 * scale, weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.82), .paragraphStyle: para])
    title.draw(in: CGRect(x: 60 * scale, y: H - 420 * scale, width: W - 120 * scale, height: 300 * scale))
    sub.draw(in: CGRect(x: 60 * scale, y: H - 520 * scale, width: W - 120 * scale, height: 80 * scale))
    NSGraphicsContext.current = nil

    // The screenshot, scaled down with rounded corners and a soft shadow, running off the bottom.
    let sw = W * 0.80, sh = sw * H / W
    let rect = CGRect(x: (W - sw) / 2, y: H - 590 * scale - sh, width: sw, height: sh)
    let path = CGPath(roundedRect: rect, cornerWidth: 64 * scale, cornerHeight: 64 * scale, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20 * scale), blur: 60 * scale, color: rgb(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: rect)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(rgb(0xFFFFFF, 0.25)); ctx.setLineWidth(4 * scale); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("framed \(name)")
}
