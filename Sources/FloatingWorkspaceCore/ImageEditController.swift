import AppKit
import CoreGraphics
import Foundation
import ImageIO

@MainActor
public final class ImageEditController: NSViewController {
    public let store: ImageDocumentStore
    public let canvasView = ImageCanvasView(frame: .zero)

    public let importButton = NSButton()
    public let replaceButton = NSButton()
    public let deleteButton = NSButton()
    public let zoomSlider = NSSlider()
    public let cropButton = NSButton()
    public let resetCropButton = NSButton()
    public let pencilButton = NSButton()
    public let textButton = NSButton()
    public let arrowButton = NSButton()
    public let colorWell = NSColorWell()
    public let textField = NSTextField()
    public let undoButton = NSButton()
    public let clearButton = NSButton()
    public let exportButton = NSButton()
    public let errorLabel = NSTextField(labelWithString: "")

    public private(set) var selectedTool: ImageEditTool = .pencil
    public private(set) var isCropEditing = false
    public var onImportRequest: (() -> Void)?
    public var onReplaceRequest: (() -> Void)?
    /// Workspace integration presents the save panel and routes the chosen URL to exportImage(to:).
    public var onExport: ((ImageDocument) -> Void)?

    private var annotationColor = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let imageDecoder: (URL) throws -> CGImage
    private var cachedImage: (documentID: String, image: CGImage)?

    public init(
        store: ImageDocumentStore,
        imageDecoder: ((URL) throws -> CGImage)? = nil
    ) {
        self.store = store
        self.imageDecoder = imageDecoder ?? Self.decodeImage(at:)
        super.init(nibName: nil, bundle: nil)
        canvasView.onCrop = { [weak self] in self?.updateCrop($0) }
        canvasView.onPencil = { [weak self] in self?.addPencil(points: $0) }
        canvasView.onText = { [weak self] in self?.addText($0, at: $1) }
        canvasView.onArrow = { [weak self] in self?.addArrow(from: $0, to: $1) }
        canvasView.textContentProvider = { [weak self] in self?.textField.stringValue ?? "" }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 540))
        configureControls()
        layoutControls()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        refreshDocument()
    }

    public func importImage(at url: URL) throws {
        _ = try store.importImage(at: url)
        cachedImage = nil
        refreshDocument()
    }

    public func replaceImage(at url: URL) throws {
        _ = try store.replaceImage(at: url)
        cachedImage = nil
        refreshDocument()
    }

    public func deleteImage() throws {
        try store.deleteDocument()
        cachedImage = nil
        setCropEditing(false)
        refreshDocument()
    }

    @objc public func zoomChanged() {
        setDisplayScale(zoomSlider.doubleValue)
    }

    @discardableResult
    public func setDisplayScale(_ scale: Double) -> Bool {
        guard scale.isFinite else { return false }
        let updated = store.update { $0.displayScale = scale }
        if updated { refreshDocument() }
        return updated
    }

    @objc public func toggleCrop() {
        setCropEditing(!isCropEditing)
    }

    public func setCropEditing(_ enabled: Bool) {
        isCropEditing = enabled
        canvasView.isCropEditingEnabled = enabled
        cropButton.state = enabled ? .on : .off
        canvasView.needsDisplay = true
    }

    @objc public func resetCrop() {
        guard store.document?.cropRect != .full else { return }
        if store.update({ $0.cropRect = .full }) {
            refreshDocument()
        }
    }

    @discardableResult
    public func updateCrop(_ crop: ImageRect) -> Bool {
        guard let crop = ImageRenderer.Layout.normalizedUnitCrop(crop),
              Self.hasOriginalAspect(crop: crop, image: canvasView.image) else { return false }
        let updated = store.update { $0.cropRect = crop }
        if updated { refreshDocument() }
        return updated
    }

    public func selectTool(_ tool: ImageEditTool) {
        selectedTool = tool
        canvasView.tool = tool
        setCropEditing(false)
        pencilButton.state = tool == .pencil ? .on : .off
        textButton.state = tool == .text ? .on : .off
        arrowButton.state = tool == .arrow ? .on : .off
    }

    @objc public func colorChanged() {
        guard let color = colorWell.color.usingColorSpace(.sRGB) else { return }
        annotationColor = RGBAColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
        canvasView.annotationColor = annotationColor
    }

    @discardableResult
    public func addPencil(
        points: [ImagePoint],
        color: RGBAColor? = nil,
        width: Double = 2
    ) -> Bool {
        guard !points.isEmpty, points.allSatisfy(Self.isValid(point:)),
              width.isFinite, width >= 0 else { return false }
        let annotation = ImageAnnotation.pencil(
            points: points,
            color: color ?? annotationColor,
            width: width
        )
        return add(annotation)
    }

    @discardableResult
    public func addText(
        _ content: String,
        at position: ImagePoint,
        color: RGBAColor? = nil,
        fontSize: Double = 16
    ) -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.isValid(point: position), fontSize.isFinite, fontSize >= 0 else { return false }
        let annotation = ImageAnnotation.text(
            content: content,
            color: color ?? annotationColor,
            fontSize: fontSize,
            position: position
        )
        return add(annotation)
    }

    @discardableResult
    public func addArrow(
        from start: ImagePoint,
        to end: ImagePoint,
        color: RGBAColor? = nil,
        width: Double = 2
    ) -> Bool {
        guard Self.isValid(point: start), Self.isValid(point: end), start != end,
              width.isFinite, width >= 0 else { return false }
        let annotation = ImageAnnotation.arrow(
            start: start,
            end: end,
            color: color ?? annotationColor,
            width: width
        )
        return add(annotation)
    }

    @objc public func undoAnnotation() {
        guard store.document?.annotations.isEmpty == false else { return }
        if store.update({ $0.annotations.removeLast() }) {
            refreshDocument()
        }
    }

    @objc public func clearAnnotations() {
        guard store.document?.annotations.isEmpty == false else { return }
        if store.update({ $0.annotations.removeAll() }) {
            refreshDocument()
        }
    }

    @objc public func exportImage() {
        guard let document = store.document else { return }
        onExport?(document)
    }

    public func exportImage(to destinationURL: URL) throws {
        guard let document = store.document else { return }
        try ImageExporter(store: store).export(document: document, to: destinationURL)
    }

    public func refreshDocument() {
        let document = store.document
        canvasView.document = document
        zoomSlider.doubleValue = document?.displayScale ?? 1
        undoButton.isEnabled = document?.annotations.isEmpty == false
        clearButton.isEnabled = document?.annotations.isEmpty == false
        resetCropButton.isEnabled = document != nil
        exportButton.isEnabled = document != nil
        deleteButton.isEnabled = document != nil
        replaceButton.isEnabled = document != nil

        guard let document else {
            cachedImage = nil
            canvasView.image = nil
            return
        }
        if let cachedImage, cachedImage.documentID == document.id {
            canvasView.image = cachedImage.image
            errorLabel.stringValue = ""
            return
        }
        do {
            let url = try store.managedURL(for: document)
            let image = try imageDecoder(url)
            cachedImage = (documentID: document.id, image: image)
            canvasView.image = image
            errorLabel.stringValue = ""
        } catch {
            cachedImage = nil
            canvasView.image = nil
            errorLabel.stringValue = error.localizedDescription
        }
    }

    private func add(_ annotation: ImageAnnotation) -> Bool {
        let updated = store.update { $0.annotations.append(annotation) }
        if updated { refreshDocument() }
        return updated
    }

    private func configureControls() {
        configure(button: importButton, title: "导入", identifier: "image-import", action: #selector(importRequested))
        configure(button: replaceButton, title: "替换", identifier: "image-replace", action: #selector(replaceRequested))
        configure(button: deleteButton, title: "删除", identifier: "image-delete", action: #selector(deleteRequested))
        configure(button: cropButton, title: "裁剪", identifier: "image-crop", action: #selector(toggleCrop), toggle: true)
        configure(button: resetCropButton, title: "重置裁剪", identifier: "image-reset-crop", action: #selector(resetCrop))
        configure(button: pencilButton, title: "画笔", identifier: "image-tool-pencil", action: #selector(pencilSelected), toggle: true)
        configure(button: textButton, title: "文字", identifier: "image-tool-text", action: #selector(textSelected), toggle: true)
        configure(button: arrowButton, title: "箭头", identifier: "image-tool-arrow", action: #selector(arrowSelected), toggle: true)
        configure(button: undoButton, title: "撤销", identifier: "image-undo", action: #selector(undoAnnotation))
        configure(button: clearButton, title: "清空", identifier: "image-clear", action: #selector(clearAnnotations))
        configure(button: exportButton, title: "导出", identifier: "image-export", action: #selector(exportRequested))

        zoomSlider.minValue = 0.1
        zoomSlider.maxValue = 4
        zoomSlider.doubleValue = 1
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomChanged)
        zoomSlider.setAccessibilityIdentifier("image-zoom")

        colorWell.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.setAccessibilityIdentifier("image-color")

        textField.placeholderString = "标注文字"
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.setAccessibilityIdentifier("image-text-content")
        textField.target = self
        textField.action = #selector(textContentChanged)

        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.setAccessibilityIdentifier("image-error")
        canvasView.setAccessibilityIdentifier("image-canvas")
        selectTool(.pencil)
    }

    private func layoutControls() {
        let fileStack = NSStackView(views: [importButton, replaceButton, deleteButton, exportButton])
        let toolStack = NSStackView(views: [
            pencilButton,
            textButton,
            arrowButton,
            textField,
            colorWell,
            undoButton,
            clearButton
        ])
        let cropStack = NSStackView(views: [cropButton, resetCropButton, zoomSlider])
        for stack in [fileStack, toolStack, cropStack] {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
        }
        let toolbar = NSStackView(views: [fileStack, toolStack, cropStack])
        toolbar.orientation = .vertical
        toolbar.alignment = .leading
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        textField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        zoomSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            canvasView.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -8),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            errorLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func configure(
        button: NSButton,
        title: String,
        identifier: String,
        action: Selector,
        toggle: Bool = false
    ) {
        button.title = title
        button.bezelStyle = .rounded
        if toggle { button.setButtonType(.toggle) }
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private static func isValid(point: ImagePoint) -> Bool {
        point.x.isFinite && point.y.isFinite &&
        (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    private static func hasOriginalAspect(crop: ImageRect, image: CGImage?) -> Bool {
        guard let image else { return true }
        let pixelWidth = crop.width * Double(image.width)
        let pixelHeight = crop.height * Double(image.height)
        let originalAspect = Double(image.width) / Double(image.height)
        let cropAspect = pixelWidth / pixelHeight
        return abs(cropAspect - originalAspect) <= 0.000_001 * max(1, originalAspect)
    }

    private static func decodeImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Self.error("图片无法解码")
        }
        return image
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "ImageEditController",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    @objc private func importRequested() {
        onImportRequest?()
    }

    @objc private func replaceRequested() {
        onReplaceRequest?()
    }

    @objc private func exportRequested() {
        exportImage()
    }

    @objc private func deleteRequested() {
        do {
            try deleteImage()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func pencilSelected() {
        selectTool(.pencil)
    }

    @objc private func textSelected() {
        selectTool(.text)
    }

    @objc private func arrowSelected() {
        selectTool(.arrow)
    }

    @objc private func textContentChanged() {
        canvasView.textContent = textField.stringValue
    }
}
