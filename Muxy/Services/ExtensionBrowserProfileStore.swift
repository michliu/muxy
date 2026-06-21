import CryptoKit
import Foundation
import os
import WebKit

private let logger = Logger(subsystem: "app.muxy", category: "ExtensionBrowserProfileStore")

struct BrowserCookie {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let expires: Date?
}

@MainActor
final class ExtensionBrowserProfileStore {
    static let shared = ExtensionBrowserProfileStore()

    private var profiles: [String: [String]]
    private let store: CodableFileStore<[String: [String]]>

    init(fileURL: URL = ExtensionBrowserProfileStore.defaultFileURL) {
        store = CodableFileStore(
            fileURL: fileURL,
            options: CodableFileStoreOptions(
                prettyPrinted: true,
                sortedKeys: true,
                filePermissions: FilePermissions.privateFile
            )
        )
        profiles = (try? store.load()) ?? [:]
    }

    static var defaultFileURL: URL {
        MuxyFileStorage.fileURL(filename: "browser-extension-profiles.json")
    }

    func profileID(extensionID: String, key: String) -> UUID {
        Self.deriveID(extensionID: extensionID, key: key)
    }

    func ensure(extensionID: String, key: String) {
        var keys = profiles[extensionID] ?? []
        guard !keys.contains(key) else { return }
        keys.append(key)
        profiles[extensionID] = keys
        persist()
    }

    func list(extensionID: String) -> [String] {
        profiles[extensionID] ?? []
    }

    func delete(extensionID: String, key: String) async {
        let id = profileID(extensionID: extensionID, key: key)
        BrowserDataStoreCache.shared.evict(id)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                if let error {
                    logger.error("Failed to remove data store: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
        var keys = profiles[extensionID] ?? []
        keys.removeAll { $0 == key }
        if keys.isEmpty {
            profiles[extensionID] = nil
        } else {
            profiles[extensionID] = keys
        }
        persist()
    }

    func clear(extensionID: String, key: String) async {
        let id = profileID(extensionID: extensionID, key: key)
        let dataStore = BrowserDataStoreCache.shared.store(for: id)
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func setCookies(extensionID: String, key: String, cookies: [BrowserCookie]) async {
        ensure(extensionID: extensionID, key: key)
        let id = profileID(extensionID: extensionID, key: key)
        let cookieStore = BrowserDataStoreCache.shared.store(for: id).httpCookieStore
        for cookie in cookies {
            guard let httpCookie = Self.makeHTTPCookie(cookie) else { continue }
            await cookieStore.setCookie(httpCookie)
        }
    }

    private func persist() {
        do {
            try store.save(profiles)
        } catch {
            logger.error("Failed to persist browser profiles: \(error.localizedDescription)")
        }
    }

    static func deriveID(extensionID: String, key: String) -> UUID {
        let input = "\(extensionID)\u{1F}\(key)"
        var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func makeHTTPCookie(_ cookie: BrowserCookie) -> HTTPCookie? {
        guard !cookie.name.isEmpty, !cookie.domain.isEmpty else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookie.name,
            .value: cookie.value,
            .domain: cookie.domain,
            .path: cookie.path.isEmpty ? "/" : cookie.path,
        ]
        if cookie.secure { properties[.secure] = "TRUE" }
        if cookie.httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires = cookie.expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}
