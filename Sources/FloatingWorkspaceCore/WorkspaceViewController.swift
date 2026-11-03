import AppKit
import Combine
import Foundation

@MainActor
public final class WorkspaceViewController: NSViewController, NSTextViewDelegate {
    let noteButton = NSButton()
    let imageButton = NSButton()
    let webButton = NSButton()
    let blankButton = NSButton()
    let noteTextView = NSTextView()
    let blankTitleField = NSTextField()
    let colorWell = NSColorWell()
    let widthField = NSTextField()
    let heightField = NSTextField()
    let saveStateLabel = NSTextField(labelWithString: "")
    let leftRail = NSView()
    let modeContainer = NSView()
    let noteScrollView = NSScrollView()
    let blankContainer = NSView()

    let store: ContentStore
    private weak var windowController: FloatingWindowController?
    private var subscriptions: Set<AnyCancellable> = []

    public init(store: ContentStore, windowController: FloatingWindowController) {
        self.store = store
        self.windowController = windowController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 540))
        buildLeftRail()
        buildModeContainer()
        buildStatusBar()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        store.$content.sink { [weak self] content in
            self?.apply(content)
        }.store(in: &subscriptions)
        store.$saveState.sink { [weak self] state in
            self?.apply(state)
        }.store(in: &subscriptions)
    }

    func selectMode(_ mode: WorkspaceMode) {
        guard mode.isEnabledInPhase1 else { return }
        store.update { $0.selectedMode = mode }
    }

    public func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === noteTextView else { return }
        store.update { $0.noteText = noteTextView.string }
    }

    @objc func blankTitleChanged() {
        store.update { $0.blankTitle = blankTitleField.stringValue }
    }

    @objc func blankColorChanged() {
        guard let color = colorWell.color.usingColorSpace(.sRGB) else { return }
        store.update {
            $0.blankBackground = RGBAColor(
                red: color.redComponent,
                green: color.greenComponent,
                blue: color.blueComponent,
                alpha: color.alphaComponent
            )
        }
    }

    @objc func blankSizeChanged() {
        guard
            let width = Double(widthField.stringValue),
            let height = Double(heightField.stringValue)
        else { return }
        windowController?.setBlankSize(width: width, height: height)
    }

    private func buildLeftRail() {
        leftRail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftRail)

        configureModeButton(noteButton, title: "便签", identifier: "mode-note", action: #selector(noteModeSelected))
        configureModeButton(imageButton, title: "图片", identifier: "mode-image", action: #selector(imageModeSelected))
        configureModeButton(webButton, title: "网页", identifier: "mode-web", action: #selector(webModeSelected))
        configureModeButton(blankButton, title: "空白", identifier: "mode-blank", action: #selector(blankModeSelected))
        imageButton.isEnabled = false
        webButton.isEnabled = false

        let stack = NSStackView(views: [noteButton, imageButton, webButton, blankButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        leftRail.addSubview(stack)

        NSLayoutConstraint.activate([
            leftRail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftRail.topAnchor.constraint(equalTo: view.topAnchor),
            leftRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftRail.widthAnchor.constraint(equalToConstant: 76),
            stack.topAnchor.constraint(equalTo: leftRail.topAnchor, constant: 12),
            stack.centerXAnchor.constraint(equalTo: leftRail.centerXAnchor)
        ])
        for button in [noteButton, imageButton, webButton, blankButton] {
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 64),
                button.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
    }

    private func buildModeContainer() {
        modeContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeContainer)

        noteTextView.font = NSFont.systemFont(ofSize: 16)
        noteTextView.isRichText = false
        noteTextView.isEditable = true
        noteTextView.isSelectable = true
        noteTextView.allowsUndo = true
        noteTextView.textContainerInset = NSSize(width: 8, height: 8)
        noteTextView.isVerticallyResizable = true
        noteTextView.isHorizontallyResizable = false
        noteTextView.autoresizingMask = [.width]
        noteTextView.textContainer?.widthTracksTextView = true
        noteTextView.delegate = self
        noteTextView.setAccessibilityIdentifier("note-editor")

        noteScrollView.translatesAutoresizingMaskIntoConstraints = false
        noteScrollView.hasVerticalScroller = true
        noteScrollView.borderType = .noBorder
        noteScrollView.documentView = noteTextView
        modeContainer.addSubview(noteScrollView)

        blankContainer.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.addSubview(blankContainer)
        buildBlankControls()

        NSLayoutConstraint.activate([
            noteScrollView.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            noteScrollView.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
            noteScrollView.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            noteScrollView.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor),
            blankContainer.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            blankContainer.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
            blankContainer.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            blankContainer.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor)
        ])
    }

    private func buildBlankControls() {
        configureField(blankTitleField, identifier: "blank-title", action: #selector(blankTitleChanged))
        configureField(widthField, identifier: "blank-width", action: #selector(blankSizeChanged))
        configureField(heightField, identifier: "blank-height", action: #selector(blankSizeChanged))
        colorWell.target = self
        colorWell.action = #selector(blankColorChanged)
        colorWell.setAccessibilityIdentifier("blank-color")
        colorWell.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [Self.label("窗口标题"), blankTitleField],
            [Self.label("背景颜色"), colorWell],
            [Self.label("窗口宽度"), widthField],
            [Self.label("窗口高度"), heightField]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        blankContainer.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: blankContainer.leadingAnchor, constant: 20),
            grid.topAnchor.constraint(equalTo: blankContainer.topAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: blankContainer.trailingAnchor, constant: -20),
            blankTitleField.widthAnchor.constraint(equalToConstant: 240),
            blankTitleField.heightAnchor.constraint(equalToConstant: 28),
            colorWell.widthAnchor.constraint(equalToConstant: 64),
            colorWell.heightAnchor.constraint(equalToConstant: 32),
            widthField.widthAnchor.constraint(equalToConstant: 120),
            widthField.heightAnchor.constraint(equalToConstant: 28),
            heightField.widthAnchor.constraint(equalToConstant: 120),
            heightField.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func buildStatusBar() {
        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        saveStateLabel.font = NSFont.systemFont(ofSize: 13)
        saveStateLabel.setAccessibilityIdentifier("save-state")
        let hotkeyHint = NSTextField(labelWithString: "⌃⌥⌘P 切换置顶")
        hotkeyHint.font = NSFont.systemFont(ofSize: 13)
        hotkeyHint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [saveStateLabel, hotkeyHint])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(stack)

        NSLayoutConstraint.activate([
            modeContainer.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            modeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            modeContainer.topAnchor.constraint(equalTo: view.topAnchor),
            modeContainer.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 36),
            stack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
    }

    private func configureModeButton(
        _ button: NSButton,
        title: String,
        identifier: String,
        action: Selector
    ) {
        button.title = title
        button.isBordered = true
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = NSFont.systemFont(ofSize: 15)
        button.setButtonType(.toggle)
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureField(_ field: NSTextField, identifier: String, action: Selector) {
        field.font = NSFont.systemFont(ofSize: 14)
        field.target = self
        field.action = action
        field.setAccessibilityIdentifier(identifier)
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private static func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 14)
        return label
    }

    private func apply(_ content: WorkspaceContent) {
        if noteTextView.string != content.noteText {
            noteTextView.string = content.noteText
        }
        if blankTitleField.stringValue != content.blankTitle {
            blankTitleField.stringValue = content.blankTitle
        }
        let background = content.blankBackground
        colorWell.color = NSColor(
            srgbRed: background.red,
            green: background.green,
            blue: background.blue,
            alpha: background.alpha
        )

        noteScrollView.isHidden = content.selectedMode != .note
        blankContainer.isHidden = content.selectedMode != .blank
        noteButton.state = content.selectedMode == .note ? .on : .off
        blankButton.state = content.selectedMode == .blank ? .on : .off
        if content.selectedMode == .blank {
            updateBlankSizeFields()
        }
    }

    private func apply(_ state: SaveState) {
        switch state {
        case .saved:
            saveStateLabel.stringValue = "已保存"
        case .saving:
            saveStateLabel.stringValue = "保存中"
        case .failed:
            saveStateLabel.stringValue = "保存失败"
        }
    }

    func updateBlankSizeFields() {
        guard let panel = windowController?.panel else { return }
        widthField.stringValue = String(Int(panel.frame.width.rounded()))
        heightField.stringValue = String(Int(panel.frame.height.rounded()))
    }

    @objc private func noteModeSelected() {
        selectMode(.note)
    }

    @objc private func imageModeSelected() {
        selectMode(.image)
    }

    @objc private func webModeSelected() {
        selectMode(.web)
    }

    @objc private func blankModeSelected() {
        selectMode(.blank)
    }
}
