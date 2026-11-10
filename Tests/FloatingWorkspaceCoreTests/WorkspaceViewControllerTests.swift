import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class WorkspaceViewControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSWindow.removeFrame(usingName: "FloatingWorkspaceFrame")
    }

    override func tearDown() {
        WorkspaceAppearance.acceptanceReduceTransparency = nil
        WorkspaceAppearance.acceptanceIncreaseContrast = nil
        super.tearDown()
    }

    func testPhaseOneControlsUseApprovedSizingAndIdentifiers() throws {
        let fixture = try makeWorkspace()

        XCTAssertTrue(fixture.workspace.noteButton.isEnabled)
        XCTAssertTrue(fixture.workspace.blankButton.isEnabled)
        XCTAssertTrue(fixture.workspace.imageButton.isEnabled)
        XCTAssertTrue(fixture.workspace.webButton.isEnabled)
        XCTAssertTrue(fixture.workspace.noteButton.isBordered)
        XCTAssertTrue(fixture.workspace.imageButton.isBordered)
        XCTAssertTrue(fixture.workspace.webButton.isBordered)
        XCTAssertTrue(fixture.workspace.blankButton.isBordered)
        XCTAssertEqual(fixture.workspace.noteTextView.font?.pointSize, 16)

        fixture.workspace.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(fixture.workspace.leftRail.frame.width, 76, accuracy: 0.001)

        XCTAssertEqual(fixture.workspace.noteButton.accessibilityIdentifier(), "mode-note")
        XCTAssertEqual(fixture.workspace.imageButton.accessibilityIdentifier(), "mode-image")
        XCTAssertEqual(fixture.workspace.webButton.accessibilityIdentifier(), "mode-web")
        XCTAssertEqual(fixture.workspace.blankButton.accessibilityIdentifier(), "mode-blank")
        XCTAssertEqual(fixture.workspace.noteTextView.accessibilityIdentifier(), "note-editor")
        XCTAssertEqual(fixture.workspace.blankTitleField.accessibilityIdentifier(), "blank-title")
        XCTAssertEqual(fixture.workspace.colorWell.accessibilityIdentifier(), "blank-color")
        XCTAssertEqual(fixture.workspace.widthField.accessibilityIdentifier(), "blank-width")
        XCTAssertEqual(fixture.workspace.heightField.accessibilityIdentifier(), "blank-height")
        XCTAssertEqual(fixture.workspace.saveStateLabel.accessibilityIdentifier(), "save-state")
    }

    func testGlassBackgroundIsBackmostAndUsesCurrentPalette() throws {
        let fixture = try makeWorkspace()
        let glassViews = fixture.workspace.view.subviews.compactMap { $0 as? GlassBackgroundView }
        let glass = try XCTUnwrap(glassViews.first)
        let palette = WorkspaceAppearance.current(appearance: fixture.workspace.view.effectiveAppearance)
        let statusBar = try XCTUnwrap(fixture.workspace.saveStateLabel.superview?.superview)

        XCTAssertEqual(glassViews.count, 1)
        XCTAssertTrue(fixture.workspace.view.subviews.first === glass)
        fixture.workspace.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(glass.frame, fixture.workspace.view.bounds)
        XCTAssertEqual(glass.gradientView.colors, palette.gradientColors)
        XCTAssertEqual(fixture.workspace.noteScrollView.backgroundColor, palette.contentBackgroundColor)
        XCTAssertEqual(fixture.workspace.noteTextView.backgroundColor, palette.contentBackgroundColor)
        XCTAssertEqual(fixture.workspace.noteTextView.textColor, .labelColor)
        XCTAssertEqual(fixture.workspace.leftRail.layer?.backgroundColor, palette.railBackgroundColor.cgColor)
        XCTAssertEqual(statusBar.layer?.backgroundColor, palette.contentBackgroundColor.cgColor)
    }

    func testModeButtonsHaveSymbolsAndDynamicSelectionColors() throws {
        let fixture = try makeWorkspace()
        let buttons = [
            fixture.workspace.noteButton,
            fixture.workspace.imageButton,
            fixture.workspace.webButton,
            fixture.workspace.blankButton
        ]
        let palette = WorkspaceAppearance.current(appearance: fixture.workspace.view.effectiveAppearance)

        XCTAssertEqual(buttons.map(\.title), ["便签", "图片", "网页", "空白"])
        for button in buttons {
            XCTAssertNotNil(button.image)
            XCTAssertEqual(button.imagePosition, .imageLeading)
        }
        fixture.workspace.view.layoutSubtreeIfNeeded()
        for button in buttons {
            XCTAssertEqual(button.frame.height, 44, accuracy: 0.001)
        }
        XCTAssertTrue(fixture.workspace.imageButton.isEnabled)
        XCTAssertTrue(fixture.workspace.webButton.isEnabled)
        XCTAssertEqual(fixture.workspace.noteButton.contentTintColor, palette.accentColor)
        XCTAssertEqual(fixture.workspace.blankButton.contentTintColor, .labelColor)

        fixture.workspace.selectMode(.blank)

        XCTAssertEqual(fixture.workspace.noteButton.contentTintColor, .labelColor)
        XCTAssertEqual(fixture.workspace.blankButton.contentTintColor, palette.accentColor)

        fixture.workspace.selectMode(.web)

        XCTAssertEqual(fixture.workspace.blankButton.contentTintColor, .labelColor)
        XCTAssertEqual(fixture.workspace.webButton.contentTintColor, palette.accentColor)

        fixture.workspace.selectMode(.image)

        XCTAssertEqual(fixture.workspace.webButton.contentTintColor, .labelColor)
        XCTAssertEqual(fixture.workspace.imageButton.contentTintColor, palette.accentColor)
    }

    func testAppearanceChangesRefreshPaletteWithoutChangingOrSavingContent() throws {
        var initial = WorkspaceContent.default
        initial.noteText = "保留正文"
        initial.isPinned = true
        let scheduler = ManualSaveScheduler()
        let saver = ControlledWorkspaceSaver()
        let store = try ContentStore(
            loader: FakeWorkspaceLoader(content: initial),
            scheduler: scheduler,
            saver: saver
        )
        let window = FloatingWindowController(store: store)
        let workspace = try XCTUnwrap(window.panel.contentViewController as? WorkspaceViewController)
        let menu = MenuBarController(windowController: window)
        let pinItem = try XCTUnwrap(menu.statusItem.menu?.items.first { $0.title == "切换置顶" })
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

        for appearance in [light, dark] {
            workspace.view.appearance = appearance
            workspace.view.viewDidChangeEffectiveAppearance()

            let glass = try XCTUnwrap(workspace.view.subviews.compactMap { $0 as? GlassBackgroundView }.first)
            let palette = WorkspaceAppearance.current(appearance: workspace.view.effectiveAppearance)
            XCTAssertEqual(glass.gradientView.colors, palette.gradientColors)
            XCTAssertEqual(workspace.noteScrollView.backgroundColor, palette.contentBackgroundColor)
            XCTAssertEqual(workspace.leftRail.layer?.backgroundColor, palette.railBackgroundColor.cgColor)
            XCTAssertEqual(window.pinButton.state, .on)
            XCTAssertEqual(window.pinButton.title, "已置顶")
            menu.menuNeedsUpdate(try XCTUnwrap(menu.statusItem.menu))
            XCTAssertEqual(pinItem.state, .on)
            XCTAssertEqual(workspace.noteTextView.string, "保留正文")
            XCTAssertEqual(store.content.selectedMode, .note)
            XCTAssertTrue(store.content.isPinned)
        }

        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(scheduler.delays.isEmpty)
        XCTAssertTrue(saver.snapshots.isEmpty)
    }

    func testAccessibilityDisplayOptionsNotificationSwitchesGlassAndSolidFallback() throws {
        WorkspaceAppearance.acceptanceReduceTransparency = false
        let fixture = try makeWorkspace()
        let glass = fixture.workspace.glassBackgroundView
        XCTAssertFalse(glass.effectView.isHidden)
        XCTAssertFalse(glass.gradientView.isHidden)

        for reduceTransparency in [true, false, true] {
            let updates = fixture.workspace.glassAppearanceUpdateCount
            WorkspaceAppearance.acceptanceReduceTransparency = reduceTransparency

            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )

            let palette = WorkspaceAppearance.current(appearance: fixture.workspace.view.effectiveAppearance)
            XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates + 1, "exactly one subscription")
            XCTAssertEqual(glass.effectView.isHidden, reduceTransparency)
            XCTAssertEqual(glass.gradientView.isHidden, reduceTransparency)
            let background = try XCTUnwrap(glass.layer?.backgroundColor)
            XCTAssertEqual(background, reduceTransparency ? palette.solidBackgroundColor.cgColor : NSColor.clear.cgColor)
            XCTAssertEqual(fixture.workspace.leftRail.layer?.backgroundColor, palette.railBackgroundColor.cgColor)
            XCTAssertEqual(fixture.workspace.noteScrollView.backgroundColor, palette.contentBackgroundColor)
        }
        XCTAssertFalse(fixture.doubles.store.isDirty)
    }

    func testEffectiveAppearanceChangeStillRestylesUnconditionally() throws {
        let fixture = try makeWorkspace()
        let updates = fixture.workspace.glassAppearanceUpdateCount

        // Assigning the appearance triggers AppKit's own effective-appearance callback.
        fixture.workspace.view.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates + 1)
        let palette = WorkspaceAppearance.current(appearance: fixture.workspace.view.effectiveAppearance)
        XCTAssertEqual(fixture.workspace.glassBackgroundView.gradientView.colors, palette.gradientColors)
        XCTAssertEqual(fixture.workspace.borderView.strokeLayer?.strokeColor, palette.borderColor.cgColor)
    }

    func testNoteOnlyEditsDoNotRestyleOrRedrawGlass() throws {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let workspace = try XCTUnwrap(window.panel.contentViewController as? WorkspaceViewController)
        let store = doubles.store
        let gradient = workspace.glassBackgroundView.gradientView
        let updates = workspace.glassAppearanceUpdateCount
        let invalidations = gradient.invalidationCount

        for text in ["a", "ab", "abc"] {
            workspace.noteTextView.string = text
            workspace.textDidChange(Notification(
                name: NSText.didChangeNotification,
                object: workspace.noteTextView
            ))
        }
        store.update { $0.isPinned.toggle() }
        store.update { $0.blankTitle = "只改标题" }

        XCTAssertEqual(store.content.noteText, "abc")
        XCTAssertEqual(workspace.saveStateLabel.stringValue, "保存中")
        XCTAssertEqual(workspace.glassAppearanceUpdateCount, updates)
        XCTAssertEqual(gradient.invalidationCount, invalidations)

        workspace.view.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertEqual(workspace.glassAppearanceUpdateCount, updates + 1)
        XCTAssertEqual(gradient.invalidationCount, invalidations + 1, "a palette change still redraws the gradient")
    }

    func testBlankModeAndColorChangesStillRestyle() throws {
        let fixture = try makeWorkspace()
        let store = fixture.doubles.store
        var updates = fixture.workspace.glassAppearanceUpdateCount

        fixture.workspace.selectMode(.blank)
        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates + 1)
        XCTAssertTrue(fixture.workspace.glassBackgroundView.effectView.isHidden)
        updates = fixture.workspace.glassAppearanceUpdateCount

        store.update { $0.blankTitle = "空白标题" }
        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates)

        store.update { $0.blankBackground = RGBAColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5) }
        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates + 1)
        let well = try XCTUnwrap(fixture.workspace.colorWell.color.usingColorSpace(.sRGB))
        XCTAssertEqual(well.blueComponent, 0.8, accuracy: 0.001)
        XCTAssertEqual(well.alphaComponent, 0.5, accuracy: 0.001)

        fixture.workspace.selectMode(.note)
        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates + 2)
        XCTAssertFalse(fixture.workspace.glassBackgroundView.effectView.isHidden)
    }

    func testTranslucentBlankColorIsPaintedOnceByThePanel() throws {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let workspace = try XCTUnwrap(window.panel.contentViewController as? WorkspaceViewController)

        doubles.store.update {
            $0.selectedMode = .blank
            $0.blankBackground = RGBAColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)
        }

        let panelColor = try XCTUnwrap(window.panel.backgroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(panelColor.blueComponent, 0.8, accuracy: 0.001)
        XCTAssertEqual(panelColor.alphaComponent, 0.5, accuracy: 0.001)
        let glassBackground = try XCTUnwrap(workspace.glassBackgroundView.layer?.backgroundColor)
        XCTAssertEqual(glassBackground.alpha, 0, accuracy: 0.001)
        XCTAssertTrue(workspace.glassBackgroundView.effectView.isHidden)
        XCTAssertTrue(workspace.glassBackgroundView.gradientView.isHidden)
    }

    func testBorderOverlayIsFrontmostAndCoversContent() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(fixture.workspace.view.subviews.last === fixture.workspace.borderView)
        XCTAssertEqual(fixture.workspace.borderView.frame, fixture.workspace.view.bounds)
        XCTAssertNil(fixture.workspace.borderView.hitTest(NSPoint(x: 10, y: 10)))
        let palette = WorkspaceAppearance.current(appearance: fixture.workspace.view.effectiveAppearance)
        XCTAssertEqual(fixture.workspace.borderView.strokeLayer?.strokeColor, palette.borderColor.cgColor)
    }

    func testReclickingSelectedNoteToggleKeepsItOn() throws {
        let fixture = try makeWorkspace()
        XCTAssertEqual(fixture.workspace.noteButton.state, .on)

        fixture.workspace.noteButton.performClick(nil)

        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .note)
        XCTAssertEqual(fixture.workspace.noteButton.state, .on)
        XCTAssertEqual(fixture.workspace.blankButton.state, .off)
    }

    func testReclickingSelectedBlankToggleKeepsItOn() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)
        XCTAssertEqual(fixture.workspace.blankButton.state, .on)

        fixture.workspace.blankButton.performClick(nil)

        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .blank)
        XCTAssertEqual(fixture.workspace.blankButton.state, .on)
        XCTAssertEqual(fixture.workspace.noteButton.state, .off)
    }

    func testImageModeInstallsOneEditorAndUpdatesVisibleContainer() throws {
        let fixture = try makeWorkspace()
        let editor = fixture.workspace.imageViewController
        XCTAssertTrue(fixture.workspace.children.contains { $0 === editor })
        XCTAssertTrue(editor.view.isDescendant(of: fixture.workspace.imageContainer))
        XCTAssertTrue(fixture.workspace.imageContainer.isHidden)

        fixture.workspace.selectMode(.web)
        fixture.workspace.selectMode(.image)

        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .image)
        XCTAssertTrue(fixture.workspace.webContainer.isHidden)
        XCTAssertTrue(fixture.workspace.noteScrollView.isHidden)
        XCTAssertTrue(fixture.workspace.blankContainer.isHidden)
        XCTAssertFalse(fixture.workspace.imageContainer.isHidden)
        XCTAssertEqual(fixture.workspace.imageButton.state, .on)
        XCTAssertEqual(fixture.workspace.webButton.state, .off)

        fixture.workspace.selectMode(.blank)
        XCTAssertTrue(fixture.workspace.imageContainer.isHidden)
        fixture.workspace.selectMode(.image)
        XCTAssertTrue(fixture.workspace.imageViewController === editor)
        XCTAssertFalse(fixture.workspace.imageContainer.isHidden)
    }

    func testWebModeInstallsOneBrowserAndUpdatesVisibleContainer() throws {
        let fixture = try makeWorkspace()
        let browser = fixture.workspace.webViewController
        XCTAssertTrue(fixture.workspace.children.contains { $0 === browser })
        XCTAssertTrue(browser.view.isDescendant(of: fixture.workspace.webContainer))
        XCTAssertTrue(fixture.workspace.webContainer.isHidden)

        fixture.workspace.selectMode(.web)

        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .web)
        XCTAssertFalse(fixture.workspace.webContainer.isHidden)
        XCTAssertTrue(fixture.workspace.noteScrollView.isHidden)
        XCTAssertTrue(fixture.workspace.blankContainer.isHidden)
        XCTAssertEqual(fixture.workspace.webButton.state, .on)
        XCTAssertEqual(fixture.workspace.noteButton.state, .off)
        XCTAssertEqual(fixture.workspace.blankButton.state, .off)

        fixture.workspace.selectMode(.blank)
        XCTAssertTrue(fixture.workspace.webContainer.isHidden)
        fixture.workspace.selectMode(.web)
        XCTAssertTrue(fixture.workspace.webViewController === browser)
        XCTAssertFalse(fixture.workspace.webContainer.isHidden)
    }

    func testReclickingSelectedWebToggleKeepsItOn() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.web)
        XCTAssertEqual(fixture.workspace.webButton.state, .on)

        fixture.workspace.webButton.performClick(nil)

        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .web)
        XCTAssertEqual(fixture.workspace.webButton.state, .on)
        XCTAssertFalse(fixture.workspace.webContainer.isHidden)
    }

    func testWebDraftEmissionsStayVisibleWithoutRestyling() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.web)
        let updates = fixture.workspace.glassAppearanceUpdateCount
        let invalidations = fixture.workspace.glassBackgroundView.gradientView.invalidationCount
        let drafts = WebDraftStore(store: fixture.doubles.store)

        try drafts.saveDraft(WebDraft(
            url: "https://example.com/",
            sanitizedBodyHTML: "<p>draft</p>",
            updatedAt: Date(timeIntervalSince1970: 1)
        ))

        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates)
        XCTAssertEqual(fixture.workspace.glassBackgroundView.gradientView.invalidationCount, invalidations)
        XCTAssertEqual(fixture.workspace.webButton.state, .on)
        XCTAssertFalse(fixture.workspace.webContainer.isHidden)
    }

    func testSelectingBlankAndNoteModesUpdatesVisibleEditor() throws {
        let fixture = try makeWorkspace()

        fixture.workspace.selectMode(.blank)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .blank)
        XCTAssertFalse(fixture.workspace.blankContainer.isHidden)
        XCTAssertTrue(fixture.workspace.noteScrollView.isHidden)

        fixture.workspace.selectMode(.note)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .note)
        XCTAssertFalse(fixture.workspace.noteScrollView.isHidden)
        XCTAssertTrue(fixture.workspace.blankContainer.isHidden)
    }

    func testNoteEditWritesPlainTextToStore() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.noteTextView.string = "编辑内容"

        fixture.workspace.textDidChange(Notification(
            name: NSText.didChangeNotification,
            object: fixture.workspace.noteTextView
        ))

        XCTAssertEqual(fixture.doubles.store.content.noteText, "编辑内容")
    }

    func testBlankTitleWritesStoreAndPanelTitle() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)
        fixture.workspace.blankTitleField.stringValue = "项目空白"

        fixture.workspace.blankTitleChanged()

        XCTAssertEqual(fixture.doubles.store.content.blankTitle, "项目空白")
        XCTAssertEqual(fixture.window.panel.title, "项目空白")
    }

    func testBlankColorWritesSRGBChannelsToStore() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.colorWell.color = NSColor(
            srgbRed: 0.12,
            green: 0.34,
            blue: 0.56,
            alpha: 0.78
        )

        fixture.workspace.blankColorChanged()

        let color = fixture.doubles.store.content.blankBackground
        XCTAssertEqual(color.red, 0.12, accuracy: 0.001)
        XCTAssertEqual(color.green, 0.34, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.56, accuracy: 0.001)
        XCTAssertEqual(color.alpha, 0.78, accuracy: 0.001)
    }

    func testBlankSizeFieldsResizeRealPanel() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.widthField.stringValue = "640"
        fixture.workspace.heightField.stringValue = "700"

        fixture.workspace.blankSizeChanged()

        XCTAssertEqual(fixture.window.panel.frame.size, NSSize(width: 640, height: 700))
    }

    func testProgrammaticPanelResizeUpdatesBothBlankSizeFields() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)

        fixture.window.panel.setFrame(NSRect(x: 100, y: 100, width: 700, height: 600), display: false)

        XCTAssertEqual(fixture.workspace.widthField.stringValue, "700")
        XCTAssertEqual(fixture.workspace.heightField.stringValue, "600")
    }

    func testClampedBlankWidthIsWrittenBackToField() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.widthField.stringValue = "100"
        fixture.workspace.heightField.stringValue = "600"

        fixture.workspace.blankSizeChanged()

        XCTAssertEqual(fixture.window.panel.frame.size, NSSize(width: 360, height: 600))
        XCTAssertEqual(fixture.workspace.widthField.stringValue, "360")
        XCTAssertEqual(fixture.workspace.heightField.stringValue, "600")
    }

    func testInstalledBlankLayoutAllowsMinimumWidth() throws {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let workspace = try XCTUnwrap(window.panel.contentViewController as? WorkspaceViewController)
        workspace.selectMode(.blank)
        workspace.widthField.stringValue = "100"
        workspace.heightField.stringValue = "600"

        workspace.blankSizeChanged()
        window.panel.layoutIfNeeded()

        XCTAssertEqual(window.panel.frame.width, 360)
        XCTAssertEqual(workspace.widthField.stringValue, "360")
    }

    func testEditingWidthAfterResizeKeepsCurrentHeight() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)
        fixture.window.panel.setFrame(NSRect(x: 100, y: 100, width: 700, height: 600), display: false)

        fixture.workspace.widthField.stringValue = "800"
        fixture.workspace.blankSizeChanged()

        XCTAssertEqual(fixture.window.panel.frame.size, NSSize(width: 800, height: 600))
    }

    func testSaveStateLabelMapsSavedSavingAndFailedStates() throws {
        let fixture = try makeWorkspace()
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "已保存")

        fixture.doubles.store.update { $0.noteText = "待保存" }
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "保存中")

        let failed = expectation(description: "save failed")
        fixture.doubles.store.flush { result in
            if case .failure = result { failed.fulfill() }
        }
        fixture.doubles.saver.completeFailure(at: 0)
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "保存失败")
    }

    func testFloatingWindowInstallsWorkspaceViewController() throws {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)

        XCTAssertTrue(window.panel.contentViewController is WorkspaceViewController)
    }

    func testBlankToImageRestoresDefaultPanelTitleAndBackground() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)
        fixture.workspace.blankTitleField.stringValue = "自定义空白"
        fixture.workspace.blankTitleChanged()
        fixture.workspace.colorWell.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        fixture.workspace.blankColorChanged()
        XCTAssertEqual(fixture.window.panel.title, "自定义空白")

        fixture.workspace.selectMode(.image)

        XCTAssertEqual(fixture.window.panel.title, "悬浮工作台")
        XCTAssertEqual(fixture.window.panel.backgroundColor, .clear)
        XCTAssertFalse(fixture.workspace.imageContainer.isHidden)
        XCTAssertTrue(fixture.workspace.blankContainer.isHidden)
    }

    func testImageDocumentEditsDoNotRestyleWorkspaceGlass() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.image)
        let updates = fixture.workspace.glassAppearanceUpdateCount
        let invalidations = fixture.workspace.glassBackgroundView.gradientView.invalidationCount
        let id = UUID().uuidString

        fixture.doubles.store.update {
            $0.imageDocument = ImageDocument(
                id: id,
                originalRelativePath: "Images/\(id).png",
                displayScale: 2,
                cropRect: ImageRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
            )
        }
        fixture.doubles.store.update { $0.noteText = "图片模式中的便签保存" }

        XCTAssertEqual(fixture.workspace.glassAppearanceUpdateCount, updates)
        XCTAssertEqual(fixture.workspace.glassBackgroundView.gradientView.invalidationCount, invalidations)
        XCTAssertFalse(fixture.workspace.imageContainer.isHidden)
        XCTAssertEqual(fixture.workspace.imageButton.state, .on)
    }

    func testImageImportDropAndFailuresShareVisibleEditorState() throws {
        let root = try temporaryDirectory()
        let workspaceURL = root.appendingPathComponent("Workspace", isDirectory: true)
        let fixture = try makeWorkspace(workspaceDirectory: workspaceURL)
        let source = root.appendingPathComponent("source.png")
        try writeImage(to: source)
        let originalBytes = try Data(contentsOf: source)

        XCTAssertTrue(fixture.workspace.importImage(at: source, replacing: false))
        let first = try XCTUnwrap(fixture.doubles.store.content.imageDocument)
        let managed = workspaceURL.appendingPathComponent(first.originalRelativePath)
        XCTAssertEqual(try Data(contentsOf: managed), originalBytes)
        XCTAssertEqual(fixture.workspace.imageViewController.errorLabel.stringValue, "")
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .image)

        let moved = root.appendingPathComponent("moved-original.png")
        try FileManager.default.moveItem(at: source, to: moved)
        let reopened = WorkspaceViewController(
            store: fixture.doubles.store,
            windowController: fixture.window,
            workspaceDirectory: workspaceURL
        )
        _ = reopened.view
        XCTAssertNotNil(reopened.imageViewController.canvasView.image)
        XCTAssertEqual(reopened.imageViewController.errorLabel.stringValue, "")

        let second = root.appendingPathComponent("second.jpg")
        try writeImage(to: second, type: .jpeg)
        fixture.workspace.imageContainer.onFileURLs?([second])
        let replacement = try XCTUnwrap(fixture.doubles.store.content.imageDocument)
        XCTAssertNotEqual(replacement.id, first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertEqual(try Data(contentsOf: moved), originalBytes)

        let unsupported = root.appendingPathComponent("unsupported.gif")
        try originalBytes.write(to: unsupported)
        let corrupt = root.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)
        let oversized = root.appendingPathComponent("oversized.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: oversized.path))
        try handle.truncate(atOffset: 50 * 1024 * 1024 + 1)
        try handle.close()

        for (url, reason) in [
            (unsupported, "PNG/JPEG"),
            (corrupt, "decode"),
            (oversized, "50MB")
        ] {
            XCTAssertFalse(fixture.workspace.importImage(at: url, replacing: true))
            XCTAssertEqual(fixture.doubles.store.content.imageDocument, replacement)
            XCTAssertTrue(
                fixture.workspace.imageViewController.errorLabel.stringValue.contains(reason),
                fixture.workspace.imageViewController.errorLabel.stringValue
            )
        }
        XCTAssertEqual(try Data(contentsOf: moved), originalBytes)
    }

    func testImageExportWritesPNGAndShowsFailureWithoutMutatingDocument() throws {
        let root = try temporaryDirectory()
        let workspaceURL = root.appendingPathComponent("Workspace", isDirectory: true)
        let fixture = try makeWorkspace(workspaceDirectory: workspaceURL)
        let source = root.appendingPathComponent("source.png")
        try writeImage(to: source)
        XCTAssertTrue(fixture.workspace.importImage(at: source, replacing: false))
        XCTAssertTrue(fixture.workspace.imageViewController.updateCrop(
            ImageRect(x: 0.25, y: 0, width: 0.5, height: 0.5)
        ))
        XCTAssertTrue(fixture.workspace.imageViewController.addPencil(
            points: [ImagePoint(x: 0.4, y: 0.5)],
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
            width: 2
        ))
        let document = fixture.doubles.store.content.imageDocument
        let destination = root.appendingPathComponent("exported.png")

        XCTAssertTrue(fixture.workspace.exportImage(to: destination))

        let exportedSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(exportedSource, 0, nil))
        XCTAssertEqual(exported.width, 100)
        XCTAssertEqual(exported.height, 50)
        XCTAssertEqual(fixture.workspace.imageViewController.errorLabel.stringValue, "")

        XCTAssertFalse(fixture.workspace.exportImage(to: root))
        XCTAssertFalse(fixture.workspace.imageViewController.errorLabel.stringValue.isEmpty)
        XCTAssertEqual(fixture.doubles.store.content.imageDocument, document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeImage(to url: URL, type: UTType = .png) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 200,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeWorkspace(workspaceDirectory: URL? = nil) throws -> (
        workspace: WorkspaceViewController,
        window: FloatingWindowController,
        doubles: ContentStoreTestDoubles
    ) {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store, workspaceDirectory: workspaceDirectory)
        let workspace = WorkspaceViewController(
            store: doubles.store,
            windowController: window,
            workspaceDirectory: workspaceDirectory
        )
        _ = workspace.view
        return (workspace, window, doubles)
    }
}
