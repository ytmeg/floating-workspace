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

        XCTAssertFalse(view.effectView.isHidden)
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

    func testApplyRendersPaletteBorderAndShadowOnBackgroundLayer() throws {
        let view = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let palette = try makePalette()

        view.apply(palette)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertGreaterThan(layer.borderWidth, 0)
        XCTAssertEqual(layer.borderColor, palette.borderColor.cgColor)
        XCTAssertGreaterThan(layer.shadowOpacity, 0)
        XCTAssertGreaterThan(layer.shadowRadius, 0)
        XCTAssertEqual(layer.shadowColor, palette.shadowColor.cgColor)
    }

    func testIncreasedContrastStrengthensRenderedBorder() throws {
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
        let normalBorder = try XCTUnwrap(view.layer?.borderColor)
        let normalAlpha = try XCTUnwrap(NSColor(cgColor: normalBorder)).alphaComponent

        view.apply(contrast)

        let contrastBorder = try XCTUnwrap(view.layer?.borderColor)
        XCTAssertEqual(contrastBorder, contrast.borderColor.cgColor)
        XCTAssertGreaterThan(NSColor(cgColor: contrastBorder)?.alphaComponent ?? 0, normalAlpha)
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
