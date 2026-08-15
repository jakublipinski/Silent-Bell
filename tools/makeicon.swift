import AppKit
import Foundation

// Icon B ("depth") at exact pixel size with NO alpha channel.
//
// Drawing via NSImage.lockFocus() inherits the display's backing scale, so a
// 1024-point canvas came out 2048px on a Retina Mac, and kept an alpha channel.
// App Store Connect rejects a 1024 marketing icon that has alpha, so the context
// is built by hand: exact pixel dimensions, noneSkipLast (opaque), no scaling.

let sand = CGColor(srgbRed: 0xCF/255, green: 0xA8/255, blue: 0x6F/255, alpha: 1)

func sandAlpha(_ a: CGFloat) -> CGColor {
    CGColor(srgbRed: 0xCF/255, green: 0xA8/255, blue: 0x6F/255, alpha: a)
}

func render(size S: CGFloat, to path: String) {
    let px = Int(S)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }

    // Radial background: a lift at the centre falling to near-black at the corners,
    // so the mark sits in light rather than on a flat field.
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0x2E/255, green: 0x2C/255, blue: 0x29/255, alpha: 1),
        CGColor(srgbRed: 0x14/255, green: 0x14/255, blue: 0x16/255, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                           endCenter: CGPoint(x: S/2, y: S/2), endRadius: S * 0.75,
                           options: [.drawsAfterEndLocation])

    func ring(_ rF: CGFloat, _ wF: CGFloat, _ a: CGFloat) {
        let r = S * rF, w = S * wF
        ctx.setStrokeColor(sandAlpha(a))
        ctx.setLineWidth(w)
        ctx.strokeEllipse(in: CGRect(x: S/2 - r, y: S/2 - r, width: r*2, height: r*2))
    }
    // Fractions of the canvas, so any size renders identically.
    //
    // The falloff is deliberately shallow. A wide range (0.18 / 0.34 / 0.62) looked
    // right at 1024px and collapsed at 120: the outer two rings stopped registering
    // and the icon read as a dot inside a single ring — which is the shape App
    // Review had already called a placeholder. All three must survive the home
    // screen, so they are brighter and the outer ones thicker to hold their weight.
    ring(0.3828, 0.0350, 0.36)
    ring(0.2930, 0.0430, 0.55)
    ring(0.2051, 0.0520, 0.80)

    // The dot is a source: glow first, then the solid core over it.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: S * 0.068, color: sandAlpha(0.55))
    ctx.setFillColor(sand)
    let dr = S * 0.0898
    ctx.fillEllipse(in: CGRect(x: S/2 - dr, y: S/2 - dr, width: dr*2, height: dr*2))
    ctx.restoreGState()
    ctx.setFillColor(sand)
    ctx.fillEllipse(in: CGRect(x: S/2 - dr, y: S/2 - dr, width: dr*2, height: dr*2))

    guard let img = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) — \(px)x\(px)")
}

let outDir = CommandLine.arguments[1]
render(size: 1024, to: "\(outDir)/AppIcon.png")        // app icon / marketing
render(size: 180, to: "\(outDir)/apple-touch-icon.png") // website home-screen icon
