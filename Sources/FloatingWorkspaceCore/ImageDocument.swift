import Foundation

public struct ImagePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func normalized() throws -> ImagePoint {
        try ImageModelValidation.finite(x, name: "Point x")
        try ImageModelValidation.finite(y, name: "Point y")
        return ImagePoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

public struct ImageRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = ImageRect(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func normalized() throws -> ImageRect {
        try ImageModelValidation.finite(x, name: "Crop x")
        try ImageModelValidation.finite(y, name: "Crop y")
        try ImageModelValidation.finite(width, name: "Crop width")
        try ImageModelValidation.finite(height, name: "Crop height")
        try ImageModelValidation.nonnegative(width, name: "Crop width")
        try ImageModelValidation.nonnegative(height, name: "Crop height")
        let normalizedX = min(max(x, 0), 1)
        let normalizedY = min(max(y, 0), 1)
        return ImageRect(
            x: normalizedX,
            y: normalizedY,
            width: min(width, 1 - normalizedX),
            height: min(height, 1 - normalizedY)
        )
    }
}

public enum ImageAnnotation: Codable, Equatable, Sendable {
    case pencil(points: [ImagePoint], color: RGBAColor, width: Double)
    case text(content: String, color: RGBAColor, fontSize: Double, position: ImagePoint)
    case arrow(start: ImagePoint, end: ImagePoint, color: RGBAColor, width: Double)

    public func normalized() throws -> ImageAnnotation {
        switch self {
        case let .pencil(points, color, width):
            guard !points.isEmpty else {
                throw ImageModelValidation.error("Pencil annotation must contain at least one point")
            }
            try ImageModelValidation.finite(width, name: "Pencil width")
            try ImageModelValidation.nonnegative(width, name: "Pencil width")
            return .pencil(
                points: try points.map { try $0.normalized() },
                color: try ImageModelValidation.normalized(color),
                width: width
            )
        case let .text(content, color, fontSize, position):
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ImageModelValidation.error("Text annotation must not be empty")
            }
            try ImageModelValidation.finite(fontSize, name: "Text font size")
            try ImageModelValidation.nonnegative(fontSize, name: "Text font size")
            return .text(
                content: trimmed,
                color: try ImageModelValidation.normalized(color),
                fontSize: fontSize,
                position: try position.normalized()
            )
        case let .arrow(start, end, color, width):
            try ImageModelValidation.finite(width, name: "Arrow width")
            try ImageModelValidation.nonnegative(width, name: "Arrow width")
            return .arrow(
                start: try start.normalized(),
                end: try end.normalized(),
                color: try ImageModelValidation.normalized(color),
                width: width
            )
        }
    }
}

public struct ImageDocument: Codable, Equatable, Sendable {
    public var id: String
    public var originalRelativePath: String
    public var displayScale: Double
    public var cropRect: ImageRect
    public var annotations: [ImageAnnotation]
    public var updatedAt: Date

    public init(
        id: String,
        originalRelativePath: String,
        displayScale: Double = 1,
        cropRect: ImageRect = .full,
        annotations: [ImageAnnotation] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.originalRelativePath = originalRelativePath
        self.displayScale = displayScale
        self.cropRect = cropRect
        self.annotations = annotations
        self.updatedAt = updatedAt
    }

    public func normalized() throws -> ImageDocument {
        try validateManagedPath()
        try ImageModelValidation.finite(displayScale, name: "Image display scale")
        return ImageDocument(
            id: id,
            originalRelativePath: originalRelativePath,
            displayScale: min(max(displayScale, 0.1), 4),
            cropRect: try cropRect.normalized(),
            annotations: try annotations.map { try $0.normalized() },
            updatedAt: updatedAt
        )
    }

    func validateManagedPath() throws {
        let pathExtension = (originalRelativePath as NSString).pathExtension.lowercased()
        guard UUID(uuidString: id) != nil,
              ["png", "jpg", "jpeg"].contains(pathExtension),
              originalRelativePath == "Images/\(id).\(pathExtension)" else {
            throw ImageModelValidation.error("Image path must identify a managed PNG/JPEG inside Images")
        }
    }
}

private enum ImageModelValidation {
    static func finite(_ value: Double, name: String) throws {
        guard value.isFinite else {
            throw error("\(name) must be finite")
        }
    }

    static func nonnegative(_ value: Double, name: String) throws {
        guard value >= 0 else {
            throw error("\(name) must be nonnegative")
        }
    }

    static func normalized(_ color: RGBAColor) throws -> RGBAColor {
        for (name, value) in [
            ("red", color.red),
            ("green", color.green),
            ("blue", color.blue),
            ("alpha", color.alpha)
        ] {
            try finite(value, name: "Annotation \(name) color channel")
        }
        return RGBAColor(
            red: min(max(color.red, 0), 1),
            green: min(max(color.green, 0), 1),
            blue: min(max(color.blue, 0), 1),
            alpha: min(max(color.alpha, 0), 1)
        )
    }

    static func error(_ message: String) -> NSError {
        NSError(
            domain: "ImageDocument",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
