import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ApplicationIconControllerTests: XCTestCase {
    private var originalAppearance: NSAppearance?
    private var originalIcon: NSImage?
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        originalAppearance = NSApp.appearance
        originalIcon = NSApp.applicationIconImage
    }

    override func tearDown() {
        NSApp.appearance = originalAppearance
        NSApp.applicationIconImage = originalIcon
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testPackagedPNGsFollowLightAndDarkEffectiveAppearance() throws {
        let bundle = try makeBundle(includeIcons: true)
        NSApp.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let controller = ApplicationIconController(application: NSApp, bundle: bundle)

        XCTAssertTrue(icon(named: "AppIcon-Light", matchesIn: bundle), "Initial light appearance must use the packaged light PNG")
        withExtendedLifetime(controller) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            XCTAssertTrue(waitForIcon(named: "AppIcon-Dark", in: bundle), "Dark appearance must use the packaged dark PNG")

            NSApp.appearance = NSAppearance(named: .aqua)
            XCTAssertTrue(waitForIcon(named: "AppIcon-Light", in: bundle), "Returning to light appearance must restore the light PNG")
        }
    }

    func testMissingRuntimePNGLeavesStaticApplicationIconUnchanged() throws {
        let bundle = try makeBundle(includeIcons: false)
        let sentinel = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        NSApp.applicationIconImage = sentinel
        let sentinelPixels = pixelBytes(NSApp.applicationIconImage)
        NSApp.appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let controller = ApplicationIconController(application: NSApp, bundle: bundle)
        withExtendedLifetime(controller) {
            XCTAssertEqual(pixelBytes(NSApp.applicationIconImage), sentinelPixels)
            controller.update()
            XCTAssertEqual(pixelBytes(NSApp.applicationIconImage), sentinelPixels)
        }
    }

    private func makeBundle(includeIcons: Bool) throws -> Bundle {
        if includeIcons, let packagedPath = ProcessInfo.processInfo.environment["FLOATING_WORKSPACE_ICON_TEST_BUNDLE"] {
            return try XCTUnwrap(Bundle(url: URL(fileURLWithPath: packagedPath)))
        }
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationIconControllerTests-\(UUID().uuidString).bundle")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        temporaryDirectories.append(bundleURL)
        let info: NSDictionary = [
            "CFBundleIdentifier": "local.floatingworkspace.icon-tests.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
        ]
        XCTAssertTrue(info.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"), atomically: true))

        if includeIcons {
            let repositoryURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appIconURL = repositoryURL.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
            try FileManager.default.copyItem(
                at: appIconURL.appendingPathComponent("AppIcon-1024.png"),
                to: resourcesURL.appendingPathComponent("AppIcon-Light.png")
            )
            try FileManager.default.copyItem(
                at: appIconURL.appendingPathComponent("AppIcon-Dark-1024.png"),
                to: resourcesURL.appendingPathComponent("AppIcon-Dark.png")
            )
        }
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func icon(named name: String, matchesIn bundle: Bundle) -> Bool {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let expected = NSImage(contentsOf: url),
              let expectedPixels = pixelBytes(expected),
              let actualPixels = pixelBytes(NSApp.applicationIconImage) else { return false }
        let width = Int(NSApp.applicationIconImage?.size.width ?? 0)
        let height = Int(NSApp.applicationIconImage?.size.height ?? 0)
        guard width == Int(expected.size.width), height == Int(expected.size.height) else { return false }
        return [(52.5, 45.5), (37.5, 34.5)].allSatisfy { x, y in
            sample(actualPixels, width: width, height: height, x: x, y: y)
                == sample(expectedPixels, width: width, height: height, x: x, y: y)
        }
    }

    private func waitForIcon(named name: String, in bundle: Bundle) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if icon(named: name, matchesIn: bundle) { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return icon(named: name, matchesIn: bundle)
    }

    private func sample(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        x: Double,
        y: Double
    ) -> [UInt8] {
        let cardX = 1 + x * 60 / 64
        let cardY = 1 + y * 60 / 64
        let column = Int(cardX * Double(width) / 82)
        let row = Int(cardY * Double(height) / 82)
        let index = (row * width + column) * 4
        return Array(pixels[index..<index + 3])
    }

    private func pixelBytes(_ image: NSImage?) -> [UInt8]? {
        guard let image,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> [UInt8]? in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            image.draw(
                in: CGRect(x: 0, y: 0, width: width, height: height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            NSGraphicsContext.restoreGraphicsState()
            return Array(buffer)
        }
    }
}
