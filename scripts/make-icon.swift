import AppKit

// Turns square artwork into Art/AppIcon.png:
//   swift scripts/make-icon.swift <artwork> Art/AppIcon.png
// Fits the art into Apple's macOS icon grid: an 824x824 rounded square centered on a
// 1024x1024 transparent canvas, with a soft drop shadow.
let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("usage: make_icon <source> <output.png>")
}
let canvas = 1024, body: CGFloat = 824, radius: CGFloat = 185.4
let origin = (CGFloat(canvas) - body) / 2
let rect = CGRect(x: origin, y: origin, width: body, height: body)

let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Shadow under the shape.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
ctx.addPath(path)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// The art, center-cropped to a square and clipped to the rounded shape.
let side = min(cg.width, cg.height)
let crop = cg.cropping(to: CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side))!
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
ctx.draw(crop, in: rect)
ctx.restoreGState()

// A hairline inner edge, like system icons.
ctx.addPath(path)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
ctx.setLineWidth(2)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
