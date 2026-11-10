import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory: URL
if let argument = CommandLine.arguments.dropFirst().first {
    outputDirectory = URL(fileURLWithPath: argument, isDirectory: true)
} else {
    outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let width = 16
let height = 12
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    throw NSError(domain: "ImageFixtures", code: 1)
}

// Original-pixel coordinates have a bottom-left origin. Each quadrant is 8 x 6 pixels.
let quadrants = ["top-left red", "top-right green", "bottom-left blue", "bottom-right yellow"]
var pixels = [UInt8](repeating: 255, count: width * height * 4)
for memoryY in 0..<height {
    let originalY = height - 1 - memoryY
    for x in 0..<width {
        let offset = (memoryY * width + x) * 4
        let isTop = originalY >= 6
        let isRight = x >= 8
        let rgb: (UInt8, UInt8, UInt8)
        switch (isTop, isRight) {
        case (true, false): rgb = (255, 0, 0)
        case (true, true): rgb = (0, 255, 0)
        case (false, false): rgb = (0, 0, 255)
        case (false, true): rgb = (255, 255, 0)
        }
        pixels[offset] = rgb.0
        pixels[offset + 1] = rgb.1
        pixels[offset + 2] = rgb.2
        pixels[offset + 3] = 255
    }
}
guard let provider = CGDataProvider(data: Data(pixels) as CFData), let image = CGImage(
    width: width,
    height: height,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
) else {
    fatalError("Could not create fixture image")
}

for (name, type) in [("colored.png", UTType.png), ("colored.jpg", UTType.jpeg)] {
    let url = outputDirectory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        fatalError("Could not create \(name) destination")
    }
    let options = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary : nil
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize \(name)")
    }
    print(url.path)
}
print("16x12; " + quadrants.joined(separator: "; "))
