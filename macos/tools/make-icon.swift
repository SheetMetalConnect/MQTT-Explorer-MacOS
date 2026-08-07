// Generates AppIcon.icns: macOS squircle, blue gradient, topic-tree motif.
// Usage: swift tools/make-icon.swift Resources/AppIcon.icns
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024

func drawIcon() -> CGImage {
    let context = CGContext(
        data: nil,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Squircle body, inset so the system shadow has room.
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: CGFloat(canvas) - inset * 2, height: CGFloat(canvas) - inset * 2)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradientColors = [
        CGColor(red: 0.36, green: 0.55, blue: 0.94, alpha: 1),
        CGColor(red: 0.10, green: 0.20, blue: 0.48, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: CGFloat(canvas) / 2, y: CGFloat(canvas)),
        end: CGPoint(x: CGFloat(canvas) / 2, y: 0),
        options: []
    )
    context.restoreGState()

    // Topic tree: root node, three children, two grandchildren.
    let root = CGPoint(x: 512, y: 700)
    let level2 = [CGPoint(x: 318, y: 512), CGPoint(x: 512, y: 512), CGPoint(x: 706, y: 512)]
    let level3 = [CGPoint(x: 430, y: 330), CGPoint(x: 594, y: 330)]

    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.setLineWidth(30)
    for child in level2 {
        context.move(to: root)
        context.addLine(to: child)
        context.strokePath()
    }
    for grandchild in level3 {
        context.move(to: level2[1])
        context.addLine(to: grandchild)
        context.strokePath()
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    func node(_ point: CGPoint, radius: CGFloat) {
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
    for child in level2 { node(child, radius: 52) }
    for grandchild in level3 { node(grandchild, radius: 42) }
    // Root with an orange accent ring: the broker.
    node(root, radius: 62)
    context.setStrokeColor(CGColor(red: 1, green: 0.62, blue: 0.16, alpha: 1))
    context.setLineWidth(12)
    context.strokeEllipse(in: CGRect(x: root.x - 82, y: root.y - 82, width: 164, height: 164))

    return context.makeImage()!
}

func writePNG(_ image: CGImage, size: Int, to url: URL) {
    let scaled = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    scaled.interpolationQuality = .high
    scaled.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let scaledImage = scaled.makeImage() else {
        fatalError("Could not render \(size)x\(size)")
    }
    let rep = NSBitmapImageRep(cgImage: scaledImage)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(size)x\(size)")
    }
    try! png.write(to: url)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

let master = drawIcon()
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for entry in entries {
    writePNG(master, size: entry.size, to: iconset.appendingPathComponent(entry.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try! process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(outputPath)")
