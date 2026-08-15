import AppKit
import Foundation

// Social preview card, 1200x630. Same mark and palette as the app icon and site.

let W: CGFloat = 1200, H: CGFloat = 630
let sand = NSColor(srgbRed: 0xCF/255, green: 0xA8/255, blue: 0x6F/255, alpha: 1)
let cream = NSColor(srgbRed: 0xED/255, green: 0xE7/255, blue: 0xDB/255, alpha: 1)
let muted = NSColor(srgbRed: 0xB8/255, green: 0xB2/255, blue: 0xA6/255, alpha: 1)

func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    if let f = NSFont(name: "NewYork-Regular", size: size) { return f }
    if let f = NSFont(name: "Georgia", size: size) { return f }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

NSColor.black.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// The mark: dot and three ripples, matching the app icon's proportions and
// opacity falloff. Scaled so the outermost ring keeps the previous card's size.
let cx = W / 2, cy: CGFloat = 470
func ring(_ r: CGFloat, _ alpha: CGFloat, _ lw: CGFloat) {
    ctx.setStrokeColor(sand.withAlphaComponent(alpha).cgColor)
    ctx.setLineWidth(lw)
    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}
ring(74, 0.18, 5.7)
ring(56.6, 0.34, 7.5)
ring(39.6, 0.62, 9.8)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 13, color: sand.withAlphaComponent(0.55).cgColor)
ctx.setFillColor(sand.cgColor)
ctx.fillEllipse(in: CGRect(x: cx - 17.3, y: cy - 17.3, width: 34.6, height: 34.6))
ctx.restoreGState()
ctx.setFillColor(sand.cgColor)
ctx.fillEllipse(in: CGRect(x: cx - 17.3, y: cy - 17.3, width: 34.6, height: 34.6))

/// Draw one line centred horizontally, and vertically about `centreY`, so the
/// stacked bands below cannot collide the way a baseline-anchored layout did.
func centre(_ s: String, _ font: NSFont, _ colour: NSColor, centreY: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let str = NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: colour, .paragraphStyle: para,
    ])
    let size = str.size()
    str.draw(in: NSRect(x: 50, y: centreY - size.height / 2,
                        width: W - 100, height: size.height + 4))
}

centre("A bell that never rings.", serif(76), cream, centreY: 300)
centre("Random, silent taps on your wrist.  ·  Apple Watch",
       NSFont.systemFont(ofSize: 29, weight: .regular), muted, centreY: 196)

let para = NSMutableParagraphStyle(); para.alignment = .center
NSAttributedString(string: "S I L E N T   B E L L", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: sand.withAlphaComponent(0.75),
    .paragraphStyle: para,
]).draw(in: NSRect(x: 50, y: 74, width: W - 100, height: 34))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
