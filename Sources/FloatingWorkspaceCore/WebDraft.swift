import Foundation

public struct WebDraft: Codable, Equatable, Sendable {
    public let url: String
    public let sanitizedBodyHTML: String
    public let updatedAt: Date

    public init(url: String, sanitizedBodyHTML: String, updatedAt: Date) {
        self.url = url
        self.sanitizedBodyHTML = sanitizedBodyHTML
        self.updatedAt = updatedAt
    }
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
        guard scheme == "http" || scheme == "https",
              isValidHostname(rawHost) else {
            throw invalidURL()
        }
        if let port = components.port {
            guard (0...65535).contains(port) else {
                throw invalidURL()
            }
        }
        let host = rawHost.lowercased()

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

    private static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.utf8.count <= 253,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 45, 48...57, 65...90, 97...122:
                    true
                default:
                    false
                }
            }
        }
    }

    private static func invalidURL() -> NSError {
        NSError(
            domain: "WebDraftKey",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid web draft URL"]
        )
    }
}
