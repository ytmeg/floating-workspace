import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public struct ImageExporter {
    typealias Renderer = (CGImage, [ImageAnnotation], CGRect) throws -> CGImage

    private let store: ImageDocumentStore
    private let renderer: Renderer

    public init(store: ImageDocumentStore) {
        self.store = store
        renderer = { image, annotations, cropRect in
            try ImageRenderer.render(image: image, annotations: annotations, cropRect: cropRect)
        }
    }

    init(store: ImageDocumentStore, renderer: @escaping Renderer) {
        self.store = store
        self.renderer = renderer
    }

    public func export(document: ImageDocument, to destinationURL: URL) throws {
        let document = try document.normalized()
        let sourceURL = try store.managedURL(for: document)
        let image = try ImageDecoding.decodeImage(at: sourceURL)
        guard let crop = ImageRenderer.Layout.normalizedUnitCrop(document.cropRect) else {
            throw Self.error("图片无法解码或裁剪区域无效", code: 1)
        }

        let originalSize = CGSize(width: image.width, height: image.height)
        let originalBounds = CGRect(origin: .zero, size: originalSize)
        let cropRect = CGRect(
            x: CGFloat(crop.x) * originalSize.width,
            y: CGFloat(crop.y) * originalSize.height,
            width: CGFloat(crop.width) * originalSize.width,
            height: CGFloat(crop.height) * originalSize.height
        ).integral.intersection(originalBounds)
        guard !cropRect.isNull, !cropRect.isEmpty else {
            throw Self.error("裁剪区域没有可导出的像素", code: 2)
        }

        let rendered = try renderer(image, document.annotations, cropRect)
        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            pngData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Self.error("无法创建 PNG 导出目标", code: 3)
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Self.error("无法完成 PNG 编码", code: 4)
        }
        try (pngData as Data).write(to: destinationURL, options: .atomic)
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(
            domain: "ImageExporter",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
