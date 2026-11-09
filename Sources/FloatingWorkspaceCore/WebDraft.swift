import Foundation

public struct WebDraft: Codable, Equatable, Sendable {
    public let url: String
    public let sanitizedBodyHTML: String
    public let updatedAt: Date
}

public enum WebDraftKey {
    public static func normalized(_ url: URL) throws -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme,
              let rawHost = components.host,
              components.user == nil,
              components.password == nil else {
            throw invalidURL()
        }

        let scheme = rawScheme.lowercased()
        let host = rawHost.lowercased()
        guard scheme == "http" || scheme == "https",
              !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw invalidURL()
        }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.fragment = nil
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }

        guard let normalized = components.string else {
            throw invalidURL()
        }
        return normalized
    }

    private static func invalidURL() -> NSError {
        NSError(
            domain: "WebDraftKey",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid web draft URL"]
        )
    }
}
