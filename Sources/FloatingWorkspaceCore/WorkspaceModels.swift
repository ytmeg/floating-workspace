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
    public var webDrafts: [String: WebDraft]

    public static let `default` = WorkspaceContent(
        schemaVersion: 2,
        selectedMode: .note,
        noteText: "",
        blankTitle: "空白窗口",
        blankBackground: RGBAColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        isPinned: true,
        webDrafts: [:]
    )

    public init(
        schemaVersion: Int,
        selectedMode: WorkspaceMode,
        noteText: String,
        blankTitle: String,
        blankBackground: RGBAColor,
        isPinned: Bool,
        webDrafts: [String: WebDraft] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.selectedMode = selectedMode
        self.noteText = noteText
        self.blankTitle = blankTitle
        self.blankBackground = blankBackground
        self.isPinned = isPinned
        self.webDrafts = webDrafts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, selectedMode, noteText, blankTitle, blankBackground, isPinned, webDrafts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        selectedMode = try container.decode(WorkspaceMode.self, forKey: .selectedMode)
        noteText = try container.decode(String.self, forKey: .noteText)
        blankTitle = try container.decode(String.self, forKey: .blankTitle)
        blankBackground = try container.decode(RGBAColor.self, forKey: .blankBackground)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        if container.contains(.webDrafts) {
            guard let drafts = try container.decodeIfPresent([String: WebDraft].self, forKey: .webDrafts) else {
                throw DecodingError.valueNotFound(
                    [String: WebDraft].self,
                    DecodingError.Context(
                        codingPath: [CodingKeys.webDrafts],
                        debugDescription: "webDrafts must not be null"
                    )
                )
            }
            webDrafts = drafts
        } else {
            webDrafts = [:]
        }
    }
}

public struct WorkspaceLoadResult: Equatable, Sendable {
    public let content: WorkspaceContent
    public let recoveryURL: URL?
    public let migrationBackupURL: URL?

    public init(content: WorkspaceContent, recoveryURL: URL?, migrationBackupURL: URL? = nil) {
        self.content = content
        self.recoveryURL = recoveryURL
        self.migrationBackupURL = migrationBackupURL
    }
}

public enum SaveState: Equatable, Sendable {
    case saved
    case saving
    case failed(String)
}
