import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class GlassBackgroundViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testNormalStateInstallsActiveEmphasizedPopoverMaterial() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = try makePalette()

        view.apply(palette)

        XCTAssertTrue(view.effectView.isDescendant(of: view))
        XCTAssertTrue(view.gradientView.isDescendant(of: view))
        XCTAssertEqual(view.effectView.material, .popover)
        XCTAssertEqual(view.effectView.blendingMode, .behindWindow)
        XCTAssertEqual(view.effectView.state, .active)
        XCTAssertTrue(view.effectView.isEmphasized)
        XCTAssertFalse(view.effectView.isHidden)
        XCTAssertFalse(view.gradientView.isHidden)
        XCTAssertFalse(view.isOpaque)
        XCTAssertNil(view.hitTest(NSPoint(x: 20, y: 20)))
    }

    func testReducedTransparencyHidesMaterialAndGradientBehindSolidFallback() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = try makePalette(reduceTransparency: true)

        view.apply(palette)

        XCTAssertTrue(view.effectView.isHidden)
        XCTAssertTrue(view.gradientView.isHidden)
        try assertBackground(view, equals: palette.solidBackgroundColor)
    }

    func testBlankColorSuppressesPaletteGradientAndBecomesTint() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let blankColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

        view.apply(try makePalette(), blankColor: blankColor)

        XCTAssertTrue(view.effectView.isHidden)
        XCTAssertTrue(view.gradientView.isHidden)
        try assertBackground(view, equals: blankColor)
    }

    func testBlankColorTakesPrecedenceForReducedTransparencyFallback() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let blankColor = NSColor(srgbRed: 0.7, green: 0.3, blue: 0.1, alpha: 1)

        view.apply(try makePalette(reduceTransparency: true), blankColor: blankColor)

        XCTAssertTrue(view.effectView.isHidden)
        XCTAssertTrue(view.gradientView.isHidden)
        try assertBackground(view, equals: blankColor)
    }

    func testReapplyingTransparentPaletteRestoresMaterialAndGradient() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        view.apply(try makePalette(reduceTransparency: true), blankColor: .red)

        view.apply(try makePalette())

        XCTAssertFalse(view.effectView.isHidden)
        XCTAssertFalse(view.gradientView.isHidden)
        try assertBackground(view, equals: .clear)
    }

    func testSwitchingBlankBackToNoteRestoresMaterialAndGradient() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        view.apply(try makePalette(), blankColor: .red)
        XCTAssertTrue(view.effectView.isHidden)

        view.apply(try makePalette())

        XCTAssertFalse(view.effectView.isHidden)
        XCTAssertFalse(view.gradientView.isHidden)
        try assertBackground(view, equals: .clear)
    }

    func testApplyRendersPaletteBorderWithoutCustomLayerShadow() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = try makePalette()

        view.apply(palette)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertGreaterThan(layer.borderWidth, 0)
        XCTAssertEqual(layer.borderColor, palette.borderColor.cgColor)
        XCTAssertEqual(layer.shadowOpacity, 0)
        XCTAssertNil(layer.shadowPath)
    }

    func testLightIncreasedContrastRendersDarkBorderWithMeaningfulContrast() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let normal = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: false
        )
        let contrast = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: true
        )
        view.apply(normal)
        let normalBorder = try renderedBorderColor(view)

        view.apply(contrast)

        let contrastBorder = try renderedBorderColor(view)
        try assertBorder(contrastBorder, red: 0x12, green: 0x19, blue: 0x26, alpha: 0.45)
        let background = NSColor(srgbRed: 0xE0 / 255, green: 0xF4 / 255, blue: 1, alpha: 1)
        let normalRatio = try contrastRatio(normalBorder, over: background)
        let contrastRatio = try contrastRatio(contrastBorder, over: background)
        XCTAssertGreaterThan(contrastRatio, 2)
        XCTAssertGreaterThan(contrastRatio, normalRatio * 2)
    }

    func testDarkIncreasedContrastRendersBrightBorderWithMeaningfulContrast() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let normal = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: false
        )
        let contrast = WorkspaceAppearance.make(
            appearance: appearance,
            reduceTransparency: false,
            increaseContrast: true
        )
        view.apply(normal)
        let normalBorder = try renderedBorderColor(view)

        view.apply(contrast)

        let contrastBorder = try renderedBorderColor(view)
        try assertBorder(contrastBorder, red: 0xFF, green: 0xFF, blue: 0xFF, alpha: 0.55)
        let background = NSColor(srgbRed: 0x12 / 255, green: 0x19 / 255, blue: 0x26 / 255, alpha: 1)
        let normalRatio = try contrastRatio(normalBorder, over: background)
        let contrastRatio = try contrastRatio(contrastBorder, over: background)
        XCTAssertGreaterThan(contrastRatio, 4.5)
        XCTAssertGreaterThan(contrastRatio, normalRatio * 2)
    }

    private func renderedBorderColor(_ view: GlassBackgroundView) throws -> NSColor {
        let border = try XCTUnwrap(view.layer?.borderColor)
        return try XCTUnwrap(NSColor(cgColor: border)?.usingColorSpace(.sRGB))
    }

    private func assertBorder(
        _ color: NSColor,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let components = try sRGBComponents(color, file: file, line: line)
        XCTAssertEqual(components.red, Double(red) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.green, Double(green) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.blue, Double(blue) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.alpha, alpha, accuracy: 0.001, file: file, line: line)
    }

    private func contrastRatio(_ border: NSColor, over background: NSColor) throws -> Double {
        let foreground = try sRGBComponents(border)
        let backdrop = try sRGBComponents(background)
        let alpha = foreground.alpha
        let borderLuminance = luminance(
            red: foreground.red * alpha + backdrop.red * (1 - alpha),
            green: foreground.green * alpha + backdrop.green * (1 - alpha),
            blue: foreground.blue * alpha + backdrop.blue * (1 - alpha)
        )
        let backgroundLuminance = luminance(red: backdrop.red, green: backdrop.green, blue: backdrop.blue)
        return (max(borderLuminance, backgroundLuminance) + 0.05)
            / (min(borderLuminance, backgroundLuminance) + 0.05)
    }

    private func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func sRGBComponents(
        _ color: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let color = try XCTUnwrap(color.usingColorSpace(.sRGB), file: file, line: line)
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    private func makePalette(reduceTransparency: Bool = false) throws -> WorkspacePalette {
        WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            reduceTransparency: reduceTransparency,
            increaseContrast: false
        )
    }

    private func assertBackground(
        _ view: GlassBackgroundView,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let background = try XCTUnwrap(view.layer?.backgroundColor, file: file, line: line)
        let actual = try XCTUnwrap(NSColor(cgColor: background)?.usingColorSpace(.sRGB), file: file, line: line)
        let expected = try XCTUnwrap(expected.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}
