import CoreGraphics
import Foundation
import ImageIO
import XCTest

final class IconResourceTests: XCTestCase {
    private struct IconEntry {
        let size: String
        let scale: String
        let pixels: Int
    }

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

    private var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var catalogURL: URL {
        repositoryURL.appendingPathComponent("Resources/Assets.xcassets")
    }

    private var appIconURL: URL {
        catalogURL.appendingPathComponent("AppIcon.appiconset")
    }

    override func setUp() {
        super.setUp()
        XCTAssertEqual(runGenerator(), 0, "generate-icons.swift must complete successfully")
    }

    func testAppIconPNGsAndManifestCoverEverySizeInLightAndDark() throws {
        let manifest = try jsonObject(at: appIconURL.appendingPathComponent("Contents.json"))
        let images = try XCTUnwrap(manifest["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, entries.count * 2)

        for entry in entries {
            for dark in [false, true] {
                let filename = "AppIcon\(dark ? "-Dark" : "")-\(entry.pixels).png"
                let matching = images.filter { image in
                    image["size"] as? String == entry.size
                        && image["scale"] as? String == entry.scale
                        && isDarkEntry(image) == dark
                }
                XCTAssertEqual(matching.count, 1, "Expected one \(dark ? "dark" : "light") entry for \(entry.size) \(entry.scale)")
                XCTAssertEqual(matching.first?["filename"] as? String, filename)
                XCTAssertEqual(matching.first?["idiom"] as? String, "mac")

                let imageURL = appIconURL.appendingPathComponent(filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path), "Missing \(filename)")
                let image = try loadImage(at: imageURL)
                XCTAssertEqual(image.width, entry.pixels, filename)
                XCTAssertEqual(image.height, entry.pixels, filename)
                let pixels = try rgbaPixels(from: image)
                let hasVisiblePixel = stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] > 0 })
                XCTAssertTrue(hasVisiblePixel, "\(filename) must contain nontransparent content")
            }
        }
    }

    func testAppIconUsesApprovedFloatingBadgeColorsAtSVGCoordinates() throws {
        let cases = [
            (dark: false, badge: (red: 0xFF, green: 0xFF, blue: 0xFF), pin: (red: 0x77, green: 0x67, blue: 0xC8)),
            (dark: true, badge: (red: 0x8B, green: 0xD0, blue: 0xFF), pin: (red: 0x14, green: 0x22, blue: 0x35)),
        ]
        for testCase in cases {
            let filename = "AppIcon\(testCase.dark ? "-Dark" : "")-1024.png"
            let image = try loadImage(at: appIconURL.appendingPathComponent(filename))
            let badge = try colorAtSVGPoint(x: 52.5, y: 45.5, image: image)
            XCTAssertEqual(badge.red, testCase.badge.red, "\(filename) badge red")
            XCTAssertEqual(badge.green, testCase.badge.green, "\(filename) badge green")
            XCTAssertEqual(badge.blue, testCase.badge.blue, "\(filename) badge blue")

            // SVG translate(-1 -1) scale(.85) maps the pin's (45, 42) to (37.25, 34.7).
            let pin = try colorAtSVGPoint(x: 37.5, y: 34.5, image: image)
            XCTAssertEqual(pin.red, testCase.pin.red, "\(filename) pin red")
            XCTAssertEqual(pin.green, testCase.pin.green, "\(filename) pin green")
            XCTAssertEqual(pin.blue, testCase.pin.blue, "\(filename) pin blue")
        }
    }

    func testMenuTemplateIsBlackAlphaAndUsesTemplateRenderingIntent() throws {
        let menuURL = catalogURL.appendingPathComponent("MenuBarTemplate.imageset")
        let manifest = try jsonObject(at: menuURL.appendingPathComponent("Contents.json"))
        let properties = try XCTUnwrap(manifest["properties"] as? [String: Any])
        XCTAssertEqual(properties["template-rendering-intent"] as? String, "template")

        let images = try XCTUnwrap(manifest["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 2)
        for (scale, pixels) in [("1x", 16), ("2x", 32)] {
            let filename = "MenuBarTemplate-\(pixels).png"
            let entry = try XCTUnwrap(images.first(where: { $0["scale"] as? String == scale }))
            XCTAssertEqual(entry["filename"] as? String, filename)
            XCTAssertEqual(entry["idiom"] as? String, "mac")
            let image = try loadImage(at: menuURL.appendingPathComponent(filename))
            XCTAssertEqual(image.width, pixels)
            XCTAssertEqual(image.height, pixels)

            let bytes = try rgbaPixels(from: image)
            var hasVisiblePixel = false
            var hasPartialAlpha = false
            for index in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = bytes[index + 3]
                guard alpha > 0 else { continue }
                hasVisiblePixel = true
                hasPartialAlpha = hasPartialAlpha || alpha < 255
                XCTAssertEqual(bytes[index], 0, "\(filename) red channel must be black")
                XCTAssertEqual(bytes[index + 1], 0, "\(filename) green channel must be black")
                XCTAssertEqual(bytes[index + 2], 0, "\(filename) blue channel must be black")
            }
            XCTAssertTrue(hasVisiblePixel, "\(filename) must contain visible pixels")
            XCTAssertTrue(hasPartialAlpha, "\(filename) must use alpha at its edges")
        }
    }

    func testInfoPlistNamesAppIcon() throws {
        let plist = try NSDictionary(
            contentsOf: repositoryURL.appendingPathComponent("Resources/Info.plist"),
            error: ()
        ) as? [String: Any]
        XCTAssertEqual(plist?["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist?["CFBundleIconName"] as? String, "AppIcon")
    }

    func testRepeatedGenerationProducesIdenticalResourceBytes() throws {
        let before = try resourceBytes()
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(runGenerator(), 0, "generate-icons.swift must complete successfully on repeated runs")
        XCTAssertEqual(try resourceBytes(), before)
    }

    private func runGenerator() -> Int32 {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = repositoryURL
        process.arguments = ["swift", "Scripts/generate-icons.swift", "Resources/Assets.xcassets"]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            XCTFail("Could not launch icon generator: \(error)")
            return -1
        }
        if process.terminationStatus != 0 {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(decoding: data, as: UTF8.self))
        }
        return process.terminationStatus
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func isDarkEntry(_ entry: [String: Any]) -> Bool {
        guard let appearances = entry["appearances"] as? [[String: String]] else { return false }
        return appearances.contains(where: {
            $0["appearance"] == "luminosity" && $0["value"] == "dark"
        })
    }

    private func colorAtSVGPoint(x: CGFloat, y: CGFloat, image: CGImage) throws -> (red: Int, green: Int, blue: Int) {
        let pixels = try rgbaPixels(from: image)
        let scale = CGFloat(image.width) / 64
        let column = Int(x * scale)
        let rowFromTop = Int(y * scale)
        let index = (rowFromTop * image.width + column) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }

    private func loadImage(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = pixels.withUnsafeMutableBytes { buffer -> CGContext? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            let context = CGContext(
                data: baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context
        }
        _ = try XCTUnwrap(context)
        return pixels
    }

    private func resourceBytes() throws -> [String: Data] {
        let files = [
            catalogURL.appendingPathComponent("Contents.json"),
            appIconURL.appendingPathComponent("Contents.json"),
            catalogURL.appendingPathComponent("MenuBarTemplate.imageset/Contents.json"),
        ] + entries.flatMap { entry in
            [false, true].map { dark in
                appIconURL.appendingPathComponent("AppIcon\(dark ? "-Dark" : "")-\(entry.pixels).png")
            }
        } + [16, 32].map {
            catalogURL.appendingPathComponent("MenuBarTemplate.imageset/MenuBarTemplate-\($0).png")
        }
        var result: [String: Data] = [:]
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
            result[relativePath] = try Data(contentsOf: file)
        }
        return result
    }
}
