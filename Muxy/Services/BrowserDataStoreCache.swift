import WebKit

@MainActor
final class BrowserDataStoreCache {
    static let shared = BrowserDataStoreCache()

    private var stores: [UUID: WKWebsiteDataStore] = [:]

    private var ephemeralStore: WKWebsiteDataStore?

    func store(for profileID: UUID?) -> WKWebsiteDataStore {
        guard let profileID else { return ephemeral() }
        if let existing = stores[profileID] { return existing }
        let store = WKWebsiteDataStore(forIdentifier: profileID)
        stores[profileID] = store
        return store
    }

    private func ephemeral() -> WKWebsiteDataStore {
        if let existing = ephemeralStore { return existing }
        let store = WKWebsiteDataStore.nonPersistent()
        ephemeralStore = store
        return store
    }

    func evict(_ profileID: UUID) {
        stores[profileID] = nil
    }
}
