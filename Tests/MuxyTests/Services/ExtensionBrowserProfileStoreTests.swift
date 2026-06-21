import Foundation
import Testing

@testable import Muxy

@Suite("ExtensionBrowserProfileStore")
@MainActor
struct ExtensionBrowserProfileStoreTests {
    @Test("derived id is stable for the same extension and key")
    func deriveStable() {
        let first = ExtensionBrowserProfileStore.deriveID(extensionID: "ext", key: "work")
        let second = ExtensionBrowserProfileStore.deriveID(extensionID: "ext", key: "work")
        #expect(first == second)
    }

    @Test("derived id differs per extension and per key")
    func deriveDistinct() {
        let a = ExtensionBrowserProfileStore.deriveID(extensionID: "ext", key: "work")
        let b = ExtensionBrowserProfileStore.deriveID(extensionID: "ext", key: "home")
        let c = ExtensionBrowserProfileStore.deriveID(extensionID: "other", key: "work")
        #expect(a != b)
        #expect(a != c)
        #expect(b != c)
    }

    @Test("derived id is not all-zero and is a valid v5-style UUID")
    func deriveVersionBits() {
        let id = ExtensionBrowserProfileStore.deriveID(extensionID: "ext", key: "work")
        #expect(id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        #expect(id.uuid.6 & 0xF0 == 0x50)
        #expect(id.uuid.8 & 0xC0 == 0x80)
    }

    @Test("separator avoids key concatenation collisions")
    func deriveSeparator() {
        let left = ExtensionBrowserProfileStore.deriveID(extensionID: "ab", key: "c")
        let right = ExtensionBrowserProfileStore.deriveID(extensionID: "a", key: "bc")
        #expect(left != right)
    }

    @Test("ensure persists keys and list returns them")
    func ensureAndList() {
        let store = makeStore()
        store.ensure(extensionID: "ext", key: "work")
        store.ensure(extensionID: "ext", key: "home")
        store.ensure(extensionID: "ext", key: "work")
        #expect(store.list(extensionID: "ext") == ["work", "home"])
        #expect(store.list(extensionID: "other").isEmpty)
    }

    @Test("keys survive reload from disk")
    func reload() {
        let url = tempURL()
        let store = ExtensionBrowserProfileStore(fileURL: url)
        store.ensure(extensionID: "ext", key: "work")
        let reloaded = ExtensionBrowserProfileStore(fileURL: url)
        #expect(reloaded.list(extensionID: "ext") == ["work"])
    }

    private func makeStore() -> ExtensionBrowserProfileStore {
        ExtensionBrowserProfileStore(fileURL: tempURL())
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-browser-profiles-\(UUID().uuidString).json")
    }
}
