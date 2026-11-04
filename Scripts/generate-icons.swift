import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconEntry {
    let size: String
    let scale: String
    let pixels: Int
}

private enum GeneratorError: Error {
    case cannotCreateContext
    case cannotCreateDestination
    case cannotWriteImage
}

// The approved floating-badge SVG uses a 64 × 64 viewBox with a top-left origin.
private let canvas: CGFloat = 64
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
private let entries = [
    IconEntry(size: "16x16", scale: "1x", pixels: 16),
    IconEntry(size: "16x16", scale: "2x", pixels: 32),
    IconEntry(size: "32x32", scale: "1x", pixels: 32),
    IconEntry(size: "32x32", scale: "2x", pixels: 64),
    IconEntry(size: "128x128", scale: "1x", pixels: 128),
    IconEntry(size: "128x128", scale: "2x", pixels: 256),
    IconEntry(size: "256x256", scale: "1x", pixels: 256),
    IconEntry(size: "256x256", scale: "2x", pixels: 512),
    IconEntry(size: "512x512", scale: "1x", pixels: 512),
    IconEntry(size: "512x512", scale: "2x", pixels: 1024),
]

private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

private func makeContext(pixels: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw GeneratorError.cannotCreateContext
    }
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)
    return context
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawBackground(in context: CGContext, dark: Bool) {
    // Normalize the mockup's 82 pt card and 22 pt radius to the SVG viewBox.
    let backgroundPath = roundedPath(CGRect(x: 0, y: 0, width: 64, height: 64), radius: 22 * 64 / 82)
    let gradientColors = dark
        ? [color(0x536887), color(0x0C1420)] as CFArray
        : [color(0x9DE0FF), color(0xA48BEB)] as CFArray
    let locations: [CGFloat] = [0, 1]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations)!
    let angle = 145 * CGFloat.pi / 180
    let direction = CGPoint(x: sin(angle), y: -cos(angle))
    let length = 64 * (abs(direction.x) + abs(direction.y))
    let center = CGPoint(x: 32, y: 32)
    let start = CGPoint(x: center.x - direction.x * length / 2, y: center.y - direction.y * length / 2)
    let end = CGPoint(x: center.x + direction.x * length / 2, y: center.y + direction.y * length / 2)

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF, dark ? 0.20 : 0.65))
    context.setLineWidth(64 / 82)
    context.addPath(backgroundPath)
    context.strokePath()
}

private func drawPin(in context: CGContext) {
    context.saveGState()
    context.translateBy(x: -1, y: -1)
    context.scaleBy(x: 0.85, y: 0.85)
    context.move(to: CGPoint(x: 42, y: 38))
    context.addLine(to: CGPoint(x: 49, y: 38))
    context.addLine(to: CGPoint(x: 48, y: 43))
    context.addLine(to: CGPoint(x: 51, y: 45))
    context.addLine(to: CGPoint(x: 51, y: 47))
    context.addLine(to: CGPoint(x: 47, y: 47))
    context.addLine(to: CGPoint(x: 47, y: 53))
    context.addLine(to: CGPoint(x: 46, y: 54))
    context.addLine(to: CGPoint(x: 45, y: 53))
    context.addLine(to: CGPoint(x: 45, y: 47))
    context.addLine(to: CGPoint(x: 41, y: 47))
    context.addLine(to: CGPoint(x: 41, y: 45))
    context.addLine(to: CGPoint(x: 44, y: 43))
    context.addLine(to: CGPoint(x: 43, y: 38))
    context.closePath()
    context.fillPath()
    context.restoreGState()
}

private func drawPane(
    in context: CGContext,
    rect: CGRect,
    angle: CGFloat,
    center: CGPoint
) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle * .pi / 180)
    context.translateBy(x: -center.x, y: -center.y)
    context.addPath(roundedPath(rect, radius: 8))
    context.fillPath()
    context.restoreGState()
}

private func drawFloatingBadge(in context: CGContext, dark: Bool, isTemplate: Bool) {
    let backColor = isTemplate
        ? color(0x000000, 0.25)
        : dark ? color(0x8BD0FF, 0.12) : color(0xFFFFFF, 0.25)
    context.setFillColor(backColor)
    drawPane(
        in: context,
        rect: CGRect(x: 12, y: 14, width: 30, height: 30),
        angle: -8,
        center: CGPoint(x: 27, y: 29)
    )

    let frontColor = isTemplate
        ? color(0x000000, 0.45)
        : dark ? color(0x8BD0FF, 0.24) : color(0xFFFFFF, 0.45)
    context.setFillColor(frontColor)
    drawPane(
        in: context,
        rect: CGRect(x: 22, y: 20, width: 30, height: 30),
        angle: 8,
        center: CGPoint(x: 37, y: 35)
    )

    let badgeColor = isTemplate ? color(0x000000) : dark ? color(0x8BD0FF) : color(0xFFFFFF)
    context.setFillColor(badgeColor)
    context.addEllipse(in: CGRect(x: 33, y: 33, width: 24, height: 24))
    context.fillPath()

    if isTemplate {
        context.saveGState()
        context.setBlendMode(.clear)
        drawPin(in: context)
        context.restoreGState()
    } else {
        context.setFillColor(dark ? color(0x142235) : color(0x7767C8))
        drawPin(in: context)
    }
}

private func drawAppIcon(in context: CGContext, dark: Bool) {
    drawBackground(in: context, dark: dark)
    drawFloatingBadge(in: context, dark: dark, isTemplate: false)
}

private func drawMenuTemplate(in context: CGContext) {
    drawFloatingBadge(in: context, dark: false, isTemplate: true)
}

private func writePNG(_ context: CGContext, to url: URL) throws {
    guard let image = context.makeImage() else {
        throw GeneratorError.cannotCreateContext
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw GeneratorError.cannotCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw GeneratorError.cannotWriteImage
    }
}

private func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

private func generate(catalogURL: URL) throws {
    let appIconURL = catalogURL.appendingPathComponent("AppIcon.appiconset")
    let menuURL = catalogURL.appendingPathComponent("MenuBarTemplate.imageset")
    try FileManager.default.createDirectory(at: appIconURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: menuURL, withIntermediateDirectories: true)

    try writeJSON(["info": ["author": "xcode", "version": 1]], to: catalogURL.appendingPathComponent("Contents.json"))

    var manifestEntries: [[String: Any]] = []
    for dark in [false, true] {
        let uniqueSizes = Array(Set(entries.map(\.pixels))).sorted()
        for pixels in uniqueSizes {
            let context = try makeContext(pixels: pixels)
            drawAppIcon(in: context, dark: dark)
            let filename = "AppIcon\(dark ? "-Dark" : "")-\(pixels).png"
            try writePNG(context, to: appIconURL.appendingPathComponent(filename))
        }
        for entry in entries {
            var manifest: [String: Any] = [
                "filename": "AppIcon\(dark ? "-Dark" : "")-\(entry.pixels).png",
                "idiom": "mac",
                "scale": entry.scale,
                "size": entry.size,
            ]
            if dark {
                manifest["appearances"] = [["appearance": "luminosity", "value": "dark"]]
            }
            manifestEntries.append(manifest)
        }
    }
    try writeJSON(
        ["images": manifestEntries, "info": ["author": "xcode", "version": 1]],
        to: appIconURL.appendingPathComponent("Contents.json")
    )

    var menuEntries: [[String: Any]] = []
    for (scale, pixels) in [("1x", 16), ("2x", 32)] {
        let context = try makeContext(pixels: pixels)
        drawMenuTemplate(in: context)
        let filename = "MenuBarTemplate-\(pixels).png"
        try writePNG(context, to: menuURL.appendingPathComponent(filename))
        menuEntries.append(["filename": filename, "idiom": "mac", "scale": scale])
    }
    try writeJSON(
        [
            "images": menuEntries,
            "info": ["author": "xcode", "version": 1],
            "properties": ["template-rendering-intent": "template"],
        ],
        to: menuURL.appendingPathComponent("Contents.json")
    )
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: generate-icons.swift <asset-catalog-root>\n".data(using: .utf8)!)
    exit(1)
}

let outputURL = URL(
    fileURLWithPath: CommandLine.arguments[1],
    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
).standardizedFileURL

do {
    try generate(catalogURL: outputURL)
} catch {
    FileHandle.standardError.write("Icon generation failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
