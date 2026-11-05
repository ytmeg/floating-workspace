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

    func testBlankColorSuppressesPaletteGradientAndLeavesPanelColorUnpainted() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let blankColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

        view.apply(try makePalette(), blankColor: blankColor)

        XCTAssertTrue(view.effectView.isHidden)
        XCTAssertTrue(view.gradientView.isHidden)
        try assertBackground(view, equals: .clear)
    }

    func testBlankColorTakesPrecedenceForReducedTransparencyFallback() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let blankColor = NSColor(srgbRed: 0.7, green: 0.3, blue: 0.1, alpha: 1)

        view.apply(try makePalette(reduceTransparency: true), blankColor: blankColor)

        XCTAssertTrue(view.effectView.isHidden)
        XCTAssertTrue(view.gradientView.isHidden)
        try assertBackground(view, equals: .clear)
    }

    func testTranslucentBlankColorIsNotCompositedASecondTime() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let blankColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)

        for palette in [try makePalette(), try makePalette(reduceTransparency: true)] {
            view.apply(palette, blankColor: blankColor)

            let background = try XCTUnwrap(view.layer?.backgroundColor)
            XCTAssertEqual(background.alpha, 0, accuracy: 0.001)
            XCTAssertTrue(view.effectView.isHidden)
            XCTAssertTrue(view.gradientView.isHidden)
        }
    }

    func testGradientInvalidatesOnlyWhenColorsChange() throws {
        let gradient = GradientView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = try makePalette()
        gradient.colors = palette.gradientColors
        let invalidations = gradient.invalidationCount

        gradient.colors = palette.gradientColors
        XCTAssertEqual(gradient.invalidationCount, invalidations)

        gradient.colors = try makePalette(appearance: .darkAqua).gradientColors
        XCTAssertEqual(gradient.invalidationCount, invalidations + 1)
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

    func testBackgroundLayerHasNoBorderOrCustomShadow() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))

        view.apply(try makePalette())

        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(layer.borderWidth, 0)
        XCTAssertEqual(layer.shadowOpacity, 0)
        XCTAssertNil(layer.shadowPath)
    }

    func testBorderStrokesSidesAndRoundedBottomCornersButNotTitlebarEdge() throws {
        let border = GlassBorderView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            reduceTransparency: false,
            increaseContrast: true
        )
        border.apply(palette)
        border.layoutSubtreeIfNeeded()

        let stroke = try XCTUnwrap(border.strokeLayer)
        XCTAssertEqual(stroke.lineWidth, 1)
        XCTAssertNil(stroke.fillColor)
        XCTAssertEqual(stroke.strokeColor, palette.borderColor.cgColor)
        XCTAssertEqual(stroke.frame, border.bounds)
        XCTAssertNil(border.hitTest(NSPoint(x: 1, y: 60)))

        // Bitmap rows run top to bottom; the view is unflipped, so the titlebar edge is row 0.
        let alpha = try renderedAlpha(stroke, size: border.bounds.size)
        XCTAssertGreaterThan(alpha(0, 60), 0, "left side")
        XCTAssertGreaterThan(alpha(199, 60), 0, "right side")
        XCTAssertGreaterThan(alpha(100, 119), 0, "bottom edge")
        XCTAssertEqual(alpha(100, 0), 0, "titlebar edge must not get a second line")
        XCTAssertEqual(alpha(0, 119), 0, "bottom-left corner follows the panel radius")
        XCTAssertEqual(alpha(199, 119), 0, "bottom-right corner follows the panel radius")
        XCTAssertGreaterThan(alpha(0, 0), 0, "top corners stay square under the titlebar")
        // The stroke centerline sits 0.5 pt inside the edge; sample around its 45° point.
        let radius = GlassBorderView.bottomCornerRadius
        let inset = Int(radius - (radius - 0.5) / 2.0.squareRoot())
        let arc: (Int, Int) -> UInt8 = { x, row in
            (-1...1).flatMap { dx in (-1...1).map { dy in alpha(x + dx, row + dy) } }.max() ?? 0
        }
        XCTAssertGreaterThan(arc(inset, 119 - inset), 0, "bottom-left arc")
        XCTAssertGreaterThan(arc(199 - inset, 119 - inset), 0, "bottom-right arc")
        XCTAssertEqual(alpha(inset + 3, 119 - inset - 3), 0, "arc interior stays unpainted")
    }

    func testBorderPathTracksResize() throws {
        let border = GlassBorderView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        border.apply(try makePalette())
        border.layoutSubtreeIfNeeded()

        border.setFrameSize(NSSize(width: 400, height: 300))
        border.layoutSubtreeIfNeeded()

        let stroke = try XCTUnwrap(border.strokeLayer)
        XCTAssertEqual(stroke.frame, border.bounds)
        let box = try XCTUnwrap(stroke.path?.boundingBoxOfPath)
        XCTAssertEqual(box.minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 399.5, accuracy: 0.001)
        XCTAssertEqual(box.minY, 0.5, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 300, accuracy: 0.001)
    }

    func testLightIncreasedContrastRendersDarkBorderWithMeaningfulContrast() throws {
        let view = GlassBorderView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
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
        let view = GlassBorderView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
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

    private func renderedAlpha(_ layer: CALayer, size: NSSize) throws -> (Int, Int) -> UInt8 {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            layer.render(in: context)
        }
        // Bitmap memory starts with the top row, so row 0 is the titlebar edge.
        return { x, row in pixels[(row * width + x) * 4 + 3] }
    }

    private func renderedBorderColor(_ view: GlassBorderView) throws -> NSColor {
        let border = try XCTUnwrap(view.strokeLayer?.strokeColor)
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

    private func makePalette(
        appearance: NSAppearance.Name = .aqua,
        reduceTransparency: Bool = false
    ) throws -> WorkspacePalette {
        WorkspaceAppearance.make(
            appearance: try XCTUnwrap(NSAppearance(named: appearance)),
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
