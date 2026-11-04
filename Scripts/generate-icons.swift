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

private let canvas: CGFloat = 1024
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
    return context
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawPin(in context: CGContext, center: CGPoint) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: -.pi / 6)
    context.addPath(roundedPath(CGRect(x: -58, y: 20, width: 116, height: 64), radius: 18))
    context.fillPath()
    context.move(to: CGPoint(x: -36, y: 20))
    context.addLine(to: CGPoint(x: 36, y: 20))
    context.addLine(to: CGPoint(x: 20, y: -22))
    context.addLine(to: CGPoint(x: -20, y: -22))
    context.closePath()
    context.fillPath()
    context.move(to: CGPoint(x: -12, y: -22))
    context.addLine(to: CGPoint(x: 12, y: -22))
    context.addLine(to: CGPoint(x: 0, y: -86))
    context.closePath()
    context.fillPath()
    context.restoreGState()
}

private func drawAppIcon(in context: CGContext, dark: Bool) {
    let background = CGRect(x: 32, y: 32, width: 960, height: 960)
    let backgroundPath = roundedPath(background, radius: 220)
    let gradientColors = dark
        ? [color(0x121926), color(0x20344A)] as CFArray
        : [color(0xE0F4FF), color(0xEEE4FF)] as CFArray
    let locations: [CGFloat] = [0, 1]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations)!

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 128, y: 896),
        end: CGPoint(x: 896, y: 128),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    context.setStrokeColor(dark ? color(0x8BD0FF, 0.38) : color(0xFFFFFF, 0.82))
    context.setLineWidth(8)
    context.addPath(backgroundPath)
    context.strokePath()

    let backPane = CGRect(x: 192, y: 352, width: 560, height: 416)
    context.setFillColor(color(0x8BD0FF, dark ? 0.52 : 0.68))
    context.addPath(roundedPath(backPane, radius: 88))
    context.fillPath()

    let frontPane = CGRect(x: 264, y: 224, width: 560, height: 416)
    context.setFillColor(dark ? color(0x26364A, 0.98) : color(0xFFFFFF, 0.94))
    context.addPath(roundedPath(frontPane, radius: 88))
    context.fillPath()
    context.setStrokeColor(dark ? color(0x8BD0FF, 0.72) : color(0xFFFFFF, 0.96))
    context.setLineWidth(8)
    context.addPath(roundedPath(frontPane, radius: 88))
    context.strokePath()

    let badgeCenter = CGPoint(x: 724, y: 676)
    context.setFillColor(color(0x8BD0FF))
    context.addEllipse(in: CGRect(x: 592, y: 544, width: 264, height: 264))
    context.fillPath()
    context.setStrokeColor(dark ? color(0x121926, 0.72) : color(0xFFFFFF, 0.9))
    context.setLineWidth(10)
    context.addEllipse(in: CGRect(x: 592, y: 544, width: 264, height: 264))
    context.strokePath()
    context.setFillColor(color(0x121926))
    drawPin(in: context, center: badgeCenter)
}

private func drawMenuTemplate(in context: CGContext) {
    context.setStrokeColor(color(0x000000))
    context.setFillColor(color(0x000000))
    context.setLineWidth(58)
    context.addPath(roundedPath(CGRect(x: 192, y: 352, width: 560, height: 416), radius: 88))
    context.strokePath()
    context.addPath(roundedPath(CGRect(x: 264, y: 224, width: 560, height: 416), radius: 88))
    context.strokePath()

    context.addEllipse(in: CGRect(x: 592, y: 544, width: 264, height: 264))
    context.fillPath()
    context.saveGState()
    context.setBlendMode(.clear)
    drawPin(in: context, center: CGPoint(x: 724, y: 676))
    context.restoreGState()
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
