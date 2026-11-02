import Foundation

public enum WorkspaceMode: String, Codable, Sendable, CaseIterable {
    case note, image, web, blank

    public var isEnabledInPhase1: Bool {
        self == .note || self == .blank
    }
}

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct WorkspaceContent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var selectedMode: WorkspaceMode
    public var noteText: String
    public var blankTitle: String
    public var blankBackground: RGBAColor
    public var isPinned: Bool

    public static let `default` = WorkspaceContent(
        schemaVersion: 1,
        selectedMode: .note,
        noteText: "",
        blankTitle: "空白窗口",
        blankBackground: RGBAColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        isPinned: true
    )
}

public struct WorkspaceLoadResult: Equatable, Sendable {
    public let content: WorkspaceContent
    public let recoveryURL: URL?
}

public enum SaveState: Equatable, Sendable {
    case saved
    case saving
    case failed(String)
}
