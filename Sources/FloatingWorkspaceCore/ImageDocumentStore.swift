import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public struct ImageDocumentStore {
    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let maximumFileSize: UInt64 = 50 * 1024 * 1024

    private let store: ContentStore
    private let workspaceDirectory: URL
    private let now: () -> Date
    private let idGenerator: () -> UUID

    public init(
        store: ContentStore,
        workspaceDirectory: URL,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.store = store
        self.workspaceDirectory = workspaceDirectory
        self.now = now
        self.idGenerator = idGenerator
    }

    public var document: ImageDocument? {
        store.content.imageDocument
    }

    public func importImage(at url: URL) throws -> ImageDocument {
        try installImage(at: url)
    }

    /// Creates a new document and UUID while retaining every previous managed copy for non-destructive history.
    /// Replacement never deletes the old copy implicitly.
    public func replaceImage(at url: URL) throws -> ImageDocument {
        try installImage(at: url)
    }

    public func deleteDocument() throws {
        guard let document = store.content.imageDocument else { return }
        let managedURL = try managedURL(for: document)
        do {
            try FileManager.default.removeItem(at: managedURL)
        } catch let error as NSError {
            guard error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError else {
                throw error
            }
        }
        store.update { $0.imageDocument = nil }
    }

    /// Normalizes and saves a mutation through the shared ContentStore.
    /// Returns false without changing content or save state if no document exists or the mutation is invalid.
    @discardableResult
    public func update(_ mutation: (inout ImageDocument) -> Void) -> Bool {
        guard var document = store.content.imageDocument else { return false }
        mutation(&document)
        guard var normalized = try? document.normalized() else { return false }
        normalized.updatedAt = now()
        store.update { $0.imageDocument = normalized }
        return true
    }

    public func managedURL(for document: ImageDocument) throws -> URL {
        try document.validateManagedPath()

        let root = workspaceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let expectedImages = root.appendingPathComponent("Images", isDirectory: true).standardizedFileURL
        let actualImages = imagesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard actualImages.path == expectedImages.path else {
            throw Self.error("Images directory must stay inside the workspace", code: 4)
        }

        let candidate = workspaceDirectory
            .appendingPathComponent(document.originalRelativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let expectedFile = expectedImages.appendingPathComponent(
            URL(fileURLWithPath: document.originalRelativePath).lastPathComponent
        )
        guard candidate.path == expectedFile.path else {
            throw Self.error("Image path escapes the managed Images directory", code: 4)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            throw Self.error("Managed image path is not a file", code: 4)
        }
        return candidate
    }

    private var imagesDirectory: URL {
        workspaceDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    private func installImage(at url: URL) throws -> ImageDocument {
        guard url.isFileURL else {
            throw Self.error("Only local PNG/JPEG images are supported", code: 1)
        }
        let resolvedSource = url.standardizedFileURL.resolvingSymlinksInPath()
        let pathExtension = resolvedSource.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(pathExtension) else {
            throw Self.error("Only local PNG/JPEG images are supported", code: 1)
        }
        let sourceResources = try resolvedSource.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceResources.isRegularFile == true, sourceResources.isSymbolicLink != true else {
            throw Self.error("Image source must be a regular file", code: 1)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: resolvedSource.path)
        guard let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            throw Self.error("Image file size could not be determined", code: 2)
        }
        guard size <= Self.maximumFileSize else {
            throw Self.error("Image exceeds the 50MB limit", code: 2)
        }
        guard let source = CGImageSourceCreateWithURL(resolvedSource as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) as String?,
              sourceType == UTType.png.identifier || sourceType == UTType.jpeg.identifier,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw Self.error("Image data could not be decoded as PNG/JPEG", code: 3)
        }

        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let id = idGenerator().uuidString
        let document = ImageDocument(
            id: id,
            originalRelativePath: "Images/\(id).\(pathExtension)",
            updatedAt: now()
        )
        let destination = try managedURL(for: document)
        try copyAtomically(from: resolvedSource, to: destination)
        store.update { $0.imageDocument = document }
        return document
    }

    private func copyAtomically(from source: URL, to destination: URL) throws {
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-image-import.tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        let stagedResources = try staged.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard stagedResources.isRegularFile == true, stagedResources.isSymbolicLink != true else {
            throw Self.error("Staged image must be a regular file", code: 4)
        }
        // Staging and a same-directory hard link publish a complete copy without overwriting an existing UUID.
        try FileManager.default.linkItem(at: staged, to: destination)
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(
            domain: "ImageDocumentStore",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
