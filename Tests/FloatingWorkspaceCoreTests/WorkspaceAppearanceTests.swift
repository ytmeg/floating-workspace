import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class WorkspaceAppearanceTests: XCTestCase {
    func testLightPaletteUsesApprovedBluePurpleGradient() throws {
        let light = WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            reduceTransparency: false,
            increaseContrast: false
        )

        XCTAssertTrue(light.usesTransparency)
        XCTAssertEqual(light.gradientColors.count, 2)
        try assertColor(light.gradientColors[0], red: 0xE0, green: 0xF4, blue: 0xFF, alpha: 0.68)
        try assertColor(light.gradientColors[1], red: 0xEE, green: 0xE4, blue: 0xFF, alpha: 0.60)
    }

    func testDarkPaletteUsesApprovedBackgroundAndAccent() throws {
        let dark = WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)),
            reduceTransparency: false,
            increaseContrast: false
        )

        XCTAssertTrue(dark.usesTransparency)
        XCTAssertEqual(dark.gradientColors.count, 2)
        try assertColor(dark.gradientColors[0], red: 0x12, green: 0x19, blue: 0x26, alpha: 0.64)
        try assertColor(dark.gradientColors[1], red: 0x12, green: 0x19, blue: 0x26, alpha: 0.64)
        XCTAssertEqual(dark.accentColor, NSColor(srgbRed: 0x8B / 255, green: 0xD0 / 255, blue: 0xFF / 255, alpha: 1))
    }

    func testReduceTransparencyReturnsSolidLightAndDarkFallbacks() throws {
        let light = WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            reduceTransparency: true,
            increaseContrast: false
        )
        let dark = WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)),
            reduceTransparency: true,
            increaseContrast: false
        )

        XCTAssertFalse(light.usesTransparency)
        XCTAssertTrue(light.gradientColors.isEmpty)
        XCTAssertEqual(light.solidBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(light.contentBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(light.railBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertFalse(dark.usesTransparency)
        XCTAssertTrue(dark.gradientColors.isEmpty)
        XCTAssertEqual(dark.contentBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(dark.railBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        try assertColor(dark.solidBackgroundColor, red: 0x12, green: 0x19, blue: 0x26, alpha: 1)
    }

    func testIncreaseContrastStrengthensBorderWithoutChangingAccent() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let light = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: false
        )
        let contrast = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: true
        )

        XCTAssertGreaterThan(contrast.borderColor.alphaComponent, light.borderColor.alphaComponent)
        XCTAssertEqual(contrast.accentColor, light.accentColor)
    }

    func testCurrentPaletteUsesWorkspaceAccessibilityFlags() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let workspace = NSWorkspace.shared
        let expected = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )

        let current = WorkspaceAppearance.current(appearance: appearance)

        XCTAssertEqual(current.usesTransparency, expected.usesTransparency)
        XCTAssertEqual(current.gradientColors, expected.gradientColors)
        XCTAssertEqual(current.solidBackgroundColor, expected.solidBackgroundColor)
        XCTAssertEqual(current.contentBackgroundColor, expected.contentBackgroundColor)
        XCTAssertEqual(current.railBackgroundColor, expected.railBackgroundColor)
        XCTAssertEqual(current.accentColor, expected.accentColor)
        XCTAssertEqual(current.borderColor, expected.borderColor)
        XCTAssertEqual(current.shadowColor, expected.shadowColor)
    }

    private func assertColor(
        _ color: NSColor,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(color.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(color.redComponent, Double(red) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.greenComponent, Double(green) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.blueComponent, Double(blue) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.alphaComponent, alpha, accuracy: 0.001, file: file, line: line)
    }
}
