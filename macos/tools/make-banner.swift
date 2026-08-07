// Renders the repo banner. Usage: swift tools/make-banner.swift ../docs/images/banner.png
import AppKit
import CoreGraphics

let width = 2400
let height = 800

let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.07, green: 0.13, blue: 0.32, alpha: 1),
        CGColor(red: 0.13, green: 0.26, blue: 0.58, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(height)),
    end: CGPoint(x: CGFloat(width), y: 0),
    options: []
)

// Topic tree motif on the right, echoing the app icon.
let originX: CGFloat = 1580
let originY: CGFloat = 400
let root = CGPoint(x: originX, y: originY + 210)
let level2 = [
    CGPoint(x: originX - 230, y: originY),
    CGPoint(x: originX, y: originY),
    CGPoint(x: originX + 230, y: originY),
]
let level3 = [
    CGPoint(x: originX - 100, y: originY - 210),
    CGPoint(x: originX + 100, y: originY - 210),
]

context.setLineCap(.round)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
context.setLineWidth(10)
for point in level2 {
    context.move(to: root)
    context.addLine(to: point)
    context.strokePath()
}
for point in level3 {
    context.move(to: level2[1])
    context.addLine(to: point)
    context.strokePath()
}

func node(_ point: CGPoint, radius: CGFloat, alpha: CGFloat) {
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}
for point in level2 { node(point, radius: 26, alpha: 0.5) }
for point in level3 { node(point, radius: 20, alpha: 0.38) }
node(root, radius: 32, alpha: 0.85)
context.setStrokeColor(CGColor(red: 1, green: 0.62, blue: 0.16, alpha: 0.9))
context.setLineWidth(7)
context.strokeEllipse(in: CGRect(x: root.x - 52, y: root.y - 52, width: 104, height: 104))

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: CGPoint) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let line = NSAttributedString(string: text, attributes: attributes)
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    line.draw(at: point)
    NSGraphicsContext.restoreGraphicsState()
}

draw("MQTT Explorer", size: 150, weight: .semibold, color: .white, at: CGPoint(x: 150, y: 470))
draw("for macOS", size: 150, weight: .thin, color: NSColor(calibratedWhite: 1, alpha: 0.72), at: CGPoint(x: 150, y: 310))
draw(
    "Native. Apple Silicon. No Electron.",
    size: 52,
    weight: .regular,
    color: NSColor(calibratedRed: 1, green: 0.62, blue: 0.16, alpha: 1),
    at: CGPoint(x: 158, y: 200)
)

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "banner.png"
let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the banner")
}
try! png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
