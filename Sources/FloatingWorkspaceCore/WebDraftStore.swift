import Foundation

@MainActor
public struct WebDraftStore {
    private let store: ContentStore

    public init(store: ContentStore) {
        self.store = store
    }

    public func draft(for url: URL) throws -> WebDraft? {
        let key = try WebDraftKey.normalized(url)
        return store.content.webDrafts[key]
    }

    public func saveDraft(_ draft: WebDraft) throws {
        guard let url = URL(string: draft.url) else {
            throw NSError(
                domain: "WebDraftStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid web draft URL"]
            )
        }
        let key = try WebDraftKey.normalized(url)
        let normalized = WebDraft(
            url: key,
            sanitizedBodyHTML: draft.sanitizedBodyHTML,
            updatedAt: draft.updatedAt
        )
        store.update { $0.webDrafts[key] = normalized }
    }
}
