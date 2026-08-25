import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Silent Bell app icon — "sand field" (App Review round 3: watch icon background
// must be light so the circular mask is visible on the black honeycomb).
// Geometry preserved from the original mark: dot r=128, ring r=312..392 @1024.
let S = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast -> PNG without an alpha channel (colortype 2), eliminating the
// App Store "no alpha in icons" risk class entirely.
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func set(_ hex: Int) {
    ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF)/255,
                             green: CGFloat((hex >> 8) & 0xFF)/255,
                             blue: CGFloat(hex & 0xFF)/255, alpha: 1))
    ctx.setStrokeColor(CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF)/255,
                               green: CGFloat((hex >> 8) & 0xFF)/255,
                               blue: CGFloat(hex & 0xFF)/255, alpha: 1))
}
set(0xCFA86F)                                   // sand field
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
set(0x6B5A40)                                   // muted ring
ctx.setLineWidth(80)
ctx.strokeEllipse(in: CGRect(x: 512-352, y: 512-352, width: 704, height: 704))
set(0x26262A)                                   // dark dot, the focal point
ctx.fillEllipse(in: CGRect(x: 512-128, y: 512-128, width: 256, height: 256))

let img = ctx.makeImage()!
for path in CommandLine.arguments.dropFirst() {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}
