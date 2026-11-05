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

    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs = []
        super.tearDown()
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

    func testMenuTemplateMatchesApprovedPaneRotationsAndAlpha() throws {
        let image = try loadImage(at: catalogURL.appendingPathComponent("MenuBarTemplate.imageset/MenuBarTemplate-32.png"))
        let pixels = try rgbaPixels(from: image)
        let cases = [
            (x: 18.0, y: 21.0, alpha: 64),       // Back rect only: 0.25 alpha.
            (x: 48.0, y: 27.0, alpha: 115),      // Front rect only: 0.45 alpha.
            (x: 27.5, y: 27.5, alpha: 150),      // Overlap: 1 - 0.75 × 0.55.
            (x: 52.5, y: 45.5, alpha: 255),      // Opaque badge.
            (x: 38.5, y: 33.0, alpha: 0),        // Interior of transformed pin cutout.
        ]
        for testCase in cases {
            let cardX = 1 + testCase.x * 60 / 64
            let cardY = 1 + testCase.y * 60 / 64
            let column = Int(cardX * Double(image.width) / 82)
            let row = Int(cardY * Double(image.height) / 82)
            let alpha = pixels[(row * image.width + column) * 4 + 3]
            XCTAssertEqual(Double(alpha), Double(testCase.alpha), accuracy: 2, "SVG point (\(testCase.x), \(testCase.y))")
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

    func testGeneratedResourcesMatchCommittedBytesWithoutRewritingThem() throws {
        let committedBefore = try resourceBytes(in: catalogURL)
        let modifiedBefore = try modificationDates(in: catalogURL)
        let generatedURL = try temporaryDirectory().appendingPathComponent("Assets.xcassets")

        XCTAssertEqual(runGenerator(outputURL: generatedURL), 0, "generate-icons.swift must complete successfully")

        let generated = try resourceBytes(in: generatedURL)
        XCTAssertEqual(Set(generated.keys), Set(committedBefore.keys))
        for (path, data) in generated {
            XCTAssertEqual(data, committedBefore[path], "Committed icon resource drifted: \(path)")
        }
        XCTAssertEqual(try resourceBytes(in: catalogURL), committedBefore)
        XCTAssertEqual(try modificationDates(in: catalogURL), modifiedBefore)
    }

    func testRepeatedGenerationProducesIdenticalResourceBytes() throws {
        let first = try temporaryDirectory().appendingPathComponent("Assets.xcassets")
        let second = try temporaryDirectory().appendingPathComponent("Assets.xcassets")

        XCTAssertEqual(runGenerator(outputURL: first), 0)
        XCTAssertEqual(runGenerator(outputURL: second), 0)

        let bytes = try resourceBytes(in: first)
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertEqual(try resourceBytes(in: second), bytes)
    }

    func testDriftCheckPassesForCommittedResourcesWithoutRewritingThem() throws {
        let modifiedBefore = try modificationDates(in: catalogURL)
        let committedBefore = try resourceBytes(in: catalogURL)

        let result = runDriftCheck(catalogURL: nil)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try resourceBytes(in: catalogURL), committedBefore)
        XCTAssertEqual(try modificationDates(in: catalogURL), modifiedBefore)
    }

    func testDriftCheckFailsAndNamesTheDriftedFile() throws {
        let copyURL = try temporaryDirectory().appendingPathComponent("Assets.xcassets")
        try FileManager.default.copyItem(at: catalogURL, to: copyURL)
        let drifted = copyURL.appendingPathComponent("AppIcon.appiconset/AppIcon-Dark-64.png")
        var bytes = try Data(contentsOf: drifted)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: drifted)

        let result = runDriftCheck(catalogURL: copyURL)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("AppIcon.appiconset/AppIcon-Dark-64.png"), result.output)
        XCTAssertEqual(try Data(contentsOf: drifted), bytes, "check mode must not repair drift")
    }

    func testDriftCheckFailsForMissingAndUnexpectedFiles() throws {
        let copyURL = try temporaryDirectory().appendingPathComponent("Assets.xcassets")
        try FileManager.default.copyItem(at: catalogURL, to: copyURL)
        try FileManager.default.removeItem(at: copyURL.appendingPathComponent("MenuBarTemplate.imageset/MenuBarTemplate-16.png"))
        try Data([0]).write(to: copyURL.appendingPathComponent("AppIcon.appiconset/Stale.png"))

        let result = runDriftCheck(catalogURL: copyURL)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("MenuBarTemplate.imageset/MenuBarTemplate-16.png"), result.output)
        XCTAssertTrue(result.output.contains("AppIcon.appiconset/Stale.png"), result.output)
    }

    func testDriftCheckUpdateModeRegeneratesIntentionally() throws {
        let copyURL = try temporaryDirectory().appendingPathComponent("Assets.xcassets")
        try FileManager.default.copyItem(at: catalogURL, to: copyURL)
        let drifted = copyURL.appendingPathComponent("AppIcon.appiconset/AppIcon-16.png")
        try Data([0]).write(to: drifted)

        let update = runDriftCheck(catalogURL: copyURL, arguments: ["--update"])
        XCTAssertEqual(update.status, 0, update.output)

        XCTAssertEqual(try resourceBytes(in: copyURL), try resourceBytes(in: catalogURL))
        XCTAssertEqual(runDriftCheck(catalogURL: copyURL).status, 0)
    }

    private func runGenerator(outputURL: URL) -> Int32 {
        run(["swift", "Scripts/generate-icons.swift", outputURL.path]).status
    }

    private func runDriftCheck(catalogURL: URL?, arguments: [String] = []) -> (status: Int32, output: String) {
        var environment = ProcessInfo.processInfo.environment
        if let catalogURL {
            environment["ICON_CATALOG"] = catalogURL.path
        }
        return run(["zsh", "Scripts/check-icon-resources.sh"] + arguments, environment: environment)
    }

    private func run(_ arguments: [String], environment: [String: String]? = nil) -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = repositoryURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            XCTFail("Could not launch \(arguments): \(error)")
            return (-1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, text)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IconResourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
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
        let scale = CGFloat(image.width) / 82
        let cardX = 1 + x * 60 / 64
        let cardY = 1 + y * 60 / 64
        let column = Int(cardX * scale)
        let rowFromTop = Int(cardY * scale)
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

    private func resourceBytes(in catalog: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in try resourcePaths(in: catalog) {
            result[path] = try Data(contentsOf: catalog.appendingPathComponent(path))
        }
        return result
    }

    private func modificationDates(in catalog: URL) throws -> [String: Date] {
        var result: [String: Date] = [:]
        for path in try resourcePaths(in: catalog) {
            let values = try catalog.appendingPathComponent(path).resourceValues(forKeys: [.contentModificationDateKey])
            result[path] = values.contentModificationDate
        }
        return result
    }

    private func resourcePaths(in catalog: URL) throws -> [String] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: catalog,
            includingPropertiesForKeys: [.isRegularFileKey]
        ))
        let prefix = catalog.resolvingSymlinksInPath().path + "/"
        return try enumerator.compactMap { item in
            let url = try XCTUnwrap(item as? URL)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  url.lastPathComponent != ".DS_Store" else { return nil }
            return url.resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "")
        }.sorted()
    }
}
