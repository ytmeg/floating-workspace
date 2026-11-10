import CoreGraphics
import Foundation
import ImageIO

/// The single decode path shared by import, canvas preview and export.
/// Pixel limits are checked from header properties before any full decode, and the
/// returned image is upright: EXIF orientation is applied so stored coordinates match what users see.
public enum ImageDecoding {
    public static let maximumPixelCount = 100_000_000
    public static let maximumDimension = 16_384

    public enum ErrorCode: Int {
        case unreadable = 1
        case missingDimensions = 2
        case tooLarge = 3
    }

    public static let errorDomain = "ImageDecoding"

    public static func decodeImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw error("图片无法解码", code: .unreadable)
        }
        return try decodeImage(from: source)
    }

    public static func decodeImage(from source: CGImageSource) throws -> CGImage {
        let header = try validatedHeader(of: source)
        let image: CGImage?
        if header.orientation == .up {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            // A full-size thumbnail with transform is ImageIO's supported way to apply EXIF orientation.
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(header.width, header.height),
                kCGImageSourceShouldCacheImmediately: true
            ] as [CFString: Any] as CFDictionary)
        }
        guard let image,
              image.width == header.uprightWidth,
              image.height == header.uprightHeight else {
            throw error("图片无法解码", code: .unreadable)
        }
        return image
    }

    /// Reads only header properties; never allocates the decoded bitmap.
    @discardableResult
    public static func validateDimensions(of source: CGImageSource) throws -> (width: Int, height: Int) {
        let header = try validatedHeader(of: source)
        return (header.uprightWidth, header.uprightHeight)
    }

    private struct Header {
        let width: Int
        let height: Int
        let orientation: CGImagePropertyOrientation

        var swapsAxes: Bool {
            [.leftMirrored, .right, .rightMirrored, .left].contains(orientation)
        }

        var uprightWidth: Int { swapsAxes ? height : width }
        var uprightHeight: Int { swapsAxes ? width : height }
    }

    private static func validatedHeader(of source: CGImageSource) throws -> Header {
        guard CGImageSourceGetType(source) != nil else {
            throw error("图片无法解码", code: .unreadable)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            throw error("无法读取图片尺寸", code: .missingDimensions)
        }
        guard width <= maximumDimension, height <= maximumDimension,
              width * height <= maximumPixelCount else {
            throw error(
                "图片尺寸 \(width)×\(height) 超过上限（每边最多 \(maximumDimension) 像素，总计最多 1 亿像素）",
                code: .tooLarge
            )
        }
        let rawOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return Header(
            width: width,
            height: height,
            orientation: CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        )
    }

    private static func error(_ message: String, code: ErrorCode) -> NSError {
        NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
